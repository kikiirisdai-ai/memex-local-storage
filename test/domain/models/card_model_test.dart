import 'package:memex/domain/models/card_model.dart';
import 'package:test/test.dart';

void main() {
  group('CardData.metadata serialization', () {
    test('round-trips through toJson/fromJson', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: ['生活'],
        uiConfigs: [],
        metadata: {
          CardMetadataKeys.moodScore: 8,
          CardMetadataKeys.moodLabel: '开心',
        },
      );

      final restored = CardData.fromJson(card.toJson());
      expect(restored.metadata, {
        'mood_score': 8,
        'mood_label': '开心',
      });
    });

    test('archivedAt round-trips through toJson/fromJson', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
        archivedAt: 500,
      );

      expect(card.toJson()['archived_at'], 500);
      expect(CardData.fromJson(card.toJson()).archivedAt, 500);
    });

    test('archivedAt absent stays null and is omitted from JSON', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
      );
      expect(card.toJson().containsKey('archived_at'), isFalse);
      expect(CardData.fromJson(card.toJson()).archivedAt, isNull);
    });

    test('copyWith(clearArchivedAt: true) clears an existing archivedAt', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
        archivedAt: 500,
      );
      final cleared = card.copyWith(clearArchivedAt: true);
      expect(cleared.archivedAt, isNull);
    });

    test('absent metadata stays null and is omitted from JSON', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
      );
      expect(card.toJson().containsKey('metadata'), isFalse);
      expect(CardData.fromJson(card.toJson()).metadata, isNull);
    });

    test('empty metadata map is omitted from JSON', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
        metadata: {},
      );
      expect(card.toJson().containsKey('metadata'), isFalse);
    });

    test('non-map metadata in JSON is ignored', () {
      final restored = CardData.fromJson({
        'fact_id': 'f1',
        'timestamp': 100,
        'status': 'completed',
        'tags': <String>[],
        'ui_configs': <Map<String, dynamic>>[],
        'metadata': 'garbage',
      });
      expect(restored.metadata, isNull);
    });

    test('copyWith sets and preserves metadata', () {
      const card = CardData(
        factId: 'f1',
        timestamp: 100,
        status: 'completed',
        tags: [],
        uiConfigs: [],
      );
      final withMood =
          card.copyWith(metadata: {CardMetadataKeys.moodScore: 5});
      expect(withMood.metadata, {'mood_score': 5});
      // A copyWith that does not mention metadata keeps the existing value.
      expect(withMood.copyWith(title: 't').metadata, {'mood_score': 5});
    });
  });

  group('sanitizeMoodScore', () {
    test('accepts ints and numeric strings within 1-10', () {
      expect(sanitizeMoodScore(1), 1);
      expect(sanitizeMoodScore(10), 10);
      expect(sanitizeMoodScore(7.4), 7);
      expect(sanitizeMoodScore('8'), 8);
      expect(sanitizeMoodScore(' 3 '), 3);
    });

    test('rejects out-of-range, mistyped, and absent values', () {
      expect(sanitizeMoodScore(0), isNull);
      expect(sanitizeMoodScore(11), isNull);
      expect(sanitizeMoodScore(-5), isNull);
      expect(sanitizeMoodScore('very happy'), isNull);
      expect(sanitizeMoodScore(null), isNull);
      expect(sanitizeMoodScore(true), isNull);
    });
  });

  group('sanitizeMediaType', () {
    test('accepts whitelisted values', () {
      expect(sanitizeMediaType('book'), 'book');
      expect(sanitizeMediaType('movie'), 'movie');
      expect(sanitizeMediaType('tv'), 'tv');
      expect(sanitizeMediaType('music'), 'music');
      expect(sanitizeMediaType('podcast'), 'podcast');
      expect(sanitizeMediaType('other'), 'other');
    });

    test('rejects unknown, non-string, or empty values', () {
      expect(sanitizeMediaType('novel'), isNull);
      expect(sanitizeMediaType('Book'), isNull);
      expect(sanitizeMediaType(''), isNull);
      expect(sanitizeMediaType(null), isNull);
      expect(sanitizeMediaType(42), isNull);
    });
  });

  group('sanitizeMediaStatus', () {
    test('accepts whitelisted values', () {
      expect(sanitizeMediaStatus('want'), 'want');
      expect(sanitizeMediaStatus('doing'), 'doing');
      expect(sanitizeMediaStatus('done'), 'done');
    });

    test('rejects unknown, non-string, or empty values', () {
      expect(sanitizeMediaStatus('watching'), isNull);
      expect(sanitizeMediaStatus(''), isNull);
      expect(sanitizeMediaStatus(null), isNull);
      expect(sanitizeMediaStatus(7), isNull);
    });
  });

  group('mediaMetadataFromUiConfigData', () {
    test('derives all metadata fields from a full media_card data map', () {
      final result = mediaMetadataFromUiConfigData({
        'media_type': 'book',
        'media_status': 'doing',
        'title': 'Ignored — not a metadata field',
        'rating': 8,
        'comment': 'Great so far',
      });

      expect(result, {
        CardMetadataKeys.mediaType: 'book',
        CardMetadataKeys.mediaStatus: 'doing',
        CardMetadataKeys.mediaRating: 8,
        CardMetadataKeys.mediaComment: 'Great so far',
      });
    });

    test('returns empty map when media_type is missing or invalid', () {
      expect(mediaMetadataFromUiConfigData({'rating': 8}), isEmpty);
      expect(
        mediaMetadataFromUiConfigData({'media_type': 'not_a_real_type'}),
        isEmpty,
      );
    });

    test('omits optional fields that are absent or invalid', () {
      final result = mediaMetadataFromUiConfigData({'media_type': 'movie'});

      expect(result, {CardMetadataKeys.mediaType: 'movie'});
    });

    test('trims comment and drops blank comments', () {
      final result = mediaMetadataFromUiConfigData({
        'media_type': 'tv',
        'comment': '   ',
      });

      expect(result, {CardMetadataKeys.mediaType: 'tv'});
    });
  });
}
