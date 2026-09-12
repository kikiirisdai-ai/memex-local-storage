import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/agent_image_attachment.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/quick_capture_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.responses);

  /// Returned in order; null entries simulate an empty model response.
  final List<String?> responses;
  int calls = 0;

  /// Every `messages` argument this client was called with, in order, so
  /// tests can inspect exactly what was sent to the model (e.g. the
  /// system-prompt goal-list injection).
  final List<List<LLMMessage>> capturedMessages = [];

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    capturedMessages.add(messages);
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

class _ThrowingClient extends _ScriptedClient {
  _ThrowingClient() : super(const []);

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    throw Exception('network down');
  }
}

QuickCaptureService _serviceWith(_ScriptedClient client) {
  return QuickCaptureService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub-model'),
    ),
  );
}

QuickCaptureService _serviceWithGoals(
  _ScriptedClient client,
  List<Goal> activeGoals,
) {
  return QuickCaptureService.forTesting(
    resourcesProvider: () async => (
      client: client as LLMClient,
      modelConfig: ModelConfig(model: 'stub-model'),
    ),
    activeGoalsProvider: () async => activeGoals,
  );
}

Goal _goal({
  required String id,
  required String title,
  required String goalType,
}) {
  return Goal(
    id: id,
    userId: 'u1',
    title: title,
    goalType: goalType,
    targetValue: goalType == 'quantitative' ? 20 : null,
    currentValue: 0,
    unit: null,
    deadline: null,
    status: 'active',
    createdAt: 0,
    completedAt: null,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('QuickCaptureService.isEligible', () {
    bool eligible({
      String scene = 'assistant',
      String agentName = 'memex_agent',
      String message = '今天去爬山了',
      List<Map<String, String>>? refs,
      int imageCount = 0,
      bool isQuickQuery = false,
      String runMode = 'auto',
    }) {
      return QuickCaptureService.isEligible(
        scene: scene,
        agentName: agentName,
        message: message,
        refs: refs,
        imageCount: imageCount,
        isQuickQuery: isQuickQuery,
        runMode: runMode,
      );
    }

    test('accepts a plain short text fragment', () {
      expect(eligible(), isTrue);
    });

    test('accepts the main-screen agent dialog scene', () {
      expect(eligible(scene: 'super_agent_home'), isTrue);
    });

    test('accepts fragments with up to nine images', () {
      expect(eligible(imageCount: 1), isTrue);
      expect(eligible(imageCount: 9), isTrue);
    });

    test('rejects fragments with more than nine images', () {
      expect(eligible(imageCount: 10), isFalse);
    });

    test('rejects non-assistant scenes', () {
      expect(eligible(scene: 'character'), isFalse);
    });

    test('rejects custom agent names', () {
      expect(eligible(agentName: 'my_custom_agent'), isFalse);
    });

    test('rejects quick queries and non-auto run modes', () {
      expect(eligible(isQuickQuery: true), isFalse);
      expect(eligible(runMode: 'record'), isFalse);
    });

    test('rejects messages with refs', () {
      expect(
        eligible(refs: [
          {'type': 'card', 'id': 'x'}
        ]),
        isFalse,
      );
    });

    test('rejects empty and oversized messages', () {
      expect(eligible(message: '   '), isFalse);
      expect(eligible(message: 'a' * 501), isFalse);
      expect(eligible(message: 'a' * 500), isTrue);
      // Empty text is fine when an image carries the content.
      expect(eligible(message: '', imageCount: 1), isTrue);
    });
  });

  group('QuickCaptureService JSON parsing', () {
    test('parses a bare JSON object', () {
      final parsed = QuickCaptureService.parseDecisionForTesting(
          '{"type":"reply","text":"hi"}');
      expect(parsed?['type'], 'reply');
    });

    test('parses JSON wrapped in fences or prose', () {
      final parsed = QuickCaptureService.parseDecisionForTesting(
          'Sure!\n```json\n{"type":"escalate"}\n```');
      expect(parsed?['type'], 'escalate');
    });

    test('returns null for garbage, non-object, and missing type', () {
      expect(QuickCaptureService.parseDecisionForTesting('not json'), isNull);
      expect(QuickCaptureService.parseDecisionForTesting(null), isNull);
      expect(QuickCaptureService.parseDecisionForTesting('[1,2]'), isNull);
      expect(QuickCaptureService.parseDecisionForTesting('{"foo":1}'), isNull);
    });
  });

  group('QuickCaptureService.run', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'quick_capture_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_quick_capture_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    test('goal suggestion: quantitative match with a model-guessed delta',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"读书","text":"看完了三章书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":[{"goal_id":"goal-1","delta":3}],'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-1', title: '读书', goalType: 'quantitative')],
      );

      final result = await service.run(
        userId: userId,
        message: '看完了三章书',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, hasLength(1));
      expect(result.goalSuggestions.first.goalId, 'goal-1');
      expect(result.goalSuggestions.first.goalTitle, '读书');
      expect(result.goalSuggestions.first.goalType, 'quantitative');
      expect(result.goalSuggestions.first.delta, 3);
    });

    test('goal suggestion: binary match ignores any delta the model sent',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"游泳","text":"终于学会游泳了！",'
            '"tags":["运动"],"mood_score":9,"mood_label":"开心",'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":[{"goal_id":"goal-2","delta":5}],'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-2', title: '学会游泳', goalType: 'binary')],
      );

      final result = await service.run(
        userId: userId,
        message: '终于学会游泳了',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, hasLength(1));
      expect(result.goalSuggestions.first.goalType, 'binary');
      expect(result.goalSuggestions.first.delta, isNull);
    });

    test('goal suggestion: unknown goal_id is dropped', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"读书","text":"看了会书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":[{"goal_id":"goal-does-not-exist","delta":1}],'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-1', title: '读书', goalType: 'quantitative')],
      );

      final result = await service.run(
        userId: userId,
        message: '看了会书',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, isEmpty);
    });

    test('goal suggestion: non-positive/non-finite delta on a quantitative '
        'goal is dropped', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"读书","text":"看了会书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":[{"goal_id":"goal-1","delta":"NaN"}],'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-1', title: '读书', goalType: 'quantitative')],
      );

      final result = await service.run(
        userId: userId,
        message: '看了会书',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, isEmpty);
    });

    test('goal suggestion: no active goals means no suggestions and no '
        'crash', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"日常","text":"今天很平淡。",'
            '"tags":[],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(client, const []);

      final result = await service.run(
        userId: userId,
        message: '今天很平淡',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      expect(result.goalSuggestions, isEmpty);
    });

    test('goal suggestion: at most 3 kept even if the model returns more',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"x","text":"x.",'
            '"tags":[],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":['
            '{"goal_id":"g1","delta":1},{"goal_id":"g2","delta":1},'
            '{"goal_id":"g3","delta":1},{"goal_id":"g4","delta":1}'
            '],"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(client, [
        _goal(id: 'g1', title: 'a', goalType: 'quantitative'),
        _goal(id: 'g2', title: 'b', goalType: 'quantitative'),
        _goal(id: 'g3', title: 'c', goalType: 'quantitative'),
        _goal(id: 'g4', title: 'd', goalType: 'quantitative'),
      ]);

      final result = await service.run(
        userId: userId,
        message: 'x',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, hasLength(3));
    });

    test('goal suggestion: duplicate goal_id in model output keeps only the '
        'first occurrence', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"读书","text":"看完了三章书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"goal_suggestions":['
            '{"goal_id":"goal-1","delta":3},{"goal_id":"goal-1","delta":7}'
            '],"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-1', title: '读书', goalType: 'quantitative')],
      );

      final result = await service.run(
        userId: userId,
        message: '看完了三章书',
        userMessageTime: DateTime.now(),
      );

      expect(result.goalSuggestions, hasLength(1));
      expect(result.goalSuggestions.first.goalId, 'goal-1');
      // First-wins: the first occurrence's delta is kept, not the second.
      expect(result.goalSuggestions.first.delta, 3);
    });

    test('goal-list injection: active goals appear in the system prompt sent '
        'to the model', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"读书","text":"看了会书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"reply":"✅"}'
      ]);
      final service = _serviceWithGoals(
        client,
        [_goal(id: 'goal-1', title: '读书', goalType: 'quantitative')],
      );

      await service.run(
        userId: userId,
        message: '看了会书',
        userMessageTime: DateTime.now(),
      );

      expect(client.capturedMessages, isNotEmpty);
      final firstCallMessages = client.capturedMessages.first;
      final systemMessage =
          firstCallMessages.whereType<SystemMessage>().single;
      expect(systemMessage.content, contains('id=goal-1'));
      expect(systemMessage.content, contains('title="读书"'));
    });

    test('card decision writes a completed snippet card', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"爬山","text":"今天去爬山，风景很好。",'
            '"tags":["运动"],"reply":"已记录你的爬山时光 ✅"}'
      ]);
      final service = _serviceWith(client);

      final result = await service.run(
        userId: userId,
        message: '今天去爬山了 风景很好',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      expect(result.cardFactId, isNotNull);
      expect(result.replyText, '已记录你的爬山时光 ✅');
      expect(client.calls, 1);

      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card, isNotNull);
      expect(card!.status, 'completed');
      expect(card.title, '爬山');
      expect(card.tags, ['运动']);
      expect(card.fact, '今天去爬山了 风景很好');
      expect(card.uiConfigs, hasLength(1));
      expect(card.uiConfigs.first.templateId, 'snippet');
      expect(card.uiConfigs.first.data['text'], '今天去爬山，风景很好。');
    });

    test('card decision enqueues the new fact for long-term memory sync',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"爬山","text":"今天去爬山，风景很好。",'
            '"tags":["运动"],"reply":"已记录你的爬山时光 ✅"}'
      ]);
      final service = _serviceWith(client);

      final result = await service.run(
        userId: userId,
        message: '今天去爬山了 风景很好',
        userMessageTime: DateTime.now(),
      );

      final pendingFile = File(path.join(
        FileSystemService.instance.getSystemPath(userId),
        'memory',
        'memory_sync_pending.json',
      ));
      expect(await pendingFile.exists(), isTrue);
      final pending = jsonDecode(await pendingFile.readAsString()) as List;
      expect(pending, contains(result.cardFactId));
    });

    test('card decision with mood writes mood metadata', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"爬山","text":"今天去爬山，太开心了！",'
            '"tags":["运动"],"mood_score":9,"mood_label":"开心","reply":"已记录 ✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '今天去爬山了 太开心了',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata, {'mood_score': 9, 'mood_label': '开心'});
    });

    test('null or invalid mood produces no metadata', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"买菜","text":"买了西红柿和鸡蛋。",'
            '"tags":["生活"],"mood_score":null,"mood_label":null,"reply":"✅"}',
        '{"type":"card","title":"买菜","text":"买了西红柿和鸡蛋。",'
            '"tags":["生活"],"mood_score":99,"mood_label":"开心","reply":"✅"}',
      ]);
      final service = _serviceWith(client);

      for (var i = 0; i < 2; i++) {
        final result = await service.run(
          userId: userId,
          message: '买了西红柿和鸡蛋',
          userMessageTime: DateTime.now(),
        );
        expect(result.outcome, QuickCaptureOutcome.card);
        final card = await FileSystemService.instance
            .readCardFile(userId, result.cardFactId!);
        expect(card!.metadata, isNull,
            reason: 'response $i must not produce mood metadata');
      }
    });

    test('media review writes media_card with status/rating/comment', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"奥本海默","text":"刚看完《奥本海默》，太震撼了。",'
            '"tags":["电影"],"mood_score":9,"mood_label":"震撼",'
            '"media_type":"movie","media_status":"done","media_rating":9,'
            '"media_comment":"太震撼了","media_author":"诺兰","media_year":"2023",'
            '"reply":"已记录 ✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '刚看完《奥本海默》太震撼了',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata?['media_type'], 'movie');
      expect(card.metadata?['media_status'], 'done');
      expect(card.metadata?['media_rating'], 9);
      expect(card.metadata?['media_comment'], '太震撼了');
      expect(card.metadata?['media_author'], '诺兰');
      expect(card.metadata?['media_year'], '2023');
      expect(card.uiConfigs, hasLength(1));
      expect(card.uiConfigs.first.templateId, 'media_card');
      expect(card.uiConfigs.first.data['media_type'], 'movie');
      expect(card.uiConfigs.first.data['media_status'], 'done');
      expect(card.uiConfigs.first.data['comment'], '太震撼了');
      expect(card.uiConfigs.first.data['rating'], 9);
    });

    test('media review with bare-number media_year does not escalate',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"奥本海默","text":"刚看完《奥本海默》，太震撼了。",'
            '"tags":["电影"],"mood_score":9,"mood_label":"震撼",'
            '"media_type":"movie","media_status":"done","media_rating":9,'
            '"media_comment":"太震撼了","media_author":"诺兰","media_year":2023,'
            '"reply":"已记录 ✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '刚看完《奥本海默》太震撼了',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata?['media_year'], '2023');
    });

    test('media without progress writes doing/no-rating', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"三体","text":"在看《三体》。",'
            '"tags":["剧集"],"mood_score":null,"mood_label":null,'
            '"media_type":"tv","media_status":"doing","media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"reply":"已记录 ✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '在看三体',
        userMessageTime: DateTime.now(),
      );

      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata?['media_type'], 'tv');
      expect(card.metadata?['media_status'], 'doing');
      expect(card.metadata!.containsKey('media_rating'), isFalse);
      expect(card.metadata!.containsKey('media_comment'), isFalse);
      expect(card.uiConfigs.first.templateId, 'media_card');
      expect(card.uiConfigs.first.data.containsKey('comment'), isFalse);
      expect(card.uiConfigs.first.data.containsKey('rating'), isFalse);
    });

    test('non-media fragment produces no media metadata', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"买菜","text":"买了西红柿和鸡蛋。",'
            '"tags":["生活"],"mood_score":null,"mood_label":null,'
            '"media_type":null,"media_status":null,"media_rating":null,'
            '"media_comment":null,"media_author":null,"media_year":null,'
            '"reply":"✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '买了西红柿和鸡蛋',
        userMessageTime: DateTime.now(),
      );

      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata, isNull);
      expect(card.uiConfigs.first.templateId, 'snippet');
    });

    test(
        'media metadata still written when a photo is attached, template '
        'stays image-first', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"看完的书","text":"读完了这本书。",'
            '"tags":["读书"],"mood_score":null,"mood_label":null,'
            '"media_type":"book","media_status":"done","media_rating":8,'
            '"media_comment":"不错","media_author":null,"media_year":null,'
            '"reply":"✅"}'
      ]);
      final service = _serviceWith(client);
      final result = await service.run(
        userId: userId,
        message: '读完了这本书',
        userMessageTime: DateTime.now(),
        images: [
          InlineAgentImage(
            base64Data: base64Encode(utf8.encode('fake-image-bytes')),
            mimeType: 'image/png',
          ),
        ],
        // Template selection keys off imageFsFilenames (the persisted asset
        // list), not the inline `images` sent to the model — the brief's
        // original test only set `images`, which wouldn't exercise the
        // "photo attached" path in _writeCard at all. Add the fs filename to
        // match how the real capture flow (and the existing photo test
        // above) attaches an image.
        imageFsFilenames: ['book_photo.jpg'],
      );

      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata?['media_type'], 'book');
      expect(card.uiConfigs.first.templateId, 'snapshot');
    });

    test('card decision with photos writes snapshot/gallery and assets',
        () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"瀑布","text":"冰岛瀑布的照片。",'
            '"tags":["旅行"],"reply":"已记录 ✅"}'
      ]);
      final service = _serviceWith(client);

      final result = await service.run(
        userId: userId,
        message: '',
        images: [
          const InlineAgentImage(base64Data: 'aGk=', mimeType: 'image/jpeg'),
          const InlineAgentImage(base64Data: 'aGk=', mimeType: 'image/jpeg'),
        ],
        imageFsFilenames: ['img_a.jpg', 'img_b.jpg'],
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.assets, [
        '![image](fs://img_a.jpg)',
        '![image](fs://img_b.jpg)',
      ]);
      expect(card.uiConfigs.first.templateId, 'gallery');
      expect(card.uiConfigs.first.data['image_urls'],
          ['fs://img_a.jpg', 'fs://img_b.jpg']);
      expect(card.uiConfigs.last.templateId, 'snippet');
    });

    test('voice note writes an audio card with transcript', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"晨间散步","text":"今天早上出门散步，天气很好。",'
            '"tags":["生活"],"reply":"已记录 ✅"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '今天早上出门散步 天气很好',
        audioFsFilename: 'audio_123.wav',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.assets, contains('[audio](fs://audio_123.wav)'));
      expect(card.uiConfigs.last.templateId, 'audio_card');
      expect(card.uiConfigs.last.data['audioUrl'], 'fs://audio_123.wav');
      expect(card.uiConfigs.last.data['content'], '今天早上出门散步，天气很好。');
    });

    test('voice note misclassified as reply is coerced into a card', () async {
      final client = _ScriptedClient(['{"type":"reply","text":"听起来不错！"}']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '今天心情不错',
        audioFsFilename: 'audio_456.wav',
        userMessageTime: DateTime.now(),
      );

      // Voice notes must always become cards, never chat replies.
      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.uiConfigs.last.templateId, 'audio_card');
      expect(card.uiConfigs.last.data['content'], '今天心情不错');
      expect(card.title, '今天心情不错');
    });

    test('reply decision returns text without writing a card', () async {
      final client = _ScriptedClient(['{"type":"reply","text":"我能听懂英语！"}']);
      final service = _serviceWith(client);

      final result = await service.run(
        userId: userId,
        message: 'Can you understand English?',
        userMessageTime: DateTime.now(),
      );

      expect(result.outcome, QuickCaptureOutcome.reply);
      expect(result.replyText, '我能听懂英语！');
      expect(result.cardFactId, isNull);
    });

    test('escalate decision passes through', () async {
      final client = _ScriptedClient(['{"type":"escalate"}']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '把上周的卡片整理成一个项目',
        userMessageTime: DateTime.now(),
      );
      expect(result.outcome, QuickCaptureOutcome.escalate);
    });

    test('malformed JSON retries once, then valid answer wins', () async {
      final client = _ScriptedClient([
        'oops not json at all',
        '{"type":"reply","text":"second try"}',
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: 'hello',
        userMessageTime: DateTime.now(),
      );
      expect(client.calls, 2);
      expect(result.outcome, QuickCaptureOutcome.reply);
      expect(result.replyText, 'second try');
    });

    test('malformed JSON twice escalates', () async {
      final client = _ScriptedClient(['garbage', 'still garbage']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: 'hello',
        userMessageTime: DateTime.now(),
      );
      expect(client.calls, 2);
      expect(result.outcome, QuickCaptureOutcome.escalate);
    });

    test('LLM exception escalates instead of throwing', () async {
      final result = await _serviceWith(_ThrowingClient()).run(
        userId: userId,
        message: 'hello',
        userMessageTime: DateTime.now(),
      );
      expect(result.outcome, QuickCaptureOutcome.escalate);
    });

    test('card decision with empty text escalates without leftover card',
        () async {
      final client = _ScriptedClient(['{"type":"card","text":"","title":"x"}']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: 'something',
        userMessageTime: DateTime.now(),
      );
      expect(result.outcome, QuickCaptureOutcome.escalate);
    });

    test('forceCard writes card even when model says reply', () async {
      final client = _ScriptedClient(['{"type":"reply","text":"haha ok"}']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '随便写点',
        userMessageTime: DateTime(2026, 8, 30),
        forceCard: true,
      );
      expect(result.outcome, QuickCaptureOutcome.card);
    });

    test('forceCard writes card even when model says escalate', () async {
      final client = _ScriptedClient(['{"type":"escalate"}']);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '随便写点',
        userMessageTime: DateTime(2026, 8, 30),
        forceCard: true,
      );
      expect(result.outcome, QuickCaptureOutcome.card);
    });

    test('originalText + polishedStyle land in card metadata', () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"t","text":"润色后","tags":[],'
            '"mood_score":null,"mood_label":null,"reply":"ok"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '润色后',
        userMessageTime: DateTime(2026, 8, 30),
        forceCard: true,
        originalText: '原始的话',
        polishedStyle: 'literary',
      );
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      expect(card!.metadata?[CardMetadataKeys.originalText], '原始的话');
      expect(card.metadata?[CardMetadataKeys.polishedStyle], 'literary');
    });

    test(
        'verbatimText uses the message as-is for the card snippet, not the '
        "model's rewrite", () async {
      final client = _ScriptedClient([
        '{"type":"card","title":"标题","text":"模型改写后的文字完全不同",'
            '"tags":["生活"],"mood_score":8,"mood_label":"开心","reply":"ok"}'
      ]);
      final result = await _serviceWith(client).run(
        userId: userId,
        message: '用户编辑后的原文',
        userMessageTime: DateTime(2026, 8, 30),
        forceCard: true,
        verbatimText: true,
      );

      expect(result.outcome, QuickCaptureOutcome.card);
      final card = await FileSystemService.instance
          .readCardFile(userId, result.cardFactId!);
      // Snippet body is the user's message verbatim, not the model's text.
      expect(card!.uiConfigs.first.templateId, 'snippet');
      expect(card.uiConfigs.first.data['text'], '用户编辑后的原文');
      // Title/mood still come from the model decision.
      expect(card.title, '标题');
      expect(card.metadata?[CardMetadataKeys.moodLabel], '开心');
    });
  });
}
