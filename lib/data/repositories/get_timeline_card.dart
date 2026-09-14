import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/repositories/hydrate_card.dart';

final _logger = getLogger('GetTimelineCardEndpoint');

/// Get single timeline card
/// Maps to backend GET /timeline/:id (or equivalent)
Future<TimelineCardModel?> getTimelineCard(String cardId) async {
  _logger.info('getTimelineCard called: cardId=$cardId');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found');
      return null;
    }

    // A single-card fetch by known id is used for the detail screen from
    // any list (including the Archive list), so archived cards must still
    // resolve — only the aggregate timeline listing excludes them.
    return await hydrateCard(userId, cardId, includeArchived: true);
  } catch (e) {
    _logger.severe('Failed to fetch timeline card $cardId: $e');
    return null;
  }
}
