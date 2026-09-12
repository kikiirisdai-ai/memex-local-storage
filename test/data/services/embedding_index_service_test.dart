import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/embedding_index_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('EmbeddingIndexService.shouldEnqueueEmbeddingIndexUpdate', () {
    final service = EmbeddingIndexService.instance;

    test('insert always enqueues', () {
      final record = DataChangeRecord(
        op: DataChangeOp.insert,
        ns: DataChangeNs.card,
        documentKey: 'f1',
        after: {'title': 'T'},
      );
      expect(service.shouldEnqueueEmbeddingIndexUpdate(record), isTrue);
    });

    test('delete always enqueues', () {
      final record = DataChangeRecord(
        op: DataChangeOp.delete,
        ns: DataChangeNs.card,
        documentKey: 'f1',
      );
      expect(service.shouldEnqueueEmbeddingIndexUpdate(record), isTrue);
    });

    test('update enqueues when an indexed field changed', () {
      final record = DataChangeRecord(
        op: DataChangeOp.update,
        ns: DataChangeNs.card,
        documentKey: 'f1',
        before: {
          'title': 'Before',
          'tags': ['tag'],
        },
        after: {
          'title': 'After',
          'tags': ['tag'],
        },
      );
      expect(service.shouldEnqueueEmbeddingIndexUpdate(record), isTrue);
    });

    test('update does not enqueue when only unrelated fields changed', () {
      final record = DataChangeRecord(
        op: DataChangeOp.update,
        ns: DataChangeNs.card,
        documentKey: 'f1',
        before: {
          'title': 'Title',
          'tags': ['tag'],
          'fact': 'raw fact',
          'comments': <dynamic>[],
        },
        after: {
          'title': 'Title',
          'tags': ['tag'],
          'fact': 'raw fact',
          'comments': [
            {'id': 'c1', 'content': 'new comment'},
          ],
        },
      );
      expect(service.shouldEnqueueEmbeddingIndexUpdate(record), isFalse);
    });

    test('non-card namespace never enqueues', () {
      final record = DataChangeRecord(
        op: DataChangeOp.insert,
        ns: DataChangeNs.pkmFile,
        documentKey: 'some/path.md',
        after: {'content': 'x'},
      );
      expect(service.shouldEnqueueEmbeddingIndexUpdate(record), isFalse);
    });
  });

  group('EmbeddingIndexService.reset', () {
    // Regression test for logout->login within the same app process: before
    // the fix, EmbeddingIndexService.reset() existed but was never wired
    // into MemexRouter.resetForLogout, so `_initialized` stayed true for the
    // process lifetime and a second init() on re-login always early-returned
    // (see init()'s `if (_initialized) return;` guard), silently skipping
    // the post-migration embedding backfill check on the second login.
    final service = EmbeddingIndexService.instance;

    test(
        'init() sets initialized; reset() clears it; a second init() '
        'proceeds instead of early-returning',
        () {
      service.init('user1');
      expect(service.isInitializedForTesting, isTrue);

      service.reset();
      expect(service.isInitializedForTesting, isFalse);

      service.init('user1');
      expect(service.isInitializedForTesting, isTrue);
    });

    test('without reset(), a second init() call is a no-op early-return',
        () {
      service.reset(); // start from a known clean state
      service.init('user2');
      expect(service.isInitializedForTesting, isTrue);

      // Calling init() again without reset() must NOT throw and must leave
      // state unchanged (it early-returns inside the `if (_initialized)`
      // guard) — this is the buggy-if-missing behavior that reset() exists
      // to undo between logins.
      expect(() => service.init('user2'), returnsNormally);
      expect(service.isInitializedForTesting, isTrue);

      service.reset();
    });
  });

  group('EmbeddingIndexService.rebuildCardEmbeddingIndex', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    CardData cardFor(String factId, {String title = 'Title'}) => CardData(
          factId: factId,
          timestamp: 0,
          status: 'active',
          tags: const [],
          uiConfigs: const [],
          title: title,
          fact: 'fact for $factId',
        );

    test(
        'skips already-indexed factIds, embeds and upserts the rest, and continues past a null embed',
        () async {
      // f1 already has an embedding for the current model — should be skipped.
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1, 0.1],
        model: 'bge-m3',
      );

      final cardPaths = ['f1_path', 'f2_path', 'f3_path'];
      final pathToFactId = {
        'f1_path': 'f1',
        'f2_path': 'f2',
        'f3_path': 'f3',
      };
      final cards = {
        'f1': cardFor('f1'),
        'f2': cardFor('f2'),
        'f3': cardFor('f3'),
      };

      final embeddedFactIds = <String>[];

      await EmbeddingIndexService.instance.rebuildCardEmbeddingIndex(
        'user1',
        dao: db.cardEmbeddingDao,
        listAllCardFiles: (userId) async => cardPaths,
        factIdFromCardPath: (path) => pathToFactId[path],
        readCardFile: (userId, factId) async => cards[factId],
        embedder: (text) async {
          // Simulate a transient embedding failure for f2; f3 succeeds.
          if (text.contains('f2')) return null;
          embeddedFactIds.add(text);
          return [0.5, 0.5];
        },
      );

      // f1 skipped (already indexed), f2 attempted-but-failed (embed null),
      // f3 embedded successfully.
      expect(embeddedFactIds, hasLength(1));
      expect(embeddedFactIds.first, contains('f3'));

      final rows = await db.cardEmbeddingDao.all();
      final factIds = rows.map((r) => r.factId).toSet();
      expect(factIds, {'f1', 'f3'});
    });

    test('skips deleted cards', () async {
      const deletedCard = CardData(
        factId: 'f1',
        timestamp: 0,
        status: 'active',
        tags: [],
        uiConfigs: [],
        deleted: true,
      );

      var embedCalls = 0;

      await EmbeddingIndexService.instance.rebuildCardEmbeddingIndex(
        'user1',
        dao: db.cardEmbeddingDao,
        listAllCardFiles: (userId) async => ['f1_path'],
        factIdFromCardPath: (path) => 'f1',
        readCardFile: (userId, factId) async => deletedCard,
        embedder: (text) async {
          embedCalls++;
          return [0.1];
        },
      );

      expect(embedCalls, 0);
      final rows = await db.cardEmbeddingDao.all();
      expect(rows, isEmpty);
    });
  });
}
