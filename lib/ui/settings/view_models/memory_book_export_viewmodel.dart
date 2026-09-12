import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:memex/data/services/memory_book_service.dart';

/// Function signature for injecting a fake "share the generated PDF" step in
/// tests, bypassing the real `Share.shareXFiles` OS share sheet.
typedef MemoryBookShareFn = Future<void> Function(
  Uint8List bytes,
  String fileName,
);

/// State/behavior for [MemoryBookExportPage]: title/date-range/tag inputs,
/// PDF generation progress, and system-share of the resulting file. Mirrors
/// CardSearchViewModel — plain `ChangeNotifier`, no Command wrapper — with
/// an added `progress` field for the multi-card export.
class MemoryBookExportViewModel extends ChangeNotifier {
  MemoryBookExportViewModel({required MemoryBookService service})
      : _service = service,
        _shareFn = null;

  /// Test-only constructor. [shareFn], when provided, replaces the default
  /// "write to temp dir + `Share.shareXFiles`" behavior so widget/unit tests
  /// never hit the OS share sheet.
  @visibleForTesting
  MemoryBookExportViewModel.forTesting({
    required MemoryBookService service,
    MemoryBookShareFn? shareFn,
  })  : _service = service,
        _shareFn = shareFn;

  final MemoryBookService _service;
  final MemoryBookShareFn? _shareFn;

  static const String _defaultTitle = '我的记忆册';

  String _title = _defaultTitle;
  String _lastAutoTitle = _defaultTitle;
  DateTime? _from;
  DateTime? _to;
  List<String> _selectedTags = [];
  bool _generating = false;
  double? _progress;
  String? _error;

  String get title => _title;
  DateTime? get from => _from;
  DateTime? get to => _to;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);
  bool get generating => _generating;
  double? get progress => _progress;
  String? get error => _error;

  /// Updates the title. Once the user edits it manually, [setDateRange]
  /// stops overwriting it with an auto-generated title.
  void setTitle(String value) {
    _title = value;
    notifyListeners();
  }

  /// Sets the active export date range. If [title] still equals the last
  /// auto-generated value (i.e. the user hasn't manually edited it), the
  /// title is refreshed to reflect the new range.
  void setDateRange(DateTime from, DateTime to) {
    _from = from;
    _to = to;
    if (_title == _lastAutoTitle) {
      final auto = _autoTitle(from, to);
      _title = auto;
      _lastAutoTitle = auto;
    }
    notifyListeners();
  }

  /// Toggles a tag in the active tag filter.
  ///
  /// TODO(memory-book-export): tag filter chips UI deferred — this state is
  /// wired end-to-end (passed to [MemoryBookService.export]) but no chips
  /// widget consumes it yet; wire chips once a convenient tag source (e.g.
  /// distinct tags across the selected range) is available.
  void toggleTag(String tag) {
    final next = List<String>.of(_selectedTags);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    _selectedTags = next;
    notifyListeners();
  }

  /// Progress callback passed to [MemoryBookService.export]; `total == 0`
  /// (no surviving cards) reports indeterminate progress.
  void updateProgress(int done, int total) {
    _progress = total == 0 ? null : done / total;
    notifyListeners();
  }

  /// Validates the date range, generates the memory-book PDF via
  /// [MemoryBookService.export], then shares the resulting bytes (via the
  /// injected [_shareFn] in tests, or the default temp-file + system share
  /// sheet in production).
  Future<void> generate(BuildContext context) async {
    if (_from == null || _to == null) {
      _error = '请选择日期范围';
      notifyListeners();
      return;
    }

    _generating = true;
    _progress = 0;
    _error = null;
    notifyListeners();

    try {
      final bytes = await _service.export(
        title: _title,
        from: _from!,
        to: _to!,
        tags: _selectedTags.isEmpty ? null : _selectedTags,
        onProgress: updateProgress,
      );

      final fileName = _safeFileName('$_title.pdf');
      if (_shareFn != null) {
        await _shareFn(bytes, fileName);
      } else if (context.mounted) {
        await _defaultShare(bytes, fileName, context);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _generating = false;
      _progress = null;
      notifyListeners();
    }
  }

  /// Default production share path: writes [bytes] to a temp file and hands
  /// it to `Share.shareXFiles`, mirroring `ShareService.shareTextAsFile`
  /// (including the iPad-safe `sharePositionOrigin` computed from a
  /// [RenderBox] on [context]).
  Future<void> _defaultShare(
    Uint8List bytes,
    String fileName,
    BuildContext context,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final sharePositionOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  String _autoTitle(DateTime from, DateTime to) =>
      '$_defaultTitle · ${_fmt(from)}–${_fmt(to)}';

  String _fmt(DateTime d) => '${d.year}/${d.month}/${d.day}';

  String _safeFileName(String fileName) {
    final sanitized = fileName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.isEmpty ? 'memory_book.pdf' : sanitized;
  }
}
