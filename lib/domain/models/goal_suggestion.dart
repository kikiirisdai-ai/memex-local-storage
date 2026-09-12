/// A quick-capture suggestion to nudge one in-progress goal, produced by
/// [QuickCaptureService] after validating the model's raw output against
/// the exact goal list that was injected into the prompt for this request.
class GoalSuggestion {
  const GoalSuggestion({
    required this.goalId,
    required this.goalTitle,
    required this.goalType,
    this.delta,
  });

  final String goalId;
  final String goalTitle;

  /// 'quantitative' | 'binary'.
  final String goalType;

  /// Suggested increment for a quantitative goal. Always null for binary
  /// (a binary suggestion means "mark complete", not "add N").
  final double? delta;
}

/// Validates a model-produced increment: accepts a positive, finite number
/// (or numeric string). Rejects NaN, Infinity, non-positive, and anything
/// that doesn't parse — same tolerant-but-strict philosophy as the other
/// quick-capture sanitizers.
double? asPositiveFinite(Object? raw) {
  final n = switch (raw) {
    num v => v.toDouble(),
    String v => double.tryParse(v.trim()),
    _ => null,
  };
  if (n == null || !n.isFinite || n <= 0) return null;
  return n;
}
