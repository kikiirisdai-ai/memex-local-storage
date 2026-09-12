import 'package:memex/domain/models/goal_model.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeGoalType', () {
    test('accepts whitelisted values', () {
      expect(sanitizeGoalType('quantitative'), 'quantitative');
      expect(sanitizeGoalType('binary'), 'binary');
    });

    test('rejects unknown, non-string, or empty values', () {
      expect(sanitizeGoalType('progress'), isNull);
      expect(sanitizeGoalType(''), isNull);
      expect(sanitizeGoalType(null), isNull);
      expect(sanitizeGoalType(1), isNull);
    });
  });

  group('sanitizeGoalStatus', () {
    test('accepts whitelisted values', () {
      expect(sanitizeGoalStatus('active'), 'active');
      expect(sanitizeGoalStatus('completed'), 'completed');
    });

    test('rejects unknown, non-string, or empty values', () {
      expect(sanitizeGoalStatus('done'), isNull);
      expect(sanitizeGoalStatus(''), isNull);
      expect(sanitizeGoalStatus(null), isNull);
      expect(sanitizeGoalStatus(2), isNull);
    });
  });
}
