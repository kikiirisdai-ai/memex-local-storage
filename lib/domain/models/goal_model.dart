const _goalTypes = {'quantitative', 'binary'};
const _goalStatuses = {'active', 'completed'};

/// Validates a goal type: 'quantitative' | 'binary', or null otherwise.
String? sanitizeGoalType(Object? raw) {
  if (raw is! String) return null;
  return _goalTypes.contains(raw) ? raw : null;
}

/// Validates a goal status: 'active' | 'completed', or null otherwise.
String? sanitizeGoalStatus(Object? raw) {
  if (raw is! String) return null;
  return _goalStatuses.contains(raw) ? raw : null;
}
