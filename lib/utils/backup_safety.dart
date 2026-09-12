import 'package:path/path.dart' as p;

/// Whether [childPath] is at or under [parentPath].
///
/// Used to defensively guard that a safety-snapshot destination directory is
/// NOT inside a directory that is about to be recursively deleted (e.g. the
/// app's `dataRoot`). Paths are normalized before comparison so trivial
/// differences (trailing slashes, `.`/`..` segments) don't cause false
/// negatives, and a path is considered "inside" its own equal path.
bool isPathInside(String childPath, String parentPath) {
  return p.isWithin(parentPath, childPath) || p.equals(parentPath, childPath);
}

/// Whether the user should be nudged to perform a manual export.
///
/// If [snoozeUntil] is set and still in the future relative to [now], the
/// nudge is suppressed regardless of how overdue the export is. Otherwise,
/// returns true when there has never been a manual export, or the last
/// export is older than [threshold].
bool shouldNudgeExport({
  DateTime? lastExport,
  DateTime? snoozeUntil,
  required DateTime now,
  Duration threshold = const Duration(days: 14),
}) {
  if (snoozeUntil != null && now.isBefore(snoozeUntil)) {
    return false;
  }
  if (lastExport == null) {
    return true;
  }
  return now.difference(lastExport) > threshold;
}

/// Whether a safety snapshot should be taken before running a database
/// migration to [code], given the [stored] last-known schema version.
///
/// Returns true only when a prior schema version is known and it is older
/// than the migration target.
bool shouldSnapshotBeforeMigration({
  int? stored,
  required int code,
}) {
  return stored != null && stored < code;
}

/// Wires the migration-safety-snapshot decision to its side effects.
///
/// Reads the previously stored schema version via [getStored], and — only
/// when [shouldSnapshotBeforeMigration] says so — invokes [snapshot] with a
/// `before_migration_v<code>` reason. This must happen strictly before
/// [migrate] runs, since a safety snapshot zips the on-disk DB file and is
/// only valid while it is still closed / pre-migration.
///
/// [migrate] then runs (e.g. `AppDatabase.init`). [setStored] is only called
/// with [code] *after* [migrate] completes successfully, so a failed or
/// partial migration never gets recorded as having reached [code] — the next
/// startup attempt will still see the old stored version and retry the
/// snapshot-before-migration logic.
///
/// [snapshot] failures are swallowed here: a failed safety snapshot must
/// never block app startup or the migration itself. Callers are expected to
/// still log the error inside their [snapshot] implementation if desired.
/// [migrate] failures are NOT swallowed — they propagate to the caller,
/// consistent with startup treating a broken migration as fatal.
Future<void> maybeSnapshotBeforeMigration({
  required Future<int?> Function() getStored,
  required int code,
  required Future<void> Function(String reason) snapshot,
  required Future<void> Function() migrate,
  required Future<void> Function(int code) setStored,
}) async {
  final stored = await getStored();
  if (shouldSnapshotBeforeMigration(stored: stored, code: code)) {
    try {
      await snapshot('before_migration_v$code');
    } catch (_) {
      // Best-effort: snapshot failure must not block startup/migration.
    }
  }
  await migrate();
  await setStored(code);
}

/// Takes a best-effort safety snapshot before a destructive "wipe" (clear
/// all data) operation.
///
/// The snapshot MUST land in a directory that survives the wipe — i.e. one
/// that is NOT inside the directory the wipe is about to recursively delete
/// (`dataRoot`). [resolveSafeDir] resolves that destination (e.g. the app's
/// support directory, which is a sibling of the documents directory the app
/// data lives under, not a descendant of it). [createBackup] then writes the
/// backup into that directory and returns the resulting file path.
///
/// This is entirely best-effort: any failure from [resolveSafeDir] or
/// [createBackup] is caught and reported via [onError] (if provided) — it is
/// never rethrown, so a failed snapshot must never block the wipe that
/// follows it.
Future<void> takeWipeSafetySnapshot({
  required Future<String> Function(String outputDir) createBackup,
  required Future<String> Function() resolveSafeDir,
  void Function(Object error)? onError,
}) async {
  try {
    final safeDir = await resolveSafeDir();
    await createBackup(safeDir);
  } catch (e) {
    onError?.call(e);
  }
}
