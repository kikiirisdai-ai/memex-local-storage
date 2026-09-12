import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/rollup_periods.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('MonthlySummaryHandler');

const String monthlySummaryTaskType = 'monthly_summary_task';

/// Task handler for [monthlySummaryTaskType]: generates the monthly rollup
/// card for the month encoded in the payload ("YYYY-MM").
Future<void> handleMonthlySummaryImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext taskContext,
) async {
  final anchor = monthlyRollup.anchorFromPayload(payload);
  if (anchor == null) {
    _logger.warning(
        'Monthly summary task missing/invalid month: ${payload['month']}');
    return;
  }
  await RollupService.instance.generate(userId, monthlyRollup, anchor);
}
