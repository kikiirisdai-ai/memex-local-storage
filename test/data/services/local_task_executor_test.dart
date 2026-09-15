import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/task_cancel_scope.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late LocalTaskExecutor executor;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    executor = LocalTaskExecutor.forTesting();
  });

  tearDown(() async {
    await executor.stop();
    await db.close();
  });

  group('LocalTaskExecutor scheduling', () {
    test('getLastTaskByType uses insertion order when createdAt ties',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'chat-1',
            type: 'super_agent_chat_turn_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now),
          ));
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'chat-2',
            type: 'super_agent_chat_turn_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now),
          ));

      expect(
        await executor.getLastTaskByType('super_agent_chat_turn_task'),
        'chat-2',
      );
    });

    test('scans past dependency-blocked queue head to run later tasks',
        () async {
      final completed = Completer<void>();
      executor.registerHandler('runnable_task', (_, __, ___) async {
        if (!completed.isCompleted) completed.complete();
      });

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'unresolved-dependency',
            type: 'dependency_task',
            payload: const Value('{}'),
            status: 'retrying',
            createdAt: Value(now),
            scheduledAt: Value(now + 3600),
          ));

      for (var i = 0; i < 50; i++) {
        await db.into(db.tasks).insert(TasksCompanion.insert(
              id: 'blocked-$i',
              type: 'blocked_task',
              payload: const Value('{}'),
              status: 'pending',
              createdAt: Value(now + i + 1),
              dependencies: Value(jsonEncode(['unresolved-dependency'])),
            ));
      }

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'runnable',
            type: 'runnable_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now + 100),
          ));

      await executor.start(userId: 'user-a');

      await completed.future.timeout(const Duration(seconds: 3));

      final runnable = await _waitForTaskStatus(db, 'runnable', 'completed');
      expect(runnable.status, 'completed');

      final blocked = await _getTask(db, 'blocked-0');
      expect(blocked.status, 'pending');
    });

    test('fails malformed dependencies and still runs a later valid task',
        () async {
      final completed = Completer<void>();
      executor.registerHandler('runnable_task', (_, __, ___) async {
        if (!completed.isCompleted) completed.complete();
      });

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'bad-dependency',
            type: 'blocked_task',
            payload: const Value('{}'),
            status: 'pending',
            priority: const Value(10),
            createdAt: Value(now),
            dependencies: const Value('not-json'),
          ));

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'runnable',
            type: 'runnable_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now + 1),
          ));

      await executor.start(userId: 'user-a');

      await completed.future.timeout(const Duration(seconds: 3));
      await _waitForTaskStatus(db, 'runnable', 'completed');

      final malformed = await _getTask(db, 'bad-dependency');
      expect(malformed.status, 'failed');
      expect(malformed.error, contains('Invalid task dependencies'));
    });

    test('uses only available concurrency slots while backlog remains queued',
        () async {
      final release = Completer<void>();
      var startedCount = 0;
      executor.registerHandler('runnable_task', (_, __, ___) async {
        startedCount++;
        await release.future;
      });

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await executor.start(userId: 'user-a');
      for (var i = 0; i < 4; i++) {
        await db.into(db.tasks).insert(TasksCompanion.insert(
              id: 'active-$i',
              type: 'already_processing',
              payload: const Value('{}'),
              status: 'processing',
              createdAt: Value(now + i),
            ));
      }

      for (var i = 0; i < 3; i++) {
        await db.into(db.tasks).insert(TasksCompanion.insert(
              id: 'runnable-$i',
              type: 'runnable_task',
              payload: const Value('{}'),
              status: 'pending',
              createdAt: Value(now + 10 + i),
            ));
      }

      await _waitUntil(() => startedCount == 1);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(startedCount, 1);

      release.complete();
      await _waitForTaskStatus(db, 'runnable-0', 'completed');
      executor.stop();
    });

    test('serializes tasks that share a concurrency policy key', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final secondStarted = Completer<void>();
      final otherCompleted = Completer<void>();

      executor.registerHandler(
        'serial_task',
        (_, __, context) async {
          if (context.taskId == 'serial-1') {
            if (!firstStarted.isCompleted) firstStarted.complete();
            await releaseFirst.future;
          } else if (context.taskId == 'serial-2') {
            if (!secondStarted.isCompleted) secondStarted.complete();
          }
        },
        concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
      );
      executor.registerHandler('other_task', (_, __, ___) async {
        if (!otherCompleted.isCompleted) otherCompleted.complete();
      });

      await _insertTask(
        db,
        id: 'serial-1',
        type: 'serial_task',
        status: 'pending',
        payload: {'value': 1},
      );
      await _insertTask(
        db,
        id: 'serial-2',
        type: 'serial_task',
        status: 'pending',
        payload: {'value': 2},
      );
      await _insertTask(
        db,
        id: 'other',
        type: 'other_task',
        status: 'pending',
        payload: {'value': 3},
      );

      await executor.start(userId: 'user-a');
      await firstStarted.future.timeout(const Duration(seconds: 3));
      await otherCompleted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect((await _getTask(db, 'serial-2')).status, 'pending');

      releaseFirst.complete();
      await secondStarted.future.timeout(const Duration(seconds: 3));
      await _waitForTaskStatus(db, 'serial-1', 'completed');
      await _waitForTaskStatus(db, 'serial-2', 'completed');
    });

    test('reports active task activity snapshot', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'pending-task',
            type: 'task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now),
          ));
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'processing-task',
            type: 'task',
            payload: const Value('{}'),
            status: 'processing',
            createdAt: Value(now),
          ));
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'retrying-task',
            type: 'task',
            payload: const Value('{}'),
            status: 'retrying',
            createdAt: Value(now),
          ));
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'completed-task',
            type: 'task',
            payload: const Value('{}'),
            status: 'completed',
            createdAt: Value(now),
          ));

      final snapshot = await executor.getTaskActivitySnapshot();

      expect(
        snapshot,
        TaskActivitySnapshot(
          pending: 1,
          processing: 1,
          retrying: 1,
          activeTaskIds: const {
            'pending-task',
            'processing-task',
            'retrying-task',
          },
          oldestActiveAt: now,
        ),
      );
      expect(snapshot.total, 3);
      expect(snapshot.hasActiveTasks, isTrue);
    });

    test('does not double-claim a task under repeated immediate polls',
        () async {
      final release = Completer<void>();
      var runCount = 0;
      executor.registerHandler('single_claim_task', (_, __, ___) async {
        runCount++;
        await release.future;
      });

      await _insertTask(
        db,
        id: 'single-claim',
        type: 'single_claim_task',
        status: 'pending',
        payload: {'value': 1},
      );

      await executor.start(userId: 'user-a');
      await _waitForTaskStatus(db, 'single-claim', 'processing');

      for (var i = 0; i < 5; i++) {
        await executor.drainAvailableTasks(
          userId: 'user-a',
          maxDuration: const Duration(milliseconds: 50),
          pollInterval: const Duration(milliseconds: 10),
        );
      }

      expect(runCount, 1);

      release.complete();
      await _waitForTaskStatus(db, 'single-claim', 'completed');
    });

    test('background drain runs available tasks and leaves future retries',
        () async {
      final completedTaskIds = <String>[];
      executor.registerHandler('drain_task', (_, __, context) async {
        completedTaskIds.add(context.taskId);
      });

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _insertTask(
        db,
        id: 'available-drain',
        type: 'drain_task',
        status: 'pending',
        payload: {'value': 1},
      );
      await _insertTask(
        db,
        id: 'future-retry',
        type: 'drain_task',
        status: 'retrying',
        payload: {'value': 2},
        scheduledAt: now + 3600,
      );

      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 25),
      );

      final available = await _getTask(db, 'available-drain');
      final futureRetry = await _getTask(db, 'future-retry');

      expect(completedTaskIds, ['available-drain']);
      expect(available.status, 'completed');
      expect(futureRetry.status, 'retrying');
      expect(result.timedOut, isFalse);
      expect(result.snapshot.retrying, 1);
      expect(result.nextRunnableDelay, isNotNull);
    });

    test('background drain waits for claimed task handlers before returning',
        () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var drainCompleted = false;
      executor.registerHandler('slow_drain_task', (_, __, context) async {
        if (!started.isCompleted) started.complete();
        await release.future;
      });

      await _insertTask(
        db,
        id: 'slow-drain',
        type: 'slow_drain_task',
        status: 'pending',
        payload: {'value': 1},
      );

      final drainFuture = executor
          .drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
      )
          .then((result) {
        drainCompleted = true;
        return result;
      });

      await started.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(drainCompleted, isFalse);
      expect((await _getTask(db, 'slow-drain')).status, 'processing');

      release.complete();
      final result = await drainFuture.timeout(const Duration(seconds: 3));

      expect(result.timedOut, isFalse);
      expect((await _getTask(db, 'slow-drain')).status, 'completed');
    });

    test('background drain does not reset already processing tasks', () async {
      await _insertTask(
        db,
        id: 'foreground-processing',
        type: 'long_task',
        status: 'processing',
        payload: {'value': 1},
      );

      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
      );

      final task = await _getTask(db, 'foreground-processing');

      expect(result.timedOut, isTrue);
      expect(task.status, 'processing');
    });

    test('foreground start takes over an abandoned foreground lease', () async {
      await _insertQueueLease(
        db,
        userId: 'user-a',
        value: 'old-process:foreground',
      );

      await executor.start(userId: 'user-a');

      final lease = await executor.getQueueLeaseForTesting('user-a');
      expect(executor.ownsQueueForTesting, isTrue);
      expect(lease?.value, executor.queueOwnerValueForTesting);
    });

    test('background drain does not take over a fresh foreground lease',
        () async {
      await _insertQueueLease(
        db,
        userId: 'user-a',
        value: 'foreground-process:foreground',
      );
      await _insertTask(
        db,
        id: 'pending-task',
        type: 'lease_task',
        status: 'pending',
        payload: {'value': 1},
      );
      executor.registerHandler('lease_task', (_, __, ___) async {});

      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
      );

      final lease = await executor.getQueueLeaseForTesting('user-a');
      final task = await _getTask(db, 'pending-task');
      expect(result.deferredToAnotherOwner, isTrue);
      expect(executor.ownsQueueForTesting, isFalse);
      expect(lease?.value, 'foreground-process:foreground');
      expect(task.status, 'pending');
    });

    test('foreground start does not take over a fresh background lease',
        () async {
      await _insertQueueLease(
        db,
        userId: 'user-a',
        value: 'background-process:background',
      );

      await executor.start(userId: 'user-a');

      final lease = await executor.getQueueLeaseForTesting('user-a');
      expect(executor.ownsQueueForTesting, isFalse);
      expect(lease?.value, 'background-process:background');
    });

    test('background drain requeues orphan processing tasks', () async {
      final completedTaskIds = <String>[];
      executor.registerHandler('orphan_task', (_, __, context) async {
        completedTaskIds.add(context.taskId);
      });
      final task = await _insertTask(
        db,
        id: 'orphan-processing',
        type: 'orphan_task',
        status: 'processing',
        payload: {'value': 1},
      );
      await executor.markTaskExecutionStartedForTesting(task);

      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 25),
        minimumStaleTaskAge: Duration.zero,
      );

      final updated = await _getTask(db, 'orphan-processing');

      expect(result.timedOut, isFalse);
      expect(completedTaskIds, ['orphan-processing']);
      expect(updated.status, 'completed');
      expect(await executor.getTaskExecutionMarkerForTesting(task.id), isNull);
    });

    test('background drain can stop an already running executor', () async {
      final completedTaskIds = <String>[];
      executor.registerHandler('drain_task', (_, __, context) async {
        completedTaskIds.add(context.taskId);
      });

      await executor.start(userId: 'user-a');
      await _insertTask(
        db,
        id: 'available-drain',
        type: 'drain_task',
        status: 'pending',
        payload: {'value': 1},
      );

      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 25),
        stopWhenDone: true,
      );

      await _insertTask(
        db,
        id: 'after-drain',
        type: 'drain_task',
        status: 'pending',
        payload: {'value': 2},
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final afterDrain = await _getTask(db, 'after-drain');

      expect(result.timedOut, isFalse);
      expect(completedTaskIds, ['available-drain']);
      expect(afterDrain.status, 'pending');
    });

    test('background drain respects user-level concurrency policy', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final secondStarted = Completer<void>();
      final completedTaskIds = <String>[];

      executor.registerHandler(
        'serial_drain_task',
        (_, __, context) async {
          if (context.taskId == 'serial-1') {
            if (!firstStarted.isCompleted) firstStarted.complete();
            await releaseFirst.future;
          } else {
            if (!secondStarted.isCompleted) secondStarted.complete();
          }
          completedTaskIds.add(context.taskId);
        },
        concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
      );

      await _insertTask(
        db,
        id: 'serial-1',
        type: 'serial_drain_task',
        status: 'pending',
        payload: {'value': 1},
      );
      await _insertTask(
        db,
        id: 'serial-2',
        type: 'serial_drain_task',
        status: 'pending',
        payload: {'value': 2},
      );

      await executor.start(userId: 'user-a');
      await firstStarted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect((await _getTask(db, 'serial-2')).status, 'pending');
      expect(secondStarted.isCompleted, isFalse);

      releaseFirst.complete();
      await secondStarted.future.timeout(const Duration(seconds: 3));
      final result = await executor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 25),
      );

      expect(result.timedOut, isFalse);
      expect(completedTaskIds, ['serial-1', 'serial-2']);
    });

    test('background drain respects user-level concurrency across executors',
        () async {
      final foregroundExecutor = executor;
      final backgroundExecutor = LocalTaskExecutor.forTesting();
      final foregroundStarted = Completer<void>();
      final releaseForeground = Completer<void>();
      final backgroundStarted = Completer<void>();

      foregroundExecutor.registerHandler(
        'serial_cross_task',
        (_, __, context) async {
          if (context.taskId == 'serial-cross-1' &&
              !foregroundStarted.isCompleted) {
            foregroundStarted.complete();
            await releaseForeground.future;
          }
        },
        concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
      );
      backgroundExecutor.registerHandler(
        'serial_cross_task',
        (_, __, context) async {
          if (!backgroundStarted.isCompleted) {
            backgroundStarted.complete();
          }
        },
        concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
      );

      await _insertTask(
        db,
        id: 'serial-cross-1',
        type: 'serial_cross_task',
        status: 'pending',
        payload: {'value': 1},
      );
      await _insertTask(
        db,
        id: 'serial-cross-2',
        type: 'serial_cross_task',
        status: 'pending',
        payload: {'value': 2},
      );

      await foregroundExecutor.start(userId: 'user-a');
      await foregroundStarted.future.timeout(const Duration(seconds: 3));

      final result = await backgroundExecutor.drainAvailableTasks(
        userId: 'user-a',
        maxDuration: const Duration(milliseconds: 120),
        pollInterval: const Duration(milliseconds: 20),
      );

      await foregroundExecutor.stop();
      releaseForeground.complete();
      await _waitForTaskStatus(db, 'serial-cross-1', 'completed');
      await backgroundExecutor.stop();

      expect(result.timedOut, isFalse);
      expect(result.deferredToAnotherOwner, isTrue);
      expect((await _getTask(db, 'serial-cross-2')).status, 'pending');
      expect(backgroundStarted.isCompleted, isFalse);
    });
  });

  group('LocalTaskExecutor crash loop guard', () {
    test('clears execution marker after successful task completion', () async {
      var handled = false;
      executor.registerHandler('ok_task', (userId, payload, context) async {
        handled = true;
      });

      await executor.start(userId: 'user-a');
      final taskId = await executor.enqueueTask(
        userId: 'user-a',
        taskType: 'ok_task',
        payload: {'value': 1},
      );

      final task = await _waitForTaskStatus(db, taskId, 'completed');

      expect(handled, isTrue);
      expect(task.status, 'completed');
      expect(await executor.getTaskExecutionMarkerForTesting(), isNull);
    });

    test(
      'clears execution marker when Dart handler failure is retryable',
      () async {
        executor.registerHandler('throw_task', (
          userId,
          payload,
          context,
        ) async {
          throw StateError('boom');
        });

        await executor.start(userId: 'user-a');
        final taskId = await executor.enqueueTask(
          userId: 'user-a',
          taskType: 'throw_task',
          payload: {'value': 1},
          maxRetries: 1,
        );

        final task = await _waitForTaskStatus(db, taskId, 'retrying');

        expect(task.retryCount, 1);
        expect(task.error, contains('boom'));
        expect(await executor.getTaskExecutionMarkerForTesting(), isNull);
      },
    );

    test(
      'a handler that never completes is aborted after the execution '
      'timeout instead of hanging the queue forever',
      () async {
        final timeoutExecutor = LocalTaskExecutor.forTesting(
          executionTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(timeoutExecutor.stop);

        timeoutExecutor.registerHandler('hangs_forever_task', (
          userId,
          payload,
          context,
        ) async {
          // Never resolves — simulates a stuck network/LLM call.
          await Completer<void>().future;
        });

        await timeoutExecutor.start(userId: 'user-a');
        final taskId = await timeoutExecutor.enqueueTask(
          userId: 'user-a',
          taskType: 'hangs_forever_task',
          payload: {'value': 1},
          maxRetries: 1,
        );

        final task = await _waitForTaskStatus(db, taskId, 'retrying');

        expect(task.retryCount, 1);
        expect(task.error, contains('exceeded'));
      },
    );

    test('first crash-like restart requeues stale processing task', () async {
      final task = await _insertTask(
        db,
        id: 'task-first-crash',
        type: 'dangerous_task',
        status: 'processing',
        payload: {'asset': 'large-image'},
      );
      await executor.markTaskExecutionStartedForTesting(task);

      await executor.start(userId: 'user-a');
      executor.stop();

      final updated = await _getTask(db, task.id);
      final marker = await executor.getTaskExecutionMarkerForTesting(task.id);
      final markerPayload = jsonDecode(marker!.value!) as Map<String, dynamic>;

      expect(updated.status, 'pending');
      expect(markerPayload['task_id'], task.id);
      expect(markerPayload['crash_count'], 1);
    });

    test('graceful app exit requeues stale task without crash count', () async {
      final task = await _insertTask(
        db,
        id: 'task-graceful-exit',
        type: 'long_running_task',
        status: 'processing',
        payload: {'value': 1},
      );
      await executor.markTaskExecutionStartedForTesting(task);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await executor.recordGracefulShutdown(reason: 'test_manual_exit');

      await executor.start(userId: 'user-a');
      executor.stop();

      final updated = await _getTask(db, task.id);

      expect(updated.status, 'pending');
      expect(await executor.getTaskExecutionMarkerForTesting(task.id), isNull);
      expect(await executor.getGracefulExitMarkerForTesting(), isNull);
    });

    test('keeps separate crash markers for concurrent processing tasks',
        () async {
      final taskA = await _insertTask(
        db,
        id: 'task-concurrent-a',
        type: 'dangerous_task_a',
        status: 'processing',
        payload: {'asset': 'large-image-a'},
      );
      final taskB = await _insertTask(
        db,
        id: 'task-concurrent-b',
        type: 'dangerous_task_b',
        status: 'processing',
        payload: {'asset': 'large-image-b'},
      );
      await executor.markTaskExecutionStartedForTesting(taskA);
      await executor.markTaskExecutionStartedForTesting(taskB);

      await executor.start(userId: 'user-a');
      executor.stop();

      final updatedA = await _getTask(db, taskA.id);
      final updatedB = await _getTask(db, taskB.id);
      final markerRows = await executor.getTaskExecutionMarkersForTesting();
      final crashCounts = {
        for (final row in markerRows)
          (jsonDecode(row.value!) as Map<String, dynamic>)['task_id']:
              (jsonDecode(row.value!) as Map<String, dynamic>)['crash_count'],
      };

      expect(updatedA.status, 'pending');
      expect(updatedB.status, 'pending');
      expect(markerRows, hasLength(2));
      expect(crashCounts[taskA.id], 1);
      expect(crashCounts[taskB.id], 1);
    });

    test('simulates process death while a real task execution is in progress',
        () async {
      final firstHandlerStarted = Completer<void>();
      final firstNeverCompletes = Completer<void>();
      executor.registerHandler('native_crash_task', (
        userId,
        payload,
        context,
      ) async {
        if (!firstHandlerStarted.isCompleted) {
          firstHandlerStarted.complete();
        }
        await firstNeverCompletes.future;
      });

      await executor.start(userId: 'user-a');
      final taskId = await executor.enqueueTask(
        userId: 'user-a',
        taskType: 'native_crash_task',
        payload: {'asset': 'oversized-image'},
      );
      await firstHandlerStarted.future.timeout(const Duration(seconds: 3));
      await _waitForTaskStatus(db, taskId, 'processing');
      await _waitForMarkerCrashCount(executor, taskId, 0);

      // Simulate process death: the task is still in progress, so the marker
      // remains and Dart finally/catch never gets a chance to clean it up.
      executor.stop();

      final secondHandlerStarted = Completer<void>();
      final secondNeverCompletes = Completer<void>();
      executor = LocalTaskExecutor.forTesting()
        ..registerHandler('native_crash_task', (
          userId,
          payload,
          context,
        ) async {
          if (!secondHandlerStarted.isCompleted) {
            secondHandlerStarted.complete();
          }
          await secondNeverCompletes.future;
        });

      await executor.start(userId: 'user-a');
      await secondHandlerStarted.future.timeout(const Duration(seconds: 3));
      await _waitForTaskStatus(db, taskId, 'processing');
      await _waitForMarkerCrashCount(executor, taskId, 1);
      executor.stop();

      executor = LocalTaskExecutor.forTesting();
      await executor.start(userId: 'user-a');
      executor.stop();

      final updated = await _getTask(db, taskId);

      expect(updated.status, 'failed');
      expect(updated.error, contains('crash-like exits'));
      expect(await executor.getTaskExecutionMarkerForTesting(taskId), isNull);
    });

    test('second crash-like restart fails task and clears marker', () async {
      final task = await _insertTask(
        db,
        id: 'task-second-crash',
        type: 'dangerous_task',
        status: 'processing',
        payload: {'asset': 'large-image'},
      );
      await executor.markTaskExecutionStartedForTesting(task);
      await _setMarkerCrashCount(db, executor, task.id, 1);

      await executor.start(userId: 'user-a');
      executor.stop();

      final updated = await _getTask(db, task.id);

      expect(updated.status, 'failed');
      expect(updated.error, contains('crash-like exits'));
      expect(await executor.getTaskExecutionMarkerForTesting(), isNull);
    });

    test(
      'bad dependency JSON fails task instead of leaving it pending forever',
      () async {
        await _insertTask(
          db,
          id: 'task-bad-deps',
          type: 'never_runs',
          status: 'pending',
          payload: {'value': 1},
          dependencies: 'not-json',
        );

        await executor.start(userId: 'user-a');

        final updated = await _waitForTaskStatus(db, 'task-bad-deps', 'failed');

        expect(updated.error, contains('Invalid task dependencies'));
        expect(await executor.getTaskExecutionMarkerForTesting(), isNull);
      },
    );
  });

  group('LocalTaskExecutor manual cancellation', () {
    Future<void> insertTask(
      String id,
      String status, {
      String type = 'cancellable_task',
    }) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: id,
            type: type,
            payload: const Value('{}'),
            status: status,
            createdAt: Value(now),
            scheduledAt: Value(now),
          ));
    }

    Future<String?> statusOf(String id) async {
      final row = await (db.select(db.tasks)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return row?.status;
    }

    // The executor clears its crash-guard marker at the very end of
    // _executeTask. Waiting on that keeps the trailing async cleanup inside
    // the test body instead of racing tearDown's db.close().
    Future<void> waitForExecutorIdle() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (await executor.getTaskExecutionMarkerForTesting() != null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Executor did not finish its per-task cleanup in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('flips every active status to cancelled and returns the count',
        () async {
      await insertTask('t-pending', 'pending');
      await insertTask('t-processing', 'processing');
      await insertTask('t-retrying', 'retrying');

      final cancelled = await executor.cancelAllActiveTasks();

      expect(cancelled, 3);
      expect(await statusOf('t-pending'), 'cancelled');
      expect(await statusOf('t-processing'), 'cancelled');
      expect(await statusOf('t-retrying'), 'cancelled');
    });

    test('leaves already-terminal tasks untouched and out of the count',
        () async {
      await insertTask('t-completed', 'completed');
      await insertTask('t-failed', 'failed');
      await insertTask('t-pending', 'pending');

      final cancelled = await executor.cancelAllActiveTasks();

      expect(cancelled, 1);
      expect(await statusOf('t-completed'), 'completed');
      expect(await statusOf('t-failed'), 'failed');
    });

    test('returns zero and no-ops when nothing is active', () async {
      await insertTask('t-completed', 'completed');

      expect(await executor.cancelAllActiveTasks(), 0);
      expect(await statusOf('t-completed'), 'completed');
    });

    test('records a cancellation reason and completion time', () async {
      await insertTask('t-pending', 'pending');

      await executor.cancelAllActiveTasks();

      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals('t-pending')))
          .getSingle();
      expect(row.error, contains('Cancelled'));
      expect(row.completedAt, isNotNull);
    });

    test('cancels the cancel scope installed for a running handler', () async {
      final handlerStarted = Completer<void>();
      CancelToken? seenToken;

      executor.registerHandler('cancellable_task', (_, __, ___) async {
        seenToken = TaskCancelScope.current;
        if (!handlerStarted.isCompleted) handlerStarted.complete();
        final blocked = Completer<void>();
        seenToken?.whenCancel.then((_) {
          if (!blocked.isCompleted) blocked.complete();
        });
        await blocked.future;
        throw Exception('cancelled mid-flight');
      });

      await insertTask('t-running', 'pending');
      await executor.start(userId: 'user-1');
      await handlerStarted.future.timeout(const Duration(seconds: 5));

      expect(seenToken, isNotNull);
      expect(seenToken!.isCancelled, isFalse);

      await executor.cancelAllActiveTasks();

      expect(seenToken!.isCancelled, isTrue);
      await waitForExecutorIdle();
    });

    test('does not reschedule a retry for a task cancelled mid-flight',
        () async {
      final handlerStarted = Completer<void>();
      final releaseHandler = Completer<void>();

      executor.registerHandler('cancellable_task', (_, __, ___) async {
        if (!handlerStarted.isCompleted) handlerStarted.complete();
        await releaseHandler.future;
        throw Exception('network died while cancelled');
      });

      await insertTask('t-running', 'pending');
      await executor.start(userId: 'user-1');
      await handlerStarted.future.timeout(const Duration(seconds: 5));

      await executor.cancelAllActiveTasks();
      releaseHandler.complete();
      await waitForExecutorIdle();

      expect(await statusOf('t-running'), 'cancelled');
    });

    test('invokes the cancellation handler so owners can wind down state',
        () async {
      final seen = <String>[];
      executor.registerCancellationHandler(
        'cancellable_task',
        (userId, payload, taskId) async => seen.add('$userId/$taskId'),
      );

      await insertTask('t-pending', 'pending');
      await executor.start(userId: 'user-1');
      await executor.cancelAllActiveTasks();

      expect(seen, ['user-1/t-pending']);
    });

    test('a handler that swallows cancellation cannot claim success', () async {
      final handlerStarted = Completer<void>();
      final releaseHandler = Completer<void>();

      // Mirrors runSuperAgentChild, which catches everything and returns a
      // result rather than propagating the cancellation.
      executor.registerHandler('cancellable_task', (_, __, ___) async {
        if (!handlerStarted.isCompleted) handlerStarted.complete();
        await releaseHandler.future;
      });

      await insertTask('t-running', 'pending');
      await executor.start(userId: 'user-1');
      await handlerStarted.future.timeout(const Duration(seconds: 5));

      await executor.cancelAllActiveTasks();
      releaseHandler.complete();
      await waitForExecutorIdle();

      expect(await statusOf('t-running'), 'cancelled');
    });

    // Load-bearing, not a nicety: every chat turn depends on the previous one
    // via getLastTaskByType, which ignores status. If a cancelled dependency
    // did not count as terminal, the first message sent after any terminate
    // would be blocked forever, since the cancelled task can never reach
    // completed/failed. Do not "fix" this back.
    test('a cancelled dependency no longer blocks dependent tasks', () async {
      final dependentRan = Completer<void>();
      executor.registerHandler('dependent_task', (_, __, ___) async {
        if (!dependentRan.isCompleted) dependentRan.complete();
      });

      await insertTask('t-dependency', 'pending');
      await executor.cancelAllActiveTasks();
      expect(await statusOf('t-dependency'), 'cancelled');

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 't-dependent',
            type: 'dependent_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now),
            scheduledAt: Value(now),
            dependencies: Value(jsonEncode(['t-dependency'])),
          ));

      await executor.start(userId: 'user-1');
      await dependentRan.future.timeout(const Duration(seconds: 5));
      await waitForExecutorIdle();
    });
  });

  group('LocalTaskExecutor active-task age', () {
    Future<void> insertTask(
      String id,
      String status, {
      required int createdAt,
    }) async {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: id,
            type: 'aging_task',
            payload: const Value('{}'),
            status: status,
            createdAt: Value(createdAt),
            scheduledAt: Value(createdAt),
          ));
    }

    test('reports the oldest active task creation time', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertTask('t-newer', 'pending', createdAt: now - 30);
      await insertTask('t-oldest', 'retrying', createdAt: now - 600);
      await insertTask('t-middle', 'processing', createdAt: now - 120);

      final snapshot = await executor.getTaskActivitySnapshot();

      expect(snapshot.oldestActiveAt, now - 600);
      expect(snapshot.oldestActiveSince,
          DateTime.fromMillisecondsSinceEpoch((now - 600) * 1000));
    });

    test('ignores terminal tasks when computing the oldest active time',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertTask('t-ancient-done', 'completed', createdAt: now - 9000);
      await insertTask('t-ancient-failed', 'failed', createdAt: now - 8000);
      await insertTask('t-active', 'pending', createdAt: now - 45);

      final snapshot = await executor.getTaskActivitySnapshot();

      expect(snapshot.oldestActiveAt, now - 45);
    });

    test('is null when nothing is active', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertTask('t-done', 'completed', createdAt: now - 60);

      final snapshot = await executor.getTaskActivitySnapshot();

      expect(snapshot.oldestActiveAt, isNull);
      expect(snapshot.oldestActiveSince, isNull);
      expect(snapshot.hasActiveTasks, isFalse);
    });

    test('empty snapshot carries no active age', () {
      const snapshot = TaskActivitySnapshot.empty();

      expect(snapshot.oldestActiveAt, isNull);
      expect(snapshot.oldestActiveSince, isNull);
    });
  });
}

Future<Task> _insertTask(
  AppDatabase db, {
  required String id,
  required String type,
  required String status,
  required Map<String, dynamic> payload,
  String? dependencies,
  int? scheduledAt,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db.into(db.tasks).insert(
        TasksCompanion.insert(
          id: id,
          type: type,
          payload: Value(jsonEncode(payload)),
          status: status,
          createdAt: Value(now),
          updatedAt: Value(now),
          maxRetries: const Value(5),
          scheduledAt: Value(scheduledAt),
          dependencies: Value(dependencies),
        ),
      );
  return _getTask(db, id);
}

Future<Task> _getTask(AppDatabase db, String id) {
  return (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
}

Future<void> _insertQueueLease(
  AppDatabase db, {
  required String userId,
  required String value,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db.into(db.kvStore).insert(
        KvStoreCompanion.insert(
          key: 'agent_queue_lease:$userId',
          value: Value(value),
          bucket: const Value('agent_queue_lease'),
          updatedAt: Value(now),
        ),
      );
}

Future<Task> _waitForTaskStatus(
  AppDatabase db,
  String taskId,
  String status, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final task = await _getTask(db, taskId);
    if (task.status == status) return task;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  final task = await _getTask(db, taskId);
  fail('Task $taskId did not reach $status. Last status: ${task.status}');
}

Future<Map<String, dynamic>> _waitForMarkerCrashCount(
  LocalTaskExecutor executor,
  String taskId,
  int crashCount, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final marker = await executor.getTaskExecutionMarkerForTesting(taskId);
    if (marker?.value != null) {
      final payload = jsonDecode(marker!.value!) as Map<String, dynamic>;
      if (payload['crash_count'] == crashCount) return payload;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  final marker = await executor.getTaskExecutionMarkerForTesting(taskId);
  fail(
    'Task $taskId marker did not reach crash_count=$crashCount. '
    'Last marker: ${marker?.value}',
  );
}

Future<void> _setMarkerCrashCount(
  AppDatabase db,
  LocalTaskExecutor executor,
  String taskId,
  int crashCount,
) async {
  final marker = await executor.getTaskExecutionMarkerForTesting(taskId);
  final payload = jsonDecode(marker!.value!) as Map<String, dynamic>;
  payload['crash_count'] = crashCount;

  await (db.update(db.kvStore)..where((kv) => kv.key.equals(marker.key))).write(
    KvStoreCompanion(
      value: Value(jsonEncode(payload)),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    ),
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
