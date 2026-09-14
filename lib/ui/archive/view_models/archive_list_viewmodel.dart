import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';

typedef ArchivedCardsFetcher = Future<Result<List<TimelineCardModel>>>
    Function();

typedef CardIdAction = Future<bool> Function(String cardId);

/// ViewModel for the "已归档" (Archive) page: lists every archived card
/// with multi-select batch restore/delete.
class ArchiveListViewModel extends ChangeNotifier {
  ArchiveListViewModel({required MemexRouter router})
      : this._(
          fetchArchivedCards: router.fetchArchivedCards,
          unarchiveCard: router.unarchiveCard,
          deleteCard: router.deleteCard,
        );

  @visibleForTesting
  factory ArchiveListViewModel.forTest({
    required ArchivedCardsFetcher fetchArchivedCards,
    CardIdAction? unarchiveCard,
    CardIdAction? deleteCard,
  }) =>
      ArchiveListViewModel._(
        fetchArchivedCards: fetchArchivedCards,
        unarchiveCard: unarchiveCard ?? (_) async => true,
        deleteCard: deleteCard ?? (_) async => true,
      );

  ArchiveListViewModel._({
    required ArchivedCardsFetcher fetchArchivedCards,
    required CardIdAction unarchiveCard,
    required CardIdAction deleteCard,
  })  : _fetchArchivedCards = fetchArchivedCards,
        _unarchiveCard = unarchiveCard,
        _deleteCard = deleteCard;

  final ArchivedCardsFetcher _fetchArchivedCards;
  final CardIdAction _unarchiveCard;
  final CardIdAction _deleteCard;

  bool isLoading = false;
  String? errorMessage;
  bool isBusy = false;
  List<TimelineCardModel> entries = const [];
  final Set<String> selectedIds = {};

  bool get hasSelection => selectedIds.isNotEmpty;
  bool get isAllSelected =>
      entries.isNotEmpty && selectedIds.length == entries.length;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final result = await _fetchArchivedCards();
    switch (result) {
      case Ok(value: final cards):
        entries = cards;
        selectedIds.removeWhere(
          (id) => !cards.any((card) => card.id == id),
        );
      case Error(error: final error):
        errorMessage = error.toString();
    }

    isLoading = false;
    notifyListeners();
  }

  void toggleSelection(String cardId) {
    if (!selectedIds.remove(cardId)) {
      selectedIds.add(cardId);
    }
    notifyListeners();
  }

  void toggleSelectAll() {
    if (isAllSelected) {
      selectedIds.clear();
    } else {
      selectedIds
        ..clear()
        ..addAll(entries.map((e) => e.id));
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    notifyListeners();
  }

  /// Restores every selected card back to the main timeline.
  Future<void> restoreSelected() async {
    if (selectedIds.isEmpty) return;
    isBusy = true;
    notifyListeners();

    for (final id in selectedIds.toList()) {
      await _unarchiveCard(id);
    }
    selectedIds.clear();
    isBusy = false;
    await load();
  }

  /// Permanently deletes every selected card.
  Future<void> deleteSelected() async {
    if (selectedIds.isEmpty) return;
    isBusy = true;
    notifyListeners();

    for (final id in selectedIds.toList()) {
      await _deleteCard(id);
    }
    selectedIds.clear();
    isBusy = false;
    await load();
  }

  @visibleForTesting
  void setEntriesForTesting(List<TimelineCardModel> value) {
    entries = value;
    notifyListeners();
  }
}
