import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/timeline_card_model.dart';

TimelineCardModel _card({String? rawText, String? title}) {
  return TimelineCardModel(
    id: 'c1',
    timestamp: DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    title: title,
    uiConfigs: const [],
    rawText: rawText,
  );
}

void main() {
  group('buildRawSnippet', () {
    test('returns the raw text verbatim, not a tokenized/spaced form', () {
      final card = _card(rawText: '今天又散步了十分钟');
      expect(buildRawSnippet(card, '散步'), '今天又散步了十分钟');
    });

    test('centres the snippet around the query when the text is long', () {
      final longText = '${'x' * 50}散步${'y' * 100}';
      final card = _card(rawText: longText);
      final snippet = buildRawSnippet(card, '散步');
      expect(snippet, contains('散步'));
      expect(snippet.startsWith('...'), isTrue);
      expect(snippet.endsWith('...'), isTrue);
    });

    test('falls back to the title when rawText is empty', () {
      final card = _card(rawText: '', title: '今天的散步');
      expect(buildRawSnippet(card, '散步'), '今天的散步');
    });

    test('returns empty string when neither rawText nor title is set', () {
      final card = _card();
      expect(buildRawSnippet(card, '散步'), '');
    });

    test('truncates with an ellipsis when the query is not found', () {
      final card = _card(rawText: 'a' * 100);
      final snippet = buildRawSnippet(card, 'nope', maxLen: 20);
      expect(snippet, 'a' * 20 + '...');
    });
  });
}
