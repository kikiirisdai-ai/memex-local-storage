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

  group('monthlyRollup.keyFor', () {
    test('YYYY-MM padded', () {
      expect(monthlyRollup.keyFor(DateTime(2026, 8, 15)), '2026-08');
      expect(monthlyRollup.keyFor(DateTime(2026, 1, 1)), '2026-01');
    });
  });

  group('monthlyRollup.anchorFromPayload / payloadFor', () {
    test('round-trips through the "YYYY-MM" payload', () {
      final anchor = DateTime(2026, 8, 1);
      final payload = monthlyRollup.payloadFor(anchor);
      expect(payload, {'month': '2026-08'});
      expect(monthlyRollup.anchorFromPayload(payload), DateTime(2026, 8, 1));
    });

    test('invalid payload → null', () {
      expect(monthlyRollup.anchorFromPayload({}), isNull);
      expect(monthlyRollup.anchorFromPayload({'month': 'nonsense'}), isNull);
    });
  });

  group('monthlyRollup.dueFor', () {
    test('month-end before 21:00 → null (prev month already done)', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 31, 20, 0),
          lastGeneratedKey: '2026-07',
          enabled: true,
        ),
        isNull,
      );
    });

    test('month-end after 21:00 → this month', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 31, 21, 30),
          lastGeneratedKey: '2026-07',
          enabled: true,
        ),
        DateTime(2026, 8, 1),
      );
    });

    test('this month already generated → null even after 21:00', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 31, 23, 0),
          lastGeneratedKey: '2026-08',
          enabled: true,
        ),
        isNull,
      );
    });

    test('disabled → always null', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 31, 23, 0),
          lastGeneratedKey: null,
          enabled: false,
        ),
        isNull,
      );
    });

    test('catch-up: previous month missed → previous month anchor', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 15, 12, 0),
          lastGeneratedKey: '2026-06',
          enabled: true,
        ),
        DateTime(2026, 7, 1),
      );
    });

    test('midweek with previous month done → null', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 15, 12, 0),
          lastGeneratedKey: '2026-07',
          enabled: true,
        ),
        isNull,
      );
    });

    test('February non-leap year (28 days)', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 2, 28, 21, 0),
          lastGeneratedKey: '2026-01',
          enabled: true,
        ),
        DateTime(2026, 2, 1),
      );
    });

    test('February leap year (29 days)', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2028, 2, 29, 21, 0),
          lastGeneratedKey: '2028-01',
          enabled: true,
        ),
        DateTime(2028, 2, 1),
      );
      // Day 28 of a leap February is NOT month-end → no trigger yet.
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2028, 2, 28, 21, 0),
          lastGeneratedKey: '2028-01',
          enabled: true,
        ),
        isNull,
      );
    });

    test('30-day month (April)', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 4, 30, 21, 0),
          lastGeneratedKey: '2026-03',
          enabled: true,
        ),
        DateTime(2026, 4, 1),
      );
    });

    test('31-day month (August)', () {
      expect(
        monthlyRollup.dueFor(
          now: DateTime(2026, 8, 31, 21, 0),
          lastGeneratedKey: '2026-07',
          enabled: true,
        ),
        DateTime(2026, 8, 1),
      );
    });
  });

  group('monthlyRollup.compose', () {
    test('narrative + highlights + mood trend + next month + mood', () {
      final md = monthlyRollup.compose({
        'narrative': '这个月过得很充实。',
        'highlights': ['完成了大项目', '养成了新习惯'],
        'mood': '满足 😊',
        'next_month': ['继续保持节奏'],
      }, [
        7,
        8,
        6,
        9,
      ]);
      expect(md, isNotNull);
      expect(md, contains('这个月过得很充实。'));
      expect(md, contains('**本月亮点**'));
      expect(md, contains('**下月展望**'));
      expect(md, contains('本月心情:满足 😊'));
    });

    test('missing narrative → null', () {
      expect(
        monthlyRollup.compose({'highlights': []}, const []),
        isNull,
      );
    });
  });

  group('monthlyRollup.collectContext / generate', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'monthly_summary_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_monthly_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    /// Writes a daily-summary card directly at [date]'s own
    /// `Cards/YYYY/MM/DD_ts_1.yaml` slot (bypassing `allocateCardFactId`,
    /// which always buckets under *today*) so tests can place cards on
    /// arbitrary historical dates within the target month.
    Future<String> seedDailySummary(
      DateTime date,
      String text, {
      int? moodScore,
    }) async {
      final factId =
          '${date.year}/${_pad2(date.month)}/${_pad2(date.day)}.md#ts_1';
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: '日记 ${_pad2(date.month)}-${_pad2(date.day)}',
          tags: [dailySummaryTag],
          metadata: moodScore != null
              ? {CardMetadataKeys.moodScore: moodScore}
              : null,
          timestamp: DateTime(date.year, date.month, date.day, 23, 59)
                  .millisecondsSinceEpoch ~/
              1000,
          uiConfigs: [
            UiConfig(templateId: 'snippet', data: {'text': text}),
          ],
        ),
      );
      return factId;
    }

    /// Writes a weekly-summary card at the ISO week's Sunday slot
    /// (`monday + 6`), mirroring when the real weekly rollup would have
    /// allocated it in production.
    Future<String> seedWeeklySummary(
      DateTime monday,
      String text, {
      int? moodScore,
    }) async {
      final sunday = DateTime(monday.year, monday.month, monday.day + 6);
      final factId =
          '${sunday.year}/${_pad2(sunday.month)}/${_pad2(sunday.day)}.md#ts_1';
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: '周总结 ${weeklyKeyFor(monday)}',
          tags: [weeklySummaryTag],
          metadata: moodScore != null
              ? {CardMetadataKeys.moodScore: moodScore}
              : null,
          timestamp: DateTime(sunday.year, sunday.month, sunday.day, 23, 59)
                  .millisecondsSinceEpoch ~/
              1000,
          uiConfigs: [
            UiConfig(templateId: 'snippet', data: {'text': text}),
          ],
        ),
      );
      return factId;
    }

    // August 2026: Aug 1 is a Saturday, Aug 31 is a Monday. The month
    // therefore has a 2-day boundary week at the start (Aug1-2, week of
    // Jul27), four full weeks (Aug3-9, 10-16, 17-23, 24-30), and a 1-day
    // boundary week at the end (Aug31, week of Aug31-Sep6) — six week
    // groups total, exercising both hybrid branches plus empty weeks.
    final monthAnchor = DateTime(2026, 8, 1);
    final firstBoundaryMonday = DateTime(2026, 7, 27);
    final secondWeekMonday = DateTime(2026, 8, 3);

    test('month with no source cards at all → skip + marks month done',
        () async {
      final client = _ScriptedClient(const []);
      final ok = await _engineWith(client)
          .generate(userId, monthlyRollup, monthAnchor);
      expect(ok, isFalse);
      expect(client.calls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('monthly_summary_last_month'), '2026-08');
    });

    test(
        'hybrid collect: full weeks read weekly cards, boundary weeks '
        'average daily cards', () async {
      // Boundary week (Aug1 Sat, Aug2 Sun) — only daily cards exist.
      await seedDailySummary(DateTime(2026, 8, 1), '周六爬山日记', moodScore: 6);
      await seedDailySummary(DateTime(2026, 8, 2), '周日休息日记', moodScore: 8);

      // Full week (Aug3-9) — a weekly card exists.
      await seedWeeklySummary(secondWeekMonday, '第一周的周总结正文', moodScore: 5);

      final collected = await monthlyRollup.collectContext(userId, monthAnchor);
      expect(collected, isNotNull);

      // 6 week groups total for August 2026.
      expect(collected!.scores.length, 6);

      // Boundary week (index 0) is the average of the two daily scores.
      expect(collected.scores[0], 7);
      // Full week (index 1) takes the weekly card's own score.
      expect(collected.scores[1], 5);
      // Remaining, unseeded weeks contribute no score.
      expect(collected.scores.sublist(2), everyElement(isNull));

      expect(collected.context, contains('周六爬山日记'));
      expect(collected.context, contains('周日休息日记'));
      expect(collected.context, contains('第一周的周总结正文'));
    });

    test('generates a monthly card from the hybrid collect', () async {
      await seedDailySummary(
          firstBoundaryMonday.add(const Duration(days: 5)), '周六爬山日记',
          moodScore: 6); // Aug 1
      await seedWeeklySummary(secondWeekMonday, '第一周的周总结正文', moodScore: 8);

      final client = _ScriptedClient([
        '{"title":"充实的八月","narrative":"这个月既有攀登也有沉淀。",'
            '"highlights":["爬山","完成周总结联动"],"mood":"满足 😊",'
            '"next_month":["继续保持节奏"]}'
      ]);
      final ok = await _engineWith(client)
          .generate(userId, monthlyRollup, monthAnchor);
      expect(ok, isTrue);
      expect(client.calls, 1);

      final prefs = await SharedPreferences.getInstance();
      final factId = prefs.getString('monthly_summary_fact_2026-08');
      expect(factId, isNotNull);

      final card =
          await FileSystemService.instance.readCardFile(userId, factId!);
      expect(card, isNotNull);
      expect(card!.tags, contains(monthlySummaryTag));
      expect(card.title, '充实的八月');
      expect(card.fact, '每月总结 2026-08');
      expect(card.metadata?[CardMetadataKeys.moodScore], isNotNull);
      expect(card.metadata?[CardMetadataKeys.moodLabel], '满足 😊');
      final text = card.uiConfigs.first.data['text'] as String;
      expect(text, contains('这个月既有攀登也有沉淀。'));
      expect(text, contains('**本月亮点**'));
      expect(text, contains('**下月展望**'));
      expect(text, contains('本月心情:满足 😊'));
      expect(card.uiConfigs[1].templateId, 'mood_curve');
    });

    test('regeneration updates the same card (idempotent)', () async {
      await seedWeeklySummary(secondWeekMonday, '第一周的周总结正文', moodScore: 6);

      final client = _ScriptedClient([
        '{"narrative":"第一版月总结。","highlights":[],"mood":"平静"}',
        '{"narrative":"第二版月总结。","highlights":[],"mood":"平静"}',
      ]);
      final engine = _engineWith(client);
      await engine.generate(userId, monthlyRollup, monthAnchor);
      await engine.generate(userId, monthlyRollup, monthAnchor);

      final prefs = await SharedPreferences.getInstance();
      final factId = prefs.getString('monthly_summary_fact_2026-08')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.uiConfigs.first.data['text'], contains('第二版月总结'));
    });

    test('user mood rating on a daily card wins over the AI score', () async {
      // Only the leading boundary week has data, from a single daily card.
      final factId =
          await seedDailySummary(DateTime(2026, 8, 1), '周六爬山日记', moodScore: 8);
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        (card) => card.copyWith(metadata: {
          ...?card.metadata,
          CardMetadataKeys.userMoodScore: 3,
        }),
      );

      final client = _ScriptedClient([
        '{"narrative":"月总结。","highlights":[],"mood":"疲惫"}',
      ]);
      await _engineWith(client).generate(userId, monthlyRollup, monthAnchor);

      final prefs = await SharedPreferences.getInstance();
      final monthlyId = prefs.getString('monthly_summary_fact_2026-08')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, monthlyId);
      // The boundary week's average must be built from the user's 3, not
      // the AI's 8.
      expect(card!.metadata?[CardMetadataKeys.moodScore], 3);
    });
  });
}
