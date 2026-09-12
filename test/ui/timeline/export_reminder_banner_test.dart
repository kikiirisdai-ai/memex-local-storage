import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/view_models/export_backup_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/export_reminder_banner.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  final bannerFinder = find.byKey(const ValueKey('export_reminder_banner'));
  final exportBtnFinder =
      find.byKey(const ValueKey('export_reminder_export_btn'));
  final dismissBtnFinder =
      find.byKey(const ValueKey('export_reminder_dismiss_btn'));

  final fixedNow = DateTime(2026, 9, 5);

  Widget buildTestable(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('never exported -> banner visible', (tester) async {
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => null,
      snoozeProvider: () async => null,
      onSnooze: (_) async {},
      onExport: (_) async {},
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsOneWidget);
  });

  testWidgets('exported 20 days ago, no snooze -> banner visible',
      (tester) async {
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => fixedNow.subtract(
        const Duration(days: 20),
      ),
      snoozeProvider: () async => null,
      onSnooze: (_) async {},
      onExport: (_) async {},
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsOneWidget);
  });

  testWidgets('exported 2 days ago -> banner hidden', (tester) async {
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => fixedNow.subtract(
        const Duration(days: 2),
      ),
      snoozeProvider: () async => null,
      onSnooze: (_) async {},
      onExport: (_) async {},
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);
  });

  testWidgets('snooze active in the future -> banner hidden even if overdue',
      (tester) async {
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => fixedNow.subtract(
        const Duration(days: 30),
      ),
      snoozeProvider: () async => fixedNow.add(const Duration(days: 1)),
      onSnooze: (_) async {},
      onExport: (_) async {},
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);
  });

  testWidgets('tapping export button invokes onExport', (tester) async {
    var exportCalled = false;
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => null,
      snoozeProvider: () async => null,
      onSnooze: (_) async {},
      onExport: (context) async {
        exportCalled = true;
      },
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    await tester.tap(exportBtnFinder);
    await tester.pumpAndSettle();

    expect(exportCalled, isTrue);
  });

  testWidgets(
      'tapping dismiss button invokes onSnooze ~3 days ahead and hides banner',
      (tester) async {
    DateTime? snoozeUntilArg;
    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => null,
      snoozeProvider: () async => null,
      onSnooze: (until) async {
        snoozeUntilArg = until;
      },
      onExport: (_) async {},
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    await tester.tap(dismissBtnFinder);
    await tester.pumpAndSettle();

    expect(snoozeUntilArg, isNotNull);
    final diff = snoozeUntilArg!.difference(fixedNow);
    expect(diff.inHours, closeTo(const Duration(days: 3).inHours, 1));

    expect(bannerFinder, findsNothing);
  });

  testWidgets(
      'export failure via the injected ViewModel surfaces an error toast '
      'and keeps the banner visible', (tester) async {
    final vm = ExportBackupViewModel.forTesting(
      createFn: () async => throw Exception('disk full'),
      shareFn: (path) async {},
    );

    await tester.pumpWidget(buildTestable(ExportReminderBanner.forTesting(
      lastExportProvider: () async => null,
      snoozeProvider: () async => null,
      onSnooze: (_) async {},
      viewModel: vm,
      now: () => fixedNow,
    )));
    await tester.pumpAndSettle();

    await tester.tap(exportBtnFinder);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(bannerFinder, findsOneWidget);
  });
}
