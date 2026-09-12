import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/external_backup_channel.dart';
import 'package:memex/utils/icloud_daily_backup.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Keeps an idempotent-per-calendar-day rolling `.memex` backup in the
/// user's iCloud folder: at most today's copy (`memex_daily.memex`) plus
/// yesterday's (`memex_daily_prev.memex`). Never throws — failures are
/// swallowed and surfaced via `UserStorage.setICloudBackupNeedsRepick`.
class ICloudDailyBackupService {
  ICloudDailyBackupService({
    ExternalBackupChannel? channel,
    Future<String> Function({
      required String outputDirectory,
      required String filePrefix,
    })? createBackupFn,
    Future<String> Function()? tempDirFn,
  })  : _channel = channel ?? ExternalBackupChannel(),
        _createBackupFn = createBackupFn ??
            (({required outputDirectory, required filePrefix}) =>
                BackupService.createBackup(
                    outputDirectory: outputDirectory, filePrefix: filePrefix)),
        _tempDirFn =
            tempDirFn ?? (() async => (await getTemporaryDirectory()).path);

  static const String dailyName = 'memex_daily.memex';
  static const String prevName = 'memex_daily_prev.memex';
  static final _log = getLogger('ICloudDailyBackupService');

  final ExternalBackupChannel _channel;
  final Future<String> Function({
    required String outputDirectory,
    required String filePrefix,
  }) _createBackupFn;
  final Future<String> Function() _tempDirFn;

  /// Prompts the user to pick an iCloud folder and, on success, persists its
  /// label and clears any pending re-pick flag.
  Future<ExternalFolder?> configureFolder(String userId) async {
    final folder = await _channel.pickICloudFolder();
    if (folder != null) {
      await UserStorage.setICloudBackupFolderLabel(userId, folder.displayName);
      await UserStorage.setICloudBackupNeedsRepick(userId, false);
    }
    return folder;
  }

  /// Writes today's rolling backup if one hasn't already been written today
  /// (unless [force] is set). Returns whether a backup was actually written.
  /// Never throws: any failure (including a stale iCloud folder) sets the
  /// needs-repick flag and returns false.
  Future<bool> maybeCreateDailyBackup({
    required String userId,
    DateTime? now,
    bool force = false,
  }) async {
    try {
      if (!await UserStorage.isAutoBackupEnabled(userId)) return false;
      final status = await _channel.icloudStatus();
      if (!status.configured) return false;
      if (status.isStale) {
        await UserStorage.setICloudBackupNeedsRepick(userId, true);
        return false;
      }

      final today = ymd(now ?? DateTime.now());
      if (!force &&
          await UserStorage.getLastICloudDailyBackupYmd(userId) == today) {
        return false;
      }

      // 1. Build the .memex into a temp dir.
      final tempDir = await _tempDirFn();
      final srcPath = await _createBackupFn(
          outputDirectory: tempDir, filePrefix: 'memex_daily_tmp');

      // 2. Roll existing files (skip roll on force/same-day overwrite).
      if (!force) {
        final names = (await _channel.listFiles()).map((f) => f.name).toList();
        final plan = planDailyRoll(
            existingNames: names, dailyName: dailyName, prevName: prevName);
        if (plan.deletePrev) await _channel.deleteFile(prevName);
        if (plan.renameDailyToPrev) {
          await _channel.renameFile(from: dailyName, to: prevName);
        }
      }

      // 3. Write today's copy.
      await _channel.writeFile(sourcePath: srcPath, fileName: dailyName);

      // 4. Clean up temp + record.
      try {
        await File(srcPath).delete();
      } catch (_) {}
      await UserStorage.setLastICloudDailyBackupYmd(userId, today);
      await UserStorage.setICloudBackupNeedsRepick(userId, false);
      _log.info('iCloud daily backup written ($today)');
      return true;
    } catch (e, st) {
      _log.warning('iCloud daily backup failed (non-blocking): $e', e, st);
      // Only a genuine bookmark problem (missing/invalidated security-scoped
      // bookmark) should nag the user to re-pick the folder. Transient
      // failures (disk full, momentary write error, offline, etc.) must not
      // trigger the re-pick prompt.
      if (e is PlatformException && e.code == 'no_bookmark') {
        await UserStorage.setICloudBackupNeedsRepick(userId, true);
      }
      return false;
    }
  }
}
