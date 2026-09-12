import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/task_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';

TimelineCardModel _card({
  List<UiConfig> uiConfigs = const [],
  String? title,
}) {
  return TimelineCardModel(
    id: 'c1',
    timestamp: DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    title: title,
    uiConfigs: uiConfigs,
  );
}

void main() {
  group('TaskEntry.fromCard', () {
    test('extracts fields from a task ui_config', () {
      final card = _card(uiConfigs: [
        const UiConfig(templateId: 'task', data: {
          'title': '交房租',
          'is_completed': false,
          'due_date': '2026-09-15T00:00:00.000',
          'priority': 'high',
        }),
      ]);

      final entry = TaskEntry.fromCard(card);

      expect(entry, isNotNull);
      expect(entry!.title, '交房租');
      expect(entry.isCompleted, isFalse);
      expect(entry.dueDate, DateTime(2026, 9, 15));
      expect(entry.priority, 'high');
      expect(entry.configIndex, 0);
    });

    test('falls back to card title when ui_config title is empty', () {
      final card = _card(
        title: '卡片标题',
        uiConfigs: [
          const UiConfig(templateId: 'task', data: {'is_completed': false}),
        ],
      );

      final entry = TaskEntry.fromCard(card);

      expect(entry!.title, '卡片标题');
    });

    test('returns null when the card has no task ui_config', () {
      final card = _card(uiConfigs: [
        const UiConfig(templateId: 'snapshot', data: {}),
      ]);

      expect(TaskEntry.fromCard(card), isNull);
    });

    test('finds the task ui_config at a non-zero index', () {
      final card = _card(uiConfigs: [
        const UiConfig(templateId: 'snapshot', data: {}),
        const UiConfig(templateId: 'task', data: {'title': '任务'}),
      ]);

      final entry = TaskEntry.fromCard(card);

      expect(entry!.configIndex, 1);
    });
  });
}
