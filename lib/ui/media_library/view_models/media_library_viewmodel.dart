import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/media_library_entry.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/result.dart';

typedef MediaLibraryCardsFetcher = Future<Result<List<TimelineCardModel>>>
    Function({int page, int limit});

typedef MediaLibraryEntryCreator = Future<Result<String>> Function({
  required String title,
  required String mediaType,
  String? mediaStatus,
  int? rating,
  String? comment,
});

/// ViewModel for the Media Library page: aggregates every card carrying a
/// `media_card` ui_config, filterable by media type and status.
class MediaLibraryViewModel extends ChangeNotifier {
  MediaLibraryViewModel({required MemexRouter router})
      : this._(
          fetchTimelineCards: router.fetchTimelineCards,
          createEntry: router.createMediaLibraryEntry,
        );

  @visibleForTesting
  factory MediaLibraryViewModel.forTest({
    required MediaLibraryCardsFetcher fetchTimelineCards,
    MediaLibraryEntryCreator? createEntry,
  }) =>
      MediaLibraryViewModel._(
        fetchTimelineCards: fetchTimelineCards,
        createEntry: createEntry ??
            ({
              required title,
              required mediaType,
              mediaStatus,
              rating,
              comment,
            }) async =>
                const Ok('test-fact-id'),
      );

  MediaLibraryViewModel._({
    required MediaLibraryCardsFetcher fetchTimelineCards,
    required MediaLibraryEntryCreator createEntry,
  })  : _fetchTimelineCards = fetchTimelineCards,
        _createEntry = createEntry;

  final MediaLibraryCardsFetcher _fetchTimelineCards;
  final MediaLibraryEntryCreator _createEntry;

  bool isLoading = false;
  String? errorMessage;
  bool isSaving = false;
  String? saveError;
  List<MediaLibraryEntry> _entries = const [];

  /// One of 'all' | 'book' | 'movie' | 'tv' | 'music' | 'podcast' | 'other'.
  String typeFilter = 'all';

  /// One of 'all' | 'want' | 'doing' | 'done'.
  String statusFilter = 'all';

  List<MediaLibraryEntry> get entries => _entries;

  List<MediaLibraryEntry> get filteredEntries => _entries.where((entry) {
        if (typeFilter != 'all' && entry.mediaType != typeFilter) {
          return false;
        }
        if (statusFilter != 'all' && entry.mediaStatus != statusFilter) {
          return false;
        }
        return true;
      }).toList();

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Large limit: a personal media log rarely exceeds a few hundred
    // entries, and this page needs the full set to filter/group client
    // side (mirrors the existing "fetch everything" pattern used for
    // period-wide tag aggregation in MemexRouter).
    final result = await _fetchTimelineCards(page: 1, limit: 1000);
    switch (result) {
      case Ok(value: final cards):
        _entries = cards
            .map(MediaLibraryEntry.fromCard)
            .whereType<MediaLibraryEntry>()
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case Error(error: final error):
        errorMessage = error.toString();
    }

    isLoading = false;
    notifyListeners();
  }

  /// Manually creates a new media entry (no LLM/quick-capture involved).
  /// Returns true on success, reloading the list; false on failure, leaving
  /// [saveError] set for the caller to surface.
  Future<bool> addManualEntry({
    required String title,
    required String mediaType,
    String? mediaStatus,
    int? rating,
    String? comment,
  }) async {
    if (title.trim().isEmpty) return false;

    isSaving = true;
    saveError = null;
    notifyListeners();

    final result = await _createEntry(
      title: title,
      mediaType: mediaType,
      mediaStatus: mediaStatus,
      rating: rating,
      comment: comment,
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

  void setTypeFilter(String type) {
    if (typeFilter == type) return;
    typeFilter = type;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    if (statusFilter == status) return;
    statusFilter = status;
    notifyListeners();
  }

  @visibleForTesting
  void setEntriesForTesting(List<MediaLibraryEntry> entries) {
    _entries = entries;
    notifyListeners();
  }
}
