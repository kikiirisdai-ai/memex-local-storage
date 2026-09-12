import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/media_library_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/ui/media_library/widgets/media_library_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaLibraryViewModel _buildViewModel() {
  final vm = MediaLibraryViewModel.forTest(
    fetchTimelineCards: ({page = 1, limit = 20}) async =>
        const Ok(<TimelineCardModel>[]),
  );
  vm.setEntriesForTesting([
    MediaLibraryEntry(
      cardId: 'book_1',
      mediaType: 'book',
      mediaStatus: 'want',
      title: 'Dune',
      comment: null,
      rating: null,
      timestamp: DateTime(2026, 1, 1),
    ),
    MediaLibraryEntry(
      cardId: 'movie_1',
      mediaType: 'movie',
      mediaStatus: 'done',
      title: 'Arrival',
      comment: 'Loved it',
      rating: 9,
      timestamp: DateTime(2026, 1, 2),
    ),
  ]);
  return vm;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('media_library_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_media_library_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('lists every media entry with its status and rating',
      (tester) async {
    final vm = _buildViewModel();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MediaLibraryScreen(),
      ),
    ));

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.textContaining('9/10'), findsOneWidget);
  });

  testWidgets('tapping a type filter narrows the list', (tester) async {
    final vm = _buildViewModel();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MediaLibraryScreen(),
      ),
    ));

    await tester.tap(find.text('Book'));
    await tester.pump();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
  });

  testWidgets('shows the empty state when there are no entries',
      (tester) async {
    final vm = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Ok(<TimelineCardModel>[]),
    );
    vm.setEntriesForTesting(const []);

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MediaLibraryScreen(),
      ),
    ));

    expect(find.text('No media records yet'), findsOneWidget);
  });

  testWidgets(
      'manually adding an entry calls addManualEntry and closes the sheet',
      (tester) async {
    String? capturedTitle;
    String? capturedType;
    final vm = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Ok(<TimelineCardModel>[]),
      createEntry: ({
        required title,
        required mediaType,
        mediaStatus,
        rating,
        comment,
      }) async {
        capturedTitle = title;
        capturedType = mediaType;
        return const Ok('new-fact-id');
      },
    );

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MediaLibraryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media_library_add_entry_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Dune');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(capturedTitle, 'Dune');
    expect(capturedType, 'book');
    expect(find.text('Add entry manually'), findsNothing);
  });

  testWidgets('submitting an empty title shows a validation error',
      (tester) async {
    var created = false;
    final vm = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Ok(<TimelineCardModel>[]),
      createEntry: ({
        required title,
        required mediaType,
        mediaStatus,
        rating,
        comment,
      }) async {
        created = true;
        return const Ok('new-fact-id');
      },
    );

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MediaLibraryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media_library_add_entry_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(created, isFalse);
    expect(find.text('Please enter a title'), findsOneWidget);
  });
}
