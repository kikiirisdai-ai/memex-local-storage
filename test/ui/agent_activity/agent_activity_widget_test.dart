import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/agent_activity/widgets/agent_activity_widget.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _barKey = ValueKey('agent_activity_loading_bar');
const _terminateKey = ValueKey('agent_activity_terminate_button');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'agent-activity-test',
      'language': 'en',
    });
    await UserStorage.initL10n();
    AgentActivityService.setInstance(LocalAgentActivityService.instance);
  });

  Widget buildHost({
    bool forceVisible = false,
    TaskActivitySnapshot initialTaskSnapshot =
        const TaskActivitySnapshot.empty(),
    Stream<TaskActivitySnapshot>? taskActivitySnapshotStream,
    Future<int> Function()? onTerminateTasks,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: AgentActivityWidget(
            forceVisible: forceVisible,
            initialTaskSnapshot: initialTaskSnapshot,
            taskActivitySnapshotStream: taskActivitySnapshotStream ??
                const Stream<TaskActivitySnapshot>.empty(),
            onTerminateTasks: onTerminateTasks,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the loading bar when forced visible', (tester) async {
    await tester.pumpWidget(buildHost(forceVisible: true));
    await tester.pump();

    expect(find.byKey(_barKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('hides when there is no active task snapshot', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_barKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('shows while a task snapshot has active work, then hides', (
    tester,
  ) async {
    final taskSnapshots = StreamController<TaskActivitySnapshot>.broadcast();

    await tester.pumpWidget(
      buildHost(taskActivitySnapshotStream: taskSnapshots.stream),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_barKey), findsNothing);

    taskSnapshots.add(
      const TaskActivitySnapshot(pending: 1, processing: 0, retrying: 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_barKey), findsOneWidget);

    taskSnapshots.add(const TaskActivitySnapshot.empty());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_barKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await taskSnapshots.close();
  });

  testWidgets('updates while task counts change without altering visibility',
      (tester) async {
    final taskSnapshots = StreamController<TaskActivitySnapshot>.broadcast();
    const initialSnapshot = TaskActivitySnapshot(
      pending: 1,
      processing: 0,
      retrying: 0,
    );

    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: initialSnapshot,
        taskActivitySnapshotStream: taskSnapshots.stream,
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_barKey), findsOneWidget);

    taskSnapshots.add(
      const TaskActivitySnapshot(pending: 1, processing: 1, retrying: 0),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_barKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await taskSnapshots.close();
  });


  TaskActivitySnapshot activeSnapshot({required Duration age}) {
    final since = DateTime.now().subtract(age);
    return TaskActivitySnapshot(
      pending: 0,
      processing: 1,
      retrying: 0,
      activeTaskIds: const {'stuck-task'},
      oldestActiveAt: since.millisecondsSinceEpoch ~/ 1000,
    );
  }

  testWidgets('hides the terminate button while AI work is still young', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: activeSnapshot(age: const Duration(seconds: 30)),
      ),
    );
    await tester.pump();

    expect(find.byKey(_barKey), findsOneWidget);
    expect(find.byKey(_terminateKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('shows the terminate button once work passes the threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: activeSnapshot(
          age: kStuckAiTasksThreshold + const Duration(seconds: 5),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_terminateKey), findsOneWidget);
    expect(find.text(UserStorage.l10n.aiTasksStuckTerminate), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('confirming the terminate button runs the terminate action', (
    tester,
  ) async {
    var terminateCalls = 0;

    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: activeSnapshot(
          age: kStuckAiTasksThreshold + const Duration(seconds: 5),
        ),
        onTerminateTasks: () async {
          terminateCalls += 1;
          return 3;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(_terminateKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The confirm dialog guards the destructive action.
    expect(find.text(UserStorage.l10n.cancelAllAiTasksConfirm), findsOneWidget);
    expect(terminateCalls, 0);

    await tester.tap(find.text(UserStorage.l10n.cancelAllAiTasks).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(terminateCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dismissing the confirm dialog leaves tasks running', (
    tester,
  ) async {
    var terminateCalls = 0;

    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: activeSnapshot(
          age: kStuckAiTasksThreshold + const Duration(seconds: 5),
        ),
        onTerminateTasks: () async {
          terminateCalls += 1;
          return 3;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(_terminateKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(UserStorage.l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(terminateCalls, 0);
    expect(find.byKey(_terminateKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('terminate button disappears when the work finishes', (
    tester,
  ) async {
    final taskSnapshots = StreamController<TaskActivitySnapshot>.broadcast();

    await tester.pumpWidget(
      buildHost(
        initialTaskSnapshot: activeSnapshot(
          age: kStuckAiTasksThreshold + const Duration(seconds: 5),
        ),
        taskActivitySnapshotStream: taskSnapshots.stream,
      ),
    );
    await tester.pump();

    expect(find.byKey(_terminateKey), findsOneWidget);

    taskSnapshots.add(const TaskActivitySnapshot.empty());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_terminateKey), findsNothing);
    expect(find.byKey(_barKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await taskSnapshots.close();
  });

  testWidgets('remains hidden with only non-terminal activity history, no '
      'active task snapshot', (tester) async {
    final activity = _FakeActivityService(history: [
      _activityMessage(
        id: 1,
        type: AgentActivityType.info,
        title: 'Old activity',
        content: 'Should not show the bar on its own.',
      ),
    ]);
    AgentActivityService.setInstance(activity);

    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(seconds: 4));

    expect(find.byKey(_barKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    activity.dispose();
  });
}

AgentActivityMessageModel _activityMessage({
  required int id,
  required AgentActivityType type,
  required String title,
  String? content,
}) {
  return AgentActivityMessageModel(
    id: id,
    type: type,
    title: title,
    content: content,
    agentName: 'Worker Agent',
    agentId: 'worker-agent',
    userId: 'agent-activity-test',
    timestamp: DateTime(2026, 1, 1),
  );
}

class _FakeActivityService implements AgentActivityService {
  _FakeActivityService({List<AgentActivityMessageModel> history = const []})
      : _history = List<AgentActivityMessageModel>.from(history);

  final _controller = StreamController<AgentActivityMessageModel>.broadcast();
  final List<AgentActivityMessageModel> _history;

  @override
  Stream<AgentActivityMessageModel> get messageStream => _controller.stream;

  @override
  Future<List<AgentActivityMessageModel>> getHistory({int limit = 10}) async {
    return _history.take(limit).toList();
  }

  @override
  Future<void> pushMessage({
    required AgentActivityType type,
    required String title,
    String? content,
    String? icon,
    required String agentName,
    required String agentId,
    String? scene,
    String? sceneId,
    String? userId,
  }) async {}

  void dispose() {
    unawaited(_controller.close());
  }
}
