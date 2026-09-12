import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/widgets/summary_reminders_tile.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  final switchFinder = find.byKey(const ValueKey('summary_reminders_toggle'));

  testWidgets('renders switch ON when readEnabled returns true',
      (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        SummaryRemindersTile(
          readEnabled: () async => true,
          writeEnabled: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final switchTile =
        tester.widget<SwitchListTile>(switchFinder);
    expect(switchTile.value, isTrue);
  });

  testWidgets('renders switch OFF when readEnabled returns false',
      (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        SummaryRemindersTile(
          readEnabled: () async => false,
          writeEnabled: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final switchTile =
        tester.widget<SwitchListTile>(switchFinder);
    expect(switchTile.value, isFalse);
  });

  testWidgets('tapping the switch calls writeEnabled with false',
      (tester) async {
    bool? written;
    await tester.pumpWidget(
      buildTestableWidget(
        SummaryRemindersTile(
          readEnabled: () async => true,
          writeEnabled: (v) async {
            written = v;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(switchFinder);
    await tester.pump();

    expect(written, isFalse);

    final switchTile =
        tester.widget<SwitchListTile>(switchFinder);
    expect(switchTile.value, isFalse);
  });
}
