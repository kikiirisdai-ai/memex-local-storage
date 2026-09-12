import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/goals/widgets/goal_form_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, GoalService service) {
  return tester.pumpWidget(
    MaterialApp(home: GoalFormPage(goalService: service)),
  );
}

void main() {
  late AppDatabase db;
  late GoalService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    await UserStorage.initL10n();
    await UserStorage.saveUser('u1');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = GoalService.forTesting(
        dao: db.goalDao, userIdProvider: () async => 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('quantitative type shows a target value field, binary does not',
      (tester) async {
    await _pump(tester, service);
    expect(find.byType(TextField), findsAtLeastNWidgets(2)); // title + target

    await tester.tap(find.text('完成型'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(1)); // title only
  });

  testWidgets('selected type chip has no checkmark', (tester) async {
    await _pump(tester, service);
    await tester.pump();

    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '数值型'));
    expect(chip.showCheckmark, isFalse);
  });

  testWidgets('saving with empty title shows an error and does not pop',
      (tester) async {
    var popped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => GoalFormPage(goalService: service),
                ),
              );
              if (result == null) {
                popped = false;
              } else {
                popped = true;
              }
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(GoalFormPage), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // Still on the form page — navigation did not pop.
    expect(find.byType(GoalFormPage), findsOneWidget);
    expect(popped, isFalse);
    expect(await service.getGoals(), isEmpty);
  });
}
