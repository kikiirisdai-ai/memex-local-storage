import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/timeline_card_model.dart';

/// A media (book/movie/tv/music/podcast) record surfaced from a card's
/// `media_card` ui_config, for the Media Library aggregation page.
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.cardId,
    required this.mediaType,
    required this.mediaStatus,
    required this.title,
    required this.comment,
    required this.rating,
    required this.timestamp,
  });

  final String cardId;

  /// One of 'book' | 'movie' | 'tv' | 'music' | 'podcast' | 'other'.
  final String mediaType;

  /// One of 'want' | 'doing' | 'done', or null when unset.
  final String? mediaStatus;
  final String title;
  final String? comment;
  final int? rating;
  final DateTime timestamp;

  /// Extracts a [MediaLibraryEntry] from [card]'s `media_card` ui_config, or
  /// null when the card carries no valid media_card data.
  static MediaLibraryEntry? fromCard(TimelineCardModel card) {
    for (final config in card.uiConfigs) {
      if (config.templateId != 'media_card') continue;
      final data = config.data;
      final mediaType = sanitizeMediaType(data['media_type']);
      if (mediaType == null) return null;
      final title = data['title'] as String?;
      return MediaLibraryEntry(
        cardId: card.id,
        mediaType: mediaType,
        mediaStatus: sanitizeMediaStatus(data['media_status']),
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : (card.title ?? ''),
        comment: data['comment'] is String &&
                (data['comment'] as String).trim().isNotEmpty
            ? (data['comment'] as String).trim()
            : null,
        rating: sanitizeMoodScore(data['rating']),
        timestamp: card.timestamp,
      );
    }
    return null;
  }
}
