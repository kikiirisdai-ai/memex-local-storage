import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/icloud_daily_backup.dart';

void main() {
  group('ymd', () {
    test('pads', () {
      expect(ymd(DateTime(2026, 9, 6)), '2026-09-06');
    });
  });

  group('planDailyRoll', () {
    const d = 'memex_daily.memex';
    const p = 'memex_daily_prev.memex';

    test('empty folder -> just write daily, no roll', () {
      final plan =
          planDailyRoll(existingNames: const [], dailyName: d, prevName: p);
      expect(plan.renameDailyToPrev, isFalse);
      expect(plan.deletePrev, isFalse);
    });

    test('only daily present -> rename daily->prev, no delete', () {
      final plan =
          planDailyRoll(existingNames: const [d], dailyName: d, prevName: p);
      expect(plan.renameDailyToPrev, isTrue);
      expect(plan.deletePrev, isFalse);
    });

    test('daily + prev present -> delete old prev then rename daily->prev', () {
      final plan =
          planDailyRoll(existingNames: const [d, p], dailyName: d, prevName: p);
      expect(plan.deletePrev, isTrue);
      expect(plan.renameDailyToPrev, isTrue);
    });

    test('only prev present (no daily) -> no roll (daily gets written fresh)',
        () {
      final plan =
          planDailyRoll(existingNames: const [p], dailyName: d, prevName: p);
      expect(plan.renameDailyToPrev, isFalse);
      expect(plan.deletePrev, isFalse);
    });
  });
}
