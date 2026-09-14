import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/repositories/hydrate_card.dart';

final _logger = getLogger('GetArchivedCardsEndpoint');

/// Every archived card (swiped out of the timeline), newest-archived first.
///
/// Mirrors the "fetch everything, filter client-side" pattern already used
/// for Goals/Tasks/Media Library aggregation — a personal archive rarely
/// exceeds a few hundred cards, so a large single page plus in-memory
/// filtering is simpler and fast enough vs. adding an indexed column to
/// the card cache table just for this.
Future<List<TimelineCardModel>> getArchivedCards() async {
  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found, returning empty archived list');
      return [];
    }

    final fileSystemService = FileSystemService.instance;
    final db = AppDatabase.instance;

    if (await db.cardDao.isCacheEmpty()) {
      await fileSystemService.rebuildCardCache(userId);
    }

    final cachedCards = await db.cardDao.getCards(page: 1, limit: 100000);

    final archived = <TimelineCardModel>[];
    for (final cachedCard in cachedCards) {
      try {
        final card = await hydrateCard(
          userId,
          cachedCard.factId,
          includeArchived: true,
        );
        if (card != null && card.archivedAt != null) {
          archived.add(card);
        }
      } catch (e) {
        _logger.warning('Failed to hydrate card ${cachedCard.factId}: $e');
      }
    }

    archived.sort((a, b) => (b.archivedAt ?? 0).compareTo(a.archivedAt ?? 0));
    return archived;
  } catch (e) {
    _logger.severe('Failed to fetch archived cards: $e');
    return [];
  }
}
