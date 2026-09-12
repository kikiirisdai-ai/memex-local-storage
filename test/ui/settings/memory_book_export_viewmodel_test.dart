import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/memory_book_service.dart';
import 'package:memex/ui/settings/view_models/memory_book_export_viewmodel.dart';

/// Fake [MemoryBookService] that captures the arguments passed to
/// [export], drives [onProgress], and returns canned bytes (or throws, for
/// the failure-path test).
class _FakeMemoryBookService extends MemoryBookService {
  _FakeMemoryBookService({
    Uint8List? bytesToReturn,
    Object? errorToThrow,
  })  : _bytesToReturn = bytesToReturn ?? Uint8List.fromList([1, 2, 3]),
        _errorToThrow = errorToThrow;

  final Uint8List _bytesToReturn;
  final Object? _errorToThrow;

  String? capturedTitle;
  DateTime? capturedFrom;
  DateTime? capturedTo;
  List<String>? capturedTags;
  final List<double?> progressReports = [];

  @override
  Future<Uint8List> export({
    required String title,
    required DateTime from,
    required DateTime to,
    List<String>? tags,
    void Function(int, int)? onProgress,
    int maxImagesPerCard = MemoryBookService.defaultMaxImagesPerCard,
    int maxTotalImages = MemoryBookService.defaultMaxTotalImages,
  }) async {
    capturedTitle = title;
    capturedFrom = from;
    capturedTo = to;
    capturedTags = tags;

    onProgress?.call(1, 2);
    onProgress?.call(2, 2);

    if (_errorToThrow != null) throw _errorToThrow;
    return _bytesToReturn;
  }
}

void main() {
  testWidgets('generate with no date range sets error and does not share',
      (tester) async {
    final service = _FakeMemoryBookService();
    Uint8List? sharedBytes;
    String? sharedFileName;

    final vm = MemoryBookExportViewModel.forTesting(
      service: service,
      shareFn: (bytes, fileName) async {
        sharedBytes = bytes;
        sharedFileName = fileName;
      },
    );

    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await vm.generate(capturedContext);

    expect(vm.error, isNotNull);
    expect(vm.generating, isFalse);
    expect(service.capturedTitle, isNull);
    expect(sharedBytes, isNull);
    expect(sharedFileName, isNull);
  });

  testWidgets(
      'generate with a valid range calls export with title/from/to/tags, '
      'advances progress, and shares the resulting bytes',
      (tester) async {
    final service = _FakeMemoryBookService(
      bytesToReturn: Uint8List.fromList([9, 9, 9]),
    );
    Uint8List? sharedBytes;
    String? sharedFileName;

    final vm = MemoryBookExportViewModel.forTesting(
      service: service,
      shareFn: (bytes, fileName) async {
        sharedBytes = bytes;
        sharedFileName = fileName;
      },
    );

    final from = DateTime(2026, 1, 1);
    final to = DateTime(2026, 1, 31);
    vm.setTitle('我的旅行');
    vm.setDateRange(from, to);
    vm.toggleTag('travel');

    final progressSnapshots = <double?>[];
    vm.addListener(() => progressSnapshots.add(vm.progress));

    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await vm.generate(capturedContext);

    expect(service.capturedTitle, '我的旅行');
    expect(service.capturedFrom, from);
    expect(service.capturedTo, to);
    expect(service.capturedTags, ['travel']);

    // progress should have advanced through 0.5 and 1.0 at some point.
    expect(progressSnapshots, contains(0.5));
    expect(progressSnapshots, contains(1.0));

    expect(sharedBytes, Uint8List.fromList([9, 9, 9]));
    expect(sharedFileName, '我的旅行.pdf');

    expect(vm.generating, isFalse);
    expect(vm.progress, isNull);
    expect(vm.error, isNull);
  });

  testWidgets('generate resets generating to false and sets error when '
      'the service throws', (tester) async {
    final service = _FakeMemoryBookService(errorToThrow: Exception('boom'));
    var shareCalled = false;

    final vm = MemoryBookExportViewModel.forTesting(
      service: service,
      shareFn: (bytes, fileName) async {
        shareCalled = true;
      },
    );

    vm.setDateRange(DateTime(2026, 2, 1), DateTime(2026, 2, 5));

    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await vm.generate(capturedContext);

    expect(vm.error, contains('boom'));
    expect(vm.generating, isFalse);
    expect(shareCalled, isFalse);
  });
}
