import 'package:test/test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/card_model.dart';

CardDetailModel _model(Map<String, dynamic>? md) => CardDetailModel(
      id: 'c1',
      title: 'test',
      timestamp: DateTime.now(),
      address: '',
      tags: [],
      rawContent: 'orig',
      insight: InsightData(
        text: '',
        relatedCards: [],
        comments: [],
      ),
      assets: [],
      metadata: md,
    );

void main() {
  test('originalText reads metadata original_text, trims, empty->null', () {
    expect(_model({'original_text': '  hi  '}).originalText, 'hi');
    expect(_model({'original_text': '   '}).originalText, isNull);
    expect(_model(null).originalText, isNull);
  });
  test('originalText returns null instead of throwing for non-String value',
      () {
    expect(_model({'original_text': 42}).originalText, isNull);
  });
  test('polishedStyle passthrough', () {
    expect(_model({'polished_style': 'literary'}).polishedStyle, 'literary');
    expect(_model(null).polishedStyle, isNull);
  });
  test('polishedStyle returns null instead of throwing for non-String value',
      () {
    expect(_model({'polished_style': 7}).polishedStyle, isNull);
  });
}
