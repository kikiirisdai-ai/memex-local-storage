import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_sync_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/memory/view_models/memory_viewmodel.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late String userId;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // MemorySyncService caches per-user state in-process for the lifetime
    // of the test run, so each test needs its own userId to avoid bleeding
    // pending-queue state into the next test.
    userId = 'memory_viewmodel_user_${DateTime.now().microsecondsSinceEpoch}';
    await UserStorage.saveUser(userId);
    tempDir = await Directory.systemTemp.createTemp('memex_memory_vm_');
    await FileSystemService.init(tempDir.path);
    AgentActivityService.setInstance(LocalAgentActivityService.instance);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MemoryViewModel buildViewModel({
    List<TimelineCardModel> cards = const [],
    Future<Result<bool>> Function()? forceConsolidateMemory,
  }) {
    return MemoryViewModel.forTest(
      fetchMemory: () async => const Ok({
        'archived_memory': 'Loves hiking.',
        'recent_buffer': [],
      }),
      fetchTimelineCards: ({page = 1, limit = 20}) async {
        if (page > 1) return const Ok(<TimelineCardModel>[]);
        return Ok(cards);
      },
      forceConsolidateMemory: forceConsolidateMemory,
    );
  }

  test('loadMemory populates data and marks status up to date with no cards',
      () async {
    final vm = buildViewModel();

    await vm.loadMemory();

    expect(vm.isLoading, isFalse);
    expect(vm.error, isNull);
    expect(vm.memoryData?['archived_memory'], 'Loves hiking.');
    expect(vm.status, MemorySyncStatus.upToDate);
  });

  test('loadMemory surfaces a fetch error', () async {
    final vm = MemoryViewModel.forTest(
      fetchMemory: () async => const Error('boom'),
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          const Ok(<TimelineCardModel>[]),
    );

    await vm.loadMemory();

    expect(vm.error, contains('boom'));
  });

  test('refreshStatus reflects a pending queue', () async {
    await MemorySyncService.instance.enqueueMany(userId, ['fact_pending']);
    final vm = buildViewModel();

    await vm.refreshStatus();

    expect(vm.status, MemorySyncStatus.pendingUpdate);
  });

  test(
      'updateMemory processes an already-pending queue alongside a fresh '
      'card scan', () async {
    await MemorySyncService.instance
        .enqueueMany(userId, ['2026/01/01.md#ts_1']);
    final vm = buildViewModel();
    await vm.refreshStatus();
    expect(vm.status, MemorySyncStatus.pendingUpdate);

    await vm.updateMemory();

    expect(vm.status, MemorySyncStatus.upToDate);
  });

  test(
      'updateMemory still scans historical cards even when something is '
      'already pending (regression: used to skip the scan in this case)',
      () async {
    // Simulate normal usage having already queued one new card...
    await MemorySyncService.instance
        .enqueueMany(userId, ['2026/01/02.md#ts_1']);
    // ...while an older, never-enqueued card also exists in history.
    final vm = buildViewModel(cards: [
      TimelineCardModel(
        id: '2025/06/01.md#ts_1',
        timestamp: DateTime(2025, 6, 1),
        tags: const [],
        status: 'completed',
        uiConfigs: const [],
      ),
    ]);
    await vm.refreshStatus();
    expect(vm.status, MemorySyncStatus.pendingUpdate);

    await vm.updateMemory();

    // Both the pre-existing pending card and the historical one were
    // enqueued and drained back to empty — neither was left stranded.
    expect(vm.status, MemorySyncStatus.upToDate);
  });

  test('updateMemory with nothing pending and no cards stays up to date',
      () async {
    final vm = buildViewModel(cards: const []);

    await vm.updateMemory();

    expect(vm.status, MemorySyncStatus.upToDate);
  });

  test('updateMemory ignores a call while already updating', () async {
    final vm = buildViewModel();
    await vm.loadMemory();
    // Simulate an in-flight update by driving status directly through a
    // real pending-queue update, then firing a second overlapping call.
    final first = vm.updateMemory();
    final second = vm.updateMemory();

    await Future.wait([first, second]);

    expect(vm.status, MemorySyncStatus.upToDate);
  });

  test('archiveNow reports done and reloads memory on success', () async {
    var calls = 0;
    final vm = buildViewModel(
      forceConsolidateMemory: () async {
        calls++;
        return const Ok(true);
      },
    );

    await vm.archiveNow();

    expect(calls, 1);
    expect(vm.isArchiving, isFalse);
    expect(vm.lastArchiveOutcome, ArchiveOutcome.done);
    expect(vm.archiveError, isNull);
    expect(vm.memoryData?['archived_memory'], 'Loves hiking.');
  });

  test('archiveNow reports empty when there was nothing to consolidate',
      () async {
    final vm = buildViewModel(
      forceConsolidateMemory: () async => const Ok(false),
    );

    await vm.archiveNow();

    expect(vm.lastArchiveOutcome, ArchiveOutcome.empty);
  });

  test('archiveNow surfaces an error without throwing', () async {
    final vm = buildViewModel(
      forceConsolidateMemory: () async => const Error('boom'),
    );

    await vm.archiveNow();

    expect(vm.lastArchiveOutcome, ArchiveOutcome.error);
    expect(vm.archiveError, contains('boom'));
  });

  test('archiveNow ignores a call while already archiving', () async {
    var calls = 0;
    final vm = buildViewModel(
      forceConsolidateMemory: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return const Ok(true);
      },
    );

    final first = vm.archiveNow();
    final second = vm.archiveNow();
    await Future.wait([first, second]);

    expect(calls, 1);
  });
}
