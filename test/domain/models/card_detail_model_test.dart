import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:test/test.dart';

CardDetailModel _detail({Map<String, dynamic>? metadata}) {
  return CardDetailModel(
    id: 'c1',
    title: 't',
    timestamp: DateTime(2026, 9, 7),
    address: '',
    tags: const [],
    rawContent: '',
    insight: InsightData.fromJson(const {}),
    assets: const [],
    metadata: metadata,
  );
}

void main() {
  group('CardDetailModel media getters', () {
    test('no media_type means not a media card', () {
      final d = _detail(metadata: {'mood_score': 7});
      expect(d.mediaType, isNull);
      expect(d.mediaStatusValue, isNull);
      expect(d.mediaRatingValue, isNull);
    });

    test('reads validated type/status/rating/comment', () {
      final d = _detail(metadata: {
        'media_type': 'movie',
        'media_status': 'done',
        'media_rating': 8,
        'media_comment': '挺好看的',
        'media_author': '诺兰',
        'media_year': '2023',
      });
      expect(d.mediaType, 'movie');
      expect(d.mediaStatusValue, 'done');
      expect(d.mediaRatingValue, 8);
      expect(d.mediaComment, '挺好看的');
      expect(d.mediaAuthor, '诺兰');
      expect(d.mediaYear, '2023');
      expect(d.isUserRatedMedia, isFalse);
    });

    test('user rating overrides AI rating', () {
      final d = _detail(metadata: {
        'media_type': 'book',
        'media_rating': 6,
        'user_media_rating': 9,
      });
      expect(d.mediaRatingValue, 9);
      expect(d.isUserRatedMedia, isTrue);
    });

    test('invalid status/rating sanitize to null', () {
      final d = _detail(metadata: {
        'media_type': 'book',
        'media_status': 'watching',
        'media_rating': 99,
      });
      expect(d.mediaStatusValue, isNull);
      expect(d.mediaRatingValue, isNull);
    });

    test('blank comment/author/year become null', () {
      final d = _detail(metadata: {
        'media_type': 'book',
        'media_comment': '   ',
        'media_author': '',
      });
      expect(d.mediaComment, isNull);
      expect(d.mediaAuthor, isNull);
      expect(d.mediaYear, isNull);
    });
  });
}
