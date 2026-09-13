import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/result.dart';

void main() {
  test(
      'a cardUpdated event for a task card refreshes the in-memory copy '
      '(reproduces "待办完成后时间线仍显示未完成")', () async {
    final taskCard = TimelineCardModel(
      id: '2026/09/13.md#ts_1',
      timestamp: DateTime(2026, 9, 13),
      tags: const [],
      status: 'completed',
      uiConfigs: [
        const UiConfig(templateId: 'task', data: {
          'title': '买香蕉',
          'is_completed': false,
        }),
      ],
    );

    final vm = TimelineViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20, tags, dateFrom, dateTo}) async =>
          Ok([taskCard]),
    );
    await vm.load.execute();
    vm.init();

    expect(vm.cards.single.uiConfigs.single.data['is_completed'], isFalse);

    EventBusService.instance.emitEvent(CardUpdatedMessage(
      id: taskCard.id,
      html: '',
      timestamp: taskCard.timestamp.millisecondsSinceEpoch ~/ 1000,
      tags: const [],
      status: 'completed',
      uiConfigs: [
        const UiConfig(templateId: 'task', data: {
          'title': '买香蕉',
          'is_completed': true,
        }),
      ],
    ));
    // EventBusService dispatches on a microtask/stream; let it flush.
    await Future<void>.delayed(Duration.zero);

    expect(vm.cards.single.id, taskCard.id);
    expect(vm.cards.single.uiConfigs.single.data['is_completed'], isTrue);
  });
}
