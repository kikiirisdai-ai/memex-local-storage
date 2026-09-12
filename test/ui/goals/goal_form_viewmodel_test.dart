import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/goals/view_models/goal_form_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GoalService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    await UserStorage.initL10n();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = GoalService.forTesting(
      dao: db.goalDao,
      userIdProvider: () async => 'u1',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('save() rejects an empty title without calling the service', () async {
    final vm = GoalFormViewModel(goalService: service);
    vm.title = '';
    vm.goalType = 'binary';

    final ok = await vm.save();
    expect(ok, isFalse);
    expect(vm.error, isNotNull);
    expect(await service.getGoals(), isEmpty);
  });

  test('save() rejects a quantitative goal with no target value', () async {
    final vm = GoalFormViewModel(goalService: service);
    vm.title = '读书';
    vm.goalType = 'quantitative';
    vm.targetValueText = '';

    final ok = await vm.save();
    expect(ok, isFalse);
    expect(vm.error, isNotNull);
  });

  test('save() rejects a non-numeric target value', () async {
    final vm = GoalFormViewModel(goalService: service);
    vm.title = '读书';
    vm.goalType = 'quantitative';
    vm.targetValueText = 'abc';

    final ok = await vm.save();
    expect(ok, isFalse);
  });

  test('save() rejects NaN/Infinity/negative/zero target values', () async {
    for (final value in ['NaN', 'Infinity', '-5', '0']) {
      final vm = GoalFormViewModel(goalService: service);
      vm.title = '读书';
      vm.goalType = 'quantitative';
      vm.targetValueText = value;

      final ok = await vm.save();
      expect(ok, isFalse, reason: 'target value "$value" should be rejected');
      expect(vm.error, isNotNull);
    }
    expect(await service.getGoals(), isEmpty);
  });

  test('save() creates a binary goal', () async {
    final vm = GoalFormViewModel(goalService: service);
    vm.title = '学会游泳';
    vm.goalType = 'binary';

    final ok = await vm.save();
    expect(ok, isTrue);
    expect(vm.error, isNull);

    final goals = await service.getGoals();
    expect(goals, hasLength(1));
    expect(goals.first.title, '学会游泳');
  });

  test('save() creates a quantitative goal with unit and deadline', () async {
    final vm = GoalFormViewModel(goalService: service);
    vm.title = '读书 20 本';
    vm.goalType = 'quantitative';
    vm.targetValueText = '20';
    vm.unit = '本';
    vm.deadline = DateTime(2026, 12, 31);

    final ok = await vm.save();
    expect(ok, isTrue);

    final goal = (await service.getGoals()).first;
    expect(goal.targetValue, 20);
    expect(goal.unit, '本');
    expect(goal.deadline, isNotNull);
  });
}
