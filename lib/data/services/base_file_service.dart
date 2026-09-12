import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';
import 'api_exception.dart';

/// Base file operations service
/// High-perf, well-encapsulated file system ops
class BaseFileService {
  final Logger _logger = getLogger('BaseFileService');

  /// Check if path is under given directory
  ///
  /// Args:
  ///   childPath: child path
  ///   parentPath: parent path
  ///
  /// Returns:
  ///   true if child under parent, else false
  bool isUnderDirectory(String childPath, String parentPath) {
    try {
      final child = path.absolute(childPath);
      final parent = path.absolute(parentPath);

      final relative = path.relative(child, from: parent);

      // If relative path has '..', not under parent
      return !relative.startsWith('..') && relative != child;
    } catch (e) {
      return false;
    }
  }

  /// Ensure path is absolute
  ///
  /// Args:
  ///   filePath: file path
  ///
  /// Returns:
  ///   absolute path
  ///
  /// Throws:
  ///   ArgumentError: if path invalid
  String ensureAbsolutePath(String filePath) {
    if (path.isAbsolute(filePath)) {
      return filePath;
    }
    return path.absolute(filePath);
  }

  /// Read file content
  ///
  /// Args:
  ///   filePath: file path (absolute)
  ///   encoding: default UTF-8
  ///
  /// Returns:
  ///   file content string
  ///
  /// Throws:
  ///   ApiException: if file not found or read fails
  Future<String> readFile(
    String filePath, {
    Encoding encoding = utf8,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        throw ApiException('File not found: $filePath');
      }

      if (await file
          .stat()
          .then((stat) => stat.type == FileSystemEntityType.directory)) {
        throw ApiException('$filePath is a directory, not a file');
      }

      return await file.readAsString(encoding: encoding);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to read file: ${e.toString()}');
    }
  }

  /// Read file line range
  ///
  /// Args:
  ///   filePath: file path (absolute)
  ///   offset: start line (1-based)
  ///   limit: line count, null = to end
  ///   encoding: default UTF-8
  ///
  /// Returns:
  ///   string of selected lines
  ///
  /// Throws:
  ///   ApiException: if file not found or read fails
  Future<String> readFileLines(
    String filePath, {
    int offset = 1,
    int? limit,
    Encoding encoding = utf8,
  }) async {
    try {
      final content = await readFile(filePath, encoding: encoding);
      final lines = content.split('\n');

      final startIdx = (offset - 1).clamp(0, lines.length);
      final endIdx = limit != null
          ? (startIdx + limit).clamp(startIdx, lines.length)
          : lines.length;

      final selectedLines = lines.sublist(startIdx, endIdx);
      return selectedLines.join('\n');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to read file lines: ${e.toString()}');
    }
  }

  /// Write file content
  ///
  /// Args:
  ///   filePath: file path (absolute)
  ///   content: file content
  ///   encoding: default UTF-8
  ///   createParentDirs: create parents if missing, default true
  ///
  /// Returns:
  ///   whether op succeeded
  ///
  /// Throws:
  ///   ApiException: if write fails
  Future<bool> writeFile(
    String filePath,
    String content, {
    Encoding encoding = utf8,
    bool createParentDirs = true,
  }) async {
    try {
      final file = File(filePath);

      if (createParentDirs) {
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
      }

      await file.writeAsString(content, encoding: encoding, flush: true);
      return true;
    } catch (e) {
      throw ApiException('Failed to write file: ${e.toString()}');
    }
  }

  /// Write bytes
  ///
  /// Args:
  ///   filePath: file path (absolute)
  ///   bytes: byte data
  ///   createParentDirs: create parents if missing, default true
  ///
  /// Returns:
  ///   whether op succeeded
  ///
  /// Throws:
  ///   ApiException: if write fails
  Future<bool> writeBytes(
    String filePath,
    List<int> bytes, {
    bool createParentDirs = true,
  }) async {
    try {
      final file = File(filePath);
      if (createParentDirs) {
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
      }
      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      throw ApiException('Failed to write file: ${e.toString()}');
    }
  }

  /// List directory (non-recursive)
  ///
  /// Args:
  ///   dirPath: dir path (absolute)
  ///   recursive: list subdirs, default false
  ///   includeHidden: include hidden, default false
  ///
  /// Returns:
  ///   list of file/dir paths (relative)
  ///
  /// Throws:
  ///   ApiException: if dir not found or read fails
  Future<List<String>> listDirectory(
    String dirPath, {
    bool recursive = false,
    bool includeHidden = false,
  }) async {
    try {
      final dir = Directory(dirPath);

      if (!await dir.exists()) {
        throw ApiException('Directory not found: $dirPath');
      }

      final stat = await dir.stat();
      if (stat.type != FileSystemEntityType.directory) {
        throw ApiException('$dirPath is not a directory');
      }

      final results = <String>[];

      if (recursive) {
        await _listDirectoryRecursive(dir, dir, results, includeHidden);
      } else {
        await _listDirectorySingle(dir, dir, results, includeHidden);
      }

      return results;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to list directory: ${e.toString()}');
    }
  }

  /// List directory recursive (internal)
  Future<void> _listDirectoryRecursive(
    Directory root,
    Directory current,
    List<String> results,
    bool includeHidden,
  ) async {
    try {
      final entities = current.list(recursive: false);

      await for (final entity in entities) {
        final stat = await entity.stat();
        final name = path.basename(entity.path);

        // Skip hidden files
        if (!includeHidden && name.startsWith('.')) {
          continue;
        }

        final relativePath = path.relative(entity.path, from: root.path);

        if (stat.type == FileSystemEntityType.directory) {
          results.add('$relativePath${path.separator}');
          await _listDirectoryRecursive(
              root, Directory(entity.path), results, includeHidden);
        } else {
          results.add(relativePath);
        }
      }
    } catch (e) {
      _logger.warning('Cannot read directory ${current.path}: $e');
    }
  }

  /// List single-level dir (internal)
  Future<void> _listDirectorySingle(
    Directory root,
    Directory current,
    List<String> results,
    bool includeHidden,
  ) async {
    try {
      final entities = current.list(recursive: false);

      await for (final entity in entities) {
        final name = path.basename(entity.path);

        // Skip hidden files
        if (!includeHidden && name.startsWith('.')) {
          continue;
        }

        final relativePath = path.relative(entity.path, from: root.path);
        final stat = await entity.stat();

        if (stat.type == FileSystemEntityType.directory) {
          results.add('$relativePath${path.separator}');
        } else {
          results.add(relativePath);
        }
      }
    } catch (e) {
      _logger.warning('Cannot read directory ${current.path}: $e');
    }
  }

  /// Remove file or directory
  ///
  /// Args:
  ///   path: file or dir path (absolute)
  ///   recursive: recursive delete for dirs, default true
  ///
  /// Returns:
  ///   whether op succeeded
  ///
  /// Throws:
  ///   ApiException: if path not found or delete fails
  Future<bool> remove(
    String path, {
    bool recursive = true,
  }) async {
    try {
      final entity = FileSystemEntity.typeSync(path);

      if (entity == FileSystemEntityType.notFound) {
        throw ApiException('Path not found: $path');
      }

      if (entity == FileSystemEntityType.directory) {
        final dir = Directory(path);
        await dir.delete(recursive: recursive);
      } else {
        final file = File(path);
        await file.delete();
      }

      return true;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Delete failed: ${e.toString()}');
    }
  }

  /// Move/rename file or directory
  ///
  /// Args:
  ///   sourcePath: source path (absolute)
  ///   destinationPath: dest path (absolute)
  ///   overwrite: overwrite if exists, default false
  ///
  /// Returns:
  ///   actual destination path
  ///
  /// Throws:
  ///   ApiException: if op fails
  Future<String> move(
    String sourcePath,
    String destinationPath, {
    bool overwrite = false,
  }) async {
    try {
      final source = FileSystemEntity.typeSync(sourcePath);

      if (source == FileSystemEntityType.notFound) {
        throw ApiException('Source path not found: $sourcePath');
      }

      final isDirectory = source == FileSystemEntityType.directory;

      // Handle destination path
      String actualDestination = destinationPath;
      final destEntity = FileSystemEntity.typeSync(destinationPath);

      if (destEntity == FileSystemEntityType.directory) {
        // If dest is dir, move source into it
        final sourceName = path.basename(sourcePath);
        actualDestination = path.join(destinationPath, sourceName);

        final finalDestEntity = FileSystemEntity.typeSync(actualDestination);
        if (finalDestEntity != FileSystemEntityType.notFound) {
          if (!overwrite) {
            throw ApiException(
              'Target $actualDestination already exists in $destinationPath. '
              'Set overwrite to true to replace.',
            );
          }
          // Remove existing target
          await remove(actualDestination, recursive: true);
        }
      } else if (destEntity != FileSystemEntityType.notFound) {
        // Target file/dir already exists
        if (!overwrite) {
          throw ApiException(
            'Target path $destinationPath already exists. '
            'Set overwrite to true to replace.',
          );
        }
        // Remove existing target
        await remove(destinationPath, recursive: true);
      } else {
        // Target missing, create parent dir
        final parentDir = Directory(path.dirname(destinationPath));
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
      }

      // Perform move
      if (isDirectory) {
        await Directory(sourcePath).rename(actualDestination);
      } else {
        await File(sourcePath).rename(actualDestination);
      }

      return actualDestination;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Move failed: ${e.toString()}');
    }
  }

  /// Check if file or dir exists
  ///
  /// Args:
  ///   path: path (absolute)
  ///
  /// Returns:
  ///   true if exists, else false
  Future<bool> exists(String path) async {
    return await FileSystemEntity.isFile(path) ||
        await FileSystemEntity.isDirectory(path);
  }

  /// Check if directory
  ///
  /// Args:
  ///   path: path (absolute)
  ///
  /// Returns:
  ///   true if dir, else false
  Future<bool> isDirectory(String path) async {
    return await FileSystemEntity.isDirectory(path);
  }

  /// Check if file
  ///
  /// Args:
  ///   path: path (absolute)
  ///
  /// Returns:
  ///   true if file, else false
  Future<bool> isFile(String path) async {
    return await FileSystemEntity.isFile(path);
  }

  /// Get file size (bytes)
  ///
  /// Args:
  ///   path: file path (absolute)
  ///
  /// Returns:
  ///   file size (bytes)
  ///
  /// Throws:
  ///   ApiException: if path not found or not file
  Future<int> getFileSize(String path) async {
    try {
      if (!await isFile(path)) {
        throw ApiException('Path is not a file: $path');
      }
      final file = File(path);
      final stat = await file.stat();
      return stat.size;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to get file size: ${e.toString()}');
    }
  }

  /// Get file modification time
  ///
  /// Args:
  ///   path: file path (absolute)
  ///
  /// Returns:
  ///   modification time
  ///
  /// Throws:
  ///   ApiException: if path not found
  Future<DateTime> getModificationTime(String path) async {
    try {
      final entity = File(path);
      if (!await entity.exists()) {
        throw ApiException('Path not found: $path');
      }
      final stat = await entity.stat();
      return stat.modified;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to get modification time: ${e.toString()}');
    }
  }
}
