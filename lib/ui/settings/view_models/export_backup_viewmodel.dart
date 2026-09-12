import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import 'package:memex/data/services/backup_service.dart';
import 'package:memex/utils/user_storage.dart';

/// State/behavior for the prominent top-level "Export Backup" settings
/// entry: one-tap `BackupService.createBackup` + OS share sheet, recording
/// the export time in [UserStorage] so the safety-net can tell how stale
/// the user's last backup is.
///
/// Mirrors [MemoryBookExportViewModel] — plain `ChangeNotifier`, no Command
/// wrapper.
class ExportBackupViewModel extends ChangeNotifier {
  ExportBackupViewModel()
      : _createFn = BackupService.createBackup,
        _shareFn = null,
        _recordFn = _defaultRecord,
        _now = DateTime.now;

  /// Test-only constructor. All OS/service/storage interactions are
  /// injectable so tests never hit `BackupService`, the OS share sheet, or
  /// `SharedPreferences`.
  @visibleForTesting
  ExportBackupViewModel.forTesting({
    required Future<String> Function() createFn,
    required Future<void> Function(String path) shareFn,
    Future<void> Function(DateTime)? recordFn,
    DateTime Function()? now,
  })  : _createFn = createFn,
        _shareFn = shareFn,
        _recordFn = recordFn ?? _defaultRecord,
        _now = now ?? DateTime.now;

  final Future<String> Function() _createFn;
  final Future<void> Function(String path)? _shareFn;
  final Future<void> Function(DateTime) _recordFn;
  final DateTime Function() _now;

  bool _generating = false;
  String? _error;
  DateTime? _lastExportAt;

  bool get generating => _generating;
  String? get error => _error;
  DateTime? get lastExportAt => _lastExportAt;

  static Future<void> _defaultRecord(DateTime when) async {
    final userId = await UserStorage.getUserId();
    if (userId != null) {
      await UserStorage.setLastManualExportAt(userId, when);
    }
  }

  /// Loads the last-recorded manual export time for the current user.
  Future<void> loadLastExport() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    _lastExportAt = await UserStorage.getLastManualExportAt(userId);
    notifyListeners();
  }

  /// Generates a `.memex` backup and opens the OS share sheet, recording
  /// the export time on success. Re-entrant calls while a previous export
  /// is still running are ignored.
  Future<void> export(BuildContext context) async {
    if (_generating) return;

    _generating = true;
    _error = null;
    notifyListeners();

    // Resolve the iPad share-sheet anchor point synchronously, before any
    // `await`, so we never touch `context` across an async gap.
    final sharePositionOrigin = _resolveSharePositionOrigin(context);

    try {
      final backupPath = await _createFn();

      if (_shareFn != null) {
        await _shareFn(backupPath);
      } else {
        await _shareViaOsShareSheet(sharePositionOrigin, backupPath);
      }

      final when = _now();
      await _recordFn(when);
      _lastExportAt = when;
    } catch (e) {
      _error = e.toString();
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  static Rect _resolveSharePositionOrigin(BuildContext context) {
    if (!context.mounted) return const Rect.fromLTWH(0, 0, 100, 100);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Rect.fromLTWH(0, 0, 100, 100);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  static Future<void> _shareViaOsShareSheet(
    Rect sharePositionOrigin,
    String backupPath,
  ) async {
    final xFile = XFile(
      backupPath,
      mimeType: BackupService.backupMimeType,
      name: path.basename(backupPath),
    );

    await Share.shareXFiles(
      [xFile],
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
