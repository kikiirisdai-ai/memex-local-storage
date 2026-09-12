import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/rollup_periods.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('YearlySummaryHandler');

const String yearlySummaryTaskType = 'yearly_summary_task';

/// Task handler for [yearlySummaryTaskType]: generates the yearly rollup
/// card for the year encoded in the payload ("YYYY").
Future<void> handleYearlySummaryImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext taskContext,
) async {
  final anchor = yearlyRollup.anchorFromPayload(payload);
  if (anchor == null) {
    _logger.warning(
        'Yearly summary task missing/invalid year: ${payload['year']}');
    return;
  }
  await RollupService.instance.generate(userId, yearlyRollup, anchor);
}
