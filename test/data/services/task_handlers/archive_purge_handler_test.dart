import 'package:memex/data/services/task_handlers/archive_purge_handler.dart';
import 'package:test/test.dart';

void main() {
  group('isPastArchiveRetention', () {
    final now = DateTime(2026, 1, 31);

    test('null archivedAt is never past retention', () {
      expect(isPastArchiveRetention(null, now: now), isFalse);
    });

    test('archived exactly 30 days ago is past retention', () {
      final archivedAt =
          DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      expect(isPastArchiveRetention(archivedAt, now: now), isTrue);
    });

    test('archived 29 days ago is not yet past retention', () {
      final archivedAt =
          DateTime(2026, 1, 2).millisecondsSinceEpoch ~/ 1000;
      expect(isPastArchiveRetention(archivedAt, now: now), isFalse);
    });

    test('archived just now is not past retention', () {
      final archivedAt = now.millisecondsSinceEpoch ~/ 1000;
      expect(isPastArchiveRetention(archivedAt, now: now), isFalse);
    });
  });
}
