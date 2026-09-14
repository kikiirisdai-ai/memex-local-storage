import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('ArchivePurgeService');

const String archivePurgeTaskType = 'archive_purge_task';

/// Archived cards older than this are hard-deleted by the purge task.
const Duration archiveRetention = Duration(days: 30);

/// Checks once a day whether the archive purge task should run, and
/// enqueues it if so. Called on app launch and on foreground resume,
/// mirroring [DailySummaryService.maybeSchedule] — cheap when idle.
class ArchivePurgeService {
  ArchivePurgeService._();
  static final instance = ArchivePurgeService._();

  static const _prefLastDate = 'archive_purge_last_date';

  bool _scheduleInFlight = false;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> maybeSchedule({DateTime? now}) async {
    if (_scheduleInFlight) return;
    _scheduleInFlight = true;
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();
      final todayKey = dateKey(now ?? DateTime.now());
      if (prefs.getString(_prefLastDate) == todayKey) return;

      await LocalTaskExecutor.instance.enqueueTask(
        userId: userId,
        taskType: archivePurgeTaskType,
        payload: const {},
        priority: 5,
        bizId: 'archive_purge:$todayKey',
      );
      await prefs.setString(_prefLastDate, todayKey);
    } catch (e, st) {
      _logger.warning('Failed to schedule archive purge', e, st);
    } finally {
      _scheduleInFlight = false;
    }
  }
}
