import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/rollup_periods.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_card_constants.dart';
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

RollupService _engineWith(_ScriptedClient client) {
  return RollupService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub-model'),
    ),
  );
}

String _pad2(int n) => n.toString().padLeft(2, '0');

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('yearlyRollup.keyFor', () {
    test('YYYY, unpadded', () {
      expect(yearlyRollup.keyFor(DateTime(2026, 8, 15)), '2026');
      expect(yearlyRollup.keyFor(DateTime(2026, 1, 1)), '2026');
    });
  });

  group('yearlyRollup.anchorFromPayload / payloadFor', () {
    test('round-trips through the "YYYY" payload', () {
      final anchor = DateTime(2026, 1, 1);
      final payload = yearlyRollup.payloadFor(anchor);
      expect(payload, {'year': '2026'});
      expect(yearlyRollup.anchorFromPayload(payload), DateTime(2026, 1, 1));
    });

    test('invalid payload → null', () {
      expect(yearlyRollup.anchorFromPayload({}), isNull);
      expect(yearlyRollup.anchorFromPayload({'year': 'nonsense'}), isNull);
    });
  });

  group('yearlyRollup.dueFor', () {
    test('12/31 before 21:00 → null (prev year already done)', () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 12, 31, 20, 0),
          lastGeneratedKey: '2025',
          enabled: true,
        ),
        isNull,
      );
    });

    test('12/31 after 21:00 → this year', () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 12, 31, 21, 30),
          lastGeneratedKey: '2025',
          enabled: true,
        ),
        DateTime(2026, 1, 1),
      );
    });

    test('this year already generated → null even after 21:00', () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 12, 31, 23, 0),
          lastGeneratedKey: '2026',
          enabled: true,
        ),
        isNull,
      );
    });

    test('disabled → always null', () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 12, 31, 23, 0),
          lastGeneratedKey: null,
          enabled: false,
        ),
        isNull,
      );
    });

    test('catch-up: previous year missed → previous year anchor', () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 8, 15, 12, 0),
          lastGeneratedKey: '2024',
          enabled: true,
        ),
        DateTime(2025, 1, 1),
      );
    });

    test('11/30 21:00 (non year-end), previous year already done → null',
        () {
      expect(
        yearlyRollup.dueFor(
          now: DateTime(2026, 11, 30, 21, 0),
          lastGeneratedKey: '2025',
          enabled: true,
        ),
        isNull,
      );
    });
  });

  group('yearlyRollup.compose', () {
    test('narrative + highlights + mood trend + next year + mood', () {
      final md = yearlyRollup.compose({
        'narrative': '这一年过得很充实。',
        'highlights': ['完成了大项目', '养成了新习惯'],
        'mood': '满足 😊',
        'next_year': ['继续保持节奏'],
      }, [
        7,
        8,
        6,
        9,
      ]);
      expect(md, isNotNull);
      expect(md, contains('这一年过得很充实。'));
      expect(md, contains('**年度亮点**'));
      expect(md, contains('**明年展望**'));
      expect(md, contains('年度心情:满足 😊'));
    });

    test('missing narrative → null', () {
      expect(
        yearlyRollup.compose({'highlights': []}, const []),
        isNull,
      );
    });
  });

  group('yearlyRollup.collectContext / generate', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'yearly_summary_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_yearly_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    /// Writes a monthly-summary card at a fixed day slot within [month] of
    /// [year] (bypassing `allocateCardFactId`, which always buckets under
    /// *today*) so tests can place cards on arbitrary historical months.
    Future<String> seedMonthlySummary(
      int month,
      String text, {
      int year = 2026,
      int? moodScore,
    }) async {
      const day = 15;
      final factId = '$year/${_pad2(month)}/${_pad2(day)}.md#ts_1';
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: '月总结 $year-${_pad2(month)}',
          tags: [monthlySummaryTag],
          metadata: moodScore != null
              ? {CardMetadataKeys.moodScore: moodScore}
              : null,
          timestamp:
              DateTime(year, month, day, 23, 59).millisecondsSinceEpoch ~/
                  1000,
          uiConfigs: [
            UiConfig(templateId: 'snippet', data: {'text': text}),
          ],
        ),
      );
      return factId;
    }

    final yearAnchor = DateTime(2026, 1, 1);

    test('year with no source cards at all → skip + marks year done',
        () async {
      final client = _ScriptedClient(const []);
      final ok =
          await _engineWith(client).generate(userId, yearlyRollup, yearAnchor);
      expect(ok, isFalse);
      expect(client.calls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('yearly_summary_last_year'), '2026');
    });

    test(
        'collectContext: months 3/6/12 seeded → scores len 12, those non-null '
        'others null, context has their text', () async {
      await seedMonthlySummary(3, '三月总结正文', moodScore: 6);
      await seedMonthlySummary(6, '六月总结正文', moodScore: 8);
      await seedMonthlySummary(12, '十二月总结正文', moodScore: 5);

      final collected = await yearlyRollup.collectContext(userId, yearAnchor);
      expect(collected, isNotNull);

      expect(collected!.scores.length, 12);
      expect(collected.scores[2], 6); // March, 0-indexed
      expect(collected.scores[5], 8); // June
      expect(collected.scores[11], 5); // December
      final others = [...collected.scores]
        ..removeAt(11)
        ..removeAt(5)
        ..removeAt(2);
      expect(others, everyElement(isNull));

      expect(collected.context, contains('三月总结正文'));
      expect(collected.context, contains('六月总结正文'));
      expect(collected.context, contains('十二月总结正文'));
    });

    test('empty year (no monthly cards) → collectContext returns null',
        () async {
      final collected = await yearlyRollup.collectContext(userId, yearAnchor);
      expect(collected, isNull);
    });

    test('generates a yearly card from the monthly rollup', () async {
      await seedMonthlySummary(3, '三月总结正文', moodScore: 6);
      await seedMonthlySummary(6, '六月总结正文', moodScore: 8);

      final client = _ScriptedClient([
        '{"title":"充实的一年","narrative":"这一年既有攀登也有沉淀。",'
            '"highlights":["爬山","完成大项目"],"mood":"满足 😊",'
            '"next_year":["继续保持节奏"]}'
      ]);
      final ok =
          await _engineWith(client).generate(userId, yearlyRollup, yearAnchor);
      expect(ok, isTrue);
      expect(client.calls, 1);

      final prefs = await SharedPreferences.getInstance();
      final factId = prefs.getString('yearly_summary_fact_2026');
      expect(factId, isNotNull);

      final card =
          await FileSystemService.instance.readCardFile(userId, factId!);
      expect(card, isNotNull);
      expect(card!.tags, contains(yearlySummaryTag));
      expect(card.title, '充实的一年');
      expect(card.fact, '每年总结 2026');
      expect(card.metadata?[CardMetadataKeys.moodScore], isNotNull);
      expect(card.metadata?[CardMetadataKeys.moodLabel], '满足 😊');
      final text = card.uiConfigs.first.data['text'] as String;
      expect(text, contains('这一年既有攀登也有沉淀。'));
      expect(text, contains('**年度亮点**'));
      expect(text, contains('**明年展望**'));
      expect(text, contains('年度心情:满足 😊'));
      expect(card.uiConfigs[1].templateId, 'mood_curve');
    });

    test('regeneration updates the same card (idempotent)', () async {
      await seedMonthlySummary(6, '六月总结正文', moodScore: 6);

      final client = _ScriptedClient([
        '{"narrative":"第一版年总结。","highlights":[],"mood":"平静"}',
        '{"narrative":"第二版年总结。","highlights":[],"mood":"平静"}',
      ]);
      final engine = _engineWith(client);
      await engine.generate(userId, yearlyRollup, yearAnchor);
      await engine.generate(userId, yearlyRollup, yearAnchor);

      final prefs = await SharedPreferences.getInstance();
      final factId = prefs.getString('yearly_summary_fact_2026')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.uiConfigs.first.data['text'], contains('第二版年总结'));
    });

    test('user mood rating on a monthly card wins over the AI score',
        () async {
      final factId =
          await seedMonthlySummary(6, '六月总结正文', moodScore: 8);
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        (card) => card.copyWith(metadata: {
          ...?card.metadata,
          CardMetadataKeys.userMoodScore: 3,
        }),
      );

      final client = _ScriptedClient([
        '{"narrative":"年总结。","highlights":[],"mood":"疲惫"}',
      ]);
      await _engineWith(client).generate(userId, yearlyRollup, yearAnchor);

      final prefs = await SharedPreferences.getInstance();
      final yearlyId = prefs.getString('yearly_summary_fact_2026')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, yearlyId);
      // The only scored month's average must be built from the user's 3,
      // not the AI's 8.
      expect(card!.metadata?[CardMetadataKeys.moodScore], 3);
    });
  });
}
