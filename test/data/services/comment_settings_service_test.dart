import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/comment_settings_service.dart';

void main() {
  group('CommentSettings defaults', () {
    // reversible: enableCharacterComment defaults to false to declutter AI
    // character comments; toggling the setting in Settings > Comments (or
    // flipping this default back to true) restores generation.
    test('default constructor has enableCharacterComment false', () {
      const settings = CommentSettings();
      expect(settings.enableCharacterComment, isFalse);
      expect(settings.showInsightText, isTrue);
      expect(settings.maxCommentCharacters, 1);
    });

    test('fromYaml({}) falls back to enableCharacterComment false', () {
      final settings = CommentSettings.fromYaml({});
      expect(settings.enableCharacterComment, isFalse);
      expect(settings.showInsightText, isTrue);
      expect(settings.maxCommentCharacters, 1);
    });

    test('fromYaml round-trips an explicit enable_character_comment: true', () {
      final settings = CommentSettings.fromYaml({
        'enable_character_comment': true,
      });
      expect(settings.enableCharacterComment, isTrue);

      final reparsed = CommentSettings.fromYaml(
        _parseYamlLikeMap(settings.toYaml()),
      );
      expect(reparsed.enableCharacterComment, isTrue);
    });

    test('fromYaml round-trips an explicit enable_character_comment: false', () {
      final settings = CommentSettings.fromYaml({
        'enable_character_comment': false,
      });
      expect(settings.enableCharacterComment, isFalse);

      final reparsed = CommentSettings.fromYaml(
        _parseYamlLikeMap(settings.toYaml()),
      );
      expect(reparsed.enableCharacterComment, isFalse);
    });

    test('copyWith can flip enableCharacterComment back on (reversibility knob)', () {
      const settings = CommentSettings();
      final restored = settings.copyWith(enableCharacterComment: true);
      expect(restored.enableCharacterComment, isTrue);
    });
  });
}

/// Minimal parser for the simple `key: value` lines produced by
/// [CommentSettings.toYaml], sufficient for round-trip assertions in tests.
Map<String, dynamic> _parseYamlLikeMap(String yaml) {
  final map = <String, dynamic>{};
  for (final line in yaml.split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(':');
    if (parts.length < 2) continue;
    final key = parts[0].trim();
    final value = parts.sublist(1).join(':').trim();
    if (value == 'true') {
      map[key] = true;
    } else if (value == 'false') {
      map[key] = false;
    } else {
      map[key] = int.tryParse(value) ?? value;
    }
  }
  return map;
}
