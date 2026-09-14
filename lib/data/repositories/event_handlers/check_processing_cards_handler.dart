import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/event_bus_message.dart';
import 'package:memex/data/services/card_renderer.dart';
import 'package:memex/domain/models/card_detail_model.dart';

final Logger _logger = getLogger('CheckProcessingCardsHandler');

/// A "processing" placeholder is considered abandoned once it's been stuck
/// this long — a card only stays in 'processing' while some agent
/// run/background task is actively working on it, so if that process was
/// killed (e.g. hit the task executor's own execution timeout) without
/// ever finishing, the card would otherwise sit showing "处理中" forever.
const Duration processingCardStaleness = Duration(minutes: 5);

@visibleForTesting
bool isStaleProcessingCard(CardData card, {required DateTime now}) {
  final startedAtSeconds = card.createdAt ?? card.timestamp;
  final startedAt =
      DateTime.fromMillisecondsSinceEpoch(startedAtSeconds * 1000);
  return now.difference(startedAt) >= processingCardStaleness;
}

/// Handle client request to check processing-status cards
/// Maps to backend _handle_check_processing_cards
///
/// Args:
///   message: EventBus message with card_ids list
Future<void> handleCheckProcessingCards(
  Map<String, dynamic> message, {
  required void Function(EventBusMessage) emitEvent,
}) async {
  try {
    final data = message['data'] as Map<String, dynamic>? ?? {};
    final cardIds = (data['card_ids'] as List<dynamic>?)?.cast<String>() ?? [];

    if (cardIds.isEmpty) {
      _logger.info('No card IDs to check');
      return;
    }

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found, cannot check processing cards');
      return;
    }

    _logger
        .info('Checking ${cardIds.length} processing cards for user $userId');

    final fileSystemService = FileSystemService.instance;

    for (final cardId in cardIds) {
      try {
        // Read card data
        final cardData = await fileSystemService.readCardFile(userId, cardId);
        if (cardData == null) {
          continue;
        }

        final cardStatus = cardData.status;

        if (cardStatus != 'processing') {
          try {
            final renderResult = await renderCard(
              userId: userId,
              cardData: cardData,
              factContent: cardData.fact,
            );

            final tags = List<String>.from(cardData.tags);
            final timestamp = cardData.timestamp;
            final title = cardData.title;

            // Extract assets and rawText from the card's own fields
            final assetsAndText =
                await extractAssetsAndRawText(userId, cardData);
            final assets = (assetsAndText['assets'] as List<AssetData>)
                .map((a) => a.toJson())
                .toList();
            final rawText = assetsAndText['rawText'] as String?;

            // Emit update via local event
            emitEvent(CardUpdatedMessage(
              id: cardId,
              html: renderResult.html ?? '',
              timestamp: timestamp,
              tags: tags,
              status: renderResult.status,
              title: title,
              uiConfigs: renderResult.uiConfigs,
              assets: assets.isNotEmpty ? assets : null,
              rawText: rawText,
              address: cardData.address,
            ));

            _logger.info(
                'Sent card update for $cardId (status changed from processing to ${renderResult.status})');
          } catch (e) {
            _logger.warning(
                'Failed to render and send card update for $cardId: $e');
          }
        } else if (isStaleProcessingCard(cardData, now: DateTime.now())) {
          try {
            await fileSystemService.deleteCard(userId, cardId);
            emitEvent(CardDeletedMessage(id: cardId));
            _logger.info(
                'Deleted stale processing card $cardId (stuck > $processingCardStaleness with no update)');
          } catch (e) {
            _logger.warning(
                'Failed to delete stale processing card $cardId: $e');
          }
        }
      } catch (e) {
        _logger.warning('Error checking card $cardId: $e');
      }
    }
  } catch (e, stackTrace) {
    _logger.severe('Error handling check_processing_cards: $e', e, stackTrace);
  }
}
