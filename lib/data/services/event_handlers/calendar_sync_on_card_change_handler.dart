import 'package:memex/data/services/calendar_sync_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/date_util.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('CalendarSyncOnCardChangeHandler');

/// Syncs a task card's due date, or an event card's start/end time, to a
/// system calendar event whenever the card is created, updated, or deleted.
Future<void> handleCalendarSyncOnCardChanged(
  String userId,
  SystemEvent<DataChangeRecord> event,
) async {
  final record = event.payload;
  if (record.ns != DataChangeNs.card) return;

  final after = _cardFromJson(record.after);
  final deleted = after == null || after.deleted == true;
  final taskData = _configData(after, 'task');
  final eventData = _configData(after, 'event');
  if (taskData == null && eventData == null && !deleted) {
    // Not a task or event card — nothing to sync.
    return;
  }

  try {
    // On delete, `after` is null so neither taskData nor eventData is
    // resolvable — but syncTaskCard/syncEventCard's removal path is the
    // exact same shared factId->eventId map either way, so it doesn't
    // matter which one we call to trigger it.
    if (taskData != null || deleted) {
      await CalendarSyncService.instance.syncTaskCard(
        factId: record.documentKey,
        title: taskData?['title']?.toString() ?? after?.title,
        dueDate: parseLocalDateTime(taskData?['due_date']),
        isCompletedOrDeleted: deleted || _isTaskDataCompleted(taskData),
      );
    }
    if (eventData != null) {
      await CalendarSyncService.instance.syncEventCard(
        factId: record.documentKey,
        title: eventData['title']?.toString() ?? after?.title,
        startTime: parseLocalDateTime(eventData['start_time']),
        endTime: parseLocalDateTime(eventData['end_time']),
        location: eventData['location']?.toString(),
        isDeleted: deleted,
      );
    }
  } catch (e, st) {
    _logger.warning(
      'Failed to sync calendar event for ${record.documentKey}',
      e,
      st,
    );
  }
}

/// Syncs a task card's due date, or an event card's start/end time, to a
/// system calendar event when the ui_config data is updated directly.
Future<void> handleCalendarSyncOnCardUiConfigUpdated(
  String userId,
  SystemEvent<CardUiConfigUpdatedPayload> event,
) async {
  final payload = event.payload;

  try {
    if (payload.templateId == 'task') {
      await CalendarSyncService.instance.syncTaskCard(
        factId: payload.cardId,
        title: payload.updatedData['title']?.toString(),
        dueDate: parseLocalDateTime(payload.updatedData['due_date']),
        isCompletedOrDeleted: _isTaskDataCompleted(payload.updatedData),
      );
    } else if (payload.templateId == 'event') {
      await CalendarSyncService.instance.syncEventCard(
        factId: payload.cardId,
        title: payload.updatedData['title']?.toString(),
        startTime: parseLocalDateTime(payload.updatedData['start_time']),
        endTime: parseLocalDateTime(payload.updatedData['end_time']),
        location: payload.updatedData['location']?.toString(),
        isDeleted: false,
      );
    }
  } catch (e, st) {
    _logger.warning(
      'Failed to sync calendar event for ui_config update ${payload.cardId}',
      e,
      st,
    );
  }
}

CardData? _cardFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return CardData.fromJson(json);
}

Map<String, dynamic>? _configData(CardData? card, String templateId) {
  if (card == null) return null;
  for (final config in card.uiConfigs) {
    if (config.templateId == templateId) {
      return config.data;
    }
  }
  return null;
}

bool _isTaskDataCompleted(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data['is_completed'] == true) return true;
  final status = data['status']?.toString().toLowerCase();
  if (status == 'completed' || status == 'done') return true;
  final subtasks = data['subtasks'];
  if (subtasks is List && subtasks.isNotEmpty) {
    final normalized = subtasks.whereType<Map>().toList();
    return normalized.isNotEmpty &&
        normalized.every((subtask) => subtask['completed'] == true);
  }
  return false;
}
