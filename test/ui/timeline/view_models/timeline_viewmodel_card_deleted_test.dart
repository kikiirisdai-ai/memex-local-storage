import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/result.dart';

void main() {
  test(
      'a cardDeleted event drops the card from the in-memory timeline '
      '(stale "processing" placeholder cleanup)', () async {
    final stuckCard = TimelineCardModel(
      id: '2026/09/13.md#ts_1',
      timestamp: DateTime(2026, 9, 13),
      tags: const [],
      status: 'processing',
      uiConfigs: const [
        UiConfig(templateId: 'classic_card', data: {'content': ''}),
      ],
    );

    final vm = TimelineViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20, tags, dateFrom, dateTo}) async =>
          Ok([stuckCard]),
    );
    await vm.load.execute();
    vm.init();

    expect(vm.cards, hasLength(1));

    EventBusService.instance.emitEvent(CardDeletedMessage(id: stuckCard.id));
    // EventBusService dispatches on a microtask/stream; let it flush.
    await Future<void>.delayed(Duration.zero);

    expect(vm.cards, isEmpty);
  });
}
