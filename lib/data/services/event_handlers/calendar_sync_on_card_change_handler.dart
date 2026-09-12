import 'package:memex/data/services/calendar_sync_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/date_util.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('CalendarSyncOnCardChangeHandler');

/// Syncs a task card's due date to a system calendar event whenever the
/// card is created, updated, or deleted.
Future<void> handleCalendarSyncOnCardChanged(
  String userId,
  SystemEvent<DataChangeRecord> event,
) async {
  final record = event.payload;
  if (record.ns != DataChangeNs.card) return;

  final after = _cardFromJson(record.after);
  final deleted = after == null || after.deleted == true;
  final taskData = _taskData(after);
  if (taskData == null && !deleted) {
    // Not a task card — nothing to sync.
    return;
  }

  try {
    await CalendarSyncService.instance.syncTaskCard(
      factId: record.documentKey,
      title: taskData?['title']?.toString() ?? after?.title,
      dueDate: parseLocalDateTime(taskData?['due_date']),
      isCompletedOrDeleted: deleted || _isTaskDataCompleted(taskData),
    );
  } catch (e, st) {
    _logger.warning(
      'Failed to sync calendar event for ${record.documentKey}',
      e,
      st,
    );
  }
}

/// Syncs a task card's due date to a system calendar event when the task's
/// ui_config data (title/due_date/completion) is updated directly.
Future<void> handleCalendarSyncOnCardUiConfigUpdated(
  String userId,
  SystemEvent<CardUiConfigUpdatedPayload> event,
) async {
  final payload = event.payload;
  if (payload.templateId != 'task') return;

  try {
    await CalendarSyncService.instance.syncTaskCard(
      factId: payload.cardId,
      title: payload.updatedData['title']?.toString(),
      dueDate: parseLocalDateTime(payload.updatedData['due_date']),
      isCompletedOrDeleted: _isTaskDataCompleted(payload.updatedData),
    );
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

Map<String, dynamic>? _taskData(CardData? card) {
  if (card == null) return null;
  for (final config in card.uiConfigs) {
    if (config.templateId == 'task') {
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
