import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/services/task_handlers/embedding_index_handler.dart';
import 'package:memex/data/services/task_handlers/fts_index_handler.dart'
    show dataChangeRecordToPayload;
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/card_embedding_dao.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/logger.dart';

/// Signature for listing all card file paths for a user, matching
/// [FileSystemService.listAllCardFiles]. Test seam for
/// [EmbeddingIndexService.rebuildCardEmbeddingIndex].
typedef ListAllCardFilesFn = Future<List<String>> Function(String userId);

/// Signature for reading a card by factId, matching
/// [FileSystemService.readCardFile]. Test seam for
/// [EmbeddingIndexService.rebuildCardEmbeddingIndex].
typedef ReadCardFileFn = Future<CardData?> Function(
    String userId, String factId);

/// Signature for parsing a factId out of a card file path, matching
/// [FileSystemService.factIdFromCardPath]. Test seam for
/// [EmbeddingIndexService.rebuildCardEmbeddingIndex].
typedef FactIdFromCardPathFn = String? Function(String cardFilePath);

/// Service responsible for keeping the `card_embeddings` table populated.
///
/// Mirrors [SearchService]'s FTS maintenance: listens to `DataChangeRecord`
/// events on the [GlobalEventBus] and incrementally re-embeds cards whose
/// indexed fields changed, plus a one-time full backfill for existing users
/// after the `card_embeddings` table is created via migration.
///
/// Architecture:
///   MemexRouter (card mutation) ──publish DataChangeRecord──▶ GlobalEventBus
///       ──subscribe (EventTaskSubscription)──▶ LocalTaskExecutor
///       ──▶ embedding_index_handler ──▶ CardEmbeddingDao (db/daos)
///
/// Usage:
///   Called once during [MemexRouter._init], alongside [SearchService.init].
class EmbeddingIndexService {
  EmbeddingIndexService._();
  static final EmbeddingIndexService instance = EmbeddingIndexService._();

  final Logger _logger = getLogger('EmbeddingIndexService');

  bool _initialized = false;

  /// Test seam for asserting init()/reset() state transitions without
  /// depending on the harder-to-observe migration/backfill side effect.
  @visibleForTesting
  bool get isInitializedForTesting => _initialized;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Wire up event subscriptions. Safe to call multiple times; only the
  /// first call takes effect.
  ///
  /// When the `card_embeddings` table was just created via DB migration
  /// (existing users upgrading past schema v17), triggers a one-time full
  /// backfill in the background so historical cards get embedded.
  void init(String userId) {
    if (_initialized) return;
    _initialized = true;

    _subscribeToDataChanges();

    if (AppDatabase.isInitialized &&
        AppDatabase.instance.needsEmbeddingRebuild) {
      AppDatabase.instance.clearEmbeddingRebuildFlag();
      _logger.info(
          'card_embeddings table newly created via migration — scheduling backfill');
      // Fire-and-forget so app startup is not blocked.
      Future(() async {
        try {
          await rebuildCardEmbeddingIndex(userId);
          _logger.info('Post-migration embedding backfill completed');
        } catch (e) {
          _logger.warning('Post-migration embedding backfill failed: $e');
        }
      });
    }
  }

  /// Reset state on logout so the next login re-initializes.
  void reset() {
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // Event subscription (consumer side) — uses persistent task queue
  // ---------------------------------------------------------------------------

  void _subscribeToDataChanges() {
    GlobalEventBus.instance.subscribe(
      eventType: SystemEventTypes.dataChanged,
      subscription: EventTaskSubscription(
        subscriptionId: 'embedding_index_update',
        taskType: 'embedding_index_update',
        priority: -1, // Lower priority than agent tasks
        maxRetries: 3,
        shouldEnqueue: (_, event) async {
          final record = event.payload as DataChangeRecord;
          return shouldEnqueueEmbeddingIndexUpdate(record);
        },
        payloadBuilder: (_, event) async {
          final record = event.payload as DataChangeRecord;
          return dataChangeRecordToPayload(record);
        },
      ),
    );
  }

  /// Whether [record] should trigger an `embedding_index_update` task.
  ///
  /// Reuses the same "indexed card field changed" gate as
  /// `SearchService._shouldEnqueueFtsIndexUpdate` (title/fact/tags/insight),
  /// so semantic and keyword indexes stay in sync about what counts as a
  /// re-index-worthy change. Replicated here (rather than importing from
  /// `SearchService`) to keep this service independently testable and
  /// decoupled from `SearchService`'s PKM-file handling, which does not
  /// apply to embeddings.
  @visibleForTesting
  bool shouldEnqueueEmbeddingIndexUpdate(DataChangeRecord record) {
    if (record.ns != DataChangeNs.card) return false;

    switch (record.op) {
      case DataChangeOp.insert:
      case DataChangeOp.delete:
        return true;
      case DataChangeOp.update:
        final before = record.before;
        final after = record.after;
        if (before == null || after == null) return true;
        return _indexedCardFieldChanged(before, after);
    }
  }

  bool _indexedCardFieldChanged(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    return _stringValue(before['title']) != _stringValue(after['title']) ||
        _stringValue(before['fact']) != _stringValue(after['fact']) ||
        _stringListValue(before['tags']) != _stringListValue(after['tags']) ||
        _insightText(before['insight']) != _insightText(after['insight']);
  }

  String _stringValue(Object? value) => value is String ? value : '';

  String _stringListValue(Object? value) {
    if (value is List) return value.whereType<String>().join(' ');
    return '';
  }

  String _insightText(Object? value) {
    if (value is Map<String, dynamic>) {
      return value['text'] as String? ?? '';
    }
    if (value is Map) {
      final text = value['text'];
      return text is String ? text : '';
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Full backfill (migration-triggered + manual/debug trigger)
  // ---------------------------------------------------------------------------

  /// Rebuild the card embedding index by scanning all card files, skipping
  /// any factId that already has an embedding for the current model.
  ///
  /// [embedder], [dao], [listAllCardFiles], and [readCardFile] are
  /// injectable so this can be driven in tests without network or real
  /// filesystem/database access.
  Future<void> rebuildCardEmbeddingIndex(
    String userId, {
    EmbedFn? embedder,
    CardEmbeddingDao? dao,
    ListAllCardFilesFn? listAllCardFiles,
    ReadCardFileFn? readCardFile,
    FactIdFromCardPathFn? factIdFromCardPath,
  }) async {
    final embedFn = embedder ?? EmbeddingService.instance.embed;
    final resolvedDao = dao ??
        (AppDatabase.isInitialized
            ? AppDatabase.instance.cardEmbeddingDao
            : null);
    if (resolvedDao == null) {
      _logger.warning('Database not initialized, skipping embedding backfill');
      return;
    }
    final listFn = listAllCardFiles ?? FileSystemService.instance.listAllCardFiles;
    final readFn = readCardFile ?? FileSystemService.instance.readCardFile;
    final factIdFn =
        factIdFromCardPath ?? FileSystemService.instance.factIdFromCardPath;

    _logger.info('Rebuilding card embedding index for user $userId');

    final alreadyIndexed = await resolvedDao.factIdsForModel(
      EmbeddingService.model,
    );

    final cardFiles = await listFn(userId);

    int indexed = 0;
    int skipped = 0;
    int failed = 0;

    for (final cardFile in cardFiles) {
      try {
        final factId = factIdFn(cardFile);
        if (factId == null) continue;

        if (alreadyIndexed.contains(factId)) {
          skipped++;
          continue;
        }

        final cardData = await readFn(userId, factId);
        if (cardData == null || cardData.deleted == true) {
          skipped++;
          continue;
        }

        final text = _combinedTextForCard(cardData);
        final vector = await embedFn(text);
        if (vector == null) {
          failed++;
          _logger.warning('Embedding backfill: embed returned null for $factId');
          continue;
        }

        await resolvedDao.upsert(
          factId: factId,
          vector: vector,
          model: EmbeddingService.model,
        );
        indexed++;
      } catch (e) {
        failed++;
        _logger.warning('Embedding backfill: error indexing $cardFile: $e');
      }
    }

    _logger.info(
      'Card embedding backfill complete. indexed=$indexed skipped=$skipped failed=$failed',
    );
  }

  String _combinedTextForCard(CardData cardData) {
    final parts = <String>[
      cardData.title ?? '',
      cardData.fact ?? '',
      cardData.tags.join(' '),
      cardData.insight?.text ?? '',
    ].where((s) => s.isNotEmpty);
    return parts.join('\n').trim();
  }
}
