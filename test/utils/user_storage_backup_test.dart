import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserStorage backup safety accessors', () {
    const userId = 'backup-safety-user';

    test('getLastManualExportAt is null when unset', () async {
      expect(await UserStorage.getLastManualExportAt(userId), isNull);
    });

    test('setLastManualExportAt / getLastManualExportAt round-trip',
        () async {
      final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await UserStorage.setLastManualExportAt(userId, when);
      final result = await UserStorage.getLastManualExportAt(userId);
      expect(
        result?.millisecondsSinceEpoch,
        when.millisecondsSinceEpoch,
      );
    });

    test('getExportNudgeSnoozeUntil is null when unset', () async {
      expect(await UserStorage.getExportNudgeSnoozeUntil(userId), isNull);
    });

    test(
        'setExportNudgeSnoozeUntil / getExportNudgeSnoozeUntil round-trip',
        () async {
      final until = DateTime.fromMillisecondsSinceEpoch(1800000000000);
      await UserStorage.setExportNudgeSnoozeUntil(userId, until);
      final result = await UserStorage.getExportNudgeSnoozeUntil(userId);
      expect(
        result?.millisecondsSinceEpoch,
        until.millisecondsSinceEpoch,
      );
    });

    test('getLastSchemaVersion is null when unset', () async {
      expect(await UserStorage.getLastSchemaVersion(), isNull);
    });

    test('setLastSchemaVersion / getLastSchemaVersion round-trip', () async {
      await UserStorage.setLastSchemaVersion(17);
      expect(await UserStorage.getLastSchemaVersion(), 17);
    });

    test('getLastSchemaVersion is global, not per-user', () async {
      await UserStorage.setLastSchemaVersion(5);
      expect(await UserStorage.getLastSchemaVersion(), 5);
    });

    test('isAutoBackupEnabled defaults to true when unset', () async {
      expect(await UserStorage.isAutoBackupEnabled(userId), isTrue);
    });
  });
}
