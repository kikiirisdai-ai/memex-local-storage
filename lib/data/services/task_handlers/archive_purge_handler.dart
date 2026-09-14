import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';

import 'package:memex/data/repositories/get_archived_cards.dart';
import 'package:memex/data/repositories/card.dart';
import 'package:memex/data/services/archive_purge_service.dart';
import 'package:memex/data/services/local_task_executor.dart';

final _logger = Logger('ArchivePurgeHandler');

/// Whether an archived card with this `archived_at` (Unix seconds) is past
/// [archiveRetention] and should be hard-deleted. Null (never archived, or
/// somehow missing the timestamp) is never past retention.
@visibleForTesting
bool isPastArchiveRetention(int? archivedAt, {required DateTime now}) {
  if (archivedAt == null) return false;
  final cutoffSeconds =
      now.subtract(archiveRetention).millisecondsSinceEpoch ~/ 1000;
  return archivedAt <= cutoffSeconds;
}

/// Hard-deletes every archived card whose `archived_at` is older than
/// [archiveRetention] (30 days).
Future<void> handleArchivePurgeImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final archived = await getArchivedCards();
  final now = DateTime.now();

  var purged = 0;
  for (final card in archived) {
    if (!isPastArchiveRetention(card.archivedAt, now: now)) continue;
    try {
      final ok = await deleteCardEndpoint(card.id);
      if (ok) purged++;
    } catch (e, st) {
      _logger.warning('Failed to purge archived card ${card.id}', e, st);
    }
  }

  if (purged > 0) {
    _logger.info('Archive purge removed $purged card(s) past retention.');
  }
}
