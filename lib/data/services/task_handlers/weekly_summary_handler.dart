import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/weekly_summary_service.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('WeeklySummaryHandler');

/// Task handler for [weeklySummaryTaskType]: generates the weekly rollup
/// card for the week whose Monday is in the payload ("YYYY-MM-DD").
Future<void> handleWeeklySummaryImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext taskContext,
) async {
  final mondayStr = payload['week_monday'] as String?;
  final monday = mondayStr != null ? DateTime.tryParse(mondayStr) : null;
  if (monday == null) {
    _logger.warning('Weekly summary task missing/invalid monday: $mondayStr');
    return;
  }
  await WeeklySummaryService.instance.generate(userId, monday);
}
