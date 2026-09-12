import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/memory_book_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/view_models/memory_book_export_viewmodel.dart';
import 'package:memex/ui/settings/widgets/memory_book_export_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMemoryBookService extends MemoryBookService {
  _FakeMemoryBookService({this.errorToThrow});

  final Object? errorToThrow;

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
    onProgress?.call(1, 1);
    if (errorToThrow != null) throw errorToThrow!;
    return Uint8List.fromList([1]);
  }
}

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Widget buildTestableWidget(MemoryBookExportViewModel viewModel) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MemoryBookExportPage(viewModel: viewModel),
    );
  }

  final titleFieldFinder =
      find.byKey(const ValueKey('memory_book_title_field'));
  final generateButtonFinder =
      find.byKey(const ValueKey('memory_book_generate_button'));

  testWidgets('renders title field and generate button', (tester) async {
    final vm = MemoryBookExportViewModel.forTesting(
      service: _FakeMemoryBookService(),
      shareFn: (bytes, fileName) async {},
    );

    await tester.pumpWidget(buildTestableWidget(vm));

    expect(titleFieldFinder, findsOneWidget);
    expect(generateButtonFinder, findsOneWidget);
  });

  testWidgets('tapping generate with no range triggers vm.generate and '
      'shows the error text', (tester) async {
    final vm = MemoryBookExportViewModel.forTesting(
      service: _FakeMemoryBookService(),
      shareFn: (bytes, fileName) async {},
    );

    await tester.pumpWidget(buildTestableWidget(vm));

    await tester.tap(generateButtonFinder);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('memory_book_error_text')),
        findsOneWidget);
  });

  testWidgets('shows progress indicator while generating', (tester) async {
    final completer = Completer<void>();
    final vm = MemoryBookExportViewModel.forTesting(
      service: _FakeMemoryBookService(),
      shareFn: (bytes, fileName) async {
        await completer.future;
      },
    );
    vm.setDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 2));

    await tester.pumpWidget(buildTestableWidget(vm));

    await tester.tap(generateButtonFinder);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('shows error text when generation fails', (tester) async {
    final vm = MemoryBookExportViewModel.forTesting(
      service: _FakeMemoryBookService(errorToThrow: Exception('boom')),
      shareFn: (bytes, fileName) async {},
    );
    vm.setDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 2));

    await tester.pumpWidget(buildTestableWidget(vm));

    await tester.tap(generateButtonFinder);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('memory_book_error_text')),
        findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });
}
