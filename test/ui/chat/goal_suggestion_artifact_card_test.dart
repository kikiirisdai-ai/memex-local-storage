import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/data/services/goal_suggestion_resolution_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/goal_dao.dart';
import 'package:memex/ui/chat/widgets/goal_suggestion_artifact_card.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test-only fake that always throws from [incrementProgress], to exercise
/// the try/catch fallback path in [GoalSuggestionArtifactCard._confirm].
class _ThrowingIncrementGoalService extends GoalService {
  _ThrowingIncrementGoalService({required GoalDao dao})
      : super.forTesting(dao: dao, userIdProvider: () async => 'u1');

  @override
  Future<bool> incrementProgress(String id, double delta) {
    throw Exception('simulated incrementProgress failure');
  }
}

Future<void> _pump(
  WidgetTester tester,
  ChatArtifact artifact,
  GoalService goalService,
  GoalSuggestionResolutionStore store,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GoalSuggestionArtifactCard(
          artifact: artifact,
          goalService: goalService,
          resolutionStore: store,
        ),
      ),
    ),
  );
}

void main() {
  late AppDatabase db;
  late GoalService goalService;
  late GoalSuggestionResolutionStore store;

  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'zh'});
    await UserStorage.initL10n();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goalService = GoalService.forTesting(
      dao: db.goalDao,
      userIdProvider: () async => 'u1',
    );
    store = GoalSuggestionResolutionStore.forTesting(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
      'unresolved quantitative suggestion shows a confirm button; tapping '
      'it increments the goal and greys out the button', (tester) async {
    final goalId = await goalService.createGoal(
      title: '读书',
      goalType: 'quantitative',
      targetValue: 20,
    );
    final artifact = ChatArtifact.goalSuggestion(
      goalId: goalId!,
      goalTitle: '读书',
      goalType: 'quantitative',
      delta: 2,
      turnId: 'turn-1',
    );

    await _pump(tester, artifact, goalService, store);
    await tester.pumpAndSettle();

    expect(find.text('读书'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final goals = await goalService.getGoals();
    expect(goals.first.currentValue, 2);
    expect(await store.isResolved(artifact.artifactId), isTrue);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('already-resolved suggestion renders greyed out on first '
      'build, without re-triggering the goal update', (tester) async {
    final goalId = await goalService.createGoal(
      title: '读书',
      goalType: 'quantitative',
      targetValue: 20,
    );
    final artifact = ChatArtifact.goalSuggestion(
      goalId: goalId!,
      goalTitle: '读书',
      goalType: 'quantitative',
      delta: 2,
      turnId: 'turn-1',
    );
    await store.markResolved(artifact.artifactId);

    await _pump(tester, artifact, goalService, store);
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    final goals = await goalService.getGoals();
    expect(goals.first.currentValue, 0); // untouched
  });

  testWidgets('binary suggestion calls markCompleted, not incrementProgress',
      (tester) async {
    final goalId = await goalService.createGoal(
      title: '学会游泳',
      goalType: 'binary',
    );
    final artifact = ChatArtifact.goalSuggestion(
      goalId: goalId!,
      goalTitle: '学会游泳',
      goalType: 'binary',
      turnId: 'turn-1',
    );

    await _pump(tester, artifact, goalService, store);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final goals = await goalService.getGoals();
    expect(goals.first.status, 'completed');
  });

  testWidgets(
      'incrementProgress throwing resets busy state so the confirm button '
      'is tappable again, and leaves the suggestion unresolved',
      (tester) async {
    final throwingGoalService = _ThrowingIncrementGoalService(dao: db.goalDao);
    final goalId = await throwingGoalService.createGoal(
      title: '读书',
      goalType: 'quantitative',
      targetValue: 20,
    );
    final artifact = ChatArtifact.goalSuggestion(
      goalId: goalId!,
      goalTitle: '读书',
      goalType: 'quantitative',
      delta: 2,
      turnId: 'turn-1',
    );

    await _pump(tester, artifact, throwingGoalService, store);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Button remains visible and tappable (not stuck disabled).
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(await store.isResolved(artifact.artifactId), isFalse);
  });
}
