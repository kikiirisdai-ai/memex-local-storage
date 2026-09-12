import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/user_stats_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/insight/widgets/insight_screen.dart';
import 'package:memex/ui/insight/widgets/user_stats_page.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AI knowledge-insight generation never reliably completes on the local
// model (times out / returns empty / hallucinates success with zero real
// tool calls). This test locks in that the Insight page now shows ONLY the
// Activity Stats section (with its working mood curve) and no longer shows
// any knowledge-insight section/switcher.
void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('insight_screen_widget_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_insight_screen_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'default state shows only Activity Stats, no knowledge-insight section',
    (tester) async {
      final vm = InsightViewModel(
        router: MemexRouter(),
        userStatsFetcher: (_) async => Ok(_snapshot()),
      );
      vm.isLoading = false;
      vm.statsSnapshot = _snapshot();
      vm.isStatsLoading = false;

      // Default selectedSection must be stats — the AI-insights section is
      // de-wired and should never be selected by default.
      expect(vm.selectedSection, InsightSection.stats);

      await tester.pumpWidget(
        _wrap(InsightScreen(viewModel: vm, isEmbedded: true)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Activity Stats content is present.
      expect(find.byType(UserStatsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('user_stats_page')), findsOneWidget);
      expect(find.text('Activity stats'), findsOneWidget);
      // Mood curve section is present within Activity Stats (scroll it into
      // view — the stats page is a lazily-built ListView).
      await tester.scrollUntilVisible(
        find.text('Mood curve'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mood curve'), findsOneWidget);

      // No knowledge-insight section switcher / AI insight list.
      // (Icons.auto_graph_rounded is intentionally NOT asserted absent — it is
      // the retained Activity Stats summary header icon, not a knowledge-insight
      // marker.)
      expect(find.text('Knowledge Insight'), findsNothing);
      expect(
        find.byKey(const ValueKey('user_stats_overview_card')),
        findsNothing,
      );

      vm.dispose();
    },
  );

  testWidgets('loadData delegates to loadStats without AI insight fetch', (
    tester,
  ) async {
    var statsFetchCalls = 0;
    final vm = InsightViewModel(
      router: MemexRouter(),
      userStatsFetcher: (_) async {
        statsFetchCalls += 1;
        return Ok(_snapshot());
      },
    );

    await vm.loadData();

    expect(statsFetchCalls, 1);
    expect(vm.statsSnapshot, isNotNull);
    expect(vm.isStatsLoading, isFalse);

    vm.dispose();
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

UserStatsSnapshot _snapshot() {
  final range = UserStatsDateRange(
    start: DateTime(2026, 5, 18),
    end: DateTime(2026, 5, 20),
  );
  final daily = [
    UserStatsDailyPoint(
      date: DateTime(2026, 5, 18),
      inputs: 2,
      words: 18,
      cards: 1,
      knowledgeUnits: 1,
      insights: 0,
      completedTodos: 0,
    ),
    UserStatsDailyPoint(
      date: DateTime(2026, 5, 19),
      inputs: 1,
      words: 8,
      cards: 1,
      knowledgeUnits: 0,
      insights: 1,
      completedTodos: 0,
    ),
    UserStatsDailyPoint(
      date: DateTime(2026, 5, 20),
      inputs: 1,
      words: 5,
      cards: 2,
      knowledgeUnits: 1,
      insights: 1,
      completedTodos: 1,
    ),
  ];
  return UserStatsSnapshot(
    range: range,
    summary: const UserStatsSummary(
      totalInputs: 4,
      totalWords: 31,
      totalCards: 4,
      totalKnowledgeUnits: 2,
      totalInsights: 2,
      totalCompletedTodos: 1,
      activeDays: 3,
      currentStreakDays: 3,
    ),
    daily: daily,
    sourceBreakdown: const UserStatsSourceBreakdown(
      textInputs: 3,
      imageInputs: 1,
      audioInputs: 1,
    ),
    topTags: const [
      UserStatsTopTag(label: 'work', count: 2),
      UserStatsTopTag(label: 'health', count: 1),
    ],
    dayDetails: {
      '2026-05-18': UserStatsDayDetail(
        date: DateTime(2026, 5, 18),
        cardTitles: const ['Morning note'],
        knowledgePaths: const ['PKM/Areas/work.md'],
      ),
      '2026-05-19': UserStatsDayDetail(
        date: DateTime(2026, 5, 19),
        insightTitles: const ['Pattern found'],
      ),
      '2026-05-20': UserStatsDayDetail(
        date: DateTime(2026, 5, 20),
        cardTitles: const ['Weekly review'],
        knowledgePaths: const ['PKM/Projects/app.md'],
        insightTitles: const ['Better cadence'],
        completedTodoTitles: const ['Clean desk'],
      ),
    },
  );
}
