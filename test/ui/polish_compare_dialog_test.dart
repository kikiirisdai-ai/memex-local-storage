import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/polish_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/chat/widgets/polish_compare_dialog.dart';
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

  testWidgets('tapping 用这个 on literary returns literary choice',
      (tester) async {
    PolishChoice? picked;
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            picked = await showPolishCompareDialog(
              ctx,
              original: '原话',
              result: const PolishResult(plain: 'A', literary: 'B'),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // All three columns present.
    expect(find.text('原话'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('polish_use_literary')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.style, 'literary');
    expect(picked!.text, 'B');
  });

  testWidgets('tapping 用这个 on original returns original choice',
      (tester) async {
    PolishChoice? picked;
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            picked = await showPolishCompareDialog(
              ctx,
              original: '原话',
              result: const PolishResult(plain: 'A', literary: 'B'),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('polish_use_original')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.style, 'original');
    expect(picked!.text, '原话');
  });

  testWidgets('failed variant shows placeholder and disables its button',
      (tester) async {
    PolishChoice? picked;
    await tester.pumpWidget(buildTestableWidget(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            picked = await showPolishCompareDialog(
              ctx,
              original: '原话',
              result: const PolishResult(plain: 'A', literary: null),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Failed literary column shows the failure placeholder text.
    expect(find.text('生成失败'), findsOneWidget);

    final literaryButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('polish_use_literary')),
    );
    expect(literaryButton.onPressed, isNull);

    // Plain variant still works normally.
    await tester.tap(find.byKey(const ValueKey('polish_use_plain')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.style, 'plain');
    expect(picked!.text, 'A');
  });
}
