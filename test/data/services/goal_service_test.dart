import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GoalService service;
  var clock = 1000;
  var uuidCounter = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    clock = 1000;
    uuidCounter = 0;
    service = GoalService.forTesting(
      dao: db.goalDao,
      idGenerator: () => 'goal-${uuidCounter++}',
      nowProvider: () => clock,
      userIdProvider: () async => 'test-user',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('createGoal', () {
    test('creates a quantitative goal and returns its id', () async {
      final id = await service.createGoal(
        title: '读书 20 本',
        goalType: 'quantitative',
        targetValue: 20,
        unit: '本',
      );
      expect(id, 'goal-0');

      final goals = await service.getGoals();
      expect(goals, hasLength(1));
      expect(goals.first.title, '读书 20 本');
      expect(goals.first.targetValue, 20);
      expect(goals.first.unit, '本');
      expect(goals.first.currentValue, 0);
      expect(goals.first.status, 'active');
      expect(goals.first.createdAt, 1000);
    });

    test('creates a binary goal with null targetValue/unit', () async {
      final id = await service.createGoal(title: '学会游泳', goalType: 'binary');
      expect(id, isNotNull);

      final goals = await service.getGoals();
      expect(goals.first.targetValue, isNull);
      expect(goals.first.unit, isNull);
    });

    test('rejects an invalid goalType', () async {
      final id = await service.createGoal(title: 'x', goalType: 'nope');
      expect(id, isNull);
      expect(await service.getGoals(), isEmpty);
    });

    test('rejects a quantitative goal with no targetValue', () async {
      final id = await service.createGoal(title: 'x', goalType: 'quantitative');
      expect(id, isNull);
      expect(await service.getGoals(), isEmpty);
    });
  });

  group('updateProgress', () {
    test('updates a quantitative goal', () async {
      final id = await service.createGoal(
        title: 'x',
        goalType: 'quantitative',
        targetValue: 10,
      );
      final ok = await service.updateProgress(id!, 3);
      expect(ok, isTrue);
      expect((await service.getGoals()).first.currentValue, 3);
    });

    test('clamps a negative value to 0', () async {
      final id = await service.createGoal(
        title: 'x',
        goalType: 'quantitative',
        targetValue: 10,
      );
      await service.updateProgress(id!, -5);
      expect((await service.getGoals()).first.currentValue, 0);
    });

    test('rejects updates on a binary goal', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      final ok = await service.updateProgress(id!, 3);
      expect(ok, isFalse);
    });

    test('returns false for a missing id', () async {
      expect(await service.updateProgress('nope', 3), isFalse);
    });
  });

  group('updateDeadline', () {
    test('sets the deadline on an existing goal', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      final ok = await service.updateDeadline(id!, 500);
      expect(ok, isTrue);

      final goals = await service.getGoals();
      expect(goals.single.deadline, 500);
    });

    test('returns false for a missing id', () async {
      expect(await service.updateDeadline('nope', 500), isFalse);
    });
  });

  group('incrementProgress', () {
    test('adds delta to the current value', () async {
      final id = await service.createGoal(
        title: 'x',
        goalType: 'quantitative',
        targetValue: 10,
      );
      await service.updateProgress(id!, 3);

      final ok = await service.incrementProgress(id, 2);
      expect(ok, isTrue);
      expect((await service.getGoals()).first.currentValue, 5);
    });

    test('rejects a binary goal', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      final ok = await service.incrementProgress(id!, 1);
      expect(ok, isFalse);
    });

    test('returns false for a missing id', () async {
      expect(await service.incrementProgress('nope', 1), isFalse);
    });

    test('concurrent increments do not lose updates (atomic write)',
        () async {
      final id = await service.createGoal(
        title: 'x',
        goalType: 'quantitative',
        targetValue: 10,
      );

      await Future.wait([
        service.incrementProgress(id!, 1),
        service.incrementProgress(id, 1),
        service.incrementProgress(id, 1),
      ]);

      expect((await service.getGoals()).first.currentValue, 3);
    });

    test('decrementing below 0 clamps at 0', () async {
      final id = await service.createGoal(
        title: 'x',
        goalType: 'quantitative',
        targetValue: 10,
      );
      await service.incrementProgress(id!, 1);

      await service.incrementProgress(id, -5);

      expect((await service.getGoals()).first.currentValue, 0);
    });
  });

  group('markCompleted / reopen', () {
    test('markCompleted sets status and completedAt', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      clock = 2000;
      final ok = await service.markCompleted(id!);
      expect(ok, isTrue);

      final goal = (await service.getGoals()).first;
      expect(goal.status, 'completed');
      expect(goal.completedAt, 2000);
    });

    test('reopen clears completedAt and sets status active', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      await service.markCompleted(id!);
      final ok = await service.reopen(id);
      expect(ok, isTrue);

      final goal = (await service.getGoals()).first;
      expect(goal.status, 'active');
      expect(goal.completedAt, isNull);
    });
  });

  group('deleteGoal', () {
    test('removes the goal', () async {
      final id = await service.createGoal(title: 'x', goalType: 'binary');
      final ok = await service.deleteGoal(id!);
      expect(ok, isTrue);
      expect(await service.getGoals(), isEmpty);
    });
  });
}
