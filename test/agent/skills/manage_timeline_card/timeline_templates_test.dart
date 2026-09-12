import 'package:memex/agent/skills/manage_timeline_card/timeline_templates.dart';
import 'package:test/test.dart';

void main() {
  group('media_card', () {
    test('is registered in allowedTemplateIds', () {
      expect(allowedTemplateIds.contains('media_card'), isTrue);
    });

    test('validateTemplateData accepts the quick-capture writer\'s real '
        'data map without throwing', () {
      // Mirrors the exact shape written by
      // QuickCaptureService._writeCard's media branch
      // (lib/data/services/quick_capture_service.dart).
      final writerData = <String, dynamic>{
        'media_type': 'book',
        'media_status': 'doing',
        'title': '百年孤独',
        'comment': '挺好看的',
        'rating': 7,
      };

      expect(
        () => validateTemplateData('media_card', writerData),
        returnsNormally,
      );
    });

    test('validateTemplateData accepts minimal data (all fields optional)',
        () {
      expect(
        () => validateTemplateData('media_card', <String, dynamic>{
          'media_type': 'movie',
          'title': '',
        }),
        returnsNormally,
      );
    });

    test('validateTemplateData accepts an empty map', () {
      expect(
        () => validateTemplateData('media_card', <String, dynamic>{}),
        returnsNormally,
      );
    });
  });
}
