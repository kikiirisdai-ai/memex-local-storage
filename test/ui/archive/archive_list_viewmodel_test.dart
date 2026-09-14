import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/archive/view_models/archive_list_viewmodel.dart';
import 'package:memex/utils/result.dart';

TimelineCardModel _card({required String id, int? archivedAt}) {
  return TimelineCardModel(
    id: id,
    timestamp: DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    title: 'Card $id',
    uiConfigs: const [],
    archivedAt: archivedAt,
  );
}

void main() {
  group('load', () {
    test('populates entries from the fetcher', () async {
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async =>
            Ok([_card(id: 'a', archivedAt: 100)]),
      );

      await vm.load();

      expect(vm.entries.map((e) => e.id), ['a']);
      expect(vm.errorMessage, isNull);
    });

    test('surfaces the fetch error', () async {
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async =>
            const Error<List<TimelineCardModel>>('boom'),
      );

      await vm.load();

      expect(vm.errorMessage, contains('boom'));
      expect(vm.entries, isEmpty);
    });

    test('drops selections for cards no longer in the archive', () async {
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async => Ok([_card(id: 'a')]),
      );
      await vm.load();
      vm.toggleSelection('a');
      vm.toggleSelection('gone');
      expect(vm.selectedIds, {'a', 'gone'});

      await vm.load();

      expect(vm.selectedIds, {'a'});
    });
  });

  group('selection', () {
    test('toggleSelectAll selects then deselects everything', () async {
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async =>
            Ok([_card(id: 'a'), _card(id: 'b')]),
      );
      await vm.load();

      vm.toggleSelectAll();
      expect(vm.selectedIds, {'a', 'b'});
      expect(vm.isAllSelected, isTrue);

      vm.toggleSelectAll();
      expect(vm.selectedIds, isEmpty);
    });
  });

  group('restoreSelected', () {
    test('calls unarchiveCard for each selected id, then reloads', () async {
      final unarchived = <String>[];
      var reloadCount = 0;
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async {
          reloadCount++;
          return Ok([_card(id: 'a'), _card(id: 'b')]);
        },
        unarchiveCard: (id) async {
          unarchived.add(id);
          return true;
        },
      );
      await vm.load();
      vm.toggleSelection('a');

      await vm.restoreSelected();

      expect(unarchived, ['a']);
      expect(vm.selectedIds, isEmpty);
      expect(reloadCount, 2);
    });
  });

  group('deleteSelected', () {
    test('calls deleteCard for each selected id, then reloads', () async {
      final deleted = <String>[];
      var reloadCount = 0;
      final vm = ArchiveListViewModel.forTest(
        fetchArchivedCards: () async {
          reloadCount++;
          return Ok([_card(id: 'a'), _card(id: 'b')]);
        },
        deleteCard: (id) async {
          deleted.add(id);
          return true;
        },
      );
      await vm.load();
      vm.toggleSelectAll();

      await vm.deleteSelected();

      expect(deleted, ['a', 'b']);
      expect(vm.selectedIds, isEmpty);
      expect(reloadCount, 2);
    });
  });
}
