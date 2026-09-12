import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:memex/data/services/rollup_periods.dart';
import 'package:memex/data/services/rollup_service.dart';

const String weeklySummaryTaskType = 'weekly_summary_task';

/// Thin facade over the generic [RollupService] engine + [weeklyRollup]
/// strategy. Generates one weekly rollup card from the week's seven daily
/// summary cards (never the raw fragments — the hierarchy keeps LLM input
/// small and stable). Includes a per-day mood sparkline built from card
/// metadata. Idempotent per ISO week — regeneration updates the same card.
///
/// All the period-specific behavior (pref keys, prompt, compose, context
/// collection) lives in `weeklyRollup` (`lib/data/services/rollup_periods.dart`);
/// this class only adapts the old public surface to the new engine so
/// existing call sites and tests keep working unchanged.
class WeeklySummaryService {
  WeeklySummaryService._() : _engine = RollupService.instance;

  static final WeeklySummaryService instance = WeeklySummaryService._();

  @visibleForTesting
  WeeklySummaryService.forTesting({
    Future<({LLMClient client, ModelConfig modelConfig})> Function()?
        resourcesProvider,
  }) : _engine =
            // ignore: invalid_use_of_visible_for_testing_member
            RollupService.forTesting(resourcesProvider: resourcesProvider);

  final RollupService _engine;

  /// Local hour on Sunday after which the week's summary may be generated.
  static const int summaryHour = weeklySummaryHour;

  /// Monday 00:00 of the week containing [date]. Calendar arithmetic (not
  /// Duration) so DST-transition weeks cannot shift the date.
  static DateTime mondayOf(DateTime date) => weeklyMondayOf(date);

  /// ISO-8601 week key, e.g. "2026-W29". The ISO year can differ from the
  /// calendar year around New Year (a week belongs to the year holding its
  /// Thursday). Computed in UTC so local DST gaps cannot skew day counts.
  static String weekKey(DateTime date) => weeklyKeyFor(date);

  /// Decides which week (returned as its Monday) needs a summary right now.
  ///
  /// - After Sunday [summaryHour] with no summary for this week → this week.
  /// - Otherwise, if the previous week was never summarized → previous week
  ///   (catch-up, mirrors the daily service's yesterday catch-up).
  /// - Otherwise null.
  @visibleForTesting
  static DateTime? dueWeekFor({
    required DateTime now,
    required String? lastGeneratedWeek,
    required bool enabled,
  }) =>
      weeklyRollup.dueFor(
        now: now,
        lastGeneratedKey: lastGeneratedWeek,
        enabled: enabled,
      );

  /// Checks whether a weekly summary is due and enqueues the generation
  /// task. Called on app launch and foreground resume; cheap when idle.
  Future<void> maybeSchedule({DateTime? now}) =>
      _engine.maybeSchedule(weeklyRollup, now: now);

  /// Generates (or regenerates) the summary card for the week starting at
  /// [monday]. Returns true when a card was written; false when skipped.
  Future<bool> generate(String userId, DateTime monday) =>
      _engine.generate(userId, weeklyRollup, monday);

  /// Gathers the week's seven daily summary cards. `dayScores` holds one
  /// entry per weekday (Mon..Sun); null where a day has no summary or no
  /// mood. Returns null when the entire week has no daily summaries.
  Future<({String context, List<int?> dayScores})?> collectWeekContext(
    String userId,
    DateTime monday,
  ) async {
    final collected = await weeklyRollup.collectContext(userId, monday);
    if (collected == null) return null;
    return (context: collected.context, dayScores: collected.scores);
  }

  // ─── Mood aggregation ──────────────────────────────────────────────

  /// Rounded average of the non-null day scores, or null when none exist.
  @visibleForTesting
  static int? averageScore(List<int?> dayScores) =>
      RollupService.averageScore(dayScores);

  /// One line like "一▃ 二▅ 三· 四▇ …" — a bar per day, "·" for days
  /// without a mood.
  @visibleForTesting
  static String sparkline(List<int?> dayScores) => weeklySparkline(dayScores);

  @visibleForTesting
  static String? composeMarkdown(
    Map<String, dynamic> decision,
    List<int?> dayScores,
  ) =>
      weeklyRollup.compose(decision, dayScores);
}
