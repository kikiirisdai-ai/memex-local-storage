import 'package:test/test.dart';
import 'package:memex/domain/models/system_card_constants.dart';

void main() {
  test('monthlySummaryTag and summaryTags', () {
    expect(monthlySummaryTag, 'MonthlySummary');
    expect(yearlySummaryTag, 'YearlySummary');
    expect(summaryTags,
        {dailySummaryTag, weeklySummaryTag, monthlySummaryTag, yearlySummaryTag});
  });
}
