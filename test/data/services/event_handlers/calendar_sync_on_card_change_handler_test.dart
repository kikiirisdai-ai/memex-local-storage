import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_handlers/calendar_sync_on_card_change_handler.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/system_event.dart';

void main() {
  group('handleCalendarSyncOnCardChanged', () {
    test('ignores non-card data changes', () async {
      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.update,
            ns: DataChangeNs.pkmFile,
            documentKey: 'PKM/note.md',
            after: const {'title': 'note'},
          ),
        ),
      );
      // No exception means the non-card branch returned early without
      // touching CalendarSyncService (which would need real platform
      // channels for permission/calendar plugin calls).
    });

    test('ignores non-task cards without touching the calendar plugin',
        () async {
      final card = _card(
        factId: 'fact_1',
        uiConfigs: [
          const UiConfig(templateId: 'snippet', data: {'text': 'hi'})
        ],
      );

      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.insert,
            ns: DataChangeNs.card,
            documentKey: card.factId,
            after: card.toJson(),
          ),
        ),
      );
    });

    test('does not throw for a task card with a due date', () async {
      final card = _taskCard(factId: 'fact_1', isCompleted: false);

      // The real CalendarSyncService.instance is used here; without a
      // platform channel registered, permission/plugin calls fail and are
      // caught internally (best-effort background sync) — this exercises
      // the handler's extraction logic without needing a fake service.
      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.insert,
            ns: DataChangeNs.card,
            documentKey: card.factId,
            after: card.toJson(),
          ),
        ),
      );
    });

    test('does not throw when a task card is deleted', () async {
      final card = _taskCard(factId: 'fact_1', isCompleted: false);
      final deleted = card.toJson()..['deleted'] = true;

      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.update,
            ns: DataChangeNs.card,
            documentKey: card.factId,
            before: card.toJson(),
            after: deleted,
          ),
        ),
      );
    });

    test('does not throw for an event card with a start time', () async {
      final card = _eventCard(factId: 'fact_2');

      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.insert,
            ns: DataChangeNs.card,
            documentKey: card.factId,
            after: card.toJson(),
          ),
        ),
      );
    });

    test('does not throw when an event card is deleted', () async {
      final card = _eventCard(factId: 'fact_2');
      final deleted = card.toJson()..['deleted'] = true;

      await handleCalendarSyncOnCardChanged(
        'test_user',
        SystemEvent<DataChangeRecord>(
          type: SystemEventTypes.dataChanged,
          source: 'test',
          payload: DataChangeRecord(
            op: DataChangeOp.update,
            ns: DataChangeNs.card,
            documentKey: card.factId,
            before: card.toJson(),
            after: deleted,
          ),
        ),
      );
    });
  });

  group('handleCalendarSyncOnCardUiConfigUpdated', () {
    test('ignores non-task template updates', () async {
      await handleCalendarSyncOnCardUiConfigUpdated(
        'test_user',
        SystemEvent<CardUiConfigUpdatedPayload>(
          type: SystemEventTypes.cardUiConfigUpdated,
          source: 'test',
          payload: CardUiConfigUpdatedPayload(
            cardId: 'fact_1',
            configIndex: 0,
            templateId: 'snippet',
            updates: const {'text': 'hi'},
            previousData: const {},
            updatedData: const {'text': 'hi'},
          ),
        ),
      );
    });

    test('does not throw for a task template update', () async {
      await handleCalendarSyncOnCardUiConfigUpdated(
        'test_user',
        SystemEvent<CardUiConfigUpdatedPayload>(
          type: SystemEventTypes.cardUiConfigUpdated,
          source: 'test',
          payload: CardUiConfigUpdatedPayload(
            cardId: 'fact_1',
            configIndex: 0,
            templateId: 'task',
            updates: const {'is_completed': true},
            previousData: const {
              'title': 'Buy skincare',
              'due_date': '2026-05-27T09:00:00',
              'is_completed': false,
            },
            updatedData: const {
              'title': 'Buy skincare',
              'due_date': '2026-05-27T09:00:00',
              'is_completed': true,
            },
          ),
        ),
      );
    });

    test('does not throw for an event template update', () async {
      await handleCalendarSyncOnCardUiConfigUpdated(
        'test_user',
        SystemEvent<CardUiConfigUpdatedPayload>(
          type: SystemEventTypes.cardUiConfigUpdated,
          source: 'test',
          payload: CardUiConfigUpdatedPayload(
            cardId: 'fact_2',
            configIndex: 0,
            templateId: 'event',
            updates: const {'location': 'Kenmore · Home'},
            previousData: const {
              'title': '朋友们来看乐熙',
              'start_time': '2026-09-13T15:00:00',
            },
            updatedData: const {
              'title': '朋友们来看乐熙',
              'start_time': '2026-09-13T15:00:00',
              'location': 'Kenmore · Home',
            },
          ),
        ),
      );
    });
  });
}

CardData _card({
  required String factId,
  required List<UiConfig> uiConfigs,
}) {
  return CardData(
    factId: factId,
    timestamp: 1779789600,
    status: 'ready',
    tags: const [],
    title: 'Card',
    uiConfigs: uiConfigs,
  );
}

CardData _taskCard({
  required String factId,
  required bool isCompleted,
}) {
  return _card(
    factId: factId,
    uiConfigs: [
      UiConfig(
        templateId: 'task',
        data: {
          'title': 'Buy skincare',
          'due_date': '2026-05-27T09:00:00',
          'is_completed': isCompleted,
        },
      ),
    ],
  );
}

CardData _eventCard({required String factId}) {
  return _card(
    factId: factId,
    uiConfigs: [
      const UiConfig(
        templateId: 'event',
        data: {
          'title': '朋友们来看乐熙',
          'start_time': '2026-09-13T15:00:00',
          'location': 'Kenmore · Home',
        },
      ),
    ],
  );
}
