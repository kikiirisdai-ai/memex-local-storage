import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/media_library_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/utils/result.dart';

MediaLibraryEntry _entry({
  required String cardId,
  required String mediaType,
  String? mediaStatus,
}) {
  return MediaLibraryEntry(
    cardId: cardId,
    mediaType: mediaType,
    mediaStatus: mediaStatus,
    title: cardId,
    comment: null,
    rating: null,
    timestamp: DateTime(2026, 1, 1),
  );
}

void main() {
  late MediaLibraryViewModel vm;

  setUp(() {
    vm = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Ok(<TimelineCardModel>[]),
    );
    vm.setEntriesForTesting([
      _entry(cardId: 'book_want', mediaType: 'book', mediaStatus: 'want'),
      _entry(cardId: 'book_done', mediaType: 'book', mediaStatus: 'done'),
      _entry(cardId: 'movie_doing', mediaType: 'movie', mediaStatus: 'doing'),
      _entry(cardId: 'tv_unset', mediaType: 'tv', mediaStatus: null),
    ]);
  });

  test('defaults to showing every entry', () {
    expect(vm.filteredEntries, hasLength(4));
  });

  test('setTypeFilter narrows to matching media type', () {
    vm.setTypeFilter('book');

    expect(
      vm.filteredEntries.map((e) => e.cardId),
      unorderedEquals(['book_want', 'book_done']),
    );
  });

  test('setStatusFilter narrows to matching status', () {
    vm.setStatusFilter('done');

    expect(vm.filteredEntries.map((e) => e.cardId), ['book_done']);
  });

  test('type and status filters combine', () {
    vm.setTypeFilter('book');
    vm.setStatusFilter('want');

    expect(vm.filteredEntries.map((e) => e.cardId), ['book_want']);
  });

  test('an entry with no status is excluded by any specific status filter',
      () {
    vm.setStatusFilter('want');

    expect(
      vm.filteredEntries.any((e) => e.cardId == 'tv_unset'),
      isFalse,
    );
  });

  test('"all" filters restore the full list', () {
    vm.setTypeFilter('book');
    vm.setTypeFilter('all');

    expect(vm.filteredEntries, hasLength(4));
  });

  test('load() extracts media_card entries and sorts newest-first', () async {
    final loaded = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async => Ok([
        TimelineCardModel(
          id: 'older',
          timestamp: DateTime(2026, 1, 1),
          tags: const [],
          status: 'completed',
          uiConfigs: const [
            UiConfig(templateId: 'media_card', data: {'media_type': 'book'}),
          ],
        ),
        TimelineCardModel(
          id: 'not_media',
          timestamp: DateTime(2026, 1, 3),
          tags: const [],
          status: 'completed',
          uiConfigs: const [
            UiConfig(templateId: 'snippet', data: {'text': 'hi'}),
          ],
        ),
        TimelineCardModel(
          id: 'newer',
          timestamp: DateTime(2026, 1, 2),
          tags: const [],
          status: 'completed',
          uiConfigs: const [
            UiConfig(templateId: 'media_card', data: {'media_type': 'movie'}),
          ],
        ),
      ]),
    );

    await loaded.load();

    expect(loaded.isLoading, isFalse);
    expect(loaded.errorMessage, isNull);
    expect(loaded.entries.map((e) => e.cardId), ['newer', 'older']);
  });

  test('load() surfaces the fetch error', () async {
    final failed = MediaLibraryViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Error<List<TimelineCardModel>>('boom'),
    );

    await failed.load();

    expect(failed.errorMessage, contains('boom'));
    expect(failed.entries, isEmpty);
  });

  group('addManualEntry', () {
    test('rejects a blank title without calling createEntry', () async {
      var called = false;
      final vm = MediaLibraryViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async =>
            const Ok(<TimelineCardModel>[]),
        createEntry: ({
          required title,
          required mediaType,
          mediaStatus,
          rating,
          comment,
        }) async {
          called = true;
          return const Ok('id');
        },
      );

      final ok = await vm.addManualEntry(title: '   ', mediaType: 'book');

      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('creates the entry and reloads the list on success', () async {
      var reloadCount = 0;
      final vm = MediaLibraryViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async {
          reloadCount++;
          return const Ok(<TimelineCardModel>[]);
        },
        createEntry: ({
          required title,
          required mediaType,
          mediaStatus,
          rating,
          comment,
        }) async =>
            const Ok('id'),
      );

      final ok = await vm.addManualEntry(title: 'Dune', mediaType: 'book');

      expect(ok, isTrue);
      expect(vm.isSaving, isFalse);
      expect(vm.saveError, isNull);
      expect(reloadCount, 1);
    });

    test('surfaces the error and does not reload on failure', () async {
      var reloadCount = 0;
      final vm = MediaLibraryViewModel.forTest(
        fetchTimelineCards: ({page = 1, limit = 20}) async {
          reloadCount++;
          return const Ok(<TimelineCardModel>[]);
        },
        createEntry: ({
          required title,
          required mediaType,
          mediaStatus,
          rating,
          comment,
        }) async =>
            const Error('boom'),
      );

      final ok = await vm.addManualEntry(title: 'Dune', mediaType: 'book');

      expect(ok, isFalse);
      expect(vm.saveError, contains('boom'));
      expect(reloadCount, 0);
    });
  });
}
