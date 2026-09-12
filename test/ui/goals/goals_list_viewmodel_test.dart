import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/goals/view_models/goals_list_viewmodel.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GoalService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = GoalService.forTesting(
      dao: db.goalDao,
      userIdProvider: () async => 'u1',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('loadGoals splits into active/completed groups', () async {
    await service.createGoal(title: 'a', goalType: 'binary');
    final doneId = await service.createGoal(title: 'b', goalType: 'binary');
    await service.markCompleted(doneId!);

    final vm = GoalsListViewModel(goalService: service);
    await vm.loadGoals();

    expect(vm.activeGoals, hasLength(1));
    expect(vm.activeGoals.first.title, 'a');
    expect(vm.completedGoals, hasLength(1));
    expect(vm.completedGoals.first.title, 'b');
  });

  test('updateProgress reloads the list with the new value', () async {
    final id = await service.createGoal(
      title: 'a',
      goalType: 'quantitative',
      targetValue: 10,
    );
    final vm = GoalsListViewModel(goalService: service);
    await vm.loadGoals();

    await vm.updateProgress(id!, 4);

    expect(vm.activeGoals.first.currentValue, 4);
  });

  test('markCompleted moves a goal from active to completed', () async {
    final id = await service.createGoal(title: 'a', goalType: 'binary');
    final vm = GoalsListViewModel(goalService: service);
    await vm.loadGoals();

    await vm.markCompleted(id!);

    expect(vm.activeGoals, isEmpty);
    expect(vm.completedGoals, hasLength(1));
  });

  test('deleteGoal removes it from the list', () async {
    final id = await service.createGoal(title: 'a', goalType: 'binary');
    final vm = GoalsListViewModel(goalService: service);
    await vm.loadGoals();

    await vm.deleteGoal(id!);

    expect(vm.activeGoals, isEmpty);
    expect(vm.completedGoals, isEmpty);
  });
}
