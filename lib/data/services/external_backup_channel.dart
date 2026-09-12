import 'package:flutter/services.dart';

class ExternalFolder {
  final String path;
  final String displayName;
  const ExternalFolder({required this.path, required this.displayName});
}

class ICloudFolderStatus {
  final bool configured;
  final String? displayName;
  final String? path;
  final bool isStale;
  const ICloudFolderStatus({
    required this.configured,
    this.displayName,
    this.path,
    this.isStale = false,
  });
}

class ICloudUploadStatus {
  final String name;
  final bool uploaded;
  final bool uploading;
  final bool hasError;
  const ICloudUploadStatus({
    required this.name,
    required this.uploaded,
    required this.uploading,
    required this.hasError,
  });
}

class ExternalBackupFile {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;
  const ExternalBackupFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });
}

/// Thin Dart wrapper over the iOS side of `com.memexlab.memex/backup_storage`.
/// Injectable so services/tests never hit the real platform channel.
class ExternalBackupChannel {
  ExternalBackupChannel({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.memexlab.memex/backup_storage');
  final MethodChannel _channel;

  Future<ExternalFolder?> pickICloudFolder() async {
    try {
      final r =
          await _channel.invokeMapMethod<String, dynamic>('icloudPickFolder');
      if (r == null) return null;
      return ExternalFolder(
        path: r['path'] as String,
        displayName: r['displayName'] as String,
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return null;
      rethrow;
    }
  }

  Future<ICloudFolderStatus> icloudStatus() async {
    final r =
        await _channel.invokeMapMethod<String, dynamic>('icloudFolderStatus');
    return ICloudFolderStatus(
      configured: (r?['configured'] as bool?) ?? false,
      displayName: r?['displayName'] as String?,
      path: r?['path'] as String?,
      isStale: (r?['isStale'] as bool?) ?? false,
    );
  }

  Future<String> writeFile(
      {required String sourcePath, required String fileName}) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
        'icloudWriteFile', {'sourcePath': sourcePath, 'fileName': fileName});
    return r!['path'] as String;
  }

  /// Copies [fileName] out of the security-scoped iCloud folder into a
  /// temp file readable via plain dart:io, and returns its path.
  Future<String> readFileToTemp(String fileName) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
        'icloudReadFileToTemp', {'fileName': fileName});
    return r!['path'] as String;
  }

  Future<bool> renameFile({required String from, required String to}) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
        'icloudRenameFile', {'from': from, 'to': to});
    return (r?['renamed'] as bool?) ?? false;
  }

  Future<bool> deleteFile(String fileName) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
        'icloudDeleteFile', {'fileName': fileName});
    return (r?['deleted'] as bool?) ?? false;
  }

  Future<List<ExternalBackupFile>> listFiles() async {
    final r =
        await _channel.invokeMapMethod<String, dynamic>('icloudListFiles');
    final list = (r?['files'] as List?) ?? const [];
    return list.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return ExternalBackupFile(
        name: m['name'] as String,
        path: m['path'] as String,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        modified: DateTime.fromMillisecondsSinceEpoch(
            (m['modifiedMs'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  Future<void> clearFolder() =>
      _channel.invokeMethod<void>('icloudClearFolder');

  /// Best-effort per-file iCloud upload status; returns an empty list on
  /// any channel error rather than throwing into callers.
  Future<List<ICloudUploadStatus>> uploadStatus() async {
    try {
      final r = await _channel
          .invokeMapMethod<String, dynamic>('icloudUploadStatus');
      final list = (r?['files'] as List?) ?? const [];
      return list.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return ICloudUploadStatus(
          name: m['name'] as String,
          uploaded: (m['uploaded'] as bool?) ?? false,
          uploading: (m['uploading'] as bool?) ?? false,
          hasError: (m['hasError'] as bool?) ?? false,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
