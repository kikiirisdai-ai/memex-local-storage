import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('clear_filter_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_timeline_clear_filter_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildApp(TimelineViewModel viewModel, InsightViewModel insightViewModel) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TimelineScreen(
          viewModel: viewModel,
          insightViewModel: insightViewModel,
          onInputTap: () {},
        ),
      ),
    );
  }

  testWidgets(
    'clear-filter chip is hidden when activeFilter is "all"',
    (tester) async {
      final viewModel = TimelineViewModel.forTest();
      final insightViewModel = InsightViewModel(router: MemexRouter());

      await tester.pumpWidget(buildApp(viewModel, insightViewModel));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('timeline_clear_filter_chip')),
        findsNothing,
      );

      viewModel.dispose();
      insightViewModel.dispose();
    },
  );

  testWidgets(
    'clear-filter chip is shown when a tag filter is active, and tapping it resets to "all"',
    (tester) async {
      final viewModel = TimelineViewModel.forTest();
      final insightViewModel = InsightViewModel(router: MemexRouter());

      viewModel.setActiveFilter('travel');

      await tester.pumpWidget(buildApp(viewModel, insightViewModel));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('timeline_clear_filter_chip')),
        findsOneWidget,
      );
      expect(find.text('travel'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timeline_clear_filter_chip')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(viewModel.activeFilter, 'all');
      expect(
        find.byKey(const ValueKey('timeline_clear_filter_chip')),
        findsNothing,
      );

      viewModel.dispose();
      insightViewModel.dispose();
    },
  );
}
