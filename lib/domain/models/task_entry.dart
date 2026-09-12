import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/date_util.dart';

/// A to-do surfaced from a card's `task` ui_config, for the manual "待办"
/// aggregation page. [configIndex] is the position of the `task` ui_config
/// within the card's ui_configs list, needed to target updates back at it
/// via `MemexRouter.updateCardUiConfig`.
class TaskEntry {
  const TaskEntry({
    required this.cardId,
    required this.configIndex,
    required this.title,
    required this.isCompleted,
    required this.dueDate,
    required this.priority,
    required this.timestamp,
  });

  final String cardId;
  final int configIndex;
  final String title;
  final bool isCompleted;
  final DateTime? dueDate;

  /// e.g. "high", or null when unset.
  final String? priority;
  final DateTime timestamp;

  /// Extracts a [TaskEntry] from [card]'s `task` ui_config, or null when the
  /// card carries no `task` ui_config.
  static TaskEntry? fromCard(TimelineCardModel card) {
    for (var i = 0; i < card.uiConfigs.length; i++) {
      final config = card.uiConfigs[i];
      if (config.templateId != 'task') continue;
      final data = config.data;
      final title = data['title'] as String?;
      return TaskEntry(
        cardId: card.id,
        configIndex: i,
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : (card.title ?? ''),
        isCompleted: data['is_completed'] == true,
        dueDate: parseLocalDateTime(data['due_date']),
        priority: data['priority'] as String?,
        timestamp: card.timestamp,
      );
    }
    return null;
  }
}
