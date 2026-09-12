import 'package:test/test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/data/services/summary_notification_service.dart';

class _FakeScheduler implements NotificationScheduler {
  final Map<int, ({DateTime when, String title, String body})> scheduled = {};
  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime whenLocal,
    required String title,
    required String body,
  }) async {
    scheduled[id] = (when: whenLocal, title: title, body: body);
  }

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('copyForDate', () {
    test('weekday -> daily', () {
      expect(copyForDate(DateTime(2026, 9, 2)).cadence, SummaryCadence.daily);
    }); // Wed
    test('sunday -> weekly', () {
      expect(copyForDate(DateTime(2026, 9, 6)).cadence, SummaryCadence.weekly);
    }); // Sun
    test('month-end -> monthly (Aug 31)', () {
      expect(
          copyForDate(DateTime(2026, 8, 31)).cadence, SummaryCadence.monthly);
    });
    test('feb 28 non-leap -> monthly', () {
      expect(
          copyForDate(DateTime(2027, 2, 28)).cadence, SummaryCadence.monthly);
    });
    test('feb 29 leap -> monthly', () {
      expect(
          copyForDate(DateTime(2028, 2, 29)).cadence, SummaryCadence.monthly);
    });
    test('month-end AND sunday -> monthly (priority)', () {
      // 2026-11-30 is a Monday; find a month-end Sunday: 2026-05-31 is Sunday
      expect(
          copyForDate(DateTime(2026, 5, 31)).cadence, SummaryCadence.monthly);
    });
    test('year-end (Dec 31) -> yearly, beats month-end', () {
      // Dec 31 is inherently month-end; year-end must win.
      expect(
          copyForDate(DateTime(2026, 12, 31)).cadence, SummaryCadence.yearly);
      expect(
          copyForDate(DateTime(2027, 12, 31)).cadence, SummaryCadence.yearly);
    });
    test('year-end body is yearly-flavored', () {
      final c = copyForDate(DateTime(2026, 12, 31));
      expect(c.title.contains('年'), isTrue);
    });
  });

  group('reschedule', () {
    test('enabled+granted schedules 30 days at 21:00 with unique ids in segment',
        () async {
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => true);
      await svc.setEnabled(true);
      await svc.reschedule(
          now: DateTime(2026, 9, 2, 8, 0)); // 8am, today 21:00 still future
      expect(fake.scheduled.length, SummaryNotificationService.horizonDays);
      for (final e in fake.scheduled.entries) {
        expect(
            e.key,
            inInclusiveRange(SummaryNotificationService.idBase,
                SummaryNotificationService.idBase +
                    SummaryNotificationService.horizonDays));
        expect(e.value.when.hour, 21);
        expect(e.value.when.minute, 0);
      }
    });
    test('past-today-21:00 is skipped (starts tomorrow)', () async {
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => true);
      await svc.setEnabled(true);
      await svc.reschedule(now: DateTime(2026, 9, 2, 22, 0)); // after 21:00
      // first scheduled day is 2026-09-03
      final firstWhen = (fake.scheduled.values.toList()
            ..sort((a, b) => a.when.compareTo(b.when)))
          .first
          .when;
      expect(firstWhen.day, 3);
    });
    test('disabled -> cancels, schedules nothing', () async {
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => true);
      await svc.setEnabled(false);
      await svc.reschedule(now: DateTime(2026, 9, 2, 8, 0));
      expect(fake.scheduled, isEmpty);
    });
    test('permission denied -> schedules nothing even if enabled', () async {
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => false);
      await svc.setEnabled(true);
      await svc.reschedule(now: DateTime(2026, 9, 2, 8, 0));
      expect(fake.scheduled, isEmpty);
    });

    test(
        'launch #2+: pref already enabled, fresh instance with _granted=false '
        're-establishes grant via reschedule() and schedules 30 (no wipe-and-bail)',
        () async {
      // Simulate a second app launch: the pref was already set to true by
      // a previous launch (so maybeFirstLaunchEnable() would early-return
      // and never call requestPermission()), and this is a brand new
      // service instance whose in-memory `_granted` cache starts false —
      // even though the OS permission is actually still granted.
      SharedPreferences.setMockInitialValues({'summary_reminders_enabled': true});
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => true);

      // No setEnabled()/maybeFirstLaunchEnable() call here on purpose —
      // this mirrors main.dart's lifecycle sites that just call
      // reschedule() directly on a freshly constructed service.
      await svc.reschedule(now: DateTime(2026, 9, 2, 8, 0));

      expect(fake.scheduled.length, SummaryNotificationService.horizonDays);
    });

    test(
        'launch #2+: pref already enabled, fresh instance, OS permission now '
        'denied -> schedules nothing', () async {
      SharedPreferences.setMockInitialValues({'summary_reminders_enabled': true});
      final fake = _FakeScheduler();
      final svc = SummaryNotificationService.forTesting(
          scheduler: fake, requestPermission: () async => false);

      await svc.reschedule(now: DateTime(2026, 9, 2, 8, 0));

      expect(fake.scheduled, isEmpty);
    });
  });

  test('isEnabled default true when unset', () async {
    final svc = SummaryNotificationService.forTesting(
        scheduler: _FakeScheduler(), requestPermission: () async => true);
    expect(await svc.isEnabled(), isTrue);
  });
}
