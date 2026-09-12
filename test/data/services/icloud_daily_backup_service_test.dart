import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/data/services/external_backup_channel.dart';
import 'package:memex/data/services/icloud_daily_backup_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Records channel calls in order so tests can assert call sequencing.
class _FakeChannel implements ExternalBackupChannel {
  final List<String> calls = [];

  ICloudFolderStatus statusToReturn =
      const ICloudFolderStatus(configured: true, isStale: false);
  List<ExternalBackupFile> listToReturn = const [];
  ExternalFolder? pickToReturn;
  bool renameReturn = true;
  bool deleteReturn = true;
  String writeReturn = '/iCloud/x/memex_daily.memex';
  String readToTempReturn = '/tmp/memex_daily.memex';
  Object? writeThrows;

  @override
  Future<ExternalFolder?> pickICloudFolder() async {
    calls.add('pick');
    return pickToReturn;
  }

  @override
  Future<String> readFileToTemp(String fileName) async {
    calls.add('readToTemp:$fileName');
    return readToTempReturn;
  }

  @override
  Future<ICloudFolderStatus> icloudStatus() async {
    calls.add('status');
    return statusToReturn;
  }

  @override
  Future<List<ExternalBackupFile>> listFiles() async {
    calls.add('list');
    return listToReturn;
  }

  @override
  Future<String> writeFile(
      {required String sourcePath, required String fileName}) async {
    calls.add('write:$fileName');
    if (writeThrows != null) throw writeThrows!;
    return writeReturn;
  }

  @override
  Future<bool> renameFile({required String from, required String to}) async {
    calls.add('rename:$from->$to');
    return renameReturn;
  }

  @override
  Future<bool> deleteFile(String fileName) async {
    calls.add('delete:$fileName');
    return deleteReturn;
  }

  @override
  Future<void> clearFolder() async {
    calls.add('clear');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  final fixedNow = DateTime(2026, 9, 6, 10, 30);

  late _FakeChannel fake;

  ICloudDailyBackupService buildService({
    Future<String> Function({
      required String outputDirectory,
      required String filePrefix,
    })? createBackupFn,
  }) {
    return ICloudDailyBackupService(
      channel: fake,
      createBackupFn: createBackupFn ??
          (({required outputDirectory, required filePrefix}) async =>
              '/tmp/out.memex'),
      tempDirFn: () async => '/tmp',
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeChannel();
  });

  test('not configured -> noop, returns false', () async {
    fake.statusToReturn =
        const ICloudFolderStatus(configured: false, isStale: false);
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isFalse);
    expect(fake.calls.any((c) => c.startsWith('write')), isFalse);
    expect(await UserStorage.getLastICloudDailyBackupYmd(userId), isNull);
  });

  test('disabled -> noop', () async {
    await UserStorage.setAutoBackupEnabled(userId, false);
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isFalse);
    expect(fake.calls, isEmpty);
  });

  test('already backed up today -> noop', () async {
    await UserStorage.setLastICloudDailyBackupYmd(userId, '2026-09-06');
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isFalse);
    expect(fake.calls.any((c) => c.startsWith('write')), isFalse);
  });

  test('first backup: empty folder -> writeFile(daily) only, records ymd',
      () async {
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    fake.listToReturn = const [];
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isTrue);
    expect(fake.calls, ['status', 'list', 'write:memex_daily.memex']);
    expect(await UserStorage.getLastICloudDailyBackupYmd(userId), '2026-09-06');
  });

  test('new day with daily present -> rename daily->prev then write daily',
      () async {
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    fake.listToReturn = [
      ExternalBackupFile(
          name: ICloudDailyBackupService.dailyName,
          path: '/i/d',
          sizeBytes: 1,
          modified: DateTime(2026, 9, 5)),
    ];
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isTrue);
    expect(fake.calls, [
      'status',
      'list',
      'rename:memex_daily.memex->memex_daily_prev.memex',
      'write:memex_daily.memex',
    ]);
  });

  test(
      'new day with daily+prev -> delete prev, rename daily->prev, write '
      'daily', () async {
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    fake.listToReturn = [
      ExternalBackupFile(
          name: ICloudDailyBackupService.dailyName,
          path: '/i/d',
          sizeBytes: 1,
          modified: DateTime(2026, 9, 5)),
      ExternalBackupFile(
          name: ICloudDailyBackupService.prevName,
          path: '/i/p',
          sizeBytes: 1,
          modified: DateTime(2026, 9, 4)),
    ];
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isTrue);
    expect(fake.calls, [
      'status',
      'list',
      'delete:memex_daily_prev.memex',
      'rename:memex_daily.memex->memex_daily_prev.memex',
      'write:memex_daily.memex',
    ]);
  });

  test('force overwrites daily without touching prev when same day', () async {
    await UserStorage.setLastICloudDailyBackupYmd(userId, '2026-09-06');
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: false);
    fake.listToReturn = [
      ExternalBackupFile(
          name: ICloudDailyBackupService.dailyName,
          path: '/i/d',
          sizeBytes: 1,
          modified: DateTime(2026, 9, 6)),
    ];
    final service = buildService();

    final result = await service.maybeCreateDailyBackup(
        userId: userId, now: fixedNow, force: true);

    expect(result, isTrue);
    expect(fake.calls, ['status', 'write:memex_daily.memex']);
    expect(fake.calls.any((c) => c.startsWith('rename')), isFalse);
    expect(fake.calls.any((c) => c.startsWith('delete')), isFalse);
  });

  test(
      'isStale on status -> sets needsRepick, returns false, does not '
      'throw', () async {
    fake.statusToReturn =
        const ICloudFolderStatus(configured: true, isStale: true);
    final service = buildService();

    final result =
        await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

    expect(result, isFalse);
    expect(await UserStorage.getICloudBackupNeedsRepick(userId), isTrue);
    expect(fake.calls.any((c) => c.startsWith('write')), isFalse);
  });

  test(
    'createBackupFn throwing a generic error -> caught, returns false, '
    'does NOT set needsRepick (transient failure, not a bookmark problem)',
    () async {
      fake.statusToReturn =
          const ICloudFolderStatus(configured: true, isStale: false);
      final service = buildService(
        createBackupFn: ({required outputDirectory, required filePrefix}) =>
            Future.error(Exception('disk full')),
      );

      final result =
          await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

      expect(result, isFalse);
      expect(await UserStorage.getICloudBackupNeedsRepick(userId), isFalse);
    },
  );

  test(
    'writeFile throwing a no_bookmark PlatformException -> caught, sets '
    'needsRepick, returns false',
    () async {
      fake.statusToReturn =
          const ICloudFolderStatus(configured: true, isStale: false);
      fake.listToReturn = const [];
      final service = buildService();
      fake.writeThrows =
          PlatformException(code: 'no_bookmark', message: 'not configured');

      final result =
          await service.maybeCreateDailyBackup(userId: userId, now: fixedNow);

      expect(result, isFalse);
      expect(await UserStorage.getICloudBackupNeedsRepick(userId), isTrue);
    },
  );

  test('configureFolder success -> stores label and clears needsRepick',
      () async {
    await UserStorage.setICloudBackupNeedsRepick(userId, true);
    fake.pickToReturn =
        const ExternalFolder(path: '/iCloud/x', displayName: 'memex backup');
    final service = buildService();

    final folder = await service.configureFolder(userId);

    expect(folder?.displayName, 'memex backup');
    expect(
        await UserStorage.getICloudBackupFolderLabel(userId), 'memex backup');
    expect(await UserStorage.getICloudBackupNeedsRepick(userId), isFalse);
  });

  test('configureFolder cancelled -> leaves storage untouched', () async {
    fake.pickToReturn = null;
    final service = buildService();

    final folder = await service.configureFolder(userId);

    expect(folder, isNull);
    expect(await UserStorage.getICloudBackupFolderLabel(userId), isNull);
  });
}
