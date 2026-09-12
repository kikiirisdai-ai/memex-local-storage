import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/goal_dao.dart';
import 'package:memex/domain/models/goal_model.dart';
import 'package:memex/utils/user_storage.dart';

/// Standalone goal-tracking service, pure CRUD over the [Goals] Drift table
/// via [GoalDao]. Read by quick capture to offer goal-progress suggestions;
/// progress is written when the user confirms a suggestion or edits in the
/// goals page. Still not rendered as a timeline card.
class GoalService {
  GoalService._()
      : _daoOverride = null,
        _idGenerator = null,
        _nowProvider = null,
        _userIdProvider = null;

  static final GoalService instance = GoalService._();

  @visibleForTesting
  GoalService.forTesting({
    GoalDao? dao,
    String Function()? idGenerator,
    int Function()? nowProvider,
    Future<String?> Function()? userIdProvider,
  })  : _daoOverride = dao,
        _idGenerator = idGenerator,
        _nowProvider = nowProvider,
        _userIdProvider = userIdProvider;

  final GoalDao? _daoOverride;
  final String Function()? _idGenerator;
  final int Function()? _nowProvider;
  final Future<String?> Function()? _userIdProvider;

  static const _uuid = Uuid();

  GoalDao get _dao => _daoOverride ?? AppDatabase.instance.goalDao;
  String _newId() => _idGenerator?.call() ?? _uuid.v4();
  int _now() =>
      _nowProvider?.call() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<String> _userId() async {
    final provider = _userIdProvider;
    if (provider != null) {
      final id = await provider();
      if (id != null) return id;
    }
    final id = await UserStorage.getUserId();
    if (id == null) {
      throw Exception('User not logged in, cannot use GoalService');
    }
    return id;
  }

  /// Creates a goal. Returns the new id, or null when [goalType] is invalid
  /// or a 'quantitative' goal is missing [targetValue].
  Future<String?> createGoal({
    required String title,
    required String goalType,
    double? targetValue,
    String? unit,
    int? deadline,
  }) async {
    final sanitizedType = sanitizeGoalType(goalType);
    if (sanitizedType == null) return null;
    if (sanitizedType == 'quantitative' && targetValue == null) return null;

    final id = _newId();
    final userId = await _userId();
    await _dao.insertGoal(
      id: id,
      userId: userId,
      title: title,
      goalType: sanitizedType,
      targetValue: sanitizedType == 'quantitative' ? targetValue : null,
      unit: sanitizedType == 'quantitative' ? unit : null,
      deadline: deadline,
      status: 'active',
      createdAt: _now(),
    );
    return id;
  }

  /// Updates the current value of a quantitative goal. Clamps negative
  /// values to 0. Returns false for a binary goal or an unknown id.
  Future<bool> updateProgress(String id, double newValue) async {
    final goal = await _dao.getGoalById(id);
    if (goal == null || goal.goalType != 'quantitative') return false;
    return _dao.updateProgress(id, newValue < 0 ? 0 : newValue);
  }

  /// Adds [delta] (expected positive, from a confirmed quick-capture
  /// suggestion) to a quantitative goal's current value. Returns false for
  /// a binary goal or an unknown id, same semantics as [updateProgress].
  Future<bool> incrementProgress(String id, double delta) async {
    final goal = await _dao.getGoalById(id);
    if (goal == null || goal.goalType != 'quantitative') return false;
    return _dao.incrementProgressBy(id, delta);
  }

  Future<bool> updateDeadline(String id, int? deadline) async {
    return _dao.updateDeadline(id, deadline);
  }

  Future<bool> markCompleted(String id) async {
    return _dao.setStatus(id, status: 'completed', completedAt: _now());
  }

  Future<bool> reopen(String id) async {
    return _dao.setStatus(id, status: 'active', completedAt: null);
  }

  Future<bool> deleteGoal(String id) async {
    return _dao.deleteGoal(id);
  }

  Future<List<Goal>> getGoals() async {
    final userId = await _userId();
    return _dao.getAllGoals(userId);
  }
}
