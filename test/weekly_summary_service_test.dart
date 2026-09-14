import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/weekly_summary_service.dart';
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

WeeklySummaryService _serviceWith(_ScriptedClient client) {
  return WeeklySummaryService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub-model'),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('weekKey', () {
    test('mid-year weeks', () {
      // 2026-07-13 is a Monday; 2026-07-19 the following Sunday.
      expect(WeeklySummaryService.weekKey(DateTime(2026, 7, 13)), '2026-W29');
      expect(WeeklySummaryService.weekKey(DateTime(2026, 7, 19)), '2026-W29');
      expect(WeeklySummaryService.weekKey(DateTime(2026, 7, 20)), '2026-W30');
    });

    test('ISO year boundary belongs to the Thursday year', () {
      // 2026-01-01 is a Thursday → week 1 of 2026.
      expect(WeeklySummaryService.weekKey(DateTime(2026, 1, 1)), '2026-W01');
      // 2027-01-01 is a Friday; its week's Thursday is 2026-12-31 → 2026-W53.
      expect(WeeklySummaryService.weekKey(DateTime(2027, 1, 1)), '2026-W53');
      expect(WeeklySummaryService.weekKey(DateTime(2027, 1, 4)), '2027-W01');
    });
  });

  group('mondayOf', () {
    test('returns Monday 00:00 for any weekday', () {
      final monday = DateTime(2026, 7, 13);
      for (var i = 0; i < 7; i++) {
        expect(
          WeeklySummaryService.mondayOf(monday.add(Duration(days: i))),
          monday,
        );
      }
    });
  });

  group('dueWeekFor', () {
    final monday = DateTime(2026, 7, 13); // W29
    final prevMonday = DateTime(2026, 7, 6); // W28

    test('Sunday after 21:00 with no summary this week → this week', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 19, 21, 30),
          lastGeneratedWeek: '2026-W28',
          enabled: true,
        ),
        monday,
      );
    });

    test('Sunday before 21:00 → catch up previous week only', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 19, 20, 0),
          lastGeneratedWeek: null,
          enabled: true,
        ),
        prevMonday,
      );
    });

    test('midweek with previous week done → null', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 15, 12, 0),
          lastGeneratedWeek: '2026-W28',
          enabled: true,
        ),
        isNull,
      );
    });

    test('midweek with previous week missed → previous week', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 15, 12, 0),
          lastGeneratedWeek: '2026-W27',
          enabled: true,
        ),
        prevMonday,
      );
    });

    test('this week already done → null even after Sunday 21:00', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 19, 23, 0),
          lastGeneratedWeek: '2026-W29',
          enabled: true,
        ),
        isNull,
      );
    });

    test('disabled → always null', () {
      expect(
        WeeklySummaryService.dueWeekFor(
          now: DateTime(2026, 7, 19, 23, 0),
          lastGeneratedWeek: null,
          enabled: false,
        ),
        isNull,
      );
    });
  });

  group('mood aggregation', () {
    test('averageScore rounds and ignores gaps', () {
      expect(WeeklySummaryService.averageScore([7, null, 8, null, null, null, 6]),
          7);
      expect(WeeklySummaryService.averageScore(List.filled(7, null)), isNull);
    });

    test('sparkline maps scores to bars and gaps to dots', () {
      final line =
          WeeklySummaryService.sparkline([1, 10, null, 5, null, null, 8]);
      expect(line, '一▁ 二█ 三· 四▄ 五· 六· 日▆');
    });

  });

  group('composeMarkdown', () {
    test('narrative + highlights + curve + next week + mood', () {
      final md = WeeklySummaryService.composeMarkdown({
        'narrative': '这一周过得很充实。',
        'highlights': ['修好了 bug', '散步三次'],
        'mood': '充实 💪',
        'next_week': ['继续周总结功能'],
      }, [
        7, 8, null, 6, null, null, 9,
      ]);
      expect(md, contains('这一周过得很充实。'));
      expect(md, contains('**本周亮点**'));
      expect(md, contains('**下周展望**'));
      expect(md, contains('本周心情:充实 💪'));
    });

    test('missing narrative → null', () {
      expect(
        WeeklySummaryService.composeMarkdown({'highlights': []}, const []),
        isNull,
      );
    });
  });

  group('WeeklySummaryService.generate', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'weekly_summary_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_weekly_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    /// Seeds a daily-summary card. Cards land in today's file bucket
    /// (allocateCardFactId uses now), which is fine: generate() scans the
    /// current week when given this week's Monday.
    Future<String> seedDailySummary(
      String title,
      String text, {
      int? moodScore,
    }) async {
      final fs = FileSystemService.instance;
      final factId = await fs.allocateCardFactId(userId);
      await fs.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: title,
          tags: [dailySummaryTag],
          metadata:
              moodScore != null ? {CardMetadataKeys.moodScore: moodScore} : null,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          uiConfigs: [
            UiConfig(templateId: 'snippet', data: {'text': text}),
          ],
        ),
      );
      return factId;
    }

    test('week without daily summaries skips and marks week done', () async {
      final client = _ScriptedClient(const []);
      final monday = WeeklySummaryService.mondayOf(DateTime.now());
      final ok = await _serviceWith(client).generate(userId, monday);
      expect(ok, isFalse);
      expect(client.calls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('weekly_summary_last_week'),
        WeeklySummaryService.weekKey(monday),
      );
    });

    test('generates a weekly card from daily summaries', () async {
      await seedDailySummary('充实的一天', '爬了山，修了 bug。', moodScore: 8);

      final client = _ScriptedClient([
        '{"title":"充实的一周","narrative":"这周爬了山也写了代码。",'
            '"highlights":["爬山"],"mood":"满足 😊","next_week":["休息"]}'
      ]);
      final service = _serviceWith(client);
      final monday = WeeklySummaryService.mondayOf(DateTime.now());
      final ok = await service.generate(userId, monday);

      expect(ok, isTrue);
      expect(client.calls, 1);

      final prefs = await SharedPreferences.getInstance();
      final key = WeeklySummaryService.weekKey(monday);
      final factId = prefs.getString('weekly_summary_fact_$key');
      expect(factId, isNotNull);

      final card =
          await FileSystemService.instance.readCardFile(userId, factId!);
      expect(card, isNotNull);
      expect(card!.tags, contains(weeklySummaryTag));
      expect(card.title, '充实的一周');
      expect(card.metadata?[CardMetadataKeys.moodScore], 8);
      expect(card.metadata?[CardMetadataKeys.moodLabel], '满足 😊');
      final text = card.uiConfigs.first.data['text'] as String;
      expect(text, contains('**本周亮点**'));
      expect(card.uiConfigs[1].templateId, 'mood_curve');
      expect(card.uiConfigs[1].data['scores'], contains(8));
      expect(card.uiConfigs[1].data['labels'], hasLength(7));
      expect(card.uiConfigs[1].data['average'], 8);
    });

    test('regeneration updates the same card (idempotent)', () async {
      await seedDailySummary('记录', '第一条。', moodScore: 6);

      final client = _ScriptedClient([
        '{"narrative":"第一版周总结。","highlights":[],"mood":"平静"}',
        '{"narrative":"第二版周总结。","highlights":[],"mood":"平静"}',
      ]);
      final service = _serviceWith(client);
      final monday = WeeklySummaryService.mondayOf(DateTime.now());
      await service.generate(userId, monday);
      await service.generate(userId, monday);

      final prefs = await SharedPreferences.getInstance();
      final key = WeeklySummaryService.weekKey(monday);
      final factId = prefs.getString('weekly_summary_fact_$key')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.uiConfigs.first.data['text'], contains('第二版周总结'));
    });

    test('user mood rating on a daily card wins over the AI score', () async {
      final factId =
          await seedDailySummary('一天', '内容。', moodScore: 8);
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        (card) => card.copyWith(metadata: {
          ...?card.metadata,
          CardMetadataKeys.userMoodScore: 3,
        }),
      );

      final client = _ScriptedClient([
        '{"narrative":"周总结。","highlights":[],"mood":"疲惫"}',
      ]);
      final monday = WeeklySummaryService.mondayOf(DateTime.now());
      await _serviceWith(client).generate(userId, monday);

      final prefs = await SharedPreferences.getInstance();
      final key = WeeklySummaryService.weekKey(monday);
      final weeklyId = prefs.getString('weekly_summary_fact_$key')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, weeklyId);
      // Week average must be built from the user's 3, not the AI's 8.
      expect(card!.metadata?[CardMetadataKeys.moodScore], 3);
    });
  });
}
