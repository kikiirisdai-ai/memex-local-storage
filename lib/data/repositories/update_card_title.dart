import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/timeline_card_event_publisher.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('UpdateCardTitleEndpoint');
FileSystemService get _fileSystemService => FileSystemService.instance;

/// Overwrites a card's title, which is how the user corrects wording the AI
/// got wrong. A blank title clears it rather than storing an empty string, so
/// the card renders the same as one the AI never titled.
///
/// Emits the timeline-card-updated event so the screen refreshes and the
/// search/embedding indexes pick up the new wording.
Future<bool> updateCardTitleEndpoint(String cardId, String title) async {
  final trimmed = title.trim();
  _logger.info('updateCardTitle called: cardId=$cardId');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw Exception('User not logged in, cannot update card title');
    }

    final updatedCardData = await _fileSystemService.updateCardFile(
      userId,
      cardId,
      (card) => trimmed.isEmpty
          ? card.copyWith(clearTitle: true)
          : card.copyWith(title: trimmed),
    );

    if (updatedCardData == null) {
      _logger.warning('Card not found: $cardId');
      return false;
    }

    await emitTimelineCardUpdated(
      userId: userId,
      cardId: cardId,
      cardData: updatedCardData,
    );
    return true;
  } catch (e) {
    _logger.severe('Failed to update card title for $cardId: $e');
    return false;
  }
}
