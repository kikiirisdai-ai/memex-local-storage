import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/db/app_database.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('GoalDao', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insertGoal then getAllGoals returns it ordered by createdAt desc',
        () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: '读书 20 本',
        goalType: 'quantitative',
        targetValue: 20,
        unit: '本',
        status: 'active',
        createdAt: 100,
      );
      await db.goalDao.insertGoal(
        id: 'g2',
        userId: 'u1',
        title: '学会游泳',
        goalType: 'binary',
        status: 'active',
        createdAt: 200,
      );

      final rows = await db.goalDao.getAllGoals('u1');
      expect(rows, hasLength(2));
      expect(rows.first.id, 'g2'); // newer first
      expect(rows.last.id, 'g1');
      expect(rows.last.targetValue, 20);
      expect(rows.last.unit, '本');
      expect(rows.first.targetValue, isNull);
    });

    test('getAllGoals scopes by userId', () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'binary',
        status: 'active',
        createdAt: 1,
      );
      await db.goalDao.insertGoal(
        id: 'g2',
        userId: 'u2',
        title: 'b',
        goalType: 'binary',
        status: 'active',
        createdAt: 1,
      );

      final u1Goals = await db.goalDao.getAllGoals('u1');
      expect(u1Goals.map((g) => g.id), ['g1']);
    });

    test('updateProgress updates currentValue and returns true', () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'quantitative',
        targetValue: 10,
        status: 'active',
        createdAt: 1,
      );

      final ok = await db.goalDao.updateProgress('g1', 5);
      expect(ok, isTrue);

      final goal = await db.goalDao.getGoalById('g1');
      expect(goal!.currentValue, 5);
    });

    test('updateProgress on a missing id returns false', () async {
      final ok = await db.goalDao.updateProgress('nope', 5);
      expect(ok, isFalse);
    });

    test('updateDeadline updates deadline and returns true', () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'binary',
        status: 'active',
        createdAt: 1,
      );

      final ok = await db.goalDao.updateDeadline('g1', 500);
      expect(ok, isTrue);

      final goal = await db.goalDao.getGoalById('g1');
      expect(goal!.deadline, 500);
    });

    test('updateDeadline with null clears an existing deadline', () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'binary',
        deadline: 500,
        status: 'active',
        createdAt: 1,
      );

      final ok = await db.goalDao.updateDeadline('g1', null);
      expect(ok, isTrue);

      final goal = await db.goalDao.getGoalById('g1');
      expect(goal!.deadline, isNull);
    });

    test('updateDeadline on a missing id returns false', () async {
      final ok = await db.goalDao.updateDeadline('nope', 500);
      expect(ok, isFalse);
    });

    test('setStatus updates status and completedAt', () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'binary',
        status: 'active',
        createdAt: 1,
      );

      final ok = await db.goalDao.setStatus('g1', status: 'completed', completedAt: 999);
      expect(ok, isTrue);

      final goal = await db.goalDao.getGoalById('g1');
      expect(goal!.status, 'completed');
      expect(goal.completedAt, 999);
    });

    test('deleteGoal removes the row and returns true; missing id returns false',
        () async {
      await db.goalDao.insertGoal(
        id: 'g1',
        userId: 'u1',
        title: 'a',
        goalType: 'binary',
        status: 'active',
        createdAt: 1,
      );

      final ok = await db.goalDao.deleteGoal('g1');
      expect(ok, isTrue);
      expect(await db.goalDao.getGoalById('g1'), isNull);

      final okAgain = await db.goalDao.deleteGoal('g1');
      expect(okAgain, isFalse);
    });
  });
}
