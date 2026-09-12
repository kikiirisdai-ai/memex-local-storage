import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/daily_summary_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
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
    return ModelMessage(model: 'stub', textOutput: responses[index]);
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

DailySummaryService _serviceWith(_ScriptedClient client) {
  return DailySummaryService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub'),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('DailySummaryService.dueDateFor', () {
    final evening = DateTime(2026, 7, 17, 21, 30);
    final morning = DateTime(2026, 7, 17, 9, 0);

    test('after 21:00 with no summary today → today', () {
      expect(
        DailySummaryService.dueDateFor(
            now: evening, lastGeneratedDate: '2026-07-16', enabled: true),
        DateTime(2026, 7, 17),
      );
    });

    test('after 21:00 but today already done → null', () {
      expect(
        DailySummaryService.dueDateFor(
            now: evening, lastGeneratedDate: '2026-07-17', enabled: true),
        isNull,
      );
    });

    test('morning with yesterday missed → yesterday', () {
      expect(
        DailySummaryService.dueDateFor(
            now: morning, lastGeneratedDate: '2026-07-15', enabled: true),
        DateTime(2026, 7, 16),
      );
      expect(
        DailySummaryService.dueDateFor(
            now: morning, lastGeneratedDate: null, enabled: true),
        DateTime(2026, 7, 16),
      );
    });

    test('morning with yesterday done → null', () {
      expect(
        DailySummaryService.dueDateFor(
            now: morning, lastGeneratedDate: '2026-07-16', enabled: true),
        isNull,
      );
    });

    test('disabled → always null', () {
      expect(
        DailySummaryService.dueDateFor(
            now: evening, lastGeneratedDate: null, enabled: false),
        isNull,
      );
    });
  });

  group('composeMarkdown', () {
    test('narrative + highlights + tomorrow + mood', () {
      final markdown = DailySummaryService.composeMarkdownForTesting({
        'narrative': '今天很充实。',
        'highlights': ['修好了 bug', '录音功能上线'],
        'tomorrow': ['继续每日总结'],
        'mood': '满足 😊',
      });
      expect(markdown, contains('今天很充实。'));
      expect(markdown, contains('**今日亮点**'));
      expect(markdown, contains('- 修好了 bug'));
      expect(markdown, contains('**明日待办**'));
      expect(markdown, contains('今日心情:满足 😊'));
    });

    test('missing narrative → null', () {
      expect(
        DailySummaryService.composeMarkdownForTesting(
            {'highlights': <String>[]}),
        isNull,
      );
    });
  });

  group('DailySummaryService.generate', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;
    final date = DateTime(2026, 7, 17);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'daily_summary_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_daily_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    Future<String> seedCard(String title, String text) async {
      final fs = FileSystemService.instance;
      final factId = await fs.allocateCardFactId(userId);
      await fs.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: title,
          timestamp: DateTime(2026, 7, 17, 10).millisecondsSinceEpoch ~/ 1000,
          uiConfigs: [
            UiConfig(templateId: 'snippet', data: {'text': text}),
          ],
        ),
      );
      return factId;
    }

    test('empty day skips generation and marks date done', () async {
      final client = _ScriptedClient(const []);
      final ok = await _serviceWith(client).generate(userId, date);
      expect(ok, isFalse);
      expect(client.calls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('daily_summary_last_date'), '2026-07-17');
    });

    test('generates a summary card from the day cards', () async {
      // Seeded cards are dated "today" (allocateCardFactId uses now), so
      // summarize the real today in this test.
      final today = DateTime.now();
      await seedCard('爬山', '今天去爬山，风景很好。');
      await seedCard('修 bug', '修好了快速通道的场景判断。');

      final client = _ScriptedClient([
        '{"title":"充实的一天","narrative":"今天爬了山，还修好了一个关键 bug。",'
            '"highlights":["爬山","修 bug"],"mood":"满足 😊","tomorrow":[]}'
      ]);
      final service = _serviceWith(client);
      final ok = await service.generate(userId, today);

      expect(ok, isTrue);
      expect(client.calls, 1);

      final prefs = await SharedPreferences.getInstance();
      final key = DailySummaryService.dateKey(today);
      final factId = prefs.getString('daily_summary_fact_$key');
      expect(factId, isNotNull);

      final card =
          await FileSystemService.instance.readCardFile(userId, factId!);
      expect(card, isNotNull);
      expect(card!.tags, contains('DailySummary'));
      expect(card.title, '充实的一天');
      final text = card.uiConfigs.first.data['text'] as String;
      expect(text, contains('今天爬了山'));
      expect(text, contains('**今日亮点**'));
    });

    test('summary card stores structured mood metadata', () async {
      final today = DateTime.now();
      await seedCard('爬山', '今天去爬山，风景很好。');

      final client = _ScriptedClient([
        '{"title":"好天气","narrative":"今天爬山看了瀑布，心情舒畅。",'
            '"highlights":["爬山"],"mood":"满足 😊","mood_score":8,"tomorrow":[]}'
      ]);
      await _serviceWith(client).generate(userId, today);

      final prefs = await SharedPreferences.getInstance();
      final key = DailySummaryService.dateKey(today);
      final factId = prefs.getString('daily_summary_fact_$key')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata, {'mood_score': 8, 'mood_label': '满足 😊'});
    });

    test('regeneration clears stale AI mood when new summary has none',
        () async {
      final today = DateTime.now();
      await seedCard('爬山', '今天去爬山。');
      await _serviceWith(_ScriptedClient([
        '{"narrative":"爬山愉快。","highlights":["爬山"],'
            '"mood":"满足","mood_score":8,"tomorrow":[]}'
      ])).generate(userId, today);
      final prefs = await SharedPreferences.getInstance();
      final factId =
          prefs.getString('daily_summary_fact_${DailySummaryService.dateKey(today)}')!;
      var card = await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata?['mood_score'], 8);

      // Regenerate the same day with a summary that has no mood.
      await _serviceWith(_ScriptedClient([
        '{"narrative":"平常的一天。","highlights":[],"tomorrow":[]}'
      ])).generate(userId, today);
      card = await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata?['mood_score'], isNull,
          reason: 'stale AI mood_score must be cleared on regeneration');
      expect(card.metadata?['mood_label'], isNull);
    });

    test('regeneration preserves user_mood_score but clears AI mood',
        () async {
      final today = DateTime.now();
      await seedCard('记录', '普通一天。');
      await _serviceWith(_ScriptedClient([
        '{"narrative":"一天。","highlights":[],"mood":"平静",'
            '"mood_score":6,"tomorrow":[]}'
      ])).generate(userId, today);
      final prefs = await SharedPreferences.getInstance();
      final factId =
          prefs.getString('daily_summary_fact_${DailySummaryService.dateKey(today)}')!;
      // User manually rates the card.
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        (c) => c.copyWith(
          metadata: {...?c.metadata, 'user_mood_score': 3},
        ),
      );
      // Regenerate with no AI mood.
      await _serviceWith(_ScriptedClient([
        '{"narrative":"又一天。","highlights":[],"tomorrow":[]}'
      ])).generate(userId, today);
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata?['user_mood_score'], 3,
          reason: 'user manual rating must survive regeneration');
      expect(card.metadata?['mood_score'], isNull,
          reason: 'AI mood_score must be cleared on regeneration');
    });

    test('invalid mood_score keeps label but drops score', () async {
      final today = DateTime.now();
      await seedCard('记录', '普通的一天。');

      final client = _ScriptedClient([
        '{"narrative":"平静的一天。","highlights":[],"mood":"平静",'
            '"mood_score":"unknown","tomorrow":[]}'
      ]);
      await _serviceWith(client).generate(userId, today);

      final prefs = await SharedPreferences.getInstance();
      final key = DailySummaryService.dateKey(today);
      final factId = prefs.getString('daily_summary_fact_$key')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.metadata, {'mood_label': '平静'});
    });

    test('regeneration updates the same card (idempotent)', () async {
      final today = DateTime.now();
      await seedCard('记录', '第一条记录。');

      final client = _ScriptedClient([
        '{"narrative":"第一版总结。","highlights":[],"mood":"平静"}',
        '{"narrative":"第二版总结。","highlights":[],"mood":"平静"}',
      ]);
      final service = _serviceWith(client);
      await service.generate(userId, today);
      await service.generate(userId, today);

      final prefs = await SharedPreferences.getInstance();
      final key = DailySummaryService.dateKey(today);
      final factId = prefs.getString('daily_summary_fact_$key')!;
      final card =
          await FileSystemService.instance.readCardFile(userId, factId);
      expect(card!.uiConfigs.first.data['text'], contains('第二版总结'));

      // Exactly one DailySummary card exists for the day.
      final dir = Directory(
          '${tempRoot.path}/workspace/_$userId/Cards/${today.year.toString().padLeft(4, '0')}/${today.month.toString().padLeft(2, '0')}');
      var summaryCount = 0;
      for (final f in dir.listSync().whereType<File>()) {
        if (f.readAsStringSync().contains('DailySummary')) summaryCount++;
      }
      expect(summaryCount, 1);
    });

    test('summary cards are excluded from their own input', () async {
      final today = DateTime.now();
      await seedCard('记录', '普通记录。');
      final client = _ScriptedClient([
        '{"narrative":"总结第一版。","highlights":[]}',
        '{"narrative":"总结第二版。","highlights":[]}',
      ]);
      final service = _serviceWith(client);
      await service.generate(userId, today);

      final context =
          await service.collectDayContext(userId, today) ?? '';
      expect(context, contains('普通记录'));
      expect(context, isNot(contains('总结第一版')));
    });
  });
}
