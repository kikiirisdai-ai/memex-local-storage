import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_body_text_fields.dart';

void main() {
  test('maps the templates that carry AI-written prose', () {
    expect(cardBodyTextFieldFor('snippet'), 'text');
    expect(cardBodyTextFieldFor('article'), 'body');
    expect(cardBodyTextFieldFor('quote'), 'content');
    expect(cardBodyTextFieldFor('classic_card'), 'content');
    expect(cardBodyTextFieldFor('snapshot'), 'caption');
  });

  test('returns null for title-only templates, which the card title covers',
      () {
    for (final templateId in [
      'event',
      'media_card',
      'gallery',
      'compact',
      'duration',
      'procedure',
      'metric',
    ]) {
      expect(cardBodyTextFieldFor(templateId), isNull, reason: templateId);
    }
  });

  test('returns null for structured templates with no single prose field', () {
    expect(cardBodyTextFieldFor('conversation'), isNull);
    expect(cardBodyTextFieldFor('routine'), isNull);
    expect(cardBodyTextFieldFor('insight_summary'), isNull);
  });

  test('returns null for an unknown template', () {
    expect(cardBodyTextFieldFor('not_a_template'), isNull);
  });
}
