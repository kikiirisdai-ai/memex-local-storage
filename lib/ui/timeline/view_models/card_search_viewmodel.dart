import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/data/services/card_retriever.dart';

/// Search state/behavior for [CardSearchScreen]. Debounces query input,
/// re-runs the search on date/tag filter changes, and exposes the result
/// set + loading/error flags via [ChangeNotifier] (mirrors
/// SettingsSearchViewModel — plain notifyListeners, no Command wrapper).
class CardSearchViewModel extends ChangeNotifier {
  CardSearchViewModel({required CardRetriever retriever})
      : _retriever = retriever;

  @visibleForTesting
  CardSearchViewModel.forTesting({required CardRetriever retriever})
      : _retriever = retriever;

  final CardRetriever _retriever;
  Timer? _debounce;

  String _query = '';
  DateTime? _from;
  DateTime? _to;
  List<String> _selectedTags = [];
  List<CardHit> _results = [];
  bool _loading = false;
  String? _error;

  String get query => _query;
  DateTime? get from => _from;
  DateTime? get to => _to;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);
  List<CardHit> get results => _results;
  bool get loading => _loading;
  String? get error => _error;

  /// Updates the query and (after a debounce) re-runs the search. A blank
  /// query clears results immediately without hitting the retriever.
  void updateQuery(String query) {
    _query = query;
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      _results = [];
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  /// Sets the active date filter and re-runs the search immediately.
  void setDateRange(DateTime? from, DateTime? to) {
    _from = from;
    _to = to;
    _run();
  }

  /// Toggles a tag in the active tag filter and re-runs the search.
  void toggleTag(String tag) {
    final next = List<String>.of(_selectedTags);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    _selectedTags = next;
    _run();
  }

  Future<void> _run() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final hits = await _retriever.search(
        _query,
        dateFrom: _from,
        dateTo: _to,
        tags: _selectedTags.isEmpty ? null : _selectedTags,
      );
      _results = hits;
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
