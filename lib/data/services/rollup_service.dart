import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/timeline_card_event_publisher.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _logger = getLogger('RollupService');

/// Strategy abstraction describing everything period-specific (weekly,
/// monthly, ...) so [RollupService] can stay period-agnostic. Every method
/// mirrors what `WeeklySummaryService` previously hard-coded for the week
/// period; ports of that logic implement this interface instead of
/// duplicating the engine.
abstract class RollupPeriod {
  /// Task type enqueued into [LocalTaskExecutor] for this period.
  String get taskType;

  /// Tag stamped onto the generated card (e.g. `weeklySummaryTag`).
  String get tag;

  /// SharedPreferences key gating whether generation is enabled.
  String get prefEnabledKey;

  /// SharedPreferences key holding the last-generated period key (ISO,
  /// lexicographically sortable).
  String get prefLastKey;

  /// SharedPreferences key holding the factId used for idempotent card
  /// writes for the period identified by [periodKey].
  String prefFactIdKey(String periodKey);

  /// Prefix used to build the task queue's dedup `bizId`.
  String get bizIdPrefix;

  /// Stable, lexicographically sortable key for the period containing
  /// [anchor] (e.g. `'2026-W29'` / `'2026-08'`).
  String keyFor(DateTime anchor);

  /// Decides which period (returned as its canonical anchor) needs a
  /// rollup right now, or null when none is due.
  DateTime? dueFor({
    required DateTime now,
    required String? lastGeneratedKey,
    required bool enabled,
  });

  /// Task payload for the period anchored at [anchor].
  Map<String, dynamic> payloadFor(DateTime anchor);

  /// Recovers the anchor date from a previously enqueued task payload.
  DateTime? anchorFromPayload(Map<String, dynamic> payload);

  /// One label per entry in [collectContext]'s `scores` — e.g. weekday
  /// names for the weekly period — used as the x-axis of the mood-curve
  /// chart appended to the generated card.
  List<String> chartLabels(DateTime anchor, int scoreCount);

  /// Fact-line text stamped on the generated card (shown as card-detail
  /// body), for the period anchored at [anchor]. Periods with a
  /// user-facing fact string (e.g. weekly's `'每周总结 <key>'`) override
  /// this; the engine only supplies a generic fallback.
  String factText(DateTime anchor);

  /// Gathers the period's source material. Returns null when there is
  /// nothing to summarize (skip semantics).
  Future<({String context, List<int?> scores})?> collectContext(
    String userId,
    DateTime anchor,
  );

  /// System prompt sent to the model for this period.
  String systemPrompt();

  /// Fallback card title when the model does not provide one.
  String defaultTitle(DateTime anchor);

  /// Timestamp (seconds since epoch conversion handled by caller) at which
  /// the generated card should sit on the timeline.
  DateTime cardTimestamp(DateTime anchor);

  /// Composes the card's markdown body from the model's decision and the
  /// collected mood [scores]. Returns null when the decision is unusable
  /// (e.g. missing narrative).
  String? compose(Map<String, dynamic> decision, List<int?> scores);
}

/// Generic rollup engine: shared mechanics (LLM resource loading, model
/// calling with a non-strict→strict retry, idempotent card writes, marker
/// bookkeeping, and scheduling) extracted from `WeeklySummaryService` so
/// additional periods (monthly, ...) can reuse them via [RollupPeriod].
class RollupService {
  RollupService._();

  static final RollupService instance = RollupService._();

  @visibleForTesting
  RollupService.forTesting({
    Future<({LLMClient client, ModelConfig modelConfig})> Function()?
        resourcesProvider,
  }) : _resourcesProvider = resourcesProvider;

  Future<({LLMClient client, ModelConfig modelConfig})> Function()?
      _resourcesProvider;

  FileSystemService get _fs => FileSystemService.instance;

  // Keyed by period.taskType so distinct periods (weekly, monthly, ...)
  // scheduled back-to-back on the shared singleton don't block each other;
  // only concurrent scheduling of the SAME period is guarded against.
  final Set<String> _inFlight = {};

  /// Checks whether [period]'s rollup is due and enqueues the generation
  /// task. Called on app launch and foreground resume; cheap when idle.
  Future<void> maybeSchedule(RollupPeriod period, {DateTime? now}) async {
    if (_inFlight.contains(period.taskType)) return;
    _inFlight.add(period.taskType);
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final userId = await UserStorage.getUserId();
          if (userId == null) {
            throw StateError('no user session yet');
          }
          final prefs = await SharedPreferences.getInstance();
          final due = period.dueFor(
            now: now ?? DateTime.now(),
            lastGeneratedKey: prefs.getString(period.prefLastKey),
            enabled: prefs.getBool(period.prefEnabledKey) ?? true,
          );
          if (due == null) return;

          final key = period.keyFor(due);
          await LocalTaskExecutor.instance.enqueueTask(
            userId: userId,
            taskType: period.taskType,
            payload: period.payloadFor(due),
            priority: 5,
            bizId: '${period.bizIdPrefix}:$key',
          );
          _logger.info('Rollup enqueued for $key (${period.taskType})');
          return;
        } catch (e, stack) {
          _logger.warning(
            'Failed to schedule rollup (attempt ${attempt + 1})',
            e,
            stack,
          );
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    } finally {
      _inFlight.remove(period.taskType);
    }
  }

  // ─── Generation ────────────────────────────────────────────────────

  /// Generates (or regenerates) the rollup card for [period] anchored at
  /// [anchor]. Returns true when a card was written; false when skipped
  /// (no context). Marker only advances on skip or success — a model
  /// failure throws and leaves the marker untouched.
  Future<bool> generate(
    String userId,
    RollupPeriod period,
    DateTime anchor,
  ) async {
    final key = period.keyFor(anchor);
    final collected = await period.collectContext(userId, anchor);
    if (collected == null) {
      _logger.info('Rollup skipped for $key: no context');
      await _markGenerated(period, anchor);
      return false;
    }

    final resources = await _loadResources();
    final decision = await _callModel(resources, period, anchor, collected.context);
    if (decision == null) {
      throw Exception('Rollup model returned unparseable output for $key');
    }

    final markdown = period.compose(decision, collected.scores);
    if (markdown == null) {
      throw Exception('Rollup output missing narrative for $key');
    }

    final prefs = await SharedPreferences.getInstance();
    final factIdPrefKey = period.prefFactIdKey(key);
    final existingFactId = prefs.getString(factIdPrefKey);
    final factId = existingFactId ?? await _fs.allocateCardFactId(userId);
    final isNewCard = existingFactId == null;

    final title = (decision['title'] as String?)?.trim();
    final mood = (decision['mood'] as String?)?.trim();
    final avgScore = RollupService.averageScore(collected.scores);

    final cardData = await _fs.updateCardFile(
      userId,
      factId,
      createIfNotExists: true,
      (card) => card.copyWith(
        status: 'completed',
        title: (title == null || title.isEmpty)
            ? period.defaultTitle(anchor)
            : title,
        fact: period.factText(anchor),
        tags: [period.tag, if (mood != null && mood.isNotEmpty) mood],
        // Always pass a map (never null) so copyWith REPLACES metadata and
        // stale AI mood is cleared on regeneration (copyWith treats null as
        // "keep existing"). Preserve the user's manual rating across regen.
        metadata: {
          if (card.metadata?[CardMetadataKeys.userMoodScore] != null)
            CardMetadataKeys.userMoodScore:
                card.metadata![CardMetadataKeys.userMoodScore],
          if (avgScore != null) CardMetadataKeys.moodScore: avgScore,
          if (mood != null && mood.isNotEmpty)
            CardMetadataKeys.moodLabel: mood,
        },
        timestamp:
            period.cardTimestamp(anchor).millisecondsSinceEpoch ~/ 1000,
        uiConfigs: [
          UiConfig(templateId: 'snippet', data: {'text': markdown}),
          if (avgScore != null)
            UiConfig(templateId: 'mood_curve', data: {
              'scores': collected.scores,
              'labels':
                  period.chartLabels(anchor, collected.scores.length),
              'average': avgScore,
            }),
        ],
      ),
    );
    if (cardData == null) {
      throw Exception('Rollup card write failed for $factId');
    }
    if (isNewCard) {
      await emitTimelineCardAdded(
          userId: userId, cardId: factId, cardData: cardData);
    } else {
      await emitTimelineCardUpdated(
          userId: userId, cardId: factId, cardData: cardData);
    }

    await prefs.setString(factIdPrefKey, factId);
    await _markGenerated(period, anchor);
    _logger.info('Rollup written for $key → $factId');
    return true;
  }

  Future<void> _markGenerated(RollupPeriod period, DateTime anchor) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(period.prefLastKey);
    final key = period.keyFor(anchor);
    // ISO-style keys sort lexicographically; never move the marker
    // backwards.
    if (existing == null || existing.compareTo(key) < 0) {
      await prefs.setString(period.prefLastKey, key);
    }
  }

  // ─── Mood aggregation (period-agnostic) ─────────────────────────────

  /// Rounded average of the non-null scores, or null when none exist.
  static int? averageScore(List<int?> scores) {
    final present = scores.whereType<int>().toList();
    if (present.isEmpty) return null;
    return (present.reduce((a, b) => a + b) / present.length).round();
  }

  static const String _sparkBars = '▁▂▃▄▅▆▇█';

  /// Maps a 1-10 score to a single bar character; `·` for null.
  static String barFor(int? score) => score == null
      ? '·'
      : _sparkBars[((score - 1) * (_sparkBars.length - 1) / 9).round()];

  /// One line of bar characters (no labels), one per entry in [scores].
  /// Callers that need labels (e.g. weekday names) should combine
  /// [barFor] with their own labels instead.
  static String sparkline(List<int?> scores) =>
      scores.map(barFor).join(' ');

  // ─── LLM ───────────────────────────────────────────────────────────

  Future<({LLMClient client, ModelConfig modelConfig})> _loadResources() {
    final provider = _resourcesProvider;
    if (provider != null) return provider();
    return UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
  }

  Future<Map<String, dynamic>?> _callModel(
    ({LLMClient client, ModelConfig modelConfig}) resources,
    RollupPeriod period,
    DateTime anchor,
    String context,
  ) async {
    final systemPrompt = period.systemPrompt();

    Future<Map<String, dynamic>?> attempt({required bool strict}) async {
      final response = await resources.client.generate(
        [
          SystemMessage(strict
              ? '$systemPrompt\n\nYour previous output was not valid JSON. '
                  'Output exactly one JSON object and nothing else.'
              : systemPrompt),
          UserMessage([TextPart(context)]),
        ],
        modelConfig: resources.modelConfig,
        jsonOutput: true,
      );
      return _parseJson(response.textOutput);
    }

    return await attempt(strict: false) ?? await attempt(strict: true);
  }

  static Map<String, dynamic>? _parseJson(String? raw) {
    if (raw == null) return null;
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
