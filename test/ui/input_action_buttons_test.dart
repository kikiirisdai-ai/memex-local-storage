import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/input_action_buttons.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    await UserStorage.initL10n();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    );
  }

  testWidgets('buttons fire callbacks when enabled', (tester) async {
    int card = 0, ai = 0, pol = 0;
    await tester.pumpWidget(buildTestableWidget(
      InputActionButtons(
        enabled: true,
        onCreateCard: () => card++,
        onAiInteract: () => ai++,
        onPolish: () => pol++,
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('action_create_card')));
    await tester.tap(find.byKey(const ValueKey('action_ai_interact')));
    await tester.tap(find.byKey(const ValueKey('action_polish')));

    expect([card, ai, pol], [1, 1, 1]);
  });

  testWidgets('buttons are disabled when enabled is false', (tester) async {
    int card = 0, ai = 0, pol = 0;
    await tester.pumpWidget(buildTestableWidget(
      InputActionButtons(
        enabled: false,
        onCreateCard: () => card++,
        onAiInteract: () => ai++,
        onPolish: () => pol++,
      ),
    ));

    await tester.tap(
      find.byKey(const ValueKey('action_create_card')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('action_ai_interact')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('action_polish')),
      warnIfMissed: false,
    );

    expect([card, ai, pol], [0, 0, 0]);
  });

  testWidgets('polish button is disabled and shows a spinner while polishing',
      (tester) async {
    int pol = 0;
    await tester.pumpWidget(buildTestableWidget(
      InputActionButtons(
        enabled: true,
        onCreateCard: () {},
        onAiInteract: () {},
        onPolish: () => pol++,
        isPolishing: true,
      ),
    ));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('action_polish')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    // A second tap while polishing must be a no-op.
    await tester.tap(
      find.byKey(const ValueKey('action_polish')),
      warnIfMissed: false,
    );
    expect(pol, 0);
  });
}
