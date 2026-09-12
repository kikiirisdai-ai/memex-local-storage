import 'package:memex/domain/models/goal_suggestion.dart';
import 'package:test/test.dart';

void main() {
  group('asPositiveFinite', () {
    test('accepts positive numbers and numeric strings', () {
      expect(asPositiveFinite(3), 3.0);
      expect(asPositiveFinite(2.5), 2.5);
      expect(asPositiveFinite('4'), 4.0);
      expect(asPositiveFinite(' 1.5 '), 1.5);
    });

    test('rejects NaN, Infinity, negative, zero, and garbage', () {
      expect(asPositiveFinite(double.nan), isNull);
      expect(asPositiveFinite(double.infinity), isNull);
      expect(asPositiveFinite('NaN'), isNull);
      expect(asPositiveFinite('Infinity'), isNull);
      expect(asPositiveFinite(-5), isNull);
      expect(asPositiveFinite(0), isNull);
      expect(asPositiveFinite('abc'), isNull);
      expect(asPositiveFinite(null), isNull);
    });
  });
}
