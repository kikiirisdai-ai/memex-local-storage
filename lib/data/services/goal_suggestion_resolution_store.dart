import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';

import 'package:memex/db/app_database.dart';

/// Tracks which quick-capture goal-suggestion artifacts the user has
/// already confirmed, using the existing generic [KvStore] table (key =
/// artifact id, bucket = a fixed marker) — no new table, no change to how
/// chat messages are stored. A row's mere presence means "resolved"; there
/// is no "rejected" state (ignoring a suggestion just leaves no row).
class GoalSuggestionResolutionStore {
  GoalSuggestionResolutionStore._() : _dbOverride = null;

  static final GoalSuggestionResolutionStore instance =
      GoalSuggestionResolutionStore._();

  @visibleForTesting
  GoalSuggestionResolutionStore.forTesting({required AppDatabase db})
      : _dbOverride = db;

  final AppDatabase? _dbOverride;
  AppDatabase get _db => _dbOverride ?? AppDatabase.instance;

  static const String _bucket = 'goal_suggestion_resolved';

  Future<bool> isResolved(String artifactId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(artifactId)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> markResolved(String artifactId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: artifactId,
            bucket: const Value(_bucket),
            value: Value(DateTime.now().millisecondsSinceEpoch.toString()),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );
  }
}
