import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'goal_dao.g.dart';

@DriftAccessor(tables: [Goals])
class GoalDao extends DatabaseAccessor<AppDatabase> with _$GoalDaoMixin {
  GoalDao(super.db);

  Future<void> insertGoal({
    required String id,
    required String userId,
    required String title,
    required String goalType,
    double? targetValue,
    double currentValue = 0,
    String? unit,
    int? deadline,
    required String status,
    required int createdAt,
  }) async {
    await into(goals).insert(GoalsCompanion.insert(
      id: id,
      userId: userId,
      title: title,
      goalType: goalType,
      targetValue: Value(targetValue),
      currentValue: Value(currentValue),
      unit: Value(unit),
      deadline: Value(deadline),
      status: status,
      createdAt: createdAt,
    ));
  }

  Future<bool> updateProgress(String id, double newValue) async {
    final rows = await (update(goals)..where((t) => t.id.equals(id)))
        .write(GoalsCompanion(currentValue: Value(newValue)));
    return rows > 0;
  }

  /// Atomically adds [delta] to `current_value` in a single SQL statement
  /// (clamped at 0), avoiding the lost-update race of a separate
  /// read-then-write. Use for increments/decrements; use [updateProgress]
  /// for an absolute user-entered value.
  Future<bool> incrementProgressBy(String id, double delta) async {
    final n = await customUpdate(
      'UPDATE goals SET current_value = MAX(0, current_value + ?) WHERE id = ?',
      variables: [Variable<double>(delta), Variable<String>(id)],
      updates: {goals},
    );
    return n > 0;
  }

  Future<bool> updateDeadline(String id, int? deadline) async {
    final rows = await (update(goals)..where((t) => t.id.equals(id)))
        .write(GoalsCompanion(deadline: Value(deadline)));
    return rows > 0;
  }

  Future<bool> setStatus(
    String id, {
    required String status,
    int? completedAt,
  }) async {
    final rows = await (update(goals)..where((t) => t.id.equals(id))).write(
      GoalsCompanion(
        status: Value(status),
        completedAt: Value(completedAt),
      ),
    );
    return rows > 0;
  }

  Future<bool> deleteGoal(String id) async {
    final rows = await (delete(goals)..where((t) => t.id.equals(id))).go();
    return rows > 0;
  }

  Future<Goal?> getGoalById(String id) async {
    return (select(goals)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<Goal>> getAllGoals(String userId) async {
    return (select(goals)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}
