import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.responses);

  final List<String?> responses;
  int calls = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    return ModelMessage(model: 'stub-model', textOutput: responses[index]);
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }
}

/// Minimal test-only [RollupPeriod]: keyed by the anchor's calendar date
/// ('YYYY-MM-DD'), with an injectable context so tests can exercise the
/// skip path (`collectContext` returning null) independently of any real
/// period's data source.
class _FakePeriod implements RollupPeriod {
  _FakePeriod({
    this.contextValue,
    String? taskType,
  }) : taskType = taskType ?? 'fake_rollup_task';

  /// Injected result for [collectContext]; null triggers skip semantics.
  ({String context, List<int?> scores})? contextValue;

  /// Distinguishes periods sharing the singleton [RollupService.instance]
  /// (e.g. two _FakePeriod instances with different taskType) so
  /// maybeSchedule's per-period in-flight guard can be exercised.
  @override
  final String taskType;

  @override
  String get tag => 'fake_rollup';

  @override
  String get prefEnabledKey => 'fake_rollup_enabled_$taskType';

  @override
  String get prefLastKey => 'fake_rollup_last_$taskType';

  @override
  String prefFactIdKey(String periodKey) => 'fake_rollup_fact_$periodKey';

  @override
  String get bizIdPrefix => taskType;

  @override
  String keyFor(DateTime anchor) =>
      '${anchor.year.toString().padLeft(4, '0')}-'
      '${anchor.month.toString().padLeft(2, '0')}-'
      '${anchor.day.toString().padLeft(2, '0')}';

  @override
  DateTime? dueFor({
    required DateTime now,
    required String? lastGeneratedKey,
    required bool enabled,
  }) {
    if (!enabled) return null;
    final key = keyFor(now);
    if (lastGeneratedKey == key) return null;
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Map<String, dynamic> payloadFor(DateTime anchor) =>
      {'anchor': keyFor(anchor)};

  @override
  DateTime? anchorFromPayload(Map<String, dynamic> payload) {
    final raw = payload['anchor'] as String?;
    if (raw == null) return null;
    final parts = raw.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  @override
  Future<({String context, List<int?> scores})?> collectContext(
    String userId,
    DateTime anchor,
  ) async =>
      contextValue;

  @override
  String systemPrompt() => 'fake system prompt';

  @override
  String defaultTitle(DateTime anchor) => 'Fake rollup for ${keyFor(anchor)}';

  @override
  String factText(DateTime anchor) => 'Rollup ${keyFor(anchor)}';

  @override
  DateTime cardTimestamp(DateTime anchor) =>
      DateTime(anchor.year, anchor.month, anchor.day, 23, 59);

  @override
  List<String> chartLabels(DateTime anchor, int scoreCount) =>
      List.generate(scoreCount, (i) => 'P${i + 1}');

  @override
  String? compose(Map<String, dynamic> decision, List<int?> scores) {
    final narrative = (decision['narrative'] as String?)?.trim();
    if (narrative == null || narrative.isEmpty) return null;
    return narrative;
  }
}

RollupService _serviceWith(_ScriptedClient client) {
  return RollupService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub-model'),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('RollupService.generate', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'rollup_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_rollup_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    test('collectContext null → returns false and marks generated (skip)',
        () async {
      final client = _ScriptedClient(const []);
      final period = _FakePeriod(contextValue: null);
      final anchor = DateTime(2026, 8, 10);

      final ok = await _serviceWith(client).generate(userId, period, anchor);

      expect(ok, isFalse);
      expect(client.calls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(period.prefLastKey), period.keyFor(anchor));
    });

    test('model failure does not advance marker and writes no card',
        () async {
      // Not valid JSON → both the non-strict and strict attempts fail.
      final client = _ScriptedClient(const ['not json', 'still not json']);
      final period = _FakePeriod(
        contextValue: (context: 'some context', scores: [7, 8]),
      );
      final anchor = DateTime(2026, 8, 10);

      await expectLater(
        () => _serviceWith(client).generate(userId, period, anchor),
        throwsException,
      );
      expect(client.calls, 2);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(period.prefLastKey), isNull);
      expect(
        prefs.getString(period.prefFactIdKey(period.keyFor(anchor))),
        isNull,
      );
    });

    test('marker never moves backwards', () async {
      final period = _FakePeriod(
        contextValue: (context: 'ctx', scores: [7]),
      );
      final laterAnchor = DateTime(2026, 8, 20);
      final earlierAnchor = DateTime(2026, 8, 10);

      final client1 = _ScriptedClient(
          const ['{"narrative":"later narrative"}']);
      await _serviceWith(client1).generate(userId, period, laterAnchor);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(period.prefLastKey), period.keyFor(laterAnchor));

      final client2 = _ScriptedClient(
          const ['{"narrative":"earlier narrative"}']);
      await _serviceWith(client2).generate(userId, period, earlierAnchor);

      // Marker must still point at the later key, not have moved back.
      expect(prefs.getString(period.prefLastKey), period.keyFor(laterAnchor));
    });

    test('idempotent regenerate reuses the same factId and updates content',
        () async {
      final period = _FakePeriod(
        contextValue: (context: 'ctx', scores: [7]),
      );
      final anchor = DateTime(2026, 8, 10);

      final client1 =
          _ScriptedClient(const ['{"narrative":"first version"}']);
      final ok1 = await _serviceWith(client1).generate(userId, period, anchor);
      expect(ok1, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final factIdKey = period.prefFactIdKey(period.keyFor(anchor));
      final factId1 = prefs.getString(factIdKey);
      expect(factId1, isNotNull);

      final client2 =
          _ScriptedClient(const ['{"narrative":"second version"}']);
      final ok2 = await _serviceWith(client2).generate(userId, period, anchor);
      expect(ok2, isTrue);

      final factId2 = prefs.getString(factIdKey);
      expect(factId2, factId1);

      final card =
          await FileSystemService.instance.readCardFile(userId, factId2!);
      expect(card, isNotNull);
      expect(card!.uiConfigs.first.data['text'], 'second version');
      expect(card.tags, contains(period.tag));
    });

    test('regeneration clears stale AI mood when new rollup has none',
        () async {
      final period = _FakePeriod(
        contextValue: (context: 'ctx', scores: [8]),
      );
      final anchor = DateTime(2026, 8, 10);

      // First generation: scores→avgScore, decision→mood label.
      await _serviceWith(_ScriptedClient(
              const ['{"narrative":"v1","mood":"满足"}']))
          .generate(userId, period, anchor);
      final prefs = await SharedPreferences.getInstance();
      final factId =
          prefs.getString(period.prefFactIdKey(period.keyFor(anchor)))!;
      var card = await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata?['mood_score'], 8);
      expect(card.metadata?['mood_label'], '满足');

      // Regenerate with no mood: no scores, decision has no mood.
      period.contextValue = (context: 'ctx', scores: [null]);
      await _serviceWith(_ScriptedClient(const ['{"narrative":"v2"}']))
          .generate(userId, period, anchor);
      card = await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata?['mood_score'], isNull,
          reason: 'stale AI mood_score must be cleared on regeneration');
      expect(card.metadata?['mood_label'], isNull);
    });
  });

  group('RollupService.maybeSchedule', () {
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'rollup_schedule_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<String>> enqueuedBizIdsFor(String taskType) async {
      final rows = await db.select(db.tasks).get();
      return rows
          .where((t) => t.type == taskType)
          .map((t) => t.bizId ?? '')
          .toList();
    }

    test(
        'scheduling two different periods back-to-back on the shared '
        'singleton enqueues both (regression: was a single shared '
        'in-flight bool that made the second call a no-op)', () async {
      final periodA = _FakePeriod(taskType: 'fake_a');
      final periodB = _FakePeriod(taskType: 'fake_b');
      final now = DateTime(2026, 8, 10);

      // Mirrors production: two unawaited maybeSchedule calls on the same
      // RollupService.instance-style singleton, back-to-back, neither
      // awaited before the other starts.
      final futureA = RollupService.instance.maybeSchedule(periodA, now: now);
      final futureB = RollupService.instance.maybeSchedule(periodB, now: now);
      await Future.wait([futureA, futureB]);

      final aBizIds = await enqueuedBizIdsFor('fake_a');
      final bBizIds = await enqueuedBizIdsFor('fake_b');

      expect(aBizIds, isNotEmpty,
          reason: 'period A must be enqueued even though period B was '
              'scheduled concurrently on the same singleton');
      expect(bBizIds, isNotEmpty,
          reason: 'period B must be enqueued even though period A was '
              'scheduled concurrently on the same singleton');
      expect(aBizIds.single, 'fake_a:${periodA.keyFor(now)}');
      expect(bBizIds.single, 'fake_b:${periodB.keyFor(now)}');
    });

    test('scheduling the same period concurrently only enqueues once',
        () async {
      final period = _FakePeriod(taskType: 'fake_same');
      final now = DateTime(2026, 8, 10);

      await Future.wait([
        RollupService.instance.maybeSchedule(period, now: now),
        RollupService.instance.maybeSchedule(period, now: now),
      ]);

      final bizIds = await enqueuedBizIdsFor('fake_same');
      expect(bizIds.length, 1);
    });
  });

  group('RollupService mood utils', () {
    test('averageScore rounds and ignores gaps', () {
      expect(RollupService.averageScore([7, null, 8, null, null, null, 6]), 7);
      expect(RollupService.averageScore(List.filled(7, null)), isNull);
    });

    test('sparkline maps scores to bars and gaps to dots', () {
      final line = RollupService.sparkline([1, 10, null, 5]);
      expect(line, '▁ █ · ▄');
    });
  });
}
