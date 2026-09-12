const scheduleBriefingCardId = '_system/schedule_briefing';
const scheduleBriefingTemplateId = 'schedule_briefing';

/// Marker tags on generated summary cards. Collectors must skip cards
/// carrying any of these so summaries never feed on other summaries.
const dailySummaryTag = 'DailySummary';
const weeklySummaryTag = 'WeeklySummary';
const monthlySummaryTag = 'MonthlySummary';
const yearlySummaryTag = 'YearlySummary';
const summaryTags = {
  dailySummaryTag,
  weeklySummaryTag,
  monthlySummaryTag,
  yearlySummaryTag,
};
