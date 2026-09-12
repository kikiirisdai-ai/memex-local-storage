import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

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
  }) {
    throw UnimplementedError();
  }
}

void main() {
  late Directory tempDir;
  late String userId;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    userId = 'memory_mgmt_user_${DateTime.now().microsecondsSinceEpoch}';
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_memory_mgmt_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MemoryManagement buildManagement({List<String?> responses = const []}) {
    return MemoryManagement(
      userId: userId,
      sourceAgent: 'memory_agent',
      client: _ScriptedClient(responses),
      modelConfig: ModelConfig(model: 'stub-model'),
    );
  }

  Future<List<dynamic>> readRecentBuffer() async {
    final memoryPath = path.join(
      FileSystemService.instance.getSystemPath(userId),
      'memory',
      'memory.json',
    );
    final content = await File(memoryPath).readAsString();
    final mem = jsonDecode(content) as Map<String, dynamic>;
    return mem['recent_buffer'] as List<dynamic>;
  }

  test('forceConsolidate is a no-op on an empty buffer', () async {
    final client = _ScriptedClient([]);
    final management = MemoryManagement(
      userId: userId,
      sourceAgent: 'memory_agent',
      client: client,
      modelConfig: ModelConfig(model: 'stub-model'),
    );

    final consolidated = await management.forceConsolidate();

    expect(consolidated, isFalse);
    expect(client.calls, 0);
  });

  test('forceConsolidate archives the buffer regardless of the normal '
      'threshold', () async {
    final management = buildManagement(
      responses: ['Identity: enjoys hiking.'],
    );

    await management.appendMemories(['Went hiking today.']);

    final consolidated = await management.forceConsolidate();

    expect(consolidated, isTrue);
  });

  test('appendMemories does not auto-consolidate below the threshold',
      () async {
    final client = _ScriptedClient([]);
    final management = MemoryManagement(
      userId: userId,
      sourceAgent: 'memory_agent',
      client: client,
      modelConfig: ModelConfig(model: 'stub-model'),
    );

    await management.appendMemories(['Just one memory.']);

    // Below the default threshold of 10 — no summarization call should
    // have been made.
    expect(client.calls, 0);
  });

  test('appendMemories skips a memory that already exists in the buffer',
      () async {
    final management = buildManagement();

    await management.appendMemories(['Enjoys hiking.']);
    await management.appendMemories(['Enjoys hiking.']);

    final buffer = await readRecentBuffer();
    expect(buffer, hasLength(1));
  });

  test('appendMemories dedup is case-insensitive and trims whitespace',
      () async {
    final management = buildManagement();

    await management.appendMemories(['Enjoys hiking.']);
    final result = await management.appendMemories(['  ENJOYS HIKING.  ']);

    final buffer = await readRecentBuffer();
    expect(buffer, hasLength(1));
    expect(result, contains('No new memories added'));
  });

  test('appendMemories dedupes within the same batch too', () async {
    final management = buildManagement();

    await management.appendMemories(['Enjoys hiking.', 'Enjoys hiking.']);

    final buffer = await readRecentBuffer();
    expect(buffer, hasLength(1));
  });

  test('appendMemories still adds genuinely new memories alongside '
      'duplicates', () async {
    final management = buildManagement();

    await management.appendMemories(['Enjoys hiking.']);
    final result =
        await management.appendMemories(['Enjoys hiking.', 'Owns a cat.']);

    final buffer = await readRecentBuffer();
    expect(buffer, hasLength(2));
    expect(result, contains('Memories appended successfully'));
    expect(result, contains('Skipped 1 duplicate'));
  });

  test('appendMemories skips a paraphrased near-duplicate, not just exact '
      'matches', () async {
    final management = buildManagement();

    await management.appendMemories(['Enjoys hiking on weekends.']);
    await management.appendMemories(['Likes hiking on the weekends.']);

    final buffer = await readRecentBuffer();
    expect(buffer, hasLength(1));
  });

  group('isNearDuplicateMemory', () {
    test('treats identical text as a duplicate', () {
      expect(
        isNearDuplicateMemory('Enjoys hiking.', 'Enjoys hiking.'),
        isTrue,
      );
    });

    test('treats a close paraphrase as a duplicate', () {
      expect(
        isNearDuplicateMemory(
          'Enjoys hiking on weekends.',
          'Likes hiking on the weekends.',
        ),
        isTrue,
      );
    });

    test('does not flag unrelated memories as duplicates', () {
      expect(
        isNearDuplicateMemory('Enjoys hiking.', 'Owns a MacBook Pro M3.'),
        isFalse,
      );
    });

    test('works for Chinese text without whitespace tokenization', () {
      expect(
        isNearDuplicateMemory('喜欢周末去爬山', '周末喜欢去爬山'),
        isTrue,
      );
      expect(
        isNearDuplicateMemory('喜欢周末去爬山', '用的是苹果笔记本电脑'),
        isFalse,
      );
    });
  });
}
