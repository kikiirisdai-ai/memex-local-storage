import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/view_models/export_backup_viewmodel.dart';
import 'package:memex/ui/settings/widgets/export_backup_tile.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Widget buildTestable(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  final tileFinder = find.byKey(const ValueKey('export_backup_tile'));
  final subtitleFinder = find.byKey(const ValueKey('export_backup_subtitle'));

  testWidgets('shows warning subtitle when never exported', (tester) async {
    final vm = ExportBackupViewModel.forTesting(
      createFn: () async => '/tmp/x.memex',
      shareFn: (path) async {},
    );

    await tester.pumpWidget(buildTestable(ExportBackupTile(viewModel: vm)));

    expect(tileFinder, findsOneWidget);
    final subtitle = tester.widget<Text>(subtitleFinder);
    expect(subtitle.data, UserStorage.l10n.exportBackupNeverExported);
  });

  testWidgets('shows last export date after a successful export', (
    tester,
  ) async {
    final vm = ExportBackupViewModel.forTesting(
      createFn: () async => '/tmp/x.memex',
      shareFn: (path) async {},
      now: () => DateTime(2026, 9, 1),
    );

    await tester.pumpWidget(buildTestable(ExportBackupTile(viewModel: vm)));

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    final subtitle = tester.widget<Text>(subtitleFinder);
    expect(subtitle.data, contains('2026'));
    expect(subtitle.data, isNot(UserStorage.l10n.exportBackupNeverExported));
  });

  testWidgets('tapping the tile invokes export (create+share called)', (
    tester,
  ) async {
    bool created = false;
    bool shared = false;
    final vm = ExportBackupViewModel.forTesting(
      createFn: () async {
        created = true;
        return '/tmp/x.memex';
      },
      shareFn: (path) async {
        shared = true;
      },
    );

    await tester.pumpWidget(buildTestable(ExportBackupTile(viewModel: vm)));
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(created, isTrue);
    expect(shared, isTrue);
  });

  testWidgets('shows an error toast when export fails', (tester) async {
    final vm = ExportBackupViewModel.forTesting(
      createFn: () async => throw Exception('boom'),
      shareFn: (path) async {},
    );

    await tester.pumpWidget(buildTestable(ExportBackupTile(viewModel: vm)));
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
