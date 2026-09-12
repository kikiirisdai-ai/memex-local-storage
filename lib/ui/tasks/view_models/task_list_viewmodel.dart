import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/task_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';

typedef TaskListCardsFetcher = Future<Result<List<TimelineCardModel>>>
    Function({int page, int limit});

typedef TaskEntryCreator = Future<Result<String>> Function({
  required String title,
  DateTime? dueDate,
  String? priority,
});

typedef TaskUiConfigUpdater = Future<bool> Function(
  String cardId,
  int configIndex,
  Map<String, dynamic> data,
);

/// ViewModel for the "待办" page: aggregates every card carrying a `task`
/// ui_config, split into active/completed.
class TaskListViewModel extends ChangeNotifier {
  TaskListViewModel({required MemexRouter router})
      : this._(
          fetchTimelineCards: router.fetchTimelineCards,
          createEntry: router.createTaskEntry,
          updateUiConfig: router.updateCardUiConfig,
        );

  @visibleForTesting
  factory TaskListViewModel.forTest({
    required TaskListCardsFetcher fetchTimelineCards,
    TaskEntryCreator? createEntry,
    TaskUiConfigUpdater? updateUiConfig,
  }) =>
      TaskListViewModel._(
        fetchTimelineCards: fetchTimelineCards,
        createEntry: createEntry ??
            ({required title, dueDate, priority}) async =>
                const Ok('test-fact-id'),
        updateUiConfig: updateUiConfig ?? (_, __, ___) async => true,
      );

  TaskListViewModel._({
    required TaskListCardsFetcher fetchTimelineCards,
    required TaskEntryCreator createEntry,
    required TaskUiConfigUpdater updateUiConfig,
  })  : _fetchTimelineCards = fetchTimelineCards,
        _createEntry = createEntry,
        _updateUiConfig = updateUiConfig;

  final TaskListCardsFetcher _fetchTimelineCards;
  final TaskEntryCreator _createEntry;
  final TaskUiConfigUpdater _updateUiConfig;

  bool isLoading = false;
  String? errorMessage;
  bool isSaving = false;
  String? saveError;
  List<TaskEntry> _entries = const [];

  List<TaskEntry> get activeEntries =>
      _entries.where((e) => !e.isCompleted).toList()
        ..sort(_byDueDateThenNewest);
  List<TaskEntry> get completedEntries =>
      _entries.where((e) => e.isCompleted).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  static int _byDueDateThenNewest(TaskEntry a, TaskEntry b) {
    if (a.dueDate != null && b.dueDate != null) {
      return a.dueDate!.compareTo(b.dueDate!);
    }
    if (a.dueDate != null) return -1;
    if (b.dueDate != null) return 1;
    return b.timestamp.compareTo(a.timestamp);
  }

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final result = await _fetchTimelineCards(page: 1, limit: 1000);
    switch (result) {
      case Ok(value: final cards):
        _entries = cards
            .map(TaskEntry.fromCard)
            .whereType<TaskEntry>()
            .toList();
      case Error(error: final error):
        errorMessage = error.toString();
    }

    isLoading = false;
    notifyListeners();
  }

  /// Manually creates a new to-do (no LLM/quick-capture involved). Returns
  /// true on success, reloading the list; false on failure, leaving
  /// [saveError] set for the caller to surface.
  Future<bool> addManualEntry({
    required String title,
    DateTime? dueDate,
    String? priority,
  }) async {
    if (title.trim().isEmpty) return false;

    isSaving = true;
    saveError = null;
    notifyListeners();

    final result = await _createEntry(
      title: title,
      dueDate: dueDate,
      priority: priority,
    );

    isSaving = false;
    switch (result) {
      case Ok():
        notifyListeners();
        await load();
        return true;
      case Error(error: final error):
        saveError = error.toString();
        notifyListeners();
        return false;
    }
  }

  Future<void> toggleCompleted(TaskEntry entry) async {
    await _updateUiConfig(entry.cardId, entry.configIndex, {
      'is_completed': !entry.isCompleted,
    });
    await load();
  }

  @visibleForTesting
  void setEntriesForTesting(List<TaskEntry> entries) {
    _entries = entries;
    notifyListeners();
  }
}
