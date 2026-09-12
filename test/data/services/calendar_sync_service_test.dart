import 'dart:collection';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/calendar_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

class _FakeCalendarPlugin implements CalendarPluginAdapter {
  final List<Calendar> calendars;
  bool retrieveCalendarsFails;
  final Map<String, Event> events = {};
  int nextEventId = 1;
  final List<String> deletedEventIds = [];

  _FakeCalendarPlugin({
    this.calendars = const [],
    this.retrieveCalendarsFails = false,
  });

  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() async {
    final result = Result<UnmodifiableListView<Calendar>>();
    if (retrieveCalendarsFails) {
      result.errors.add(const ResultError(1, 'boom'));
    } else {
      result.data = UnmodifiableListView(calendars);
    }
    return result;
  }

  @override
  Future<Result<String>?> createOrUpdateEvent(Event event) async {
    final id = event.eventId ?? 'evt_${nextEventId++}';
    events[id] = event;
    final result = Result<String>();
    result.data = id;
    return result;
  }

  @override
  Future<Result<bool>> deleteEvent(String calendarId, String eventId) async {
    events.remove(eventId);
    deletedEventIds.add(eventId);
    final result = Result<bool>();
    result.data = true;
    return result;
  }
}

CalendarSyncService _buildService({
  required _FakeCalendarPlugin plugin,
  bool permissionGranted = true,
}) {
  return CalendarSyncService(
    plugin: plugin,
    isPermissionGranted: () async => permissionGranted,
    prefsProvider: SharedPreferences.getInstance,
  );
}

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('creates a calendar event for a task with a due date', () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_1'
        ..isDefault = true
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, hasLength(1));
    final event = plugin.events.values.single;
    expect(event.title, 'Buy milk');
    expect(event.calendarId, 'cal_1');
  });

  test('updates the existing event on a second sync instead of duplicating',
      () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_1'
        ..isDefault = true
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );
    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk and eggs',
      dueDate: DateTime(2026, 1, 2, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, hasLength(1));
    expect(plugin.events.values.single.title, 'Buy milk and eggs');
  });

  test('removes the mapped event once the task is completed', () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_1'
        ..isDefault = true
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );
    expect(plugin.events, hasLength(1));

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: true,
    );

    expect(plugin.events, isEmpty);
    expect(plugin.deletedEventIds, hasLength(1));
  });

  test('removes the mapped event once the due date is cleared', () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_1'
        ..isDefault = true
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );
    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: null,
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, isEmpty);
  });

  test('does nothing when calendar permission is not granted', () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_1'
        ..isDefault = true
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin, permissionGranted: false);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, isEmpty);
  });

  test('skips a read-only calendar and falls back to a writable one',
      () async {
    final plugin = _FakeCalendarPlugin(calendars: [
      Calendar()
        ..id = 'cal_readonly'
        ..isDefault = true
        ..isReadOnly = true,
      Calendar()
        ..id = 'cal_writable'
        ..isDefault = false
        ..isReadOnly = false,
    ]);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events.values.single.calendarId, 'cal_writable');
  });

  test('no-ops without crashing when no writable calendar exists', () async {
    final plugin = _FakeCalendarPlugin(calendars: const []);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, isEmpty);
  });

  test('no-ops without crashing when retrieveCalendars fails', () async {
    final plugin = _FakeCalendarPlugin(retrieveCalendarsFails: true);
    final service = _buildService(plugin: plugin);

    await service.syncTaskCard(
      factId: 'fact_1',
      title: 'Buy milk',
      dueDate: DateTime(2026, 1, 1, 9),
      isCompletedOrDeleted: false,
    );

    expect(plugin.events, isEmpty);
  });
}
