/// Which `data` key holds the editable prose for a given card template.
///
/// Only templates whose body is free text the AI writes are listed. Templates
/// whose text is just a title (event, media_card, gallery, compact, duration,
/// procedure, metric) are covered by editing the card-level title instead, and
/// structured templates (conversation, routine, insight_summary) have no
/// single prose field to edit.
const Map<String, String> cardBodyTextFields = {
  'snippet': 'text',
  'article': 'body',
  'quote': 'content',
  'classic_card': 'content',
  'snapshot': 'caption',
};

/// The prose key for [templateId], or null when the template has no editable
/// body text.
String? cardBodyTextFieldFor(String templateId) =>
    cardBodyTextFields[templateId];
