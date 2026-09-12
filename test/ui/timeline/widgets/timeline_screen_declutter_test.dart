import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/schedule/widgets/schedule_aggregator_screen.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('declutter_hide_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_timeline_declutter_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'kShowActionCenter is false, so the timeline header hides the notification bell',
    (tester) async {
      // reversible: this documents/guards the flag; flipping kShowActionCenter
      // back to true restores the Action Center notification bell button.
      expect(kShowActionCenter, isFalse);

      final viewModel = TimelineViewModel.forTest();
      final insightViewModel = InsightViewModel(router: MemexRouter());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineScreen(
              viewModel: viewModel,
              insightViewModel: insightViewModel,
              onInputTap: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture &&
              widget.toString().contains('notification_bell'),
        ),
        findsNothing,
      );

      viewModel.dispose();
      insightViewModel.dispose();
    },
  );

  testWidgets(
    'kShowScheduleEntry is false, so openScheduleTab() is a no-op',
    (tester) async {
      // reversible: this documents/guards the flag; flipping
      // kShowScheduleEntry back to true restores schedule navigation.
      expect(kShowScheduleEntry, isFalse);

      final viewModel = TimelineViewModel.forTest();
      final insightViewModel = InsightViewModel(router: MemexRouter());
      final timelineKey = GlobalKey<TimelineScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineScreen(
              key: timelineKey,
              viewModel: viewModel,
              insightViewModel: insightViewModel,
              onInputTap: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      timelineKey.currentState?.openScheduleTab();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ScheduleAggregatorScreen), findsNothing);

      viewModel.dispose();
      insightViewModel.dispose();
    },
  );
}
