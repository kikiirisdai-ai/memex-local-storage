import 'dart:io';

import 'package:memex/data/services/daily_summary_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_card_constants.dart';
import 'package:path/path.dart' as p;

/// [RollupPeriod] implementations. Kept separate from [RollupService] so the
/// engine stays period-agnostic; this file has the period-specific porting
/// of what used to be hard-coded in the concrete `*SummaryService` classes.
///
/// This file intentionally does NOT import `weekly_summary_service.dart` —
/// that facade imports this file (for `weeklyRollup`), so the reverse import
/// would create a cycle. Any pure date-arithmetic the facade's static
/// members need lives here instead and is exposed as top-level functions.

/// Local hour on Sunday after which the week's summary may be generated.
const int weeklySummaryHour = 21;

/// Monday 00:00 of the week containing [date]. Calendar arithmetic (not
/// Duration) so DST-transition weeks cannot shift the date.
DateTime weeklyMondayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));

/// ISO-8601 week key, e.g. "2026-W29". The ISO year can differ from the
/// calendar year around New Year (a week belongs to the year holding its
/// Thursday). Computed in UTC so local DST gaps cannot skew day counts.
String weeklyKeyFor(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  final week = thursday.difference(firstDay).inDays ~/ 7 + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// One line like "一▃ 二▅ 三· 四▇ …" — a bar per day, "·" for days
/// without a mood. The engine's own `RollupService.sparkline` is label-free;
/// the weekly UI/tests expect the weekday-labeled form, so it's rebuilt here
/// from `RollupService.barFor` + the weekday labels.
String weeklySparkline(List<int?> scores) {
  final parts = <String>[];
  for (var i = 0; i < 7; i++) {
    parts.add('${_weekdayNames[i]}${RollupService.barFor(scores[i])}');
  }
  return parts.join(' ');
}

const String _weeklySystemPrompt = '''
You are the user's private diary assistant. Given their seven end-of-day
summaries for one week, write the weekly review in the SAME LANGUAGE as the
summaries (default to Simplified Chinese when mixed).

Ground every statement in the provided material — never invent events.
Look for the arc of the week: recurring themes, how the mood moved, what
actually got done versus what kept slipping.

Respond with STRICT JSON only, no markdown fences:
{"title":"<short week-flavored title>",
 "narrative":"<first-person weekly review, 200-400 characters, warm and
honest, connecting the week's threads rather than listing days>",
 "highlights":["<3-6 bullet-worthy wins or moments of the week>"],
 "mood":"<one word + emoji for the week overall>",
 "next_week":["<0-3 intentions that follow from this week>"]}''';

/// Ports the weekly-rollup behavior that previously lived hard-coded in
/// `WeeklySummaryService` into a [RollupPeriod] the generic [RollupService]
/// can drive. `WeeklySummaryService` is now a thin facade delegating here.
class _WeeklyRollupPeriod implements RollupPeriod {
  const _WeeklyRollupPeriod();

  @override
  String get taskType => 'weekly_summary_task';

  @override
  String get tag => weeklySummaryTag;

  @override
  String get prefEnabledKey => 'weekly_summary_enabled';

  @override
  String get prefLastKey => 'weekly_summary_last_week';

  @override
  String prefFactIdKey(String periodKey) => 'weekly_summary_fact_$periodKey';

  @override
  String get bizIdPrefix => 'weekly_summary';

  @override
  String keyFor(DateTime anchor) => weeklyKeyFor(anchor);

  @override
  String factText(DateTime anchor) => '每周总结 ${keyFor(anchor)}';

  @override
  DateTime? dueFor({
    required DateTime now,
    required String? lastGeneratedKey,
    required bool enabled,
  }) {
    if (!enabled) return null;
    final monday = weeklyMondayOf(now);
    final thisKey = keyFor(monday);
    final sundayDue =
        DateTime(monday.year, monday.month, monday.day + 6, weeklySummaryHour);

    if (!now.isBefore(sundayDue) && lastGeneratedKey != thisKey) {
      return monday;
    }
    final prevMonday = DateTime(monday.year, monday.month, monday.day - 7);
    final prevKey = keyFor(prevMonday);
    if (lastGeneratedKey != thisKey && lastGeneratedKey != prevKey) {
      return prevMonday;
    }
    return null;
  }

  @override
  Map<String, dynamic> payloadFor(DateTime anchor) =>
      {'week_monday': DailySummaryService.dateKey(anchor)};

  @override
  DateTime? anchorFromPayload(Map<String, dynamic> payload) {
    final raw = payload['week_monday'] as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  @override
  Future<({String context, List<int?> scores})?> collectContext(
    String userId,
    DateTime anchor,
  ) async {
    final monday = weeklyMondayOf(anchor);
    final fs = FileSystemService.instance;
    final sections = <String>[];
    final dayScores = List<int?>.filled(7, null);

    for (var i = 0; i < 7; i++) {
      final date = DateTime(monday.year, monday.month, monday.day + i);
      final card = await _dailySummaryCardFor(fs, userId, date);
      if (card == null) continue;

      dayScores[i] = _cardScore(card);

      final buffer = StringBuffer(
          '## 周${_weekdayNames[i]} ${DailySummaryService.dateKey(date)}');
      if (dayScores[i] != null) buffer.write('（心情 ${dayScores[i]}/10）');
      buffer.writeln();
      if (card.title != null && card.title!.isNotEmpty) {
        buffer.writeln('**${card.title}**');
      }
      final text = _summaryBodyText(card);
      if (text.isNotEmpty) buffer.writeln(_truncate(text, 600));
      sections.add(buffer.toString().trimRight());
    }

    if (sections.isEmpty) return null;

    // The engine's model-calling step no longer adds any period framing —
    // it just sends whatever `collectContext` returns as the user message.
    // Re-embed the same "周: <weekKey> (<date> 起)" header here so the LLM
    // input is byte-for-byte identical to before the migration.
    final context =
        '周: ${keyFor(monday)}（${DailySummaryService.dateKey(monday)} 起）'
        '\n\n${sections.join('\n\n')}';
    return (context: context, scores: dayScores);
  }

  @override
  String systemPrompt() => _weeklySystemPrompt;

  @override
  String defaultTitle(DateTime anchor) =>
      '${anchor.month}月${anchor.day}日那一周 · 每周总结';

  @override
  DateTime cardTimestamp(DateTime anchor) =>
      DateTime(anchor.year, anchor.month, anchor.day + 6, 23, 59);

  @override
  String? compose(Map<String, dynamic> decision, List<int?> scores) {
    final narrative = (decision['narrative'] as String?)?.trim();
    if (narrative == null || narrative.isEmpty) return null;

    final buffer = StringBuffer(narrative);

    final highlights = _stringList(decision['highlights']);
    if (highlights.isNotEmpty) {
      buffer.write('\n\n**本周亮点**\n');
      buffer.writeAll(highlights.map((h) => '- ${h.trim()}'), '\n');
    }

    final avg = RollupService.averageScore(scores);
    if (avg != null) {
      buffer.write('\n\n**情绪曲线** ${weeklySparkline(scores)}（均值 $avg/10）');
    }

    final nextWeek = _stringList(decision['next_week']);
    if (nextWeek.isNotEmpty) {
      buffer.write('\n\n**下周展望**\n');
      buffer.writeAll(nextWeek.map((t) => '- ${t.trim()}'), '\n');
    }

    final mood = (decision['mood'] as String?)?.trim();
    if (mood != null && mood.isNotEmpty) {
      buffer.write('\n\n本周心情:$mood');
    }
    return buffer.toString();
  }

  static List<String> _stringList(Object? raw) => raw is List
      ? raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
      : const <String>[];
}

/// The weekly rollup strategy, ported behavior-for-behavior from the former
/// `WeeklySummaryService` hard-coded logic.
const RollupPeriod weeklyRollup = _WeeklyRollupPeriod();

// ─── Shared card-scanning helpers (weekly + monthly) ────────────────────
//
// Both periods scan `Cards/YYYY/MM/DD_*.yaml` for a completed card carrying
// a specific tag. These live at file scope so `monthlyRollup`'s hybrid
// collect can reuse the exact same day-lookup weekly relies on, plus an
// analogous week-lookup for full-in-month weeks.

Future<CardData?> _dailySummaryCardFor(
  FileSystemService fs,
  String userId,
  DateTime date,
) async {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final dir = Directory(p.join(fs.getCardsPath(userId), year, month));
  if (!await dir.exists()) return null;

  final files = (await dir.list().toList())
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('${day}_'));
  for (final file in files) {
    final factId = fs.factIdFromCardPath(file.path);
    if (factId == null) continue;
    final card = await fs.readCardFile(userId, factId);
    if (card == null || card.status != 'completed') continue;
    if (card.tags.contains(dailySummaryTag)) return card;
  }
  return null;
}

/// Finds the weekly-summary card (tag [weeklySummaryTag]) for the ISO week
/// starting at [monday]. Only meaningful for weeks fully contained in one
/// calendar month — the day range therefore never crosses a month/year
/// boundary, so a single `Cards/YYYY/MM/` directory covers it.
Future<CardData?> _weeklySummaryCardFor(
  FileSystemService fs,
  String userId,
  DateTime monday,
) async {
  final year = monday.year.toString().padLeft(4, '0');
  final month = monday.month.toString().padLeft(2, '0');
  final dir = Directory(p.join(fs.getCardsPath(userId), year, month));
  if (!await dir.exists()) return null;

  final weekDays = List.generate(7, (i) => monday.day + i);
  final files = (await dir.list().toList()).whereType<File>().where((f) {
    final day = int.tryParse(p.basename(f.path).split('_').first);
    return day != null && weekDays.contains(day);
  });
  for (final file in files) {
    final factId = fs.factIdFromCardPath(file.path);
    if (factId == null) continue;
    final card = await fs.readCardFile(userId, factId);
    if (card == null || card.status != 'completed') continue;
    if (card.tags.contains(weeklySummaryTag)) return card;
  }
  return null;
}

String _summaryBodyText(CardData card) {
  for (final config in card.uiConfigs) {
    final value = config.data['text'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return card.fact?.trim() ?? '';
}

String _truncate(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// `userMoodScore` always wins over the model-inferred `moodScore`.
int? _cardScore(CardData card) =>
    sanitizeMoodScore(card.metadata?[CardMetadataKeys.userMoodScore]) ??
    sanitizeMoodScore(card.metadata?[CardMetadataKeys.moodScore]);

List<String> _stringList(Object? raw) => raw is List
    ? raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
    : const <String>[];

// ─── Monthly rollup ──────────────────────────────────────────────────────

/// Local hour on the last day of the month after which the month's summary
/// may be generated.
const int monthlySummaryHour = 21;

const String _monthlySystemPrompt = '''
You are the user's private diary assistant. Given a hybrid digest of one
month — full in-month weeks summarized as weekly reviews, plus the loose
days at the start/end of the month that didn't form a complete week — write
the monthly review in the SAME LANGUAGE as the material (default to
Simplified Chinese when mixed).

Ground every statement in the provided material — never invent events.
Look for the arc of the month: recurring themes across weeks, how the mood
moved, what actually got done versus what kept slipping.

Respond with STRICT JSON only, no markdown fences:
{"title":"<short month-flavored title>",
 "narrative":"<first-person monthly review, 250-500 characters, warm and
honest, connecting the month's threads rather than listing weeks>",
 "highlights":["<3-6 bullet-worthy wins or moments of the month>"],
 "mood":"<one word + emoji for the month overall>",
 "next_month":["<0-3 intentions that follow from this month>"]}''';

/// Ports the monthly-rollup behavior described in the SDD brief into a
/// [RollupPeriod]. Uses a hybrid collect: full in-month ISO weeks reuse
/// their already-generated weekly-summary cards (via [weeklyRollup]'s tag),
/// while boundary weeks that straddle a month edge fall back to reading
/// just the in-month daily-summary cards directly.
class _MonthlyRollupPeriod implements RollupPeriod {
  const _MonthlyRollupPeriod();

  @override
  String get taskType => 'monthly_summary_task';

  @override
  String get tag => monthlySummaryTag;

  @override
  String get prefEnabledKey => 'monthly_summary_enabled';

  @override
  String get prefLastKey => 'monthly_summary_last_month';

  @override
  String prefFactIdKey(String periodKey) => 'monthly_summary_fact_$periodKey';

  @override
  String get bizIdPrefix => 'monthly_summary';

  @override
  String keyFor(DateTime anchor) => '${anchor.year.toString().padLeft(4, '0')}-'
      '${anchor.month.toString().padLeft(2, '0')}';

  @override
  String factText(DateTime anchor) => '每月总结 ${keyFor(anchor)}';

  @override
  DateTime? dueFor({
    required DateTime now,
    required String? lastGeneratedKey,
    required bool enabled,
  }) {
    if (!enabled) return null;
    final thisMonth = DateTime(now.year, now.month, 1);
    final thisKey = keyFor(thisMonth);
    // DateTime(y, m+1, 0) is the last day of month m — Dart normalizes the
    // 0-day into the previous month, so this naturally yields 28/29/30/31.
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;

    final alreadyDoneThisMonth =
        lastGeneratedKey != null && lastGeneratedKey.compareTo(thisKey) >= 0;

    if (now.day == lastDayOfMonth &&
        now.hour >= monthlySummaryHour &&
        !alreadyDoneThisMonth) {
      return thisMonth;
    }

    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final prevKey = keyFor(prevMonth);
    final alreadyDonePrevMonth =
        lastGeneratedKey != null && lastGeneratedKey.compareTo(prevKey) >= 0;
    if (!alreadyDoneThisMonth && !alreadyDonePrevMonth) {
      return prevMonth;
    }
    return null;
  }

  @override
  Map<String, dynamic> payloadFor(DateTime anchor) => {'month': keyFor(anchor)};

  @override
  DateTime? anchorFromPayload(Map<String, dynamic> payload) {
    final raw = payload['month'] as String?;
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    return DateTime(year, month, 1);
  }

  @override
  Future<({String context, List<int?> scores})?> collectContext(
    String userId,
    DateTime anchor,
  ) async {
    final fs = FileSystemService.instance;
    final monthStart = DateTime(anchor.year, anchor.month, 1);
    final monthEnd = DateTime(anchor.year, anchor.month + 1, 0);

    // Group every in-month day by the Monday of its ISO week, preserving
    // first-seen (i.e. chronological) week order.
    final weekOrder = <DateTime>[];
    final daysByWeek = <DateTime, List<DateTime>>{};
    for (var day = monthStart;
        !day.isAfter(monthEnd);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final monday = weeklyMondayOf(day);
      final days = daysByWeek.putIfAbsent(monday, () {
        weekOrder.add(monday);
        return <DateTime>[];
      });
      days.add(day);
    }

    final sections = <String>[];
    final scores = <int?>[];

    for (final monday in weekOrder) {
      final weekEnd = DateTime(monday.year, monday.month, monday.day + 6);
      final fullyInMonth =
          !monday.isBefore(monthStart) && !weekEnd.isAfter(monthEnd);

      if (fullyInMonth) {
        final card = await _weeklySummaryCardFor(fs, userId, monday);
        if (card == null) {
          scores.add(null);
          continue;
        }
        final score = _cardScore(card);
        scores.add(score);

        final buffer = StringBuffer('## 周 ${weeklyKeyFor(monday)}'
            '（${DailySummaryService.dateKey(monday)} ~ '
            '${DailySummaryService.dateKey(weekEnd)}）');
        if (score != null) buffer.write('（心情 $score/10）');
        buffer.writeln();
        if (card.title != null && card.title!.isNotEmpty) {
          buffer.writeln('**${card.title}**');
        }
        final text = _summaryBodyText(card);
        if (text.isNotEmpty) buffer.writeln(_truncate(text, 600));
        sections.add(buffer.toString().trimRight());
      } else {
        final days = daysByWeek[monday]!;
        final daySections = <String>[];
        final dayScoresForWeek = <int?>[];
        for (final date in days) {
          final card = await _dailySummaryCardFor(fs, userId, date);
          if (card == null) continue;
          final score = _cardScore(card);
          dayScoresForWeek.add(score);

          final buffer =
              StringBuffer('## ${DailySummaryService.dateKey(date)}');
          if (score != null) buffer.write('（心情 $score/10）');
          buffer.writeln();
          if (card.title != null && card.title!.isNotEmpty) {
            buffer.writeln('**${card.title}**');
          }
          final text = _summaryBodyText(card);
          if (text.isNotEmpty) buffer.writeln(_truncate(text, 600));
          daySections.add(buffer.toString().trimRight());
        }
        if (daySections.isEmpty) {
          scores.add(null);
          continue;
        }
        scores.add(RollupService.averageScore(dayScoresForWeek));
        sections.add('## 跨月周 ${weeklyKeyFor(monday)}（月内 ${days.length} 天）\n\n'
            '${daySections.join('\n\n')}');
      }
    }

    if (sections.isEmpty) return null;

    final context = '月: ${keyFor(monthStart)}\n\n${sections.join('\n\n')}';
    return (context: context, scores: scores);
  }

  @override
  String systemPrompt() => _monthlySystemPrompt;

  @override
  String defaultTitle(DateTime anchor) =>
      '${anchor.year}年${anchor.month}月 · 每月总结';

  @override
  DateTime cardTimestamp(DateTime anchor) =>
      DateTime(anchor.year, anchor.month + 1, 0, 23, 59);

  @override
  String? compose(Map<String, dynamic> decision, List<int?> scores) {
    final narrative = (decision['narrative'] as String?)?.trim();
    if (narrative == null || narrative.isEmpty) return null;

    final buffer = StringBuffer(narrative);

    final highlights = _stringList(decision['highlights']);
    if (highlights.isNotEmpty) {
      buffer.write('\n\n**本月亮点**\n');
      buffer.writeAll(highlights.map((h) => '- ${h.trim()}'), '\n');
    }

    final avg = RollupService.averageScore(scores);
    if (avg != null) {
      buffer
          .write('\n\n**情绪走势** ${RollupService.sparkline(scores)}（均值 $avg/10）');
    }

    final nextMonth = _stringList(decision['next_month']);
    if (nextMonth.isNotEmpty) {
      buffer.write('\n\n**下月展望**\n');
      buffer.writeAll(nextMonth.map((t) => '- ${t.trim()}'), '\n');
    }

    final mood = (decision['mood'] as String?)?.trim();
    if (mood != null && mood.isNotEmpty) {
      buffer.write('\n\n本月心情:$mood');
    }
    return buffer.toString();
  }
}

/// The monthly rollup strategy: hybrid collect over full in-month weekly
/// cards plus boundary-week daily cards, per the SDD brief.
const RollupPeriod monthlyRollup = _MonthlyRollupPeriod();

// ─── Yearly rollup ───────────────────────────────────────────────────────

/// Local hour on Dec 31 after which the year's summary may be generated.
const int yearlySummaryHour = 21;

const String _yearlySystemPrompt = '''
You are the user's private diary assistant. Given the twelve monthly
reviews for one year (some months may be missing), write the yearly review
in the SAME LANGUAGE as the material (default to Simplified Chinese when
mixed).

Ground every statement in the provided material — never invent events.
Look for the arc of the year: recurring themes across months, how the mood
moved, what actually got done versus what kept slipping.

Respond with STRICT JSON only, no markdown fences:
{"title":"<short year-flavored title>",
 "narrative":"<first-person yearly review, 300-600 characters, warm and
honest, connecting the year's threads rather than listing months>",
 "highlights":["<3-6 bullet-worthy wins or moments of the year>"],
 "mood":"<one word + emoji for the year overall>",
 "next_year":["<0-3 intentions that follow from this year>"]}''';

/// Finds the monthly-summary card (tag [monthlySummaryTag]) for calendar
/// month [month] of [year]. The real generation path allocates the card's
/// factId against "now" (month-end, same month as the anchor), so a single
/// `Cards/YYYY/MM/` directory always covers it.
Future<CardData?> _monthlySummaryCardFor(
  FileSystemService fs,
  String userId,
  int year,
  int month,
) async {
  final yearStr = year.toString().padLeft(4, '0');
  final monthStr = month.toString().padLeft(2, '0');
  final dir = Directory(p.join(fs.getCardsPath(userId), yearStr, monthStr));
  if (!await dir.exists()) return null;

  final files = (await dir.list().toList()).whereType<File>();
  for (final file in files) {
    final factId = fs.factIdFromCardPath(file.path);
    if (factId == null) continue;
    final card = await fs.readCardFile(userId, factId);
    if (card == null || card.status != 'completed') continue;
    if (card.tags.contains(monthlySummaryTag)) return card;
  }
  return null;
}

/// Ports the yearly-rollup behavior described in the SDD brief into a
/// [RollupPeriod]. A mechanical mirror of [_MonthlyRollupPeriod]: rolls up
/// the 12 monthly-summary cards (no hybrid, no daily/weekly reads) into one
/// yearly card.
class _YearlyRollupPeriod implements RollupPeriod {
  const _YearlyRollupPeriod();

  @override
  String get taskType => 'yearly_summary_task';

  @override
  String get tag => yearlySummaryTag;

  @override
  String get prefEnabledKey => 'yearly_summary_enabled';

  @override
  String get prefLastKey => 'yearly_summary_last_year';

  @override
  String prefFactIdKey(String periodKey) => 'yearly_summary_fact_$periodKey';

  @override
  String get bizIdPrefix => 'yearly_summary';

  @override
  String keyFor(DateTime anchor) => '${anchor.year}';

  @override
  String factText(DateTime anchor) => '每年总结 ${keyFor(anchor)}';

  @override
  DateTime? dueFor({
    required DateTime now,
    required String? lastGeneratedKey,
    required bool enabled,
  }) {
    if (!enabled) return null;
    final thisYear = DateTime(now.year, 1, 1);
    final thisKey = keyFor(thisYear);
    final alreadyDoneThisYear =
        lastGeneratedKey != null && lastGeneratedKey.compareTo(thisKey) >= 0;

    if (now.month == 12 &&
        now.day == 31 &&
        now.hour >= yearlySummaryHour &&
        !alreadyDoneThisYear) {
      return thisYear;
    }

    final prevYear = DateTime(now.year - 1, 1, 1);
    final prevKey = keyFor(prevYear);
    final alreadyDonePrevYear =
        lastGeneratedKey != null && lastGeneratedKey.compareTo(prevKey) >= 0;
    if (!alreadyDoneThisYear && !alreadyDonePrevYear) {
      return prevYear;
    }
    return null;
  }

  @override
  Map<String, dynamic> payloadFor(DateTime anchor) => {'year': keyFor(anchor)};

  @override
  DateTime? anchorFromPayload(Map<String, dynamic> payload) {
    final raw = payload['year'] as String?;
    if (raw == null) return null;
    final year = int.tryParse(raw);
    if (year == null) return null;
    return DateTime(year, 1, 1);
  }

  @override
  Future<({String context, List<int?> scores})?> collectContext(
    String userId,
    DateTime anchor,
  ) async {
    final fs = FileSystemService.instance;
    final sections = <String>[];
    final scores = <int?>[];

    for (var month = 1; month <= 12; month++) {
      final card = await _monthlySummaryCardFor(fs, userId, anchor.year, month);
      if (card == null) {
        scores.add(null);
        continue;
      }
      final score = _cardScore(card);
      scores.add(score);

      final buffer = StringBuffer('## $month月');
      if (score != null) buffer.write('（心情 $score/10）');
      buffer.writeln();
      if (card.title != null && card.title!.isNotEmpty) {
        buffer.writeln('**${card.title}**');
      }
      final text = _summaryBodyText(card);
      if (text.isNotEmpty) buffer.writeln(_truncate(text, 600));
      sections.add(buffer.toString().trimRight());
    }

    if (sections.isEmpty) return null;

    final context = '年: ${keyFor(anchor)}\n\n${sections.join('\n\n')}';
    return (context: context, scores: scores);
  }

  @override
  String systemPrompt() => _yearlySystemPrompt;

  @override
  String defaultTitle(DateTime anchor) => '${anchor.year}年 · 年度总结';

  @override
  DateTime cardTimestamp(DateTime anchor) =>
      DateTime(anchor.year, 12, 31, 23, 59);

  @override
  String? compose(Map<String, dynamic> decision, List<int?> scores) {
    final narrative = (decision['narrative'] as String?)?.trim();
    if (narrative == null || narrative.isEmpty) return null;

    final buffer = StringBuffer(narrative);

    final highlights = _stringList(decision['highlights']);
    if (highlights.isNotEmpty) {
      buffer.write('\n\n**年度亮点**\n');
      buffer.writeAll(highlights.map((h) => '- ${h.trim()}'), '\n');
    }

    final avg = RollupService.averageScore(scores);
    if (avg != null) {
      buffer
          .write('\n\n**情绪走势** ${RollupService.sparkline(scores)}（均值 $avg/10）');
    }

    final nextYear = _stringList(decision['next_year']);
    if (nextYear.isNotEmpty) {
      buffer.write('\n\n**明年展望**\n');
      buffer.writeAll(nextYear.map((t) => '- ${t.trim()}'), '\n');
    }

    final mood = (decision['mood'] as String?)?.trim();
    if (mood != null && mood.isNotEmpty) {
      buffer.write('\n\n年度心情:$mood');
    }
    return buffer.toString();
  }
}

/// The yearly rollup strategy: rolls up the 12 monthly-summary cards for a
/// calendar year, per the SDD brief.
const RollupPeriod yearlyRollup = _YearlyRollupPeriod();
