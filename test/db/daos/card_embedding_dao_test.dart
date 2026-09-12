import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/db/app_database.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('CardEmbeddingDao', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsert then all() returns rows with vectors, model preserved',
        () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1, 0.2, 0.3],
        model: 'text-embedding-3-small',
      );
      await db.cardEmbeddingDao.upsert(
        factId: 'f2',
        vector: [0.4, 0.5],
        model: 'text-embedding-3-small',
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, hasLength(2));

      final f1 = rows.firstWhere((r) => r.factId == 'f1');
      expect(f1.vector, hasLength(3));
      expect(f1.vector[0], closeTo(0.1, 1e-9));
      expect(f1.vector[1], closeTo(0.2, 1e-9));
      expect(f1.vector[2], closeTo(0.3, 1e-9));

      final f2 = rows.firstWhere((r) => r.factId == 'f2');
      expect(f2.vector, hasLength(2));
      expect(f2.vector[0], closeTo(0.4, 1e-9));
      expect(f2.vector[1], closeTo(0.5, 1e-9));

      final factIds = await db.cardEmbeddingDao.factIdsForModel(
        'text-embedding-3-small',
      );
      expect(factIds, {'f1', 'f2'});
    });

    test('upsert with same factId overwrites existing row', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1, 0.1],
        model: 'model-a',
      );
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.9, 0.9, 0.9],
        model: 'model-b',
      );

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, hasLength(1));
      expect(rows.first.vector, hasLength(3));
      expect(rows.first.vector[0], closeTo(0.9, 1e-9));

      final oldModelIds = await db.cardEmbeddingDao.factIdsForModel('model-a');
      expect(oldModelIds, isEmpty);

      final newModelIds = await db.cardEmbeddingDao.factIdsForModel('model-b');
      expect(newModelIds, {'f1'});
    });

    test('deleteByFactId removes only the targeted row', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1],
        model: 'm',
      );
      await db.cardEmbeddingDao.upsert(
        factId: 'f2',
        vector: [0.2],
        model: 'm',
      );

      await db.cardEmbeddingDao.deleteByFactId('f1');

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, hasLength(1));
      expect(rows.first.factId, 'f2');
    });

    test('factIdsForModel filters by model', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1],
        model: 'model-a',
      );
      await db.cardEmbeddingDao.upsert(
        factId: 'f2',
        vector: [0.2],
        model: 'model-b',
      );

      final aIds = await db.cardEmbeddingDao.factIdsForModel('model-a');
      expect(aIds, {'f1'});

      final bIds = await db.cardEmbeddingDao.factIdsForModel('model-b');
      expect(bIds, {'f2'});
    });

    test('clear() empties the table', () async {
      await db.cardEmbeddingDao.upsert(
        factId: 'f1',
        vector: [0.1],
        model: 'm',
      );
      await db.cardEmbeddingDao.upsert(
        factId: 'f2',
        vector: [0.2],
        model: 'm',
      );

      await db.cardEmbeddingDao.clear();

      final rows = await db.cardEmbeddingDao.all();
      expect(rows, isEmpty);
    });
  });
}
