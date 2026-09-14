import 'package:memex/data/services/task_handlers/comment_agent_handler.dart';
import 'package:test/test.dart';

void main() {
  group('shouldSkipAiCommentReply', () {
    test(
        'skips when character comments are disabled and the turn was not '
        'explicitly routed to a character (regression: used to always run '
        'the comment agent regardless of this setting)', () {
      expect(
        shouldSkipAiCommentReply(
          forceReply: false,
          characterCommentsEnabled: false,
        ),
        isTrue,
      );
    });

    test('runs when character comments are enabled', () {
      expect(
        shouldSkipAiCommentReply(
          forceReply: false,
          characterCommentsEnabled: true,
        ),
        isFalse,
      );
    });

    test(
        'always runs when the user explicitly routed the turn to a '
        'character (@mention or replying to its comment), even if the '
        'setting is disabled', () {
      expect(
        shouldSkipAiCommentReply(
          forceReply: true,
          characterCommentsEnabled: false,
        ),
        isFalse,
      );
    });

    test('runs when both forceReply and the setting are true', () {
      expect(
        shouldSkipAiCommentReply(
          forceReply: true,
          characterCommentsEnabled: true,
        ),
        isFalse,
      );
    });
  });
}
