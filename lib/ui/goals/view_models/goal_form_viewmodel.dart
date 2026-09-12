import 'package:flutter/foundation.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Form state for creating a goal. Plain ChangeNotifier, no Command wrapper
/// (mirrors CardSearchViewModel/MemoryViewModel style).
class GoalFormViewModel extends ChangeNotifier {
  GoalFormViewModel({required GoalService goalService})
      : _goalService = goalService;

  final GoalService _goalService;

  String title = '';
  String goalType = 'quantitative';
  String targetValueText = '';
  String? unit;
  DateTime? deadline;

  bool isSaving = false;
  String? error;

  /// Validates and creates the goal. Returns true on success.
  Future<bool> save() async {
    if (title.trim().isEmpty) {
      error = UserStorage.l10n.goalFormTitleRequired;
      notifyListeners();
      return false;
    }

    double? targetValue;
    if (goalType == 'quantitative') {
      final parsed = double.tryParse(targetValueText.trim());
      if (parsed == null || !parsed.isFinite || parsed <= 0) {
        error = UserStorage.l10n.goalFormTargetValueRequired;
        notifyListeners();
        return false;
      }
      targetValue = parsed;
    }

    isSaving = true;
    error = null;
    notifyListeners();

    final id = await _goalService.createGoal(
      title: title.trim(),
      goalType: goalType,
      targetValue: targetValue,
      unit: (unit?.trim().isEmpty ?? true) ? null : unit!.trim(),
      deadline:
          deadline == null ? null : deadline!.millisecondsSinceEpoch ~/ 1000,
    );

    isSaving = false;
    if (id == null) {
      error = UserStorage.l10n.unknownError;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }
}
