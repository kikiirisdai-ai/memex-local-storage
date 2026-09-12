import 'dart:math' as math;

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';

/// A single retrieval result: a timeline card matched by a query, with the
/// FTS snippet that justified the match.
class CardHit {
  final String cardId;
  final String title;
  final String snippet;
  final DateTime date;
  final List<String> tags;

  const CardHit({
    required this.cardId,
    required this.title,
    required this.snippet,
    required this.date,
    this.tags = const [],
  });
}

/// Abstraction over "find cards relevant to this query" so agent tools and
/// UI surfaces don't depend on a specific retrieval strategy (keyword FTS
/// today; embeddings/hybrid later).
abstract class CardRetriever {
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  });
}

/// Signature for the underlying search call [KeywordCardRetriever] delegates
/// to. Matches [MemexRouter.searchCardHits] shape, and is used as the test
/// seam via [KeywordCardRetriever.forTesting].
typedef CardHitSearchFn = Future<Result<List<({TimelineCardModel card, String snippet})>>>
    Function(String query, {int limit});

/// Keyword retriever: delegates to the existing FTS5 index via
/// [MemexRouter.searchCardHits], then applies date/tag filtering in Dart
/// (FTS5 has no native support for filtering on hydrated card fields like
/// tags/timestamp, since those aren't indexed FTS columns).
class KeywordCardRetriever implements CardRetriever {
  KeywordCardRetriever({MemexRouter? router})
      : _searchFn = (router ?? MemexRouter()).searchCardHits;

  KeywordCardRetriever._forTesting(this._searchFn);

  /// Test seam: bypass [MemexRouter] entirely and inject a fake search
  /// function returning (card, snippet) pairs directly.
  factory KeywordCardRetriever.forTesting({
    required CardHitSearchFn searchFn,
  }) =>
      KeywordCardRetriever._forTesting(searchFn);

  static final CardRetriever instance = KeywordCardRetriever();

  final CardHitSearchFn _searchFn;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    // Post-filtering narrows the candidate set, so over-fetch from FTS
    // before trimming to the caller's requested limit.
    final candidateLimit = math.max(limit * 3, 60);

    final result = await _searchFn(query, limit: candidateLimit);
    final hits = switch (result) {
      Ok(value: final v) => v,
      Error() => const <({TimelineCardModel card, String snippet})>[],
    };

    final filtered = hits.where((hit) {
      final card = hit.card;
      if (dateFrom != null && card.timestamp.isBefore(dateFrom)) return false;
      if (dateTo != null && card.timestamp.isAfter(dateTo)) return false;
      if (tags != null && tags.isNotEmpty) {
        final hasAnyTag = card.tags.any(tags.contains);
        if (!hasAnyTag) return false;
      }
      return true;
    });

    return filtered.take(limit).map((hit) {
      final card = hit.card;
      return CardHit(
        cardId: card.id,
        title: card.title ?? '',
        snippet: _stripSnippetMarkers(hit.snippet),
        date: card.timestamp,
        tags: card.tags,
      );
    }).toList();
  }

  static String _stripSnippetMarkers(String snippet) {
    return snippet.replaceAll('<b>', '').replaceAll('</b>', '');
  }
}
