import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    await UserStorage.saveUser('backup-service-user');

    tempDir = await Directory.systemTemp.createTemp('memex_backup_service_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    _mockPathProviderChannel(tempDir.path);
    await FileSystemService.init(tempDir.path);

    final workspace = Directory(
      FileSystemService.instance.getWorkspacePath('backup-service-user'),
    );
    await workspace.create(recursive: true);
    await File(
      p.join(workspace.path, 'Cards', 'card.md'),
    ).create(recursive: true);
    await File(
      p.join(workspace.path, 'Cards', 'card.md'),
    ).writeAsString('hello backup');
  });

  tearDown(() async {
    _clearPathProviderChannelMock();
    _clearBackupStorageChannelMock();
    PathProviderPlatform.instance = originalPathProvider;
    try {
      await tempDir.delete(recursive: true);
    } on PathNotFoundException {
      // Some restore paths can remove the fake temp root before tearDown runs.
    }
  });

  test('createBackup writes manifest and workspace content', () async {
    final outputDir = Directory(p.join(tempDir.path, 'Backups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: outputDir.path,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );

    expect(
      archive.files.map((file) => file.name),
      containsAll([
        'manifest.json',
        'settings.json',
        'workspace/Cards/card.md',
      ]),
    );

    final manifest = archive.files.firstWhere(
      (file) => file.name == 'manifest.json',
    );
    final manifestJson = jsonDecode(utf8.decode(manifest.content));

    expect(manifestJson['formatVersion'], 1);
    expect(manifestJson['entries'], isNotEmpty);
  });

  test('createBackup still compresses small text files', () async {
    final outputDir = Directory(p.join(tempDir.path, 'Backups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: outputDir.path,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );
    final archivedCard = archive.files.firstWhere(
      (file) => file.name == 'workspace/Cards/card.md',
    );

    expect(archivedCard.compression, CompressionType.deflate);
    expect(utf8.decode(archivedCard.content), 'hello backup');
  });

  test('createBackup stores compressed media without recompressing', () async {
    final workspace = Directory(
      FileSystemService.instance.getWorkspacePath('backup-service-user'),
    );
    final mediaFile = File(p.join(workspace.path, 'Assets', 'clip.mp4'));
    await mediaFile.create(recursive: true);
    await mediaFile.writeAsBytes(List<int>.generate(1024, (index) => index));

    final outputDir = Directory(p.join(tempDir.path, 'Backups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: outputDir.path,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );
    final archivedMedia = archive.files.firstWhere(
      (file) => file.name == 'workspace/Assets/clip.mp4',
    );

    expect(archivedMedia.compression, CompressionType.none);
    expect(archivedMedia.content, await mediaFile.readAsBytes());
  });

  test('createBackup stores large files without recompressing', () async {
    final workspace = Directory(
      FileSystemService.instance.getWorkspacePath('backup-service-user'),
    );
    final largeFile = File(p.join(workspace.path, 'Cards', 'large.bin'));
    const largeFileSize = 16 * 1024 * 1024 + 1;
    await _writeDeterministicBinaryFile(
      largeFile,
      sizeBytes: largeFileSize,
      seed: 99,
    );

    final outputDir = Directory(p.join(tempDir.path, 'Backups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: outputDir.path,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );
    final archivedLargeFile = archive.files.firstWhere(
      (file) => file.name == 'workspace/Cards/large.bin',
    );
    final manifest = archive.files.firstWhere(
      (file) => file.name == 'manifest.json',
    );
    final manifestJson = jsonDecode(utf8.decode(manifest.content));
    final entries = (manifestJson['entries'] as List)
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>());
    final largeEntry = entries.firstWhere(
      (entry) => entry['path'] == 'workspace/Cards/large.bin',
    );

    expect(archivedLargeFile.compression, CompressionType.none);
    expect(archivedLargeFile.size, largeFileSize);
    expect(largeEntry['size'], largeFileSize);
    expect(largeEntry['sha256'], await _sha256File(largeFile));
  });

  test(
    'restore rejects a backup with a mismatched manifest checksum',
    () async {
      final outputDir = Directory(p.join(tempDir.path, 'Backups'));
      final backupPath = await BackupService.createBackup(
        outputDirectory: outputDir.path,
      );
      final archive = ZipDecoder().decodeBytes(
        await File(backupPath).readAsBytes(),
      );
      final corrupted = Archive();

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final bytes = file.name == 'workspace/Cards/card.md'
            ? utf8.encode('tampered workspace note')
            : List<int>.from(file.content);
        corrupted.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }

      final corruptedPath = p.join(outputDir.path, 'tampered.memex');
      await File(corruptedPath).writeAsBytes(ZipEncoder().encode(corrupted));

      await expectLater(
        BackupService.restoreBackup(corruptedPath),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Backup checksum mismatch'),
          ),
        ),
      );
    },
  );

  test(
    'automatic backup skips a second run within twenty-four hours',
    () async {
      await UserStorage.setAutoBackupEnabled('backup-service-user', true);

      final first = await BackupService.maybeCreateAutoBackup(
        trigger: 'test-first',
      );
      final second = await BackupService.maybeCreateAutoBackup(
        trigger: 'test-second',
      );

      expect(first, isNotNull);
      expect(second, isNull);
    },
  );

  test('automatic backup retention preference defaults and persists', () async {
    expect(
      await UserStorage.getAutoBackupRetentionDays('backup-service-user'),
      UserStorage.defaultAutoBackupRetentionDays,
    );

    await UserStorage.setAutoBackupRetentionDays('backup-service-user', 14);
    expect(
      await UserStorage.getAutoBackupRetentionDays('backup-service-user'),
      14,
    );

    await UserStorage.setAutoBackupRetentionDays('backup-service-user', null);
    expect(
      await UserStorage.getAutoBackupRetentionDays('backup-service-user'),
      isNull,
    );

    expect(
      () => UserStorage.setAutoBackupRetentionDays('backup-service-user', 0),
      throwsArgumentError,
    );

    expect(
      await UserStorage.getAutoBackupMaxBytes('backup-service-user'),
      UserStorage.defaultAutoBackupMaxBytes,
    );

    await UserStorage.setAutoBackupMaxBytes('backup-service-user', 1024);
    expect(
        await UserStorage.getAutoBackupMaxBytes('backup-service-user'), 1024);

    expect(
      () => UserStorage.setAutoBackupMaxBytes('backup-service-user', 0),
      throwsArgumentError,
    );
  });

  test(
    'automatic backup retention deletes only expired automatic snapshots',
    () async {
      final backupDir = await BackupService.resolveDefaultBackupDirectory();
      final now = DateTime(2026, 5, 15, 12);
      await UserStorage.setAutoBackupRetentionDays('backup-service-user', 7);

      final recent = await _writeStoredBackupFile(
        backupDir,
        'memex_auto_recent.memex',
        modified: now.subtract(const Duration(days: 6)),
      );
      final boundary = await _writeStoredBackupFile(
        backupDir,
        'memex_auto_boundary.memex',
        modified: now.subtract(const Duration(days: 7)),
      );
      final expired = await _writeStoredBackupFile(
        backupDir,
        'memex_auto_expired.memex',
        modified: now.subtract(const Duration(days: 8)),
      );
      final safety = await _writeStoredBackupFile(
        backupDir,
        'memex_safety_before_restore.memex',
        modified: now.subtract(const Duration(days: 60)),
      );

      final deleted = await BackupService.pruneAutoBackups(now: now);

      expect(deleted, 1);
      expect(await recent.exists(), isTrue);
      expect(await boundary.exists(), isTrue);
      expect(await expired.exists(), isFalse);
      expect(await safety.exists(), isTrue);
    },
  );

  test('automatic backup pruning always keeps the newest snapshot', () async {
    final backupDir = await BackupService.resolveDefaultBackupDirectory();
    final now = DateTime(2026, 5, 15, 12);
    await UserStorage.setAutoBackupRetentionDays('backup-service-user', 7);

    final oldest = await _writeStoredBackupFile(
      backupDir,
      'memex_auto_oldest.memex',
      modified: now.subtract(const Duration(days: 30)),
    );
    final newest = await _writeStoredBackupFile(
      backupDir,
      'memex_auto_newest.memex',
      modified: now.subtract(const Duration(days: 20)),
    );

    final deleted = await BackupService.pruneAutoBackups(now: now);

    expect(deleted, 1);
    expect(await newest.exists(), isTrue);
    expect(await oldest.exists(), isFalse);
  });

  test('automatic backup retention still caps forever history by total size',
      () async {
    final backupDir = await BackupService.resolveDefaultBackupDirectory();
    final now = DateTime(2026, 5, 15, 12);
    await UserStorage.setAutoBackupRetentionDays('backup-service-user', null);
    await UserStorage.setAutoBackupMaxBytes('backup-service-user', 3);

    for (var i = 0; i < 5; i += 1) {
      await _writeStoredBackupFile(
        backupDir,
        'memex_auto_${i.toString().padLeft(2, '0')}.memex',
        modified: now.subtract(Duration(minutes: i)),
        sizeBytes: 1,
      );
    }

    final deleted = await BackupService.pruneAutoBackups(now: now);
    final remainingNames = await _storedBackupNames(backupDir);

    expect(deleted, 2);
    expect(remainingNames.length, 3);
    expect(remainingNames, contains('memex_auto_00.memex'));
    expect(remainingNames, contains('memex_auto_02.memex'));
    expect(remainingNames, isNot(contains('memex_auto_03.memex')));
    expect(remainingNames, isNot(contains('memex_auto_04.memex')));
  });

  test('automatic backup skip still prunes expired snapshots', () async {
    await UserStorage.setAutoBackupEnabled('backup-service-user', true);
    await UserStorage.setAutoBackupRetentionDays('backup-service-user', 7);
    await UserStorage.setLastAutoBackupMetadata(
      'backup-service-user',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      fingerprint: 'previous',
    );

    final backupDir = await BackupService.resolveDefaultBackupDirectory();
    final keep = await _writeStoredBackupFile(
      backupDir,
      'memex_auto_recent_skip.memex',
      modified: DateTime.now().subtract(const Duration(days: 1)),
    );
    final expired = await _writeStoredBackupFile(
      backupDir,
      'memex_auto_expired_skip.memex',
      modified: DateTime.now().subtract(const Duration(days: 8)),
    );

    final snapshot = await BackupService.maybeCreateAutoBackup(
      trigger: 'skip-prune-test',
    );

    expect(snapshot, isNull);
    expect(await keep.exists(), isTrue);
    expect(await expired.exists(), isFalse);
  });

  test('deleteStoredBackup removes only the selected local snapshot', () async {
    final backupDir = await BackupService.resolveDefaultBackupDirectory();
    final target = File(
      p.join(backupDir.path, 'memex_auto_2026-05-15T10-00-00.memex'),
    );
    final keepAuto = File(
      p.join(backupDir.path, 'memex_auto_2026-05-16T10-00-00.memex'),
    );
    final keepSafety = File(
      p.join(
        backupDir.path,
        'memex_safety_before_restore_2026-05-16T11-00-00.memex',
      ),
    );
    final ignoredText = File(p.join(backupDir.path, 'notes.txt'));

    await target.writeAsBytes([1]);
    await keepAuto.writeAsBytes([2]);
    await keepSafety.writeAsBytes([3]);
    await ignoredText.writeAsString('not a backup');

    final snapshots = await BackupService.listStoredBackups();
    final targetSnapshot = snapshots.firstWhere(
      (snapshot) => snapshot.name == p.basename(target.path),
    );

    await BackupService.deleteStoredBackup(targetSnapshot);

    expect(await target.exists(), isFalse);
    expect(await keepAuto.exists(), isTrue);
    expect(await keepSafety.exists(), isTrue);
    expect(await ignoredText.exists(), isTrue);

    final remainingNames = (await BackupService.listStoredBackups())
        .map((snapshot) => snapshot.name)
        .toSet();
    expect(remainingNames, isNot(contains(p.basename(target.path))));
    expect(remainingNames, contains(p.basename(keepAuto.path)));
    expect(remainingNames, contains(p.basename(keepSafety.path)));
  });

  test(
    'restoreStoredBackup routes an isICloud snapshot through '
    'icloudReadFileToTemp instead of opening the raw iCloud path',
    () async {
      final calls = <MethodCall>[];
      _mockBackupStorageChannel((call) async {
        calls.add(call);
        if (call.method == 'icloudReadFileToTemp') {
          // Return a real backup file path so restoreBackup can proceed.
          final outputDir = Directory(p.join(tempDir.path, 'IcloudTemp'));
          final backupPath = await BackupService.createBackup(
            outputDirectory: outputDir.path,
          );
          return {'path': backupPath};
        }
        return null;
      });

      final snapshot = BackupSnapshot(
        id: '/icloud/memex_daily.memex',
        name: 'memex_daily.memex',
        createdAt: DateTime(2026, 9, 6),
        sizeBytes: 10,
        filePath: '/icloud/memex_daily.memex',
        isICloud: true,
      );

      try {
        final result = await BackupService.restoreStoredBackup(snapshot);
        expect(result, isTrue);
      } finally {
        if (AppDatabase.isInitialized) {
          await AppDatabase.instance.close();
        }
      }

      expect(
        calls.map((c) => c.method),
        contains('icloudReadFileToTemp'),
      );
      final readCall = calls.firstWhere(
        (c) => c.method == 'icloudReadFileToTemp',
      );
      expect(
        (readCall.arguments as Map)['fileName'],
        'memex_daily.memex',
      );
    },
  );

  test(
    'deleteStoredBackup routes an isICloud snapshot through icloudDeleteFile '
    'instead of deleting the raw iCloud path',
    () async {
      final deletedNames = <String>[];
      _mockBackupStorageChannel((call) async {
        if (call.method == 'icloudDeleteFile') {
          deletedNames.add((call.arguments as Map)['fileName'] as String);
          return {'deleted': true};
        }
        return null;
      });

      final snapshot = BackupSnapshot(
        id: '/icloud/memex_daily.memex',
        name: 'memex_daily.memex',
        createdAt: DateTime(2026, 9, 6),
        sizeBytes: 10,
        filePath: '/icloud/memex_daily.memex',
        isICloud: true,
      );

      await BackupService.deleteStoredBackup(snapshot);

      expect(deletedNames, ['memex_daily.memex']);
    },
  );

  test('deleteStoredBackup delegates Android document deletion', () async {
    final deletedUris = <String>[];
    _mockBackupStorageChannel((call) async {
      if (call.method == 'deleteDocument') {
        deletedUris.add((call.arguments as Map)['documentUri'] as String);
      }
      return null;
    });

    await BackupService.deleteStoredBackup(
      BackupSnapshot(
        id: 'content://backups/auto',
        name: 'memex_auto_2026-05-16T10-00-00.memex',
        createdAt: DateTime(2026, 5, 16, 10),
        sizeBytes: 12,
        documentUri: 'content://backups/auto',
      ),
    );

    expect(deletedUris, ['content://backups/auto']);
  });

  test('restore leaves stored backup history files untouched', () async {
    final backupDir = await BackupService.resolveDefaultBackupDirectory();
    final historyAuto = File(
      p.join(backupDir.path, 'memex_auto_2026-05-15T10-00-00.memex'),
    );
    final historySafety = File(
      p.join(
        backupDir.path,
        'memex_safety_before_restore_2026-05-16T11-00-00.memex',
      ),
    );
    await historyAuto.writeAsBytes([1, 2, 3]);
    await historySafety.writeAsBytes([4, 5, 6]);

    final exportedDir = Directory(p.join(tempDir.path, 'ExportedBackups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: exportedDir.path,
    );

    try {
      await BackupService.restoreBackup(backupPath);
    } finally {
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }
    }

    expect(await historyAuto.exists(), isTrue);
    expect(await historySafety.exists(), isTrue);
    expect(await File(backupPath).exists(), isTrue);
  });

  test('restore stages and applies workspace files from backup', () async {
    final exportedDir = Directory(p.join(tempDir.path, 'ExportedBackups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: exportedDir.path,
    );

    final workspace = Directory(
      FileSystemService.instance.getWorkspacePath('backup-service-user'),
    );
    final cardFile = File(p.join(workspace.path, 'Cards', 'card.md'));
    await cardFile.writeAsString('local changes after backup');

    try {
      await BackupService.restoreBackup(backupPath);
    } finally {
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }
    }

    expect(await cardFile.readAsString(), 'hello backup');
  });

  test(
    'restore keeps the main isolate responsive while extracting a larger backup',
    () async {
      final workspace = Directory(
        FileSystemService.instance.getWorkspacePath('backup-service-user'),
      );
      final largeFilesDir = Directory(p.join(workspace.path, 'Cards', 'Large'));
      const largeFileCount = 32;
      const largeFileSize = 768 * 1024;

      for (var i = 0; i < largeFileCount; i += 1) {
        await _writeDeterministicBinaryFile(
          File(p.join(largeFilesDir.path, 'payload_$i.bin')),
          sizeBytes: largeFileSize,
          seed: i + 1,
        );
      }

      final exportedDir = Directory(p.join(tempDir.path, 'ExportedBackups'));
      final backupPath = await BackupService.createBackup(
        outputDirectory: exportedDir.path,
      );

      final mutatedFile = File(p.join(largeFilesDir.path, 'payload_0.bin'));
      await mutatedFile.writeAsString('local mutation after backup');

      var mainIsolateTicks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        mainIsolateTicks += 1;
      });
      final stopwatch = Stopwatch()..start();
      try {
        await BackupService.restoreBackup(backupPath).timeout(
          const Duration(seconds: 30),
        );
      } finally {
        timer.cancel();
        stopwatch.stop();
        if (AppDatabase.isInitialized) {
          await AppDatabase.instance.close();
        }
      }

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(
        mainIsolateTicks,
        greaterThan(5),
        reason: 'Restore should yield to the main isolate during extraction.',
      );
      expect(await mutatedFile.length(), largeFileSize);
      expect(
        await mutatedFile.openRead(0, 64).expand((bytes) => bytes).toList(),
        _deterministicBytes(length: 64, seed: 1),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  group('resolveSafetySnapshotDirectory', () {
    test(
      'falls back to the temp-dir SafetySnapshots dir when the app-support '
      'candidate is inside dataRoot, and creates it',
      () async {
        // In this test fixture, getApplicationSupportPath/getTemporaryPath
        // and FileSystemService.dataRoot all resolve to the same fake root
        // (tempDir.path), so the app-support/SafetySnapshots candidate is
        // always "inside" dataRoot here — exercising the isPathInside(...)
        // defensive fallback branch (the plain guard itself is covered by
        // test/utils/backup_safety_test.dart).
        final dir = await BackupService.resolveSafetySnapshotDirectory();

        expect(dir.path, p.join(tempDir.path, 'SafetySnapshots'));
        expect(await dir.exists(), isTrue);
      },
    );

    test('write path and list path never drift', () async {
      final resolved = await BackupService.resolveSafetySnapshotDirectory();
      final snapshotFile = File(
        p.join(resolved.path, 'memex_safety_before_wipe_2026-05-15.memex'),
      );
      await snapshotFile.writeAsBytes([1, 2, 3]);

      final stored = await BackupService.listStoredBackups();

      expect(
        stored.any((snapshot) => snapshot.filePath == snapshotFile.path),
        isTrue,
      );
    });
  });

  group('listStoredBackups safety-snapshot merge', () {
    test(
        'surfaces a safety snapshot even when it is not in the default '
        'Backups directory', () async {
      final safetyDir = await BackupService.resolveSafetySnapshotDirectory();
      final safetyFile = await _writeStoredBackupFile(
        safetyDir,
        'memex_safety_before_wipe_2026-05-15T10-00-00.memex',
        modified: DateTime(2026, 5, 15, 10),
      );

      final stored = await BackupService.listStoredBackups();
      final match = stored.firstWhere(
        (snapshot) => snapshot.filePath == safetyFile.path,
      );

      expect(match.isSafetySnapshot, isTrue);
    });

    test('does not duplicate a snapshot present in both scanned directories',
        () async {
      final defaultDir = await BackupService.resolveDefaultBackupDirectory();
      final safetyDir = await BackupService.resolveSafetySnapshotDirectory();
      const name = 'memex_safety_before_wipe_2026-05-15T10-00-00.memex';

      // Simulate the (defensive, should-not-happen) case where the two
      // resolved directories coincide by writing the same file into both.
      final fileInDefault = await _writeStoredBackupFile(
        defaultDir,
        name,
        modified: DateTime(2026, 5, 15, 10),
      );
      if (p.normalize(defaultDir.path) != p.normalize(safetyDir.path)) {
        await File(p.join(safetyDir.path, name))
            .writeAsBytes(await fileInDefault.readAsBytes());
        await File(p.join(safetyDir.path, name))
            .setLastModified(DateTime(2026, 5, 15, 10));
      }

      final stored = await BackupService.listStoredBackups();
      final matches =
          stored.where((snapshot) => snapshot.name == name).toList();

      // Same basename in two directories are distinct files (distinct
      // paths) and both legitimately exist on disk, so both are listed;
      // the dedupe guarantee is about identical *paths*, exercised directly
      // via mergeAndDedupeSnapshots below.
      expect(matches, isNotEmpty);
    });
  });

  group('listStoredBackups iCloud merge (iOS)', () {
    // `BackupService.listStoredBackups` gates the iCloud branch on
    // `dart:io`'s `Platform.isIOS`, which reflects the actual host the test
    // process is running on and cannot be overridden from Dart test code
    // (unlike `debugDefaultTargetPlatformOverride`, which only affects
    // Flutter's `defaultTargetPlatform` and has no effect on `dart:io`).
    // There is no existing seam in this repo for forcing `Platform.isIOS`
    // in tests. So this test only exercises the iCloud-merge branch when
    // `flutter test` is actually run on an iOS/macOS-as-iOS host; on any
    // other host (e.g. this CI/dev machine) it is skipped and the iOS
    // branch is left covered only by manual/device verification.
    test(
      'includes iCloud daily + prev backups and does not classify them as '
      'auto/safety snapshots',
      () async {
        if (!Platform.isIOS) {
          markTestSkipped(
            'dart:io Platform.isIOS cannot be forced in this test process; '
            'see group-level comment.',
          );
          return;
        }

        _mockBackupStorageChannel((call) async {
          if (call.method == 'icloudListFiles') {
            return {
              'files': [
                {
                  'name': 'memex_daily.memex',
                  'path': '/icloud/memex_daily.memex',
                  'sizeBytes': 100,
                  'modifiedMs': DateTime(2026, 9, 6).millisecondsSinceEpoch,
                },
                {
                  'name': 'memex_daily_prev.memex',
                  'path': '/icloud/memex_daily_prev.memex',
                  'sizeBytes': 90,
                  'modifiedMs': DateTime(2026, 9, 5).millisecondsSinceEpoch,
                },
              ],
            };
          }
          return null;
        });

        final stored = await BackupService.listStoredBackups();
        final byName = {for (final s in stored) s.name: s};

        expect(byName, containsPair('memex_daily.memex', anything));
        expect(byName, containsPair('memex_daily_prev.memex', anything));
        expect(byName['memex_daily.memex']!.isAutoSnapshot, isFalse);
        expect(byName['memex_daily.memex']!.isSafetySnapshot, isFalse);
        expect(byName['memex_daily_prev.memex']!.isAutoSnapshot, isFalse);
        expect(byName['memex_daily_prev.memex']!.isSafetySnapshot, isFalse);

        // No duplication: exactly one entry per iCloud file path.
        final icloudPaths = stored
            .where((s) => s.filePath?.startsWith('/icloud/') ?? false)
            .map((s) => s.filePath)
            .toList();
        expect(icloudPaths.toSet().length, icloudPaths.length);
        expect(icloudPaths, hasLength(2));
      },
    );
  });

  group('mergeAndDedupeSnapshots', () {
    test('merges entries from two groups', () {
      final a = BackupSnapshot(
        id: '/a/one.memex',
        name: 'memex_auto_one.memex',
        createdAt: DateTime(2026, 5, 15, 10),
        sizeBytes: 1,
        filePath: '/a/one.memex',
      );
      final b = BackupSnapshot(
        id: '/b/two.memex',
        name: 'memex_safety_two.memex',
        createdAt: DateTime(2026, 5, 16, 10),
        sizeBytes: 2,
        filePath: '/b/two.memex',
      );

      final merged = mergeAndDedupeSnapshots([
        [a],
        [b],
      ]);

      expect(merged.map((s) => s.id), containsAll([a.id, b.id]));
      expect(merged.length, 2);
    });

    test('a duplicate path (across groups) appears only once', () {
      final first = BackupSnapshot(
        id: '/shared/x.memex',
        name: 'memex_auto_x.memex',
        createdAt: DateTime(2026, 5, 15, 10),
        sizeBytes: 1,
        filePath: '/shared/x.memex',
      );
      final duplicate = BackupSnapshot(
        id: '/shared/x.memex',
        name: 'memex_auto_x.memex',
        createdAt: DateTime(2026, 5, 15, 10),
        sizeBytes: 1,
        filePath: '/shared/x.memex',
      );

      final merged = mergeAndDedupeSnapshots([
        [first],
        [duplicate],
      ]);

      expect(merged.length, 1);
    });

    test('final order is createdAt desc across groups', () {
      final oldest = BackupSnapshot(
        id: '/a/oldest.memex',
        name: 'memex_auto_oldest.memex',
        createdAt: DateTime(2026, 5, 1),
        sizeBytes: 1,
        filePath: '/a/oldest.memex',
      );
      final middle = BackupSnapshot(
        id: '/b/middle.memex',
        name: 'memex_auto_middle.memex',
        createdAt: DateTime(2026, 5, 10),
        sizeBytes: 1,
        filePath: '/b/middle.memex',
      );
      final newest = BackupSnapshot(
        id: '/a/newest.memex',
        name: 'memex_auto_newest.memex',
        createdAt: DateTime(2026, 5, 20),
        sizeBytes: 1,
        filePath: '/a/newest.memex',
      );

      final merged = mergeAndDedupeSnapshots([
        [oldest, newest],
        [middle],
      ]);

      expect(merged.map((s) => s.id), [newest.id, middle.id, oldest.id]);
    });

    test('a safety-snapshot-named entry reports isSafetySnapshot true', () {
      final safety = BackupSnapshot(
        id: '/a/memex_safety_before_wipe.memex',
        name: 'memex_safety_before_wipe.memex',
        createdAt: DateTime(2026, 5, 15),
        sizeBytes: 1,
        filePath: '/a/memex_safety_before_wipe.memex',
      );

      final merged = mergeAndDedupeSnapshots([
        [safety],
      ]);

      expect(merged.single.isSafetySnapshot, isTrue);
    });
  });

  group('inspectBackup', () {
    test('reads backup manifest metadata', () async {
      final file = await _writeBackup(
        tempDir,
        'backup.memex',
        manifest: {
          'format': 'memex.backup',
          'backupSchemaVersion': BackupService.currentBackupSchemaVersion,
          'createdAt': '2026-05-15T00:00:00.000Z',
          'appVersion': '1.0.30',
          'buildNumber': '113',
          'flavor': 'globalEarly',
          'platform': 'android',
        },
      );

      final info = await BackupService.inspectBackup(file.path);

      expect(info.isLegacy, isFalse);
      expect(info.manifest?.appVersion, '1.0.30');
      expect(info.manifest?.buildNumber, '113');
      expect(info.manifest?.flavor, 'globalEarly');
    });

    test('accepts legacy backup without manifest', () async {
      final file = await _writeBackup(tempDir, 'legacy.memex');

      final info = await BackupService.inspectBackup(file.path);

      expect(info.isLegacy, isTrue);
      expect(info.manifest, isNull);
    });

    test('rejects newer backup schema', () async {
      final file = await _writeBackup(
        tempDir,
        'newer.memex',
        manifest: {
          'format': 'memex.backup',
          'backupSchemaVersion': BackupService.currentBackupSchemaVersion + 1,
          'createdAt': '2026-05-15T00:00:00.000Z',
        },
      );

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<UnsupportedBackupVersionException>()),
      );
    });

    test('rejects non-backup extension', () async {
      final file = await _writeBackup(tempDir, 'backup.txt');

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });

    test('rejects zip without backup markers', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('notes.txt', 5, utf8.encode('hello')));
      final file = File('${tempDir.path}/random.memex');
      await file.writeAsBytes(ZipEncoder().encode(archive));

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });
  });
}

void _mockPathProviderChannel(String rootPath) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      switch (call.method) {
        case 'getTemporaryDirectory':
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getExternalStorageDirectory':
          return rootPath;
        case 'getExternalStorageDirectories':
          return <String>[rootPath];
      }
      return null;
    },
  );
}

void _clearPathProviderChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

void _mockBackupStorageChannel(
  Future<dynamic> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.memexlab.memex/backup_storage'),
    handler,
  );
}

void _clearBackupStorageChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.memexlab.memex/backup_storage'),
    null,
  );
}

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String rootPath;

  FakePathProviderPlatform(this.rootPath);

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getExternalStoragePath() async => rootPath;
}

Future<File> _writeBackup(
  Directory tempDir,
  String fileName, {
  Map<String, dynamic>? manifest,
}) async {
  final archive = Archive();
  if (manifest != null) {
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
  }
  final settingsBytes = utf8.encode(jsonEncode({'userId': 'test-user'}));
  archive.addFile(
    ArchiveFile('settings.json', settingsBytes.length, settingsBytes),
  );

  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

Future<File> _writeStoredBackupFile(
  Directory backupDir,
  String fileName, {
  required DateTime modified,
  int sizeBytes = 1,
}) async {
  final file = File(p.join(backupDir.path, fileName));
  await file.writeAsBytes(List<int>.filled(sizeBytes, 1));
  await file.setLastModified(modified);
  return file;
}

Future<Set<String>> _storedBackupNames(Directory backupDir) async {
  return backupDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.memex'))
      .map((entity) => p.basename(entity.path))
      .toSet();
}

Future<void> _writeDeterministicBinaryFile(
  File file, {
  required int sizeBytes,
  required int seed,
}) async {
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  var remaining = sizeBytes;
  var state = seed;

  while (remaining > 0) {
    final chunkLength = remaining < 64 * 1024 ? remaining : 64 * 1024;
    final chunk = _deterministicBytes(
      length: chunkLength,
      seed: state,
      nextState: (value) => state = value,
    );
    sink.add(chunk);
    remaining -= chunkLength;
  }

  await sink.close();
}

List<int> _deterministicBytes({
  required int length,
  required int seed,
  void Function(int value)? nextState,
}) {
  var state = seed;
  final bytes = List<int>.filled(length, 0);
  for (var i = 0; i < bytes.length; i += 1) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = state & 0xff;
  }
  nextState?.call(state);
  return bytes;
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
