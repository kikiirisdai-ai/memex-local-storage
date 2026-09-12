/// Pure helpers for the iCloud daily rolling backup. No IO.
String ymd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

class DailyRollPlan {
  final bool deletePrev;
  final bool renameDailyToPrev;
  final String dailyName;
  final String prevName;
  const DailyRollPlan({
    required this.deletePrev,
    required this.renameDailyToPrev,
    required this.dailyName,
    required this.prevName,
  });
}

/// Decide the rolling actions so the folder keeps at most today's + yesterday's
/// copy. Existing today's `dailyName` becomes `prevName` (after removing any
/// stale prev); a fresh `dailyName` is then written by the caller.
DailyRollPlan planDailyRoll({
  required List<String> existingNames,
  required String dailyName,
  required String prevName,
}) {
  final hasDaily = existingNames.contains(dailyName);
  final hasPrev = existingNames.contains(prevName);
  return DailyRollPlan(
    renameDailyToPrev: hasDaily,
    deletePrev: hasDaily && hasPrev,
    dailyName: dailyName,
    prevName: prevName,
  );
}
