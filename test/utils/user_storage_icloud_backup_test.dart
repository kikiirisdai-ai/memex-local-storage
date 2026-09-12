import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ymd round-trip + null default', () async {
    expect(await UserStorage.getLastICloudDailyBackupYmd('u'), isNull);
    await UserStorage.setLastICloudDailyBackupYmd('u', '2026-09-06');
    expect(await UserStorage.getLastICloudDailyBackupYmd('u'), '2026-09-06');
  });

  test('folder label set/clear', () async {
    await UserStorage.setICloudBackupFolderLabel('u', 'memex backup');
    expect(await UserStorage.getICloudBackupFolderLabel('u'), 'memex backup');
    await UserStorage.setICloudBackupFolderLabel('u', null);
    expect(await UserStorage.getICloudBackupFolderLabel('u'), isNull);
  });

  test('needsRepick default false + round-trip', () async {
    expect(await UserStorage.getICloudBackupNeedsRepick('u'), isFalse);
    await UserStorage.setICloudBackupNeedsRepick('u', true);
    expect(await UserStorage.getICloudBackupNeedsRepick('u'), isTrue);
  });
}
