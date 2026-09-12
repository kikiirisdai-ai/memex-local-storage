import 'package:logging/logging.dart';
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/card_embedding_dao.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/logger.dart';

final Logger _logger = getLogger('EmbeddingIndexHandler');

/// Signature for embedding text, matching [EmbeddingService.embed]. Used as
/// the test seam for [handleEmbeddingIndexUpdateImpl].
typedef EmbedFn = Future<List<double>?> Function(String text);

/// Thrown when an embedding could not be produced (e.g. Ollama unreachable).
/// Intentionally a plain [Exception] (not `NonRetryableTaskException`) so
/// [LocalTaskExecutor] retries the task later once the model is reachable
/// again.
class EmbeddingUnavailableException implements Exception {
  final String factId;
  EmbeddingUnavailableException(this.factId);

  @override
  String toString() =>
      'EmbeddingUnavailableException: could not embed card $factId';
}

/// Task handler for `embedding_index_update` tasks.
///
/// Mirrors [handleFtsIndexUpdateImpl]: persisted via [LocalTaskExecutor] so
/// embedding updates survive app restarts. Payload contains a serialized
/// `DataChangeRecord` (see [dataChangeRecordToPayload] in
/// `fts_index_handler.dart`).
///
/// [embedder] and [dao] are injectable so this handler can be exercised in
/// tests without hitting the network or a real database.
Future<void> handleEmbeddingIndexUpdateImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context, {
  EmbedFn? embedder,
  CardEmbeddingDao? dao,
}) async {
  final op = payload['op'] as String?;
  final ns = payload['ns'] as String?;
  final documentKey = payload['document_key'] as String?;
  final after = payload['after'] as Map<String, dynamic>?;

  if (op == null || ns == null || documentKey == null) {
    _logger.warning('Invalid embedding index task payload: $payload');
    return;
  }

  if (ns != DataChangeNs.card) {
    // Only cards are embedded for semantic search; PKM files are out of scope.
    return;
  }

  final embedFn = embedder ?? EmbeddingService.instance.embed;
  final resolvedDao = dao ??
      (AppDatabase.isInitialized
          ? AppDatabase.instance.cardEmbeddingDao
          : null);

  if (resolvedDao == null) {
    _logger.warning('Database not initialized, skipping embedding update');
    return;
  }

  switch (op) {
    case 'delete':
      await resolvedDao.deleteByFactId(documentKey);
      break;
    case 'insert':
    case 'update':
      if (after == null) return;
      final text = _combinedText(after);
      final vector = await embedFn(text);
      if (vector == null) {
        // Don't upsert a stale/missing embedding — throw so the task queue
        // retries this later (e.g. once Ollama is reachable again).
        throw EmbeddingUnavailableException(documentKey);
      }
      await resolvedDao.upsert(
        factId: documentKey,
        vector: vector,
        model: EmbeddingService.model,
      );
      break;
    default:
      _logger.fine('Unknown embedding index op: $op');
  }
}

/// Build the text to embed from a card's `after` snapshot. Uses the same
/// fields as the FTS index (title + fact + tags + insight text) so semantic
/// and keyword search stay aligned on what's "indexed".
String _combinedText(Map<String, dynamic> after) {
  final title = after['title'] as String? ?? '';
  final fact = after['fact'] as String? ?? '';
  final tags = (after['tags'] as List?)?.whereType<String>().join(' ') ?? '';
  final insightMap = after['insight'] as Map<String, dynamic>?;
  final insight = insightMap?['text'] as String? ?? '';

  return [title, fact, tags, insight]
      .where((s) => s.isNotEmpty)
      .join('\n')
      .trim();
}
