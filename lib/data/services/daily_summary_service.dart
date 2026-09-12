import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/timeline_card_event_publisher.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/system_card_constants.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _logger = getLogger('DailySummaryService');

const String dailySummaryTaskType = 'daily_summary_task';

/// Generates one end-of-day summary card: a first-person narrative diary
/// plus structured highlights, produced by a single LLM call over the day's
/// timeline cards and chat activity. Idempotent per date — regeneration
/// updates the same card.
class DailySummaryService {
  DailySummaryService._();

  static final DailySummaryService instance = DailySummaryService._();

  @visibleForTesting
  DailySummaryService.forTesting({
    Future<({LLMClient client, ModelConfig modelConfig})> Function()?
        resourcesProvider,
  }) : _resourcesProvider = resourcesProvider;

  Future<({LLMClient client, ModelConfig modelConfig})> Function()?
      _resourcesProvider;

  /// Local hour after which the day's summary may be generated.
  static const int summaryHour = 21;

  static const String _prefEnabled = 'daily_summary_enabled';
  static const String _prefLastDate = 'daily_summary_last_date';
  static String _prefFactIdForDate(String dateKey) =>
      'daily_summary_fact_$dateKey';

  FileSystemService get _fs => FileSystemService.instance;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // ─── Scheduling ────────────────────────────────────────────────────

  /// Decides which date (if any) needs a summary right now.
  ///
  /// - After [summaryHour] with no summary for today → today.
  /// - Before that (or today already done), if yesterday was never
  ///   summarized → yesterday (catch-up for a night the app wasn't opened).
  /// - Otherwise null.
  @visibleForTesting
  static DateTime? dueDateFor({
    required DateTime now,
    required String? lastGeneratedDate,
    required bool enabled,
  }) {
    if (!enabled) return null;
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final todayKey = dateKey(today);
    final yesterdayKey = dateKey(yesterday);

    if (now.hour >= summaryHour && lastGeneratedDate != todayKey) {
      return today;
    }
    if (lastGeneratedDate != todayKey && lastGeneratedDate != yesterdayKey) {
      return yesterday;
    }
    return null;
  }

  bool _scheduleInFlight = false;

  /// Checks whether a summary is due and enqueues the generation task.
  /// Called on app launch and on foreground resume; cheap when idle.
  /// Retries a few times because the first call can race DB initialization.
  Future<void> maybeSchedule({DateTime? now}) async {
    if (_scheduleInFlight) return;
    _scheduleInFlight = true;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final userId = await UserStorage.getUserId();
          if (userId == null) {
            // User session not loaded yet (early app startup) — retry.
            throw StateError('no user session yet');
          }
          final prefs = await SharedPreferences.getInstance();
          final due = dueDateFor(
            now: now ?? DateTime.now(),
            lastGeneratedDate: prefs.getString(_prefLastDate),
            enabled: prefs.getBool(_prefEnabled) ?? true,
          );
          if (due == null) return;

          final key = dateKey(due);
          await LocalTaskExecutor.instance.enqueueTask(
            userId: userId,
            taskType: dailySummaryTaskType,
            payload: {'date': key},
            priority: 5,
            bizId: 'daily_summary:$key',
          );
          _logger.info('Daily summary enqueued for $key');
          return;
        } catch (e, stack) {
          _logger.warning(
            'Failed to schedule daily summary (attempt ${attempt + 1})',
            e,
            stack,
          );
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    } finally {
      _scheduleInFlight = false;
    }
  }

  // ─── Generation ────────────────────────────────────────────────────

  /// Generates (or regenerates) the summary card for [date].
  /// Returns true when a card was written; false when skipped (no data).
  Future<bool> generate(String userId, DateTime date) async {
    final context = await collectDayContext(userId, date);
    if (context == null) {
      _logger.info('Daily summary skipped for ${dateKey(date)}: no activity');
      await _markGenerated(date);
      return false;
    }

    final resources = await _loadResources();
    final decision = await _callModel(resources, date, context);
    if (decision == null) {
      throw Exception('Daily summary model returned unparseable output');
    }

    final markdown = _composeMarkdown(decision);
    if (markdown == null) {
      throw Exception('Daily summary output missing narrative');
    }

    final prefs = await SharedPreferences.getInstance();
    final existingFactId = prefs.getString(_prefFactIdForDate(dateKey(date)));
    final factId = existingFactId ?? await _fs.allocateCardFactId(userId);
    final isNewCard = existingFactId == null;

    // Card sits at the end of the summarized day on the timeline.
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59);
    final title = (decision['title'] as String?)?.trim();
    final mood = (decision['mood'] as String?)?.trim();
    final moodScore = sanitizeMoodScore(decision['mood_score']);

    final cardData = await _fs.updateCardFile(
      userId,
      factId,
      createIfNotExists: true,
      (card) => card.copyWith(
        status: 'completed',
        title: (title == null || title.isEmpty)
            ? '${date.month}月${date.day}日 · 每日总结'
            : title,
        fact: '每日总结 ${dateKey(date)}',
        tags: [dailySummaryTag, if (mood != null && mood.isNotEmpty) mood],
        // Always pass a map (never null) so copyWith REPLACES metadata and
        // stale AI mood is cleared on regeneration (copyWith treats null as
        // "keep existing"). Preserve the user's manual rating across regen.
        metadata: {
          if (card.metadata?[CardMetadataKeys.userMoodScore] != null)
            CardMetadataKeys.userMoodScore:
                card.metadata![CardMetadataKeys.userMoodScore],
          if (moodScore != null) CardMetadataKeys.moodScore: moodScore,
          if (mood != null && mood.isNotEmpty)
            CardMetadataKeys.moodLabel: mood,
        },
        timestamp: endOfDay.millisecondsSinceEpoch ~/ 1000,
        uiConfigs: [
          UiConfig(templateId: 'snippet', data: {'text': markdown}),
        ],
      ),
    );
    if (cardData == null) {
      throw Exception('Daily summary card write failed for $factId');
    }
    if (isNewCard) {
      await emitTimelineCardAdded(
          userId: userId, cardId: factId, cardData: cardData);
    } else {
      await emitTimelineCardUpdated(
          userId: userId, cardId: factId, cardData: cardData);
    }

    await prefs.setString(_prefFactIdForDate(dateKey(date)), factId);
    await _markGenerated(date);
    _logger.info('Daily summary written for ${dateKey(date)} → $factId');
    return true;
  }

  Future<void> _markGenerated(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefLastDate);
    final key = dateKey(date);
    // Never move the marker backwards (yesterday catch-up after today ran).
    if (existing == null || existing.compareTo(key) < 0) {
      await prefs.setString(_prefLastDate, key);
    }
  }

  // ─── Data collection ───────────────────────────────────────────────

  /// Gathers the day's timeline cards and chat activity as plain text.
  /// Returns null when the day has no user activity at all.
  Future<String?> collectDayContext(String userId, DateTime date) async {
    final sections = <String>[];

    final cards = await _collectCards(userId, date);
    if (cards.isNotEmpty) {
      sections.add('## 今天的记录卡片\n${cards.join('\n')}');
    }

    final chats = await _collectChatEvents(userId, date);
    if (chats.isNotEmpty) {
      sections.add('## 今天和助手的对话\n${chats.join('\n')}');
    }

    if (sections.isEmpty) return null;
    return sections.join('\n\n');
  }

  Future<List<String>> _collectCards(String userId, DateTime date) async {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final dir = Directory(p.join(_fs.getCardsPath(userId), year, month));
    if (!await dir.exists()) return const [];

    final entries = <String>[];
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('${day}_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final factId = _fs.factIdFromCardPath(file.path);
      if (factId == null) continue;
      final card = await _fs.readCardFile(userId, factId);
      if (card == null || card.status != 'completed') continue;
      // Never feed on generated summaries (own or weekly rollups).
      if (card.tags.any(summaryTags.contains)) continue;

      final time = DateTime.fromMillisecondsSinceEpoch(card.timestamp * 1000);
      final hhmm = '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
      final buffer = StringBuffer('- [$hhmm]');
      if (card.title != null && card.title!.isNotEmpty) {
        buffer.write(' ${card.title}');
      }
      final text = _cardBodyText(card);
      if (text.isNotEmpty) {
        buffer.write(': ${_truncate(text, 400)}');
      }
      if (card.tags.isNotEmpty) {
        buffer.write(' (标签: ${card.tags.join(', ')})');
      }
      entries.add(buffer.toString());
    }
    return entries;
  }

  static String _cardBodyText(CardData card) {
    final parts = <String>[];
    for (final config in card.uiConfigs) {
      final data = config.data;
      for (final key in ['text', 'content', 'caption']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          parts.add(value.trim());
        }
      }
    }
    if (parts.isEmpty && card.fact != null && card.fact!.trim().isNotEmpty) {
      parts.add(card.fact!.trim());
    }
    return parts.join(' / ');
  }

  Future<List<String>> _collectChatEvents(String userId, DateTime date) async {
    final logPath = _fs.eventLogService.getEventLogPath(userId, date);
    final file = File(logPath);
    if (!await file.exists()) return const [];

    final entries = <String>[];
    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Map<String, dynamic> event;
        try {
          event = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (event['event_type'] != 'user_chat') continue;
        final metadata = event['metadata'];
        final message =
            metadata is Map ? metadata['message']?.toString() : null;
        if (message == null || message.trim().isEmpty) continue;
        final localTime = event['event_time_local']?.toString() ?? '';
        final hhmm = localTime.length >= 16 ? localTime.substring(11, 16) : '';
        entries.add('- [$hhmm] ${_truncate(message.trim(), 200)}');
      }
    } catch (e) {
      _logger.warning('Failed to read event log for daily summary: $e');
    }
    return entries;
  }

  static String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  // ─── LLM ───────────────────────────────────────────────────────────

  Future<({LLMClient client, ModelConfig modelConfig})> _loadResources() {
    final provider = _resourcesProvider;
    if (provider != null) return provider();
    return UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
  }

  static const String _systemPrompt = '''
You are the user's private diary assistant. Given everything they captured
today (timeline cards and assistant chats), write their end-of-day summary
in the SAME LANGUAGE as their captured content (default to Simplified
Chinese when mixed).

Ground every statement in the provided material — never invent events.

Respond with STRICT JSON only, no markdown fences:
{"title":"<short date-flavored title>",
 "narrative":"<first-person diary paragraph, 120-300 characters, warm and
natural, weaving the day's events / sights / thoughts together>",
 "highlights":["<2-5 bullet-worthy moments or accomplishments>"],
 "mood":"<one word + emoji>",
 "mood_score":<integer 1-10, 1 = very negative day, 5-6 = neutral, 10 = very
positive day, judged only from the provided material>,
 "tomorrow":["<0-3 follow-ups implied by today's content>"]}''';

  Future<Map<String, dynamic>?> _callModel(
    ({LLMClient client, ModelConfig modelConfig}) resources,
    DateTime date,
    String context,
  ) async {
    Future<Map<String, dynamic>?> attempt({required bool strict}) async {
      final response = await resources.client.generate(
        [
          SystemMessage(strict
              ? '$_systemPrompt\n\nYour previous output was not valid JSON. '
                  'Output exactly one JSON object and nothing else.'
              : _systemPrompt),
          UserMessage([
            TextPart('日期: ${dateKey(date)}\n\n$context'),
          ]),
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

  @visibleForTesting
  static Map<String, dynamic>? parseJsonForTesting(String? raw) =>
      _parseJson(raw);

  static String? _composeMarkdown(Map<String, dynamic> decision) {
    final narrative = (decision['narrative'] as String?)?.trim();
    if (narrative == null || narrative.isEmpty) return null;

    final buffer = StringBuffer(narrative);

    final highlights = (decision['highlights'] is List)
        ? (decision['highlights'] as List)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList()
        : const <String>[];
    if (highlights.isNotEmpty) {
      buffer.write('\n\n**今日亮点**\n');
      buffer.writeAll(highlights.map((h) => '- ${h.trim()}'), '\n');
    }

    final tomorrow = (decision['tomorrow'] is List)
        ? (decision['tomorrow'] as List)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList()
        : const <String>[];
    if (tomorrow.isNotEmpty) {
      buffer.write('\n\n**明日待办**\n');
      buffer.writeAll(tomorrow.map((t) => '- ${t.trim()}'), '\n');
    }

    final mood = (decision['mood'] as String?)?.trim();
    if (mood != null && mood.isNotEmpty) {
      buffer.write('\n\n今日心情:$mood');
    }
    return buffer.toString();
  }

  @visibleForTesting
  static String? composeMarkdownForTesting(Map<String, dynamic> decision) =>
      _composeMarkdown(decision);
}
