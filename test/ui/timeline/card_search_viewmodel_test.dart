import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/ui/timeline/view_models/card_search_viewmodel.dart';

/// Fake retriever that records the args it was called with and returns a
/// canned result (or throws, for error-path tests).
class _FakeCardRetriever implements CardRetriever {
  _FakeCardRetriever({this.hitsToReturn = const [], this.errorToThrow});

  List<CardHit> hitsToReturn;
  Object? errorToThrow;

  int callCount = 0;
  String? lastQuery;
  DateTime? lastFrom;
  DateTime? lastTo;
  List<String>? lastTags;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    callCount++;
    lastQuery = query;
    lastFrom = dateFrom;
    lastTo = dateTo;
    lastTags = tags;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return hitsToReturn;
  }
}

CardHit _hit(String id) => CardHit(
      cardId: id,
      title: 'Title $id',
      snippet: 'Snippet $id',
      date: DateTime(2026, 1, 1),
    );

void main() {
  group('CardSearchViewModel', () {
    test('updateQuery with non-blank query populates results after debounce',
        () async {
      final fake = _FakeCardRetriever(hitsToReturn: [_hit('1'), _hit('2')]);
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      vm.updateQuery('hello');
      expect(vm.loading, isFalse); // not yet run — debounced

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(fake.callCount, 1);
      expect(fake.lastQuery, 'hello');
      expect(vm.results.length, 2);
      expect(vm.loading, isFalse);
      expect(vm.error, isNull);
    });

    test('updateQuery with blank query clears results without searching',
        () async {
      final fake = _FakeCardRetriever(hitsToReturn: [_hit('1')]);
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      vm.updateQuery('hello');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(vm.results, isNotEmpty);

      vm.updateQuery('   ');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(fake.callCount, 1); // no additional search call
      expect(vm.results, isEmpty);
    });

    test('setDateRange passes date args through to retriever.search',
        () async {
      final fake = _FakeCardRetriever(hitsToReturn: [_hit('1')]);
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 2, 1);
      vm.updateQuery('foo');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      vm.setDateRange(from, to);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.lastFrom, from);
      expect(fake.lastTo, to);
    });

    test('toggleTag passes tags through to retriever.search', () async {
      final fake = _FakeCardRetriever(hitsToReturn: [_hit('1')]);
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      vm.updateQuery('foo');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      vm.toggleTag('work');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.lastTags, ['work']);
      expect(vm.selectedTags, ['work']);

      vm.toggleTag('work');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fake.lastTags, isNull); // empty tag list -> null passthrough
      expect(vm.selectedTags, isEmpty);
    });

    test('error path sets error and clears loading', () async {
      final fake = _FakeCardRetriever(errorToThrow: Exception('boom'));
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      vm.updateQuery('hello');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(vm.error, isNotNull);
      expect(vm.loading, isFalse);
      expect(vm.results, isEmpty);
    });

    test('notifies listeners on loading transitions', () async {
      final fake = _FakeCardRetriever(hitsToReturn: [_hit('1')]);
      final vm = CardSearchViewModel.forTesting(retriever: fake);

      var notifyCount = 0;
      vm.addListener(() => notifyCount++);

      vm.updateQuery('hello');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(notifyCount, greaterThan(0));
    });
  });
}
