import 'package:memex/data/services/daily_summary_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('DailySummaryHandler');

/// Task handler for [dailySummaryTaskType]: generates the end-of-day summary
/// card for the date in the payload ("YYYY-MM-DD").
Future<void> handleDailySummaryImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext taskContext,
) async {
  final dateStr = payload['date'] as String?;
  final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
  if (date == null) {
    _logger.warning('Daily summary task missing/invalid date: $dateStr');
    return;
  }
  await DailySummaryService.instance.generate(userId, date);
}
