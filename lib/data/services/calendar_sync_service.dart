import 'dart:collection';
import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/utils/logger.dart';
import 'package:memex/utils/permission_utils.dart';

final _logger = getLogger('CalendarSyncService');

/// Thin wrapper around [DeviceCalendarPlugin] so tests can inject a fake
/// without touching the platform channel.
abstract class CalendarPluginAdapter {
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars();
  Future<Result<String>?> createOrUpdateEvent(Event event);
  Future<Result<bool>> deleteEvent(String calendarId, String eventId);
}

class _DeviceCalendarPluginAdapter implements CalendarPluginAdapter {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() =>
      _plugin.retrieveCalendars();

  @override
  Future<Result<String>?> createOrUpdateEvent(Event event) =>
      _plugin.createOrUpdateEvent(event);

  @override
  Future<Result<bool>> deleteEvent(String calendarId, String eventId) =>
      _plugin.deleteEvent(calendarId, eventId);
}

/// One-way sync of task-card due dates and event-card start/end times to a
/// system calendar event.
///
/// Best-effort background sync, not a user-facing action: it silently
/// no-ops when calendar permission hasn't been granted rather than
/// prompting or surfacing errors to the UI.
class CalendarSyncService {
  CalendarSyncService({
    CalendarPluginAdapter? plugin,
    Future<bool> Function()? isPermissionGranted,
    Future<SharedPreferences> Function()? prefsProvider,
  })  : _plugin = plugin ?? _DeviceCalendarPluginAdapter(),
        _isPermissionGranted =
            isPermissionGranted ?? PermissionUtils.isCalendarPermissionGranted,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static final instance = CalendarSyncService();

  static const _prefsKey = 'calendar_sync_event_map';

  final CalendarPluginAdapter _plugin;
  final Future<bool> Function() _isPermissionGranted;
  final Future<SharedPreferences> Function() _prefsProvider;

  String? _calendarId;

  /// Create/update the calendar event for a task card with a due date, or
  /// remove any previously-synced event if the task is completed, has no
  /// due date, or the card was deleted.
  Future<void> syncTaskCard({
    required String factId,
    required String? title,
    required DateTime? dueDate,
    required bool isCompletedOrDeleted,
  }) async {
    if (!await _isPermissionGranted()) return;

    try {
      if (isCompletedOrDeleted || dueDate == null) {
        await _removeMappedEvent(factId);
        return;
      }

      final calendarId = await _resolveCalendarId();
      if (calendarId == null) return;

      final map = await _loadMap();
      final event = Event(
        calendarId,
        eventId: map[factId],
        title: (title?.trim().isNotEmpty ?? false) ? title : 'Memex',
        start: TZDateTime.from(dueDate, local),
        end: TZDateTime.from(dueDate.add(const Duration(hours: 1)), local),
      );

      final result = await _plugin.createOrUpdateEvent(event);
      final newEventId = result?.data;
      if (result?.isSuccess == true && newEventId != null) {
        map[factId] = newEventId;
        await _saveMap(map);
      } else {
        _logger.warning(
          'Failed to sync calendar event for $factId: ${result?.errors}',
        );
      }
    } catch (e, st) {
      _logger.warning('Calendar sync error for $factId', e, st);
    }
  }

  /// Create/update the calendar event for an event-card (title/start_time/
  /// end_time/location), or remove any previously-synced event if the card
  /// has no start time or was deleted. Shares the same factId->eventId map
  /// as [syncTaskCard] — a card is only ever one template, so there's no
  /// collision between the two.
  Future<void> syncEventCard({
    required String factId,
    required String? title,
    required DateTime? startTime,
    required DateTime? endTime,
    required String? location,
    required bool isDeleted,
  }) async {
    if (!await _isPermissionGranted()) return;

    try {
      if (isDeleted || startTime == null) {
        await _removeMappedEvent(factId);
        return;
      }

      final calendarId = await _resolveCalendarId();
      if (calendarId == null) return;

      final map = await _loadMap();
      final event = Event(
        calendarId,
        eventId: map[factId],
        title: (title?.trim().isNotEmpty ?? false) ? title : 'Memex',
        start: TZDateTime.from(startTime, local),
        end: TZDateTime.from(
          endTime ?? startTime.add(const Duration(hours: 1)),
          local,
        ),
        location: (location?.trim().isNotEmpty ?? false) ? location : null,
      );

      final result = await _plugin.createOrUpdateEvent(event);
      final newEventId = result?.data;
      if (result?.isSuccess == true && newEventId != null) {
        map[factId] = newEventId;
        await _saveMap(map);
      } else {
        _logger.warning(
          'Failed to sync calendar event for $factId: ${result?.errors}',
        );
      }
    } catch (e, st) {
      _logger.warning('Calendar sync error for $factId', e, st);
    }
  }

  Future<void> _removeMappedEvent(String factId) async {
    final map = await _loadMap();
    final eventId = map.remove(factId);
    if (eventId == null) return;
    await _saveMap(map);

    final calendarId = await _resolveCalendarId();
    if (calendarId == null) return;
    try {
      await _plugin.deleteEvent(calendarId, eventId);
    } catch (e, st) {
      _logger.warning('Failed to delete calendar event for $factId', e, st);
    }
  }

  Future<String?> _resolveCalendarId() async {
    if (_calendarId != null) return _calendarId;
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess) return null;
    final writable =
        result.data!.where((c) => c.isReadOnly != true).toList();
    if (writable.isEmpty) return null;
    final defaultCalendar = writable.firstWhere(
      (c) => c.isDefault == true,
      orElse: () => writable.first,
    );
    _calendarId = defaultCalendar.id;
    return _calendarId;
  }

  Future<Map<String, String>> _loadMap() async {
    final prefs = await _prefsProvider();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMap(Map<String, String> map) async {
    final prefs = await _prefsProvider();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
