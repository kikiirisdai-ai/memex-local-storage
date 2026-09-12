import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/goals/widgets/goals_list_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, GoalService service) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: GoalsListPage(goalService: service),
    ),
  );
}

void main() {
  late AppDatabase db;
  late GoalService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    await UserStorage.initL10n();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = GoalService.forTesting(
        dao: db.goalDao, userIdProvider: () async => 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
      'shows an active binary goal with a mark-complete button and a '
      'quantitative goal with +/- steppers', (tester) async {
    await service.createGoal(title: '学会游泳', goalType: 'binary');
    await service.createGoal(
      title: '读书 20 本',
      goalType: 'quantitative',
      targetValue: 20,
      unit: '本',
    );

    await _pump(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('学会游泳'), findsOneWidget);
    expect(find.text('读书 20 本'), findsOneWidget);
    // One "+" for the quantitative stepper, one "+" for the app bar's add
    // (new goal) button.
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    expect(find.byIcon(Icons.remove), findsOneWidget); // stepper -
  });

  testWidgets('tapping + increments a quantitative goal by 1', (tester) async {
    await service.createGoal(
      title: '读书',
      goalType: 'quantitative',
      targetValue: 10,
    );

    await _pump(tester, service);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    final goals = await service.getGoals();
    expect(goals.first.currentValue, 1);
  });

  testWidgets('empty state shows nothing crashes', (tester) async {
    await _pump(tester, service);
    await tester.pumpAndSettle();
    expect(find.byType(GoalsListPage), findsOneWidget);
  });

  testWidgets('active goal with a past deadline renders the date in red',
      (tester) async {
    final pastDeadline =
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/
            1000;
    await service.createGoal(
      title: '逾期目标',
      goalType: 'binary',
      deadline: pastDeadline,
    );

    await _pump(tester, service);
    await tester.pumpAndSettle();

    final d = DateTime.fromMillisecondsSinceEpoch(pastDeadline * 1000);
    final expected =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final textFinder = find.text(expected);
    expect(textFinder, findsOneWidget);
    final textWidget = tester.widget<Text>(textFinder);
    expect(textWidget.style?.color, Colors.red);
  });

  testWidgets(
      'tapping an existing goal\'s deadline badge opens the date picker',
      (tester) async {
    final deadline =
        DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch ~/
            1000;
    await service.createGoal(
      title: '有截止日期的目标',
      goalType: 'binary',
      deadline: deadline,
    );

    await _pump(tester, service);
    await tester.pumpAndSettle();

    final d = DateTime.fromMillisecondsSinceEpoch(deadline * 1000);
    final expected =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await tester.tap(find.text(expected));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('completed goal shows its completion date', (tester) async {
    final id = await service.createGoal(title: '已完成目标', goalType: 'binary');
    await service.markCompleted(id!);

    await _pump(tester, service);
    await tester.pumpAndSettle();

    final goals = await service.getGoals();
    final completedAt = goals.first.completedAt!;
    final d = DateTime.fromMillisecondsSinceEpoch(completedAt * 1000);
    final expected =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets(
      'tapping the current-value text opens a dialog that updates progress '
      'on save', (tester) async {
    await service.createGoal(
      title: '读书',
      goalType: 'quantitative',
      targetValue: 10,
    );

    await _pump(tester, service);
    await tester.pumpAndSettle();

    await tester.tap(find.text('0/10'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text(UserStorage.l10n.save));
    await tester.pumpAndSettle();

    final goals = await service.getGoals();
    expect(goals.first.currentValue, 7);
  });
}
