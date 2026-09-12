import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';

void main() {
  group('visibleComments (AI character comment declutter)', () {
    // reversible: when enableCharacterComment is true, all comments are
    // shown unchanged; this is the knob that restores the old behavior.
    test('keeps all comments when enableCharacterComment is true', () {
      final comments = [_userComment(), _aiComment()];

      final result = visibleComments(comments, true);

      expect(result, hasLength(2));
      expect(result.map((c) => c.id), ['user-1', 'ai-1']);
    });

    test('hides AI comments but keeps user comments when disabled', () {
      final comments = [_userComment(), _aiComment()];

      final result = visibleComments(comments, false);

      expect(result, hasLength(1));
      expect(result.single.id, 'user-1');
      expect(result.single.isAi, isFalse);
    });

    test('returns empty list when only AI comments exist and disabled', () {
      final comments = [_aiComment(), _aiComment(id: 'ai-2')];

      final result = visibleComments(comments, false);

      expect(result, isEmpty);
    });

    test('is a no-op on an empty comment list', () {
      expect(visibleComments(const [], false), isEmpty);
      expect(visibleComments(const [], true), isEmpty);
    });
  });
}

Comment _userComment() {
  return Comment(
    id: 'user-1',
    content: 'A user-written comment',
    isAi: false,
    timestamp: 1000,
  );
}

Comment _aiComment({String id = 'ai-1'}) {
  return Comment(
    id: id,
    content: 'An AI character comment',
    isAi: true,
    timestamp: 1001,
    character: CharacterInfo(id: 'char-1', name: 'Nova', tags: const []),
  );
}
