import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/semantic_card_retriever.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/timeline_card_model.dart';

TimelineCardModel _card({
  required String id,
  required DateTime timestamp,
  List<String> tags = const [],
  String? title,
  String? rawText,
}) {
  return TimelineCardModel(
    id: id,
    timestamp: timestamp,
    tags: tags,
    status: 'completed',
    title: title,
    uiConfigs: const [],
    rawText: rawText,
  );
}

void main() {
  group('SemanticCardRetriever default vectorsProvider is lazy', () {
    // Must run before any test in this file calls AppDatabase.setTestInstance
    // / AppDatabase.init, so AppDatabase's static _instance is still unset.
    test(
        'constructing SemanticCardRetriever() does not touch AppDatabase.instance',
        () {
      expect(AppDatabase.isInitialized, isFalse);
      // Regression guard for the bug fixed here: the old code captured
      // `AppDatabase.instance.cardEmbeddingDao.all` as a tear-off at
      // construction time, which evaluates `AppDatabase.instance` eagerly
      // and would throw "Database not initialized" right here. The fixed
      // default wraps that in a closure so it is only evaluated inside
      // search(), at call time.
      expect(() => SemanticCardRetriever(), returnsNormally);
    });

    test(
        'the vectorsProvider pattern used in production re-resolves '
        'AppDatabase.instance on every call, surviving a simulated '
        'logout->login DB re-init (AppDatabase.instance swapped mid-session)',
        () async {
      final db1 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db1.close());
      AppDatabase.setTestInstance(db1);
      await db1.cardEmbeddingDao.upsert(
        factId: 'db1-fact',
        vector: [1.0, 0.0],
        model: 'bge-m3',
      );

      // Mirrors the exact closure now used as the production default in
      // SemanticCardRetriever (see _defaultVectorsProvider): it reads
      // AppDatabase.instance at call time rather than capturing a tear-off
      // at construction, so it keeps working after AppDatabase.instance is
      // swapped out (as AppDatabase.init() does on every login).
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () => AppDatabase.instance.cardEmbeddingDao.all(),
        hydrateFn: (factIds) async => factIds
            .map((id) => (
                  card: _card(id: id, timestamp: DateTime(2026, 1, 1)),
                  snippet: 'snippet-$id',
                ))
            .toList(),
      );

      final firstHits = await retriever.search('q');
      expect(firstHits.map((h) => h.cardId), ['db1-fact']);

      // Simulate logout -> login: AppDatabase.init() closes the old DB and
      // assigns a brand new instance. The retriever above was constructed
      // while db1 was current and must NOT still be bound to it.
      await db1.close();
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db2.close());
      AppDatabase.setTestInstance(db2);
      await db2.cardEmbeddingDao.upsert(
        factId: 'db2-fact',
        vector: [1.0, 0.0],
        model: 'bge-m3',
      );

      final secondHits = await retriever.search('q');
      expect(secondHits.map((h) => h.cardId), ['db2-fact']);
    });
  });

  group('SemanticCardRetriever.search', () {
    test('orders hits by cosine similarity, descending', () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () async => [
          (factId: 'low', vector: [0.0, 1.0]), // orthogonal -> sim 0
          (factId: 'high', vector: [1.0, 0.0]), // identical -> sim 1
          (factId: 'mid', vector: [1.0, 1.0]), // sim ~0.707
        ],
        hydrateFn: (factIds) async {
          return factIds
              .map((id) => (
                    card: _card(id: id, timestamp: DateTime(2026, 1, 1)),
                    snippet: 'snippet-$id',
                  ))
              .toList();
        },
      );

      final hits = await retriever.search('q');

      expect(hits.map((h) => h.cardId), ['high', 'mid', 'low']);
    });

    test('returns empty list when embedding fails (embed returns null)',
        () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => null,
        vectorsProvider: () async => [
          (factId: 'a', vector: [1.0, 0.0]),
        ],
        hydrateFn: (factIds) async => [],
      );

      final hits = await retriever.search('q');

      expect(hits, isEmpty);
    });

    test('returns empty list when there are no stored vectors', () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () async => [],
        hydrateFn: (factIds) async => [],
      );

      final hits = await retriever.search('q');

      expect(hits, isEmpty);
    });

    test('filters out cards before dateFrom / after dateTo', () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () async => [
          (factId: 'old', vector: [1.0, 0.0]),
          (factId: 'new', vector: [0.9, 0.1]),
          (factId: 'future', vector: [0.8, 0.2]),
        ],
        hydrateFn: (factIds) async => [
          (
            card: _card(id: 'old', timestamp: DateTime(2020, 1, 1)),
            snippet: 'old',
          ),
          (
            card: _card(id: 'new', timestamp: DateTime(2026, 6, 1)),
            snippet: 'new',
          ),
          (
            card: _card(id: 'future', timestamp: DateTime(2027, 1, 1)),
            snippet: 'future',
          ),
        ],
      );

      final hits = await retriever.search(
        'q',
        dateFrom: DateTime(2025, 1, 1),
        dateTo: DateTime(2026, 12, 31),
      );

      expect(hits.map((h) => h.cardId), ['new']);
    });

    test('keeps only cards matching any of the requested tags', () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () async => [
          (factId: 'a', vector: [1.0, 0.0]),
          (factId: 'b', vector: [0.9, 0.1]),
        ],
        hydrateFn: (factIds) async => [
          (
            card: _card(
              id: 'a',
              timestamp: DateTime(2026, 1, 1),
              tags: const ['工作'],
            ),
            snippet: 'a',
          ),
          (
            card: _card(
              id: 'b',
              timestamp: DateTime(2026, 1, 1),
              tags: const ['旅行', '美食'],
            ),
            snippet: 'b',
          ),
        ],
      );

      final hits = await retriever.search('q', tags: ['美食']);

      expect(hits.map((h) => h.cardId), ['b']);
    });

    test('trims results to the requested limit', () async {
      final retriever = SemanticCardRetriever.forTesting(
        embedder: (query) async => [1.0, 0.0],
        vectorsProvider: () async => [
          for (var i = 0; i < 5; i++)
            (factId: 'c$i', vector: [1.0 - i * 0.01, 0.0]),
        ],
        hydrateFn: (factIds) async {
          return factIds
              .map((id) => (
                    card: _card(id: id, timestamp: DateTime(2026, 1, 1)),
                    snippet: 'snippet-$id',
                  ))
              .toList();
        },
      );

      final hits = await retriever.search('q', limit: 2);

      expect(hits, hasLength(2));
    });
  });
}
