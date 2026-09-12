import 'package:flutter/foundation.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/memory_sync_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';

typedef MemoryCardsFetcher = Future<Result<List<TimelineCardModel>>> Function({
  int page,
  int limit,
});

/// Result of the last manual "force archive" action, for UI feedback.
enum ArchiveOutcome { done, empty, error }

/// ViewModel for the Memory page. Holds memory data and delegates to
/// [MemexRouter] and [MemorySyncService].
class MemoryViewModel extends ChangeNotifier {
  MemoryViewModel({required MemexRouter router})
      : this._(
          fetchMemory: router.getMemory,
          fetchTimelineCards: router.fetchTimelineCards,
          forceConsolidateMemory: router.forceConsolidateMemory,
        );

  @visibleForTesting
  factory MemoryViewModel.forTest({
    required Future<Result<Map<String, dynamic>>> Function() fetchMemory,
    required MemoryCardsFetcher fetchTimelineCards,
    Future<Result<bool>> Function()? forceConsolidateMemory,
    MemorySyncService? memorySyncService,
    Future<String?> Function()? getUserId,
  }) =>
      MemoryViewModel._(
        fetchMemory: fetchMemory,
        fetchTimelineCards: fetchTimelineCards,
        forceConsolidateMemory:
            forceConsolidateMemory ?? (() async => const Ok(false)),
        memorySyncService: memorySyncService,
        getUserId: getUserId,
      );

  MemoryViewModel._({
    required Future<Result<Map<String, dynamic>>> Function() fetchMemory,
    required MemoryCardsFetcher fetchTimelineCards,
    required Future<Result<bool>> Function() forceConsolidateMemory,
    MemorySyncService? memorySyncService,
    Future<String?> Function()? getUserId,
  })  : _fetchMemory = fetchMemory,
        _fetchTimelineCards = fetchTimelineCards,
        _forceConsolidateMemory = forceConsolidateMemory,
        _memorySyncService = memorySyncService ?? MemorySyncService.instance,
        _getUserId = getUserId ?? UserStorage.getUserId;

  final Future<Result<Map<String, dynamic>>> Function() _fetchMemory;
  final MemoryCardsFetcher _fetchTimelineCards;
  final Future<Result<bool>> Function() _forceConsolidateMemory;
  final MemorySyncService _memorySyncService;
  final Future<String?> Function() _getUserId;

  Map<String, dynamic>? memoryData;
  bool isLoading = true;
  String? error;
  bool isArchiving = false;
  ArchiveOutcome? lastArchiveOutcome;
  String? archiveError;

  MemorySyncStatus status = MemorySyncStatus.upToDate;

  Future<void> loadMemory() async {
    isLoading = true;
    error = null;
    notifyListeners();
    final result = await _fetchMemory();
    result.when(
      onOk: (data) {
        memoryData = data;
        error = null;
      },
      onError: (e, __) => error = e.toString(),
    );
    isLoading = false;
    notifyListeners();
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    final userId = await _getUserId();
    if (userId == null) return;
    status = await _memorySyncService.getStatus(userId);
    notifyListeners();
  }

  /// Forces memory to sync now: scans every captured card (so any that
  /// predate this feature and were never enqueued get picked up too), then
  /// processes the full pending queue regardless of the normal batch
  /// threshold.
  ///
  /// Always re-scans, even when nothing was pending — gating the scan on
  /// "queue currently empty" would skip historical cards whenever normal
  /// usage had already queued a few new ones, which is silently wrong for
  /// the explicit "update memory" action.
  Future<void> updateMemory() async {
    if (status == MemorySyncStatus.updating) return;

    final userId = await _getUserId();
    if (userId == null) return;

    status = MemorySyncStatus.updating;
    notifyListeners();

    try {
      final allFactIds = await _fetchAllCardFactIds();
      await _memorySyncService.enqueueMany(userId, allFactIds);
      await _memorySyncService.processNow(userId);
      await loadMemory();
    } finally {
      await refreshStatus();
    }
  }

  /// Forces the recent buffer to consolidate into the long-term archive
  /// right now, regardless of the normal size threshold (10 entries).
  Future<void> archiveNow() async {
    if (isArchiving) return;

    isArchiving = true;
    lastArchiveOutcome = null;
    archiveError = null;
    notifyListeners();

    try {
      final result = await _forceConsolidateMemory();
      result.when(
        onOk: (consolidated) {
          lastArchiveOutcome =
              consolidated ? ArchiveOutcome.done : ArchiveOutcome.empty;
        },
        onError: (e, __) {
          lastArchiveOutcome = ArchiveOutcome.error;
          archiveError = e.toString();
        },
      );
      await loadMemory();
    } finally {
      isArchiving = false;
      notifyListeners();
    }
  }

  Future<List<String>> _fetchAllCardFactIds() async {
    const pageLimit = 100;
    var page = 1;
    final factIds = <String>[];

    while (true) {
      final result = await _fetchTimelineCards(page: page, limit: pageLimit);
      final cards = result.when(
        onOk: (cards) => cards,
        onError: (_, __) => const <TimelineCardModel>[],
      );
      if (cards.isEmpty) break;

      factIds.addAll(cards.map((c) => c.id));

      if (cards.length < pageLimit) break;
      page++;
    }

    return factIds;
  }
}
