import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_handlers/embedding_index_handler.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/db/app_database.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('handleEmbeddingIndexUpdateImpl', () {
    late AppDatabase db;
    final context =
        TaskContext(taskId: 't1', taskType: 'embedding_index_update');

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    Map<String, dynamic> insertPayload({
      required String factId,
      required Map<String, dynamic> after,
      String op = 'insert',
    }) {
      return {
        'op': op,
        'ns': DataChangeNs.card,
        'document_key': factId,
        'after': after,
      };
    }

    test('insert: embeds combined text and upserts vector', () async {
      String? capturedText;
      final payload = insertPayload(
        factId: 'f1',
        after: {
          'title': 'My Title',
          'fact': 'the fact content',
          'tags': ['tag1', 'tag2'],
          'insight': {'text': 'insight text'},
        },
      );

      await handleEmbeddingIndexUpdateImpl(
        'user1',
        payload,
        context,
        embedder: (text) async {
          capturedText = text;
          return [0.1, 0.2, 0.3];
        },
        dao: db.cardEmbeddingDao,
      );

      expect(capturedText, contains('My Title'));
      expect(capturedText, contains('the fact content'));
      expect(capturedText, contains('tag1'));
      expect(capturedText, contains('tag2'));
      expect(capturedText, contains('insight text'));

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, hasLength(1));
      expect(rows.first.factId, 'f1');
      expect(rows.first.vector, [0.1, 0.2, 0.3]);
    });

    test('update: re-embeds and upserts', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.0, 0.0],
        model: 'bge-m3',
      );

      final payload = insertPayload(
        op: 'update',
        factId: 'f1',
        after: {
          'title': 'Updated Title',
          'fact': 'updated fact',
          'tags': <String>[],
        },
      );

      await handleEmbeddingIndexUpdateImpl(
        'user1',
        payload,
        context,
        embedder: (text) async => [0.9, 0.9],
        dao: db.cardEmbeddingDao,
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, hasLength(1));
      expect(rows.first.vector, [0.9, 0.9]);
    });

    test('delete: removes embedding by factId', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1, 0.2],
        model: 'bge-m3',
      );

      final payload = {
        'op': 'delete',
        'ns': DataChangeNs.card,
        'document_key': 'f1',
      };

      await handleEmbeddingIndexUpdateImpl(
        'user1',
        payload,
        context,
        embedder: (text) async {
          fail('embedder should not be called on delete');
        },
        dao: db.cardEmbeddingDao,
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, isEmpty);
    });

    test('embed returning null throws EmbeddingUnavailableException and does not upsert',
        () async {
      final payload = insertPayload(
        factId: 'f1',
        after: {'title': 'T', 'fact': 'F', 'tags': <String>[]},
      );

      await expectLater(
        () => handleEmbeddingIndexUpdateImpl(
          'user1',
          payload,
          context,
          embedder: (text) async => null,
          dao: db.cardEmbeddingDao,
        ),
        throwsA(isA<EmbeddingUnavailableException>()),
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, isEmpty);
    });

    test('non-card namespace is a no-op', () async {
      final payload = {
        'op': 'insert',
        'ns': DataChangeNs.pkmFile,
        'document_key': 'some/path.md',
        'after': {'content': 'irrelevant'},
      };

      await handleEmbeddingIndexUpdateImpl(
        'user1',
        payload,
        context,
        embedder: (text) async {
          fail('embedder should not be called for non-card namespace');
        },
        dao: db.cardEmbeddingDao,
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, isEmpty);
    });
  });
}
