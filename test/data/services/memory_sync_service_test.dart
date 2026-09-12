import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/memory_sync_service.dart';
import 'package:memex/domain/models/card_model.dart';

CardData _card({
  String? fact,
  String? title,
  List<UiConfig> uiConfigs = const [],
}) {
  return CardData(
    factId: '2026/01/01.md#ts_1',
    timestamp: 1779789600,
    status: 'completed',
    tags: const [],
    title: title,
    fact: fact,
    uiConfigs: uiConfigs,
  );
}

void main() {
  group('deriveMemorySyncText', () {
    test('uses card.fact when present, ignoring uiConfigs', () {
      final text = deriveMemorySyncText(_card(
        fact: 'Went hiking today.',
        title: 'Hiking',
        uiConfigs: const [
          UiConfig(templateId: 'snippet', data: {'text': 'ignored'}),
        ],
      ));

      expect(text, 'Went hiking today.');
    });

    test('falls back to title + uiConfig data for a structured card with no '
        'fact', () {
      final text = deriveMemorySyncText(_card(
        title: 'Dune',
        uiConfigs: const [
          UiConfig(templateId: 'media_card', data: {
            'media_type': 'book',
            'media_status': 'doing',
            'rating': 8,
          }),
        ],
      ));

      expect(text, isNotNull);
      expect(text, contains('Dune'));
      expect(text, contains('[media_card]'));
      expect(text, contains('media_type: book'));
      expect(text, contains('media_status: doing'));
      expect(text, contains('rating: 8'));
    });

    test('falls back to uiConfig data alone when there is no title', () {
      final text = deriveMemorySyncText(_card(
        uiConfigs: const [
          UiConfig(templateId: 'task', data: {'title': 'Buy milk'}),
        ],
      ));

      expect(text, '[task] title: Buy milk');
    });

    test('returns null when there is no fact, title, or usable uiConfig data',
        () {
      final text = deriveMemorySyncText(_card(
        uiConfigs: const [
          UiConfig(templateId: 'snippet', data: {}),
        ],
      ));

      expect(text, isNull);
    });

    test('a blank fact is treated as absent and falls back to uiConfigs', () {
      final text = deriveMemorySyncText(_card(
        fact: '   ',
        title: 'Fallback title',
      ));

      expect(text, 'Fallback title');
    });

    test('skips empty/blank uiConfig field values', () {
      final text = deriveMemorySyncText(_card(
        uiConfigs: const [
          UiConfig(templateId: 'media_card', data: {
            'media_type': 'movie',
            'comment': '',
            'rating': null,
          }),
        ],
      ));

      expect(text, '[media_card] media_type: movie');
    });
  });
}
