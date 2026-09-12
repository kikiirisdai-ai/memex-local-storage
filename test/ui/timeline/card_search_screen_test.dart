import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/timeline/view_models/card_search_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/card_search_screen.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCardRetriever implements CardRetriever {
  _FakeCardRetriever({this.hitsToReturn = const []});

  final List<CardHit> hitsToReturn;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    if (query.trim().isEmpty) return [];
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
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Widget buildTestableWidget(CardSearchViewModel viewModel) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CardSearchScreen(viewModel: viewModel),
    );
  }

  final searchFieldFinder = find.byKey(const ValueKey('card_search_field'));

  testWidgets('shows empty-state before any input', (tester) async {
    final vm = CardSearchViewModel.forTesting(
      retriever: _FakeCardRetriever(),
    );
    await tester.pumpWidget(buildTestableWidget(vm));
    await tester.pump();

    expect(find.text('输入关键词搜索'), findsOneWidget);
  });

  testWidgets('renders result tiles after typing and debounce elapses',
      (tester) async {
    final vm = CardSearchViewModel.forTesting(
      retriever: _FakeCardRetriever(hitsToReturn: [_hit('a'), _hit('b')]),
    );
    await tester.pumpWidget(buildTestableWidget(vm));

    await tester.enterText(searchFieldFinder, 'hello');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(const ValueKey('card_search_result_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('card_search_result_b')), findsOneWidget);
    expect(find.text('没有找到相关记录'), findsNothing);
  });

  testWidgets('shows no-results state when search yields nothing',
      (tester) async {
    final vm = CardSearchViewModel.forTesting(
      retriever: _FakeCardRetriever(hitsToReturn: []),
    );
    await tester.pumpWidget(buildTestableWidget(vm));

    await tester.enterText(searchFieldFinder, 'nothingmatches');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('没有找到相关记录'), findsOneWidget);
  });

  testWidgets(
      'tapping a result tile opens the card detail screen (factId with slashes)',
      (tester) async {
    // Real timeline-card factIds contain '/' and '#' (e.g. 2025/11/23.md#ts_1).
    // The tile must open the detail screen by object (Navigator.push), NOT by
    // URL — a '/card/<factId>' push breaks GoRouter's single-segment ':id'
    // matching and crashes. This uses a realistic factId to lock that in.
    const factId = '2025/11/23.md#ts_1';
    final vm = CardSearchViewModel.forTesting(
      retriever: _FakeCardRetriever(hitsToReturn: [_hit(factId)]),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardSearchScreen(viewModel: vm),
      ),
    );

    await tester.enterText(searchFieldFinder, 'hello');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('card_search_result_$factId')));
    await tester.pump();
    await tester.pump();

    // The detail screen was pushed (it may still be loading its card, but the
    // route/widget must exist without throwing a navigation error).
    expect(find.byType(TimelineCardDetailScreen), findsOneWidget);
  });
}
