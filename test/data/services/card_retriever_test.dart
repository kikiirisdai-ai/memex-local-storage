import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';

TimelineCardModel _card({
  required String id,
  required DateTime timestamp,
  List<String> tags = const [],
  String? title,
}) {
  return TimelineCardModel(
    id: id,
    timestamp: timestamp,
    tags: tags,
    status: 'completed',
    title: title,
    uiConfigs: const [],
  );
}

void main() {
  group('KeywordCardRetriever.search', () {
    test('maps hits to CardHit and strips <b> snippet markers', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Ok([
            (
              card: _card(
                id: 'c1',
                timestamp: DateTime(2026, 1, 1),
                tags: const ['旅行'],
                title: '爬山',
              ),
              snippet: '今天去<b>爬山</b>看瀑布',
            ),
          ]);
        },
      );

      final hits = await retriever.search('爬山');

      expect(hits, hasLength(1));
      expect(hits.single.cardId, 'c1');
      expect(hits.single.title, '爬山');
      expect(hits.single.snippet, '今天去爬山看瀑布');
      expect(hits.single.date, DateTime(2026, 1, 1));
      expect(hits.single.tags, ['旅行']);
    });

    test('filters out cards before dateFrom', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Ok([
            (
              card: _card(id: 'old', timestamp: DateTime(2020, 1, 1)),
              snippet: 'old',
            ),
            (
              card: _card(id: 'new', timestamp: DateTime(2026, 6, 1)),
              snippet: 'new',
            ),
          ]);
        },
      );

      final hits =
          await retriever.search('q', dateFrom: DateTime(2025, 1, 1));

      expect(hits.map((h) => h.cardId), ['new']);
    });

    test('filters out cards after dateTo', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Ok([
            (
              card: _card(id: 'early', timestamp: DateTime(2026, 1, 1)),
              snippet: 'early',
            ),
            (
              card: _card(id: 'late', timestamp: DateTime(2026, 12, 1)),
              snippet: 'late',
            ),
          ]);
        },
      );

      final hits = await retriever.search('q', dateTo: DateTime(2026, 6, 1));

      expect(hits.map((h) => h.cardId), ['early']);
    });

    test('keeps only cards matching any of the requested tags', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Ok([
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
          ]);
        },
      );

      final hits = await retriever.search('q', tags: ['美食']);

      expect(hits.map((h) => h.cardId), ['b']);
    });

    test('trims results to the requested limit', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Ok([
            for (var i = 0; i < 5; i++)
              (
                card: _card(id: 'c$i', timestamp: DateTime(2026, 1, 1)),
                snippet: 'snippet $i',
              ),
          ]);
        },
      );

      final hits = await retriever.search('q', limit: 2);

      expect(hits, hasLength(2));
    });

    test('returns empty list when the search function errors', () async {
      final retriever = KeywordCardRetriever.forTesting(
        searchFn: (query, {int limit = 20}) async {
          return Error(Exception('boom'));
        },
      );

      final hits = await retriever.search('q');

      expect(hits, isEmpty);
    });
  });
}
