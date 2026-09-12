import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/data/services/semantic_card_retriever.dart';

/// Reciprocal Rank Fusion: merges two independently-ranked hit lists into a
/// single ranking without needing comparable relevance scores across the
/// two retrieval strategies.
///
/// For each list, a hit at 0-based rank `i` contributes `1 / (k + i + 1)` to
/// its cardId's fused score. Hits present in both lists accumulate both
/// contributions. The higher `k` is, the less top ranks dominate; `60` is
/// RRF's conventional default.
///
/// When a cardId appears in both lists, the [CardHit] instance from [a]
/// (conventionally the keyword retriever) is kept, since its title/snippet
/// come from the FTS match rather than a truncated raw-text fallback.
///
/// If [b] is empty, the fused order is equivalent to [a]'s order.
List<CardHit> rrfMerge(
  List<CardHit> a,
  List<CardHit> b, {
  int k = 60,
  required int limit,
}) {
  final scores = <String, double>{};
  final hitsById = <String, CardHit>{};

  void accumulate(List<CardHit> hits) {
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      scores[hit.cardId] = (scores[hit.cardId] ?? 0.0) + 1.0 / (k + i + 1);
      hitsById.putIfAbsent(hit.cardId, () => hit);
    }
  }

  // Accumulate a first so its CardHit instance wins putIfAbsent below.
  accumulate(a);
  accumulate(b);

  final ordered = scores.keys.toList()
    ..sort((x, y) => scores[y]!.compareTo(scores[x]!));

  return ordered.take(limit).map((id) => hitsById[id]!).toList();
}

/// Hybrid retriever: runs [KeywordCardRetriever] and [SemanticCardRetriever]
/// in parallel and fuses their results with [rrfMerge]. Either retriever
/// failing (throwing, or — for semantic, before the corpus is backfilled —
/// simply returning `[]`) degrades gracefully to the other's ranking.
class HybridCardRetriever implements CardRetriever {
  HybridCardRetriever()
      : _keyword = KeywordCardRetriever.instance,
        _semantic = SemanticCardRetriever.instance;

  HybridCardRetriever._forTesting(this._keyword, this._semantic);

  /// Test seam: inject fake keyword/semantic retrievers directly.
  factory HybridCardRetriever.forTesting({
    required CardRetriever keyword,
    required CardRetriever semantic,
  }) =>
      HybridCardRetriever._forTesting(keyword, semantic);

  static final CardRetriever instance = HybridCardRetriever();

  final CardRetriever _keyword;
  final CardRetriever _semantic;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    Future<List<CardHit>> safeSearch(CardRetriever retriever) async {
      try {
        return await retriever.search(
          query,
          limit: limit,
          dateFrom: dateFrom,
          dateTo: dateTo,
          tags: tags,
        );
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      safeSearch(_keyword),
      safeSearch(_semantic),
    ]);

    return rrfMerge(results[0], results[1], limit: limit);
  }
}
