import 'package:memex/domain/models/media_library_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:test/test.dart';

TimelineCardModel _card({
  String id = 'card_1',
  DateTime? timestamp,
  String? cardTitle,
  required List<UiConfig> uiConfigs,
}) {
  return TimelineCardModel(
    id: id,
    timestamp: timestamp ?? DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    title: cardTitle,
    uiConfigs: uiConfigs,
  );
}

void main() {
  group('MediaLibraryEntry.fromCard', () {
    test('extracts all fields from a full media_card config', () {
      final entry = MediaLibraryEntry.fromCard(_card(uiConfigs: [
        const UiConfig(templateId: 'media_card', data: {
          'media_type': 'book',
          'media_status': 'doing',
          'title': 'Dune',
          'comment': 'Great world-building',
          'rating': 9,
        }),
      ]));

      expect(entry, isNotNull);
      expect(entry!.mediaType, 'book');
      expect(entry.mediaStatus, 'doing');
      expect(entry.title, 'Dune');
      expect(entry.comment, 'Great world-building');
      expect(entry.rating, 9);
    });

    test('falls back to the card title when the config has none', () {
      final entry = MediaLibraryEntry.fromCard(_card(
        cardTitle: 'Card-level title',
        uiConfigs: [
          const UiConfig(
            templateId: 'media_card',
            data: {'media_type': 'movie'},
          ),
        ],
      ));

      expect(entry!.title, 'Card-level title');
      expect(entry.mediaStatus, isNull);
      expect(entry.rating, isNull);
      expect(entry.comment, isNull);
    });

    test('returns null for a card with no media_card config', () {
      final entry = MediaLibraryEntry.fromCard(_card(uiConfigs: [
        const UiConfig(templateId: 'snippet', data: {'text': 'hi'}),
      ]));

      expect(entry, isNull);
    });

    test('returns null when media_type is missing or invalid', () {
      final entry = MediaLibraryEntry.fromCard(_card(uiConfigs: [
        const UiConfig(
          templateId: 'media_card',
          data: {'media_type': 'not_a_real_type'},
        ),
      ]));

      expect(entry, isNull);
    });

    test('drops a blank comment', () {
      final entry = MediaLibraryEntry.fromCard(_card(uiConfigs: [
        const UiConfig(
          templateId: 'media_card',
          data: {'media_type': 'tv', 'comment': '   '},
        ),
      ]));

      expect(entry!.comment, isNull);
    });
  });
}
