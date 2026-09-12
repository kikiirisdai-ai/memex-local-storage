import 'package:flutter/foundation.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';

/// List state for the "My Goals" page. Plain ChangeNotifier, no Command
/// wrapper (mirrors CardSearchViewModel/MemoryViewModel style). Groups are
/// derived client-side from a single fetch, and every mutation reloads the
/// whole list — simplest correct approach for a low-cardinality list.
class GoalsListViewModel extends ChangeNotifier {
  GoalsListViewModel({required GoalService goalService})
      : _goalService = goalService;

  final GoalService _goalService;

  List<Goal> _goals = [];
  bool isLoading = false;
  String? error;

  List<Goal> get activeGoals =>
      _goals.where((g) => g.status == 'active').toList();
  List<Goal> get completedGoals =>
      _goals.where((g) => g.status == 'completed').toList();

  Future<void> loadGoals() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _goals = await _goalService.getGoals();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> updateProgress(String id, double newValue) async {
    await _goalService.updateProgress(id, newValue);
    await loadGoals();
  }

  /// Atomic +/- stepper: adds [delta] (positive or negative) via
  /// [GoalService.incrementProgress] instead of reading the current value
  /// and writing an absolute one, avoiding a lost-update race on rapid taps.
  Future<void> incrementProgress(String id, double delta) async {
    await _goalService.incrementProgress(id, delta);
    await loadGoals();
  }

  Future<void> updateDeadline(String id, int? deadline) async {
    await _goalService.updateDeadline(id, deadline);
    await loadGoals();
  }

  Future<void> markCompleted(String id) async {
    await _goalService.markCompleted(id);
    await loadGoals();
  }

  Future<void> reopen(String id) async {
    await _goalService.reopen(id);
    await loadGoals();
  }

  Future<void> deleteGoal(String id) async {
    await _goalService.deleteGoal(id);
    await loadGoals();
  }
}
