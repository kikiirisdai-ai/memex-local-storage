import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/tasks/view_models/task_list_viewmodel.dart';
import 'package:memex/utils/result.dart';

TimelineCardModel _taskCard({
  required String id,
  required String title,
  bool isCompleted = false,
  DateTime? dueDate,
  DateTime? timestamp,
}) {
  return TimelineCardModel(
    id: id,
    timestamp: timestamp ?? DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    uiConfigs: [
      UiConfig(templateId: 'task', data: {
        'title': title,
        'is_completed': isCompleted,
        if (dueDate != null) 'due_date': dueDate.toIso8601String(),
      }),
    ],
  );
}

void main() {
  group('load', () {
    test('splits into active/completed groups', () async {
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async => Ok([
          _taskCard(id: 'a', title: 'Active'),
          _taskCard(id: 'b', title: 'Done', isCompleted: true),
        ]),
      );

      await vm.load();

      expect(vm.activeEntries.map((e) => e.title), ['Active']);
      expect(vm.completedEntries.map((e) => e.title), ['Done']);
    });

    test('sorts active entries by due date, undated first go last',
        () async {
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async => Ok([
          _taskCard(id: 'a', title: 'No date'),
          _taskCard(id: 'b', title: 'Later', dueDate: DateTime(2026, 9, 20)),
          _taskCard(id: 'c', title: 'Sooner', dueDate: DateTime(2026, 9, 10)),
        ]),
      );

      await vm.load();

      expect(vm.activeEntries.map((e) => e.title),
          ['Sooner', 'Later', 'No date']);
    });

    test('surfaces the fetch error', () async {
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async =>
            const Error<List<TimelineCardModel>>('boom'),
      );

      await vm.load();

      expect(vm.errorMessage, contains('boom'));
      expect(vm.activeEntries, isEmpty);
    });
  });

  group('addManualEntry', () {
    test('rejects a blank title without calling createEntry', () async {
      var called = false;
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async => const Ok([]),
        createEntry: ({required title, dueDate, priority}) async {
          called = true;
          return const Ok('id');
        },
      );

      final ok = await vm.addManualEntry(title: '   ');

      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('creates the entry and reloads the list on success', () async {
      var reloadCount = 0;
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async {
          reloadCount++;
          return const Ok([]);
        },
        createEntry: ({required title, dueDate, priority}) async =>
            const Ok('id'),
      );

      final ok = await vm.addManualEntry(title: '交房租');

      expect(ok, isTrue);
      expect(vm.isSaving, isFalse);
      expect(reloadCount, 1);
    });

    test('surfaces the error and does not reload on failure', () async {
      var reloadCount = 0;
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async {
          reloadCount++;
          return const Ok([]);
        },
        createEntry: ({required title, dueDate, priority}) async =>
            const Error('boom'),
      );

      final ok = await vm.addManualEntry(title: '交房租');

      expect(ok, isFalse);
      expect(vm.saveError, contains('boom'));
      expect(reloadCount, 0);
    });
  });

  group('toggleCompleted', () {
    test('calls updateUiConfig with the flipped completion and reloads',
        () async {
      Map<String, dynamic>? capturedData;
      String? capturedCardId;
      var reloadCount = 0;
      final vm = TaskListViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async {
          reloadCount++;
          return Ok([_taskCard(id: 'a', title: 'Active')]);
        },
        updateUiConfig: (cardId, configIndex, data) async {
          capturedCardId = cardId;
          capturedData = data;
          return true;
        },
      );

      await vm.load();
      final entry = vm.activeEntries.single;
      await vm.toggleCompleted(entry);

      expect(capturedCardId, 'a');
      expect(capturedData, {'is_completed': true});
      expect(reloadCount, 2);
    });
  });
}
