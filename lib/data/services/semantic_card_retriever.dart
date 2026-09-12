import 'dart:math' as math;

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/timeline_card_model.dart';

/// Signature for embedding a query string into a vector. Matches
/// [EmbeddingService.embed]; used as the test seam via
/// [SemanticCardRetriever.forTesting].
typedef EmbedFn = Future<List<double>?> Function(String text);

/// Signature for fetching all stored card embeddings. Matches
/// [CardEmbeddingDao.all]; used as the test seam via
/// [SemanticCardRetriever.forTesting].
typedef VectorsProviderFn = Future<List<({String factId, List<double> vector})>>
    Function();

/// Signature for hydrating a list of factIds (already ranked by similarity)
/// into (card, snippet) pairs. Order of the input list is preserved in the
/// output where possible.
typedef HydrateFn = Future<List<({TimelineCardModel card, String snippet})>>
    Function(List<String> factIds);

/// Semantic retriever: embeds the query, compares it against every stored
/// card embedding via cosine similarity, and hydrates the top candidates.
///
/// Until the embeddings table is backfilled (see indexing/backfill task),
/// [_vectorsProvider] returns an empty list and this retriever degrades to
/// returning `[]` — callers should combine it with [KeywordCardRetriever]
/// via [HybridCardRetriever] rather than depend on it alone.
class SemanticCardRetriever implements CardRetriever {
  SemanticCardRetriever()
      : _embed = EmbeddingService.instance.embed,
        // Resolved lazily at call time (not captured here) so this keeps
        // working after logout→login, when AppDatabase.init() closes the
        // old DB and swaps in a new AppDatabase.instance. Capturing the DAO
        // tear-off at construction would keep pointing at the closed DB.
        _vectorsProvider = _defaultVectorsProvider,
        _hydrateFn = _defaultHydrate;

  SemanticCardRetriever._forTesting(
    this._embed,
    this._vectorsProvider,
    this._hydrateFn,
  );

  /// Test seam: bypass [EmbeddingService]/[CardEmbeddingDao]/[MemexRouter]
  /// entirely and inject fakes directly.
  factory SemanticCardRetriever.forTesting({
    required EmbedFn embedder,
    required VectorsProviderFn vectorsProvider,
    required HydrateFn hydrateFn,
  }) =>
      SemanticCardRetriever._forTesting(embedder, vectorsProvider, hydrateFn);

  static final CardRetriever instance = SemanticCardRetriever();

  final EmbedFn _embed;
  final VectorsProviderFn _vectorsProvider;
  final HydrateFn _hydrateFn;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    final queryVector = await _embed(query);
    if (queryVector == null) return const [];

    final stored = await _vectorsProvider();
    if (stored.isEmpty) return const [];

    // Post-filtering narrows the candidate set, so over-fetch before
    // trimming to the caller's requested limit (mirrors KeywordCardRetriever).
    final candidateLimit = math.max(limit * 3, 60);

    final scored = stored
        .map(
          (e) => (
            factId: e.factId,
            score: cosineSimilarity(queryVector, e.vector),
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final candidateIds =
        scored.take(candidateLimit).map((e) => e.factId).toList();
    if (candidateIds.isEmpty) return const [];

    final hydrated = await _hydrateFn(candidateIds);
    final byFactId = {for (final h in hydrated) h.card.id: h};

    // Preserve similarity order; skip factIds that failed to hydrate.
    final ordered = candidateIds
        .map((id) => byFactId[id])
        .whereType<({TimelineCardModel card, String snippet})>();

    final filtered = ordered.where((hit) {
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
        snippet: hit.snippet,
        date: card.timestamp,
        tags: card.tags,
      );
    }).toList();
  }

  static Future<List<({String factId, List<double> vector})>>
      _defaultVectorsProvider() => AppDatabase.instance.cardEmbeddingDao.all();

  static Future<List<({TimelineCardModel card, String snippet})>>
      _defaultHydrate(List<String> factIds) async {
    final cards = await MemexRouter().fetchCardByIds(factIds);
    return cards.map((card) => (card: card, snippet: _snippetFor(card))).toList();
  }

  static const int _snippetMaxLength = 120;

  static String _snippetFor(TimelineCardModel card) {
    final source = card.rawText ?? card.title ?? '';
    if (source.length <= _snippetMaxLength) return source;
    return source.substring(0, _snippetMaxLength);
  }
}
