import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/backup_safety.dart';

void main() {
  group('shouldNudgeExport', () {
    final now = DateTime(2026, 9, 5);

    test('null lastExport -> true', () {
      expect(
        shouldNudgeExport(lastExport: null, snoozeUntil: null, now: now),
        isTrue,
      );
    });

    test('lastExport 20 days ago -> true', () {
      final lastExport = now.subtract(const Duration(days: 20));
      expect(
        shouldNudgeExport(
          lastExport: lastExport,
          snoozeUntil: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('lastExport 2 days ago -> false', () {
      final lastExport = now.subtract(const Duration(days: 2));
      expect(
        shouldNudgeExport(
          lastExport: lastExport,
          snoozeUntil: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('snoozeUntil in future -> false even if overdue', () {
      final lastExport = now.subtract(const Duration(days: 20));
      final snoozeUntil = now.add(const Duration(days: 5));
      expect(
        shouldNudgeExport(
          lastExport: lastExport,
          snoozeUntil: snoozeUntil,
          now: now,
        ),
        isFalse,
      );
    });

    test('snoozeUntil in past + overdue -> true', () {
      final lastExport = now.subtract(const Duration(days: 20));
      final snoozeUntil = now.subtract(const Duration(days: 1));
      expect(
        shouldNudgeExport(
          lastExport: lastExport,
          snoozeUntil: snoozeUntil,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('shouldSnapshotBeforeMigration', () {
    test('stored null -> false', () {
      expect(shouldSnapshotBeforeMigration(stored: null, code: 17), isFalse);
    });

    test('stored 16, code 17 -> true', () {
      expect(shouldSnapshotBeforeMigration(stored: 16, code: 17), isTrue);
    });

    test('stored 17, code 17 -> false', () {
      expect(shouldSnapshotBeforeMigration(stored: 17, code: 17), isFalse);
    });

    test('stored 18, code 17 -> false', () {
      expect(shouldSnapshotBeforeMigration(stored: 18, code: 17), isFalse);
    });
  });

  group('maybeSnapshotBeforeMigration', () {
    test('stored < code -> snapshots (before migrate), then migrates, then sets stored version', () async {
      String? snapshotReason;
      int? setStoredValue;
      final callOrder = <String>[];

      await maybeSnapshotBeforeMigration(
        getStored: () async => 16,
        code: 17,
        snapshot: (reason) async {
          snapshotReason = reason;
          callOrder.add('snapshot');
        },
        migrate: () async {
          callOrder.add('migrate');
        },
        setStored: (value) async {
          setStoredValue = value;
          callOrder.add('setStored');
        },
      );

      expect(snapshotReason, 'before_migration_v17');
      expect(setStoredValue, 17);
      expect(callOrder, ['snapshot', 'migrate', 'setStored']);
    });

    test('stored == code -> no snapshot, still migrates and sets stored version', () async {
      var snapshotCalled = false;
      var migrateCalled = false;
      int? setStoredValue;

      await maybeSnapshotBeforeMigration(
        getStored: () async => 17,
        code: 17,
        snapshot: (reason) async {
          snapshotCalled = true;
        },
        migrate: () async {
          migrateCalled = true;
        },
        setStored: (value) async {
          setStoredValue = value;
        },
      );

      expect(snapshotCalled, isFalse);
      expect(migrateCalled, isTrue);
      expect(setStoredValue, 17);
    });

    test('stored == null (first install) -> no snapshot, still migrates and sets stored version', () async {
      var snapshotCalled = false;
      var migrateCalled = false;
      int? setStoredValue;

      await maybeSnapshotBeforeMigration(
        getStored: () async => null,
        code: 17,
        snapshot: (reason) async {
          snapshotCalled = true;
        },
        migrate: () async {
          migrateCalled = true;
        },
        setStored: (value) async {
          setStoredValue = value;
        },
      );

      expect(snapshotCalled, isFalse);
      expect(migrateCalled, isTrue);
      expect(setStoredValue, 17);
    });

    test('snapshot throws -> migrate still runs and setStored is still called (startup not blocked)', () async {
      var migrateCalled = false;
      int? setStoredValue;

      await maybeSnapshotBeforeMigration(
        getStored: () async => 16,
        code: 17,
        snapshot: (reason) async {
          throw Exception('snapshot failed');
        },
        migrate: () async {
          migrateCalled = true;
        },
        setStored: (value) async {
          setStoredValue = value;
        },
      );

      expect(migrateCalled, isTrue);
      expect(setStoredValue, 17);
    });

    test('migrate throws -> setStored is NOT called (failed migration must not be recorded)', () async {
      var setStoredCalled = false;

      await expectLater(
        maybeSnapshotBeforeMigration(
          getStored: () async => 16,
          code: 17,
          snapshot: (reason) async {},
          migrate: () async {
            throw Exception('migration failed');
          },
          setStored: (value) async {
            setStoredCalled = true;
          },
        ),
        throwsA(isA<Exception>()),
      );

      expect(setStoredCalled, isFalse);
    });
  });

  group('isPathInside', () {
    test('child directly under parent -> true', () {
      expect(isPathInside('/a/b/Backups', '/a/b'), isTrue);
    });

    test('sibling directory, not under parent -> false', () {
      expect(isPathInside('/a/Support/x', '/a/b'), isFalse);
    });

    test('equal paths -> true', () {
      expect(isPathInside('/a/b', '/a/b'), isTrue);
    });

    test('sibling with shared prefix but not nested -> false', () {
      expect(isPathInside('/a/bb', '/a/b'), isFalse);
    });
  });

  group('takeWipeSafetySnapshot', () {
    test('calls createBackup with the resolved safe dir', () async {
      String? capturedDir;
      var resolveCalled = false;

      await takeWipeSafetySnapshot(
        resolveSafeDir: () async {
          resolveCalled = true;
          return '/App/Library/Application Support/SafetySnapshots';
        },
        createBackup: (outputDir) async {
          capturedDir = outputDir;
          return '/App/Library/Application Support/SafetySnapshots/x.memex';
        },
      );

      expect(resolveCalled, isTrue);
      expect(capturedDir, '/App/Library/Application Support/SafetySnapshots');
    });

    test('createBackup throws -> does not rethrow, onError is called',
        () async {
      Object? reportedError;

      await takeWipeSafetySnapshot(
        resolveSafeDir: () async => '/App/Library/Application Support/x',
        createBackup: (outputDir) async {
          throw Exception('boom');
        },
        onError: (error) {
          reportedError = error;
        },
      );

      expect(reportedError, isNotNull);
    });

    test('resolveSafeDir throws -> does not rethrow, onError is called',
        () async {
      Object? reportedError;

      await takeWipeSafetySnapshot(
        resolveSafeDir: () async => throw Exception('resolve failed'),
        createBackup: (outputDir) async => 'unused',
        onError: (error) {
          reportedError = error;
        },
      );

      expect(reportedError, isNotNull);
    });
  });

  group('wipe safety snapshot location guard', () {
    test('safe dir for wipe is NOT inside representative iOS dataRoot', () {
      const dataRoot = '/App/Documents';
      const safeDir = '/App/Library/Application Support/SafetySnapshots';
      expect(isPathInside(safeDir, dataRoot), isFalse);
    });
  });
}
