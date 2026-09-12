import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/polish_edit_confirm_sheet.dart';
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
      home: child,
    );
  }

  testWidgets('edit then confirm returns edited text', (tester) async {
    String? out;
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            out = await showPolishEditConfirmSheet(ctx, initialText: '初始');
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('初始'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('polish_edit_field')),
      '改过的',
    );
    await tester.tap(find.byKey(const ValueKey('polish_confirm_button')));
    await tester.pumpAndSettle();

    expect(out, '改过的');
  });

  testWidgets('cancel returns null', (tester) async {
    String? out = 'unset';
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            out = await showPolishEditConfirmSheet(ctx, initialText: '初始');
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('polish_cancel_button')));
    await tester.pumpAndSettle();

    expect(out, isNull);
  });

  testWidgets('confirm trims whitespace from edited text', (tester) async {
    String? out;
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            out = await showPolishEditConfirmSheet(ctx, initialText: '初始');
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('polish_edit_field')),
      '  带空格  ',
    );
    await tester.tap(find.byKey(const ValueKey('polish_confirm_button')));
    await tester.pumpAndSettle();

    expect(out, '带空格');
  });
}
