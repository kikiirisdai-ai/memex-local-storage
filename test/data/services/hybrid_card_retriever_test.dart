import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/data/services/hybrid_card_retriever.dart';

CardHit _hit(String id, {String title = '', String snippet = ''}) {
  return CardHit(
    cardId: id,
    title: title.isEmpty ? id : title,
    snippet: snippet.isEmpty ? 'snippet-$id' : snippet,
    date: DateTime(2026, 1, 1),
  );
}

class _FakeRetriever implements CardRetriever {
  _FakeRetriever(this._hits, {this.error});

  final List<CardHit> _hits;
  final Object? error;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    if (error != null) throw error!;
    return _hits.take(limit).toList();
  }
}

void main() {
  group('rrfMerge', () {
    test('fuses two ranked lists by reciprocal rank, deduping by cardId',
        () {
      final keyword = [_hit('a'), _hit('b'), _hit('c')];
      final semantic = [_hit('b'), _hit('a'), _hit('d')];

      final merged = rrfMerge(keyword, semantic, limit: 10);

      // a: 1/(60+1) + 1/(60+2); b: 1/(60+2) + 1/(60+1) -> tie with a
      // a and b both get the sum of rank1+rank2 contributions, so they tie.
      // c: 1/(60+3); d: 1/(60+3) -> tie.
      // Regardless of exact ordering among ties, a & b must outrank c & d.
      final ids = merged.map((h) => h.cardId).toList();
      expect(ids.length, 4);
      expect(ids.indexOf('a'), lessThan(ids.indexOf('c')));
      expect(ids.indexOf('b'), lessThan(ids.indexOf('d')));
      expect(ids.toSet(), {'a', 'b', 'c', 'd'});
    });

    test('semantic empty -> result is equivalent to keyword order', () {
      final keyword = [_hit('a'), _hit('b'), _hit('c')];

      final merged = rrfMerge(keyword, const [], limit: 10);

      expect(merged.map((h) => h.cardId).toList(), ['a', 'b', 'c']);
    });

    test('respects limit', () {
      final keyword = [_hit('a'), _hit('b'), _hit('c')];

      final merged = rrfMerge(keyword, const [], limit: 2);

      expect(merged, hasLength(2));
    });

    test('prefers keyword hit instance (title/snippet) on dedupe', () {
      final keyword = [_hit('a', title: 'keyword-title')];
      final semantic = [_hit('a', title: 'semantic-title')];

      final merged = rrfMerge(keyword, semantic, limit: 10);

      expect(merged.single.title, 'keyword-title');
    });
  });

  group('HybridCardRetriever.search', () {
    test('merges keyword and semantic results', () async {
      final retriever = HybridCardRetriever.forTesting(
        keyword: _FakeRetriever([_hit('a'), _hit('b')]),
        semantic: _FakeRetriever([_hit('b'), _hit('c')]),
      );

      final hits = await retriever.search('q');

      expect(hits.map((h) => h.cardId).toSet(), {'a', 'b', 'c'});
    });

    test('degrades to keyword-only order when semantic throws', () async {
      final retriever = HybridCardRetriever.forTesting(
        keyword: _FakeRetriever([_hit('a'), _hit('b'), _hit('c')]),
        semantic: _FakeRetriever(const [], error: Exception('boom')),
      );

      final hits = await retriever.search('q');

      expect(hits.map((h) => h.cardId).toList(), ['a', 'b', 'c']);
    });

    test('degrades to keyword-only order when semantic returns empty',
        () async {
      final retriever = HybridCardRetriever.forTesting(
        keyword: _FakeRetriever([_hit('a'), _hit('b'), _hit('c')]),
        semantic: _FakeRetriever(const []),
      );

      final hits = await retriever.search('q');

      expect(hits.map((h) => h.cardId).toList(), ['a', 'b', 'c']);
    });
  });
}
