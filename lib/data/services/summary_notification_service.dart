import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Cadence used to pick the reminder copy for a given day.
enum SummaryCadence { daily, weekly, monthly, yearly }

/// Returns the cadence + Chinese title/body for the reminder scheduled on
/// [day]. Priority: year-end (Dec 31) > month-end > Sunday (weekly) > daily.
({SummaryCadence cadence, String title, String body}) copyForDate(
    DateTime day) {
  // Year-end wins over month-end (Dec 31 is inherently month-end).
  if (day.month == 12 && day.day == 31) {
    return (
      cadence: SummaryCadence.yearly,
      title: '年度总结时间',
      body: '这一年过得怎么样?花点时间回顾这一年的记录吧。',
    );
  }
  final lastDayOfMonth = DateTime(day.year, day.month + 1, 0).day;
  if (day.day == lastDayOfMonth) {
    return (
      cadence: SummaryCadence.monthly,
      title: '月度总结时间',
      body: '这个月过得怎么样?花几分钟回顾一下这个月的记录吧。',
    );
  }
  if (day.weekday == DateTime.sunday) {
    return (
      cadence: SummaryCadence.weekly,
      title: '周总结时间',
      body: '这一周过得怎么样?花几分钟回顾一下本周的记录吧。',
    );
  }
  return (
    cadence: SummaryCadence.daily,
    title: '每日记录提醒',
    body: '今天发生了什么?花几分钟记录下来吧。',
  );
}

/// Abstraction over the underlying local-notifications plugin so tests can
/// inject a fake instead of touching the real plugin/platform channels.
abstract class NotificationScheduler {
  Future<void> cancel(int id);
  Future<void> schedule({
    required int id,
    required DateTime whenLocal,
    required String title,
    required String body,
  });

  /// IDs currently pending in this service's id segment (or all pending
  /// ids — the service is responsible for filtering to its own segment).
  Future<List<int>> pendingIds();
}

class _RealNotificationScheduler implements NotificationScheduler {
  _RealNotificationScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> schedule({
    required int id,
    required DateTime whenLocal,
    required String title,
    required String body,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(whenLocal, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<List<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending
        .where((r) =>
            r.id >= SummaryNotificationService.idBase &&
            r.id <=
                SummaryNotificationService.idBase +
                    SummaryNotificationService.horizonDays)
        .map((r) => r.id)
        .toList();
  }
}

/// Schedules the rolling 21:00 local "write a summary" reminder notification,
/// deduped so only one cadence (month > week > day) fires per day.
class SummaryNotificationService {
  SummaryNotificationService._()
      : _scheduler = _RealNotificationScheduler(
          FlutterLocalNotificationsPlugin(),
        ),
        _requestPermission = null;

  static final SummaryNotificationService instance =
      SummaryNotificationService._();

  @visibleForTesting
  SummaryNotificationService.forTesting({
    required NotificationScheduler scheduler,
    Future<bool> Function()? requestPermission,
  })  : _scheduler = scheduler,
        _requestPermission = requestPermission;

  static const int idBase = 9000;
  static const int horizonDays = 30;
  static const int reminderHour = 21;
  static const String prefEnabled = 'summary_reminders_enabled';

  final NotificationScheduler _scheduler;
  final Future<bool> Function()? _requestPermission;

  bool _granted = false;
  bool _initialized = false;

  /// Set by the app shell to navigate to the home/timeline screen when a
  /// reminder notification is tapped. Left unset in tests / before the app
  /// wires it up, in which case the tap is a safe no-op.
  void Function()? onReminderTapped;

  /// Initializes timezone data and the real plugin. No-op-safe to call
  /// multiple times. Only meaningful for the real (singleton) instance;
  /// the fake-backed `forTesting` instances don't need it.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      // Fall back to UTC if the local timezone name can't be resolved;
      // scheduling still works, just anchored to UTC.
    }

    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Tap handler hook — invokes [onReminderTapped] (set by the app shell)
  /// so tapping a reminder notification brings the app to the home/timeline
  /// screen. Safe no-op if the callback hasn't been set.
  void _onNotificationTapped(NotificationResponse response) {
    onReminderTapped?.call();
  }

  Future<bool> requestPermission() async {
    if (_requestPermission != null) {
      _granted = await _requestPermission();
      return _granted;
    }
    final ios = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    final result = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    _granted = result ?? false;
    return _granted;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefEnabled) ?? true;
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefEnabled, v);
    if (v) {
      await requestPermission();
      await reschedule();
    } else {
      await _cancelOwn();
    }
  }

  /// Cancels this service's entire id segment (idBase..idBase+horizonDays).
  Future<void> _cancelOwn() async {
    for (var offset = 0; offset <= horizonDays; offset++) {
      await _scheduler.cancel(idBase + offset);
    }
  }

  Future<void> reschedule({DateTime? now}) async {
    now ??= DateTime.now();

    // If the user has turned reminders off, clear any existing schedule
    // and stop — nothing left to do.
    if (!await isEnabled()) {
      await _cancelOwn();
      return;
    }

    // `_granted` is an in-memory cache that resets to false every process
    // start. Re-establish it here rather than trusting a stale false: on
    // iOS, requestPermissions() is idempotent and returns the current
    // authorization status without re-prompting once the user has already
    // decided, so this is safe to call on every reschedule.
    if (!_granted) {
      _granted = await requestPermission();
    }

    // Still not granted (either truly denied, or not yet asked and the
    // fake/real check returned false) — do NOT touch the existing
    // schedule. A transient lack of a cached grant must never wipe out a
    // possibly-valid, already-scheduled set of reminders.
    if (!_granted) return;

    // Only cancel once we know we're about to reschedule the full horizon.
    await _cancelOwn();

    var startDay = DateTime(now.year, now.month, now.day);
    final todayAt21 =
        DateTime(now.year, now.month, now.day, reminderHour);
    if (!now.isBefore(todayAt21)) {
      startDay = startDay.add(const Duration(days: 1));
    }

    for (var offset = 0; offset < horizonDays; offset++) {
      final day = startDay.add(Duration(days: offset));
      final whenLocal =
          DateTime(day.year, day.month, day.day, reminderHour);
      final copy = copyForDate(day);
      await _scheduler.schedule(
        id: idBase + offset,
        whenLocal: whenLocal,
        title: copy.title,
        body: copy.body,
      );
    }
  }

  Future<void> maybeFirstLaunchEnable() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(prefEnabled)) return;
    await prefs.setBool(prefEnabled, true);
    await requestPermission();
    await reschedule();
  }
}
