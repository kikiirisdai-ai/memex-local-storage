import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:memex/data/services/agent_image_attachment.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/data/services/memory_sync_service.dart';
import 'package:memex/data/services/timeline_card_event_publisher.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/goal_suggestion.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('QuickCaptureService');

/// Outcome of a quick-capture attempt.
enum QuickCaptureOutcome {
  /// The message was a life record; a timeline card was written.
  card,

  /// The message was conversational; [QuickCaptureResult.replyText] holds
  /// the assistant reply to persist.
  reply,

  /// The single call could not confidently handle the message (or errored);
  /// the caller must fall through to the full super-agent pipeline.
  escalate,
}

class QuickCaptureResult {
  const QuickCaptureResult._(
    this.outcome, {
    this.replyText,
    this.cardFactId,
    this.goalSuggestions = const [],
  });

  const QuickCaptureResult.escalate() : this._(QuickCaptureOutcome.escalate);

  const QuickCaptureResult.reply(String text)
      : this._(QuickCaptureOutcome.reply, replyText: text);

  const QuickCaptureResult.card(
    String factId, {
    String? replyText,
    List<GoalSuggestion> goalSuggestions = const [],
  }) : this._(
          QuickCaptureOutcome.card,
          cardFactId: factId,
          replyText: replyText,
          goalSuggestions: goalSuggestions,
        );

  final QuickCaptureOutcome outcome;
  final String? replyText;
  final String? cardFactId;
  final List<GoalSuggestion> goalSuggestions;
}

/// Fast path for simple fragments: one LLM call decides record-vs-chat and,
/// for records, produces the timeline card directly — bypassing the
/// multi-call super-agent orchestration. Anything the gate or the model is
/// not confident about escalates to the unchanged full pipeline, so this
/// path can only make simple captures faster, never lose functionality.
class QuickCaptureService {
  QuickCaptureService._();

  static final QuickCaptureService instance = QuickCaptureService._();

  @visibleForTesting
  QuickCaptureService.forTesting({
    Future<({LLMClient client, ModelConfig modelConfig})> Function()?
        resourcesProvider,
    Future<List<Goal>> Function()? activeGoalsProvider,
  })  : _resourcesProvider = resourcesProvider,
        _activeGoalsProvider = activeGoalsProvider;

  Future<({LLMClient client, ModelConfig modelConfig})> Function()?
      _resourcesProvider;
  Future<List<Goal>> Function()? _activeGoalsProvider;

  static const int maxMessageChars = 500;
  static const int maxImages = 9;

  FileSystemService get _fs => FileSystemService.instance;

  /// Conservative admission gate. Anything outside the well-understood
  /// simple-fragment shape goes to the full pipeline.
  static bool isEligible({
    required String scene,
    required String agentName,
    required String message,
    required List<Map<String, String>>? refs,
    required int imageCount,
    required bool isQuickQuery,
    required String runMode,
  }) {
    if (isQuickQuery) return false;
    if (runMode != 'auto') return false;
    // 'super_agent_home' is what the main-screen agent dialog actually sends;
    // 'assistant' is the payload default used by programmatic senders.
    if (scene != 'super_agent_home' && scene != 'assistant') return false;
    if (agentName != 'memex_agent') return false;
    if (refs != null && refs.isNotEmpty) return false;
    if (imageCount > maxImages) return false;
    final trimmed = message.trim();
    if (trimmed.isEmpty && imageCount == 0) return false;
    if (trimmed.length > maxMessageChars) return false;
    return true;
  }

  /// Runs the single-call fast path. Never throws: any failure returns
  /// [QuickCaptureResult.escalate] so the caller falls back safely.
  Future<QuickCaptureResult> run({
    required String userId,
    required String message,
    List<InlineAgentImage> images = const [],
    List<String> imageFsFilenames = const [],
    String? audioFsFilename,
    required DateTime userMessageTime,
    bool forceCard = false,
    String? originalText,
    String? polishedStyle,
    bool verbatimText = false,
  }) async {
    final isVoiceNote = audioFsFilename != null && audioFsFilename.isNotEmpty;
    try {
      final activeGoals = await _fetchActiveGoals();
      final resources = await _loadResources();
      final decision = await _callModel(
        resources: resources,
        message: message,
        images: images,
        isVoiceNote: isVoiceNote,
        activeGoals: activeGoals,
      );

      // Voice notes must always become cards. When the model misclassifies
      // (or returns garbage) fall back to a deterministic card built from
      // the transcription, so the audio + transcript are never lost.
      if (isVoiceNote && (decision == null || decision['type'] != 'card')) {
        return await _writeCard(
          userId: userId,
          decision: {
            'type': 'card',
            'title': _fallbackVoiceTitle(message),
            'text': message.trim(),
          },
          originalMessage: message,
          userMessageTime: userMessageTime,
          imageFsFilenames: imageFsFilenames,
          audioFsFilename: audioFsFilename,
          originalText: originalText,
          polishedStyle: polishedStyle,
          verbatimText: verbatimText,
          activeGoals: activeGoals,
        );
      }

      // Callers can force a card even when the model is uncertain (escalate),
      // thinks it's chit-chat (reply), or errors out on parsing: build a
      // minimal card from the raw message so the record is never lost. Only
      // an actual model-produced card decision is left as-is.
      if (forceCard && decision?['type'] != 'card') {
        return await _writeCard(
          userId: userId,
          decision: {
            'text': message.trim(),
            'reply': '',
          },
          originalMessage: message,
          userMessageTime: userMessageTime,
          imageFsFilenames: imageFsFilenames,
          audioFsFilename: audioFsFilename,
          originalText: originalText,
          polishedStyle: polishedStyle,
          verbatimText: verbatimText,
          activeGoals: activeGoals,
        );
      }
      if (decision == null) return const QuickCaptureResult.escalate();

      switch (decision['type']) {
        case 'card':
          return await _writeCard(
            userId: userId,
            decision: decision,
            originalMessage: message,
            userMessageTime: userMessageTime,
            imageFsFilenames: imageFsFilenames,
            audioFsFilename: audioFsFilename,
            originalText: originalText,
            polishedStyle: polishedStyle,
            verbatimText: verbatimText,
            activeGoals: activeGoals,
          );
        case 'reply':
          final text = (decision['text'] as String?)?.trim();
          if (text == null || text.isEmpty) {
            return const QuickCaptureResult.escalate();
          }
          return QuickCaptureResult.reply(text);
        default:
          return const QuickCaptureResult.escalate();
      }
    } catch (e, stack) {
      _logger.warning(
          'Quick capture failed, escalating to full pipeline', e, stack);
      return const QuickCaptureResult.escalate();
    }
  }

  static String _fallbackVoiceTitle(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return '语音记录';
    return trimmed.length <= 18 ? trimmed : '${trimmed.substring(0, 18)}…';
  }

  Future<({LLMClient client, ModelConfig modelConfig})> _loadResources() {
    final provider = _resourcesProvider;
    if (provider != null) return provider();
    // Same resolution as the chat agent, so the fast path always uses the
    // model the user configured for chat.
    return UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
  }

  Future<List<Goal>> _fetchActiveGoals() async {
    final provider = _activeGoalsProvider;
    try {
      if (provider != null) return await provider();
      final goals = await GoalService.instance.getGoals();
      return goals.where((g) => g.status == 'active').toList();
    } catch (e, stack) {
      _logger.warning('Failed to fetch active goals for suggestion', e, stack);
      return const [];
    }
  }

  static String _buildSystemPrompt(List<Goal> activeGoals) {
    final goalsSection = activeGoals.isEmpty
        ? ''
        : '''

The user currently has these IN-PROGRESS goals (only suggest against this
exact list, never invent a goal that isn't here):
${activeGoals.map((g) => '- id=${g.id} title="${g.title}" type=${g.goalType}').join('\n')}

If this fragment describes making progress on one of these goals, suggest
it — but ONLY when the fragment's activity is the SAME real-world activity
as the goal's title (e.g. a goal titled "读书" matches reading text, NOT
running/walking/eating/etc. just because some goal happens to exist). A
goal being the only one in the list, or the most recently created, is
NEVER a reason to suggest it — matching is about topic, not availability.
For a quantitative goal, guess how much progress was made from the text
(e.g. "看完3章" → delta 3; if the text has no clear amount but is still
clearly that goal, e.g. "读了会书", default delta to 1); for a binary
goal, suggest it only when the text implies COMPLETION (e.g. "终于学会游
泳了"), with delta always null. Suggest AT MOST 3 goals, ordered by
confidence. When nothing matches, "goal_suggestions" is an empty list —
never guess just to fill it.
Example: goal list has only id=g1 title="读书" type=quantitative. Fragment
"今天又跑步了十分钟" is about running, not reading → goal_suggestions: [].
''';

    return '''
You are Memex quick-capture. The user sent one short fragment. Decide:

1. It is a LIFE RECORD (something they did, saw, felt, ate, thought — diary
   material) → output a timeline card.
2. It is CONVERSATION (a question, a request, chit-chat directed at you)
   → output a short reply in the user's language.
3. It needs deeper handling (multiple distinct events, explicit commands
   about existing cards/knowledge, anything you are unsure about)
   → output escalate.

A fragment that is mostly photos with little or no text is almost always a
LIFE RECORD: describe what the photos show in the card text and pick a
fitting title. Only treat a photo as conversation when the text explicitly
asks a question about it.

For cards, also gauge the mood the fragment itself expresses: mood_score is
an integer 1-10 (1 = very negative, 10 = very positive) and mood_label is
one short mood word in the SAME language as the fragment. Only score when
the text contains an explicit feeling word or emotional tone. A bare fact,
list, or plan has NO mood — use null for both, never a "neutral" score.
Examples:
- "买了西红柿和鸡蛋" → "mood_score":null,"mood_label":null
- "meeting moved to 3pm" → "mood_score":null,"mood_label":null
- "今天散步心情舒畅" → "mood_score":8,"mood_label":"舒畅"
- "so tired of this bug" → "mood_score":3,"mood_label":"frustrated"

Also detect whether the fragment is a media record — a diary note about a
book, movie, TV show, album, or podcast the user watched/read/listened to,
or plans to. When it is, fill the media_* fields; otherwise all six must be
null.
- media_type: one of "book","movie","tv","music","podcast","other", or null.
- media_status: "done" when the text says finished/watched/read/listened
  through (看完/读完/听完/追完); "doing" when it says currently
  watching/reading (在看/在读/在追); "want" when it only expresses intent
  with no progress (想看/想读); null if no media detected.
- media_rating: integer 1-10 ONLY when the text expresses a clear opinion
  about it; null otherwise — never guess a neutral score.
- media_comment: a short review in the user's own words when present,
  else null.
- media_author/media_year: only when explicitly stated in the text, else
  null.
Examples:
- "在看《三体》" → media_type:"tv", media_status:"doing", media_rating:null, media_comment:null
- "刚看完XX电影，挺好看的" → media_type:"movie", media_status:"done", media_rating:7, media_comment:"挺好看的"
- "想读《百年孤独》" → media_type:"book", media_status:"want", media_rating:null, media_comment:null
- "今天散步心情舒畅" → media_type:null, media_status:null, media_rating:null, media_comment:null
$goalsSection
For a "card" response, you MUST include every key in the schema below —
mood_score, mood_label, media_type, media_status, media_rating,
media_comment, media_author, media_year, goal_suggestions — even when
several of them are null/empty. Never drop a key from the object just
because its value is null.

Respond with STRICT JSON only, no markdown fences, one of:
{"type":"card","title":"<short title, user language>","text":"<polished markdown restating the record, user language, keep the user's meaning and tone, do not invent facts>","tags":["<1-3 topical tags>"],"mood_score":<1-10 or null>,"mood_label":"<one mood word or null>","media_type":"<book|movie|tv|music|podcast|other or null>","media_status":"<want|doing|done or null>","media_rating":<1-10 or null>,"media_comment":"<short review or null>","media_author":"<author/director or null>","media_year":"<year or null>","goal_suggestions":[{"goal_id":"<id from the list above>","delta":<positive number or null>}],"reply":"<one-sentence confirmation to show in chat>"}
{"type":"reply","text":"<your reply>"}
{"type":"escalate"}''';
  }

  Future<Map<String, dynamic>?> _callModel({
    required ({LLMClient client, ModelConfig modelConfig}) resources,
    required String message,
    required List<InlineAgentImage> images,
    bool isVoiceNote = false,
    required List<Goal> activeGoals,
  }) async {
    final userText = isVoiceNote
        ? 'This is the transcription of a voice note the user just recorded '
            '(a voice diary fragment — treat it as a LIFE RECORD and output a '
            'card). IMPORTANT: the card "text" must keep the transcription '
            'VERBATIM — you may only add punctuation, paragraph breaks, and '
            'fix obvious transcription typos. Never rephrase, summarize, or '
            'add words the user did not say:\n$message'
        : message;
    final parts = <UserContentPart>[
      TextPart(userText),
      for (final image in images) ImagePart(image.base64Data, image.mimeType),
    ];

    final systemPrompt = _buildSystemPrompt(activeGoals);

    Future<Map<String, dynamic>?> attempt({required bool strict}) async {
      final response = await resources.client.generate(
        [
          SystemMessage(strict
              ? '$systemPrompt\n\nYour previous output was not valid JSON. '
                  'Output exactly one JSON object and nothing else.'
              : systemPrompt),
          UserMessage(parts),
        ],
        modelConfig: resources.modelConfig,
        jsonOutput: true,
      );
      return _parseDecision(response.textOutput);
    }

    return await attempt(strict: false) ?? await attempt(strict: true);
  }

  @visibleForTesting
  static Map<String, dynamic>? parseDecisionForTesting(String? raw) =>
      _parseDecision(raw);

  static Map<String, dynamic>? _parseDecision(String? raw) {
    if (raw == null) return null;
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] is! String) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Tolerantly coerces a decoded JSON value into a trimmed, non-empty
  /// string. Models sometimes emit numeric-looking fields (e.g. a year) as
  /// bare JSON numbers instead of the requested string, which would throw
  /// on a direct `as String?` cast.
  static String? _asTrimmedString(Object? raw) {
    final s = switch (raw) {
      String v => v,
      num v => v.toString(),
      _ => null,
    };
    final trimmed = s?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<QuickCaptureResult> _writeCard({
    required String userId,
    required Map<String, dynamic> decision,
    required String originalMessage,
    required DateTime userMessageTime,
    List<String> imageFsFilenames = const [],
    String? audioFsFilename,
    String? originalText,
    String? polishedStyle,
    bool verbatimText = false,
    required List<Goal> activeGoals,
  }) async {
    final text = (decision['text'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      return const QuickCaptureResult.escalate();
    }
    // Polish-confirmed cards preview the user's own edited text verbatim,
    // never the model's rewrite; title/tags/mood still come from decision.
    final cardBodyText = verbatimText ? originalMessage.trim() : text;
    final title = (decision['title'] as String?)?.trim();
    final tags = (decision['tags'] is List)
        ? (decision['tags'] as List).whereType<String>().take(3).toList()
        : const <String>[];
    final moodScore = sanitizeMoodScore(decision['mood_score']);
    final moodLabel = (decision['mood_label'] as String?)?.trim();
    final mediaType = sanitizeMediaType(decision['media_type']);
    final mediaStatus = sanitizeMediaStatus(decision['media_status']);
    final mediaRating = sanitizeMoodScore(decision['media_rating']);
    final mediaComment = _asTrimmedString(decision['media_comment']);
    final mediaAuthor = _asTrimmedString(decision['media_author']);
    final mediaYear = _asTrimmedString(decision['media_year']);
    final activeGoalsById = {for (final g in activeGoals) g.id: g};
    final goalSuggestions = <GoalSuggestion>[];
    final seenGoalIds = <String>{};
    final rawGoalSuggestions = decision['goal_suggestions'];
    if (rawGoalSuggestions is List) {
      for (final raw in rawGoalSuggestions) {
        if (goalSuggestions.length >= 3) break;
        if (raw is! Map) continue;
        final goalId = _asTrimmedString(raw['goal_id']);
        final goal = goalId == null ? null : activeGoalsById[goalId];
        if (goal == null) continue;
        if (!seenGoalIds.add(goal.id)) continue;
        if (goal.goalType == 'quantitative') {
          final delta = asPositiveFinite(raw['delta']);
          if (delta == null) continue;
          goalSuggestions.add(GoalSuggestion(
            goalId: goal.id,
            goalTitle: goal.title,
            goalType: goal.goalType,
            delta: delta,
          ));
        } else {
          goalSuggestions.add(GoalSuggestion(
            goalId: goal.id,
            goalTitle: goal.title,
            goalType: goal.goalType,
          ));
        }
      }
    }
    final metadata = <String, dynamic>{
      if (moodScore != null) CardMetadataKeys.moodScore: moodScore,
      if (moodScore != null && moodLabel != null && moodLabel.isNotEmpty)
        CardMetadataKeys.moodLabel: moodLabel,
      if (originalText != null && originalText.trim().isNotEmpty)
        CardMetadataKeys.originalText: originalText.trim(),
      if (polishedStyle != null && polishedStyle.trim().isNotEmpty)
        CardMetadataKeys.polishedStyle: polishedStyle.trim(),
      if (mediaType != null) CardMetadataKeys.mediaType: mediaType,
      if (mediaType != null && mediaStatus != null)
        CardMetadataKeys.mediaStatus: mediaStatus,
      if (mediaType != null && mediaRating != null)
        CardMetadataKeys.mediaRating: mediaRating,
      if (mediaType != null && mediaComment != null)
        CardMetadataKeys.mediaComment: mediaComment,
      if (mediaType != null && mediaAuthor != null)
        CardMetadataKeys.mediaAuthor: mediaAuthor,
      if (mediaType != null && mediaYear != null)
        CardMetadataKeys.mediaYear: mediaYear,
    };

    final factId = await _fs.allocateCardFactId(userId);
    final timestampSecs = userMessageTime.millisecondsSinceEpoch ~/ 1000;
    CardData? cardData;
    try {
      cardData = await _fs.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: (title == null || title.isEmpty) ? null : title,
          fact: originalMessage.trim(),
          tags: tags.isNotEmpty ? tags : card.tags,
          metadata: metadata.isNotEmpty ? metadata : null,
          timestamp: timestampSecs,
          assets: (imageFsFilenames.isNotEmpty || audioFsFilename != null)
              ? [
                  for (final f in imageFsFilenames) '![image](fs://$f)',
                  if (audioFsFilename != null) '[audio](fs://$audioFsFilename)',
                ]
              : null,
          uiConfigs: [
            if (imageFsFilenames.length == 1)
              UiConfig(templateId: 'snapshot', data: {
                'image_url': 'fs://${imageFsFilenames.first}',
                if (title != null && title.isNotEmpty) 'caption': title,
              })
            else if (imageFsFilenames.length > 1)
              UiConfig(templateId: 'gallery', data: {
                'image_urls': [
                  for (final f in imageFsFilenames) 'fs://$f',
                ],
                if (title != null && title.isNotEmpty) 'title': title,
              }),
            if (audioFsFilename != null)
              UiConfig(templateId: 'audio_card', data: {
                'audioUrl': 'fs://$audioFsFilename',
                'content': cardBodyText,
              })
            else if (mediaType != null &&
                imageFsFilenames.isEmpty &&
                audioFsFilename == null)
              UiConfig(templateId: 'media_card', data: {
                'media_type': mediaType,
                if (mediaStatus != null) 'media_status': mediaStatus,
                'title': title ?? '',
                if (mediaComment != null) 'comment': mediaComment,
                if (mediaRating != null) 'rating': mediaRating,
              })
            else
              UiConfig(templateId: 'snippet', data: {'text': cardBodyText}),
          ],
        ),
      );
    } catch (e, stack) {
      _logger.warning('Quick capture card write threw for $factId', e, stack);
      cardData = null;
    }
    if (cardData == null) {
      // Roll back the pre-allocated placeholder so the timeline never shows
      // an empty processing card; the full pipeline will mint its own fact.
      try {
        await _fs.deleteCard(userId, factId);
      } catch (_) {}
      return const QuickCaptureResult.escalate();
    }
    await emitTimelineCardAdded(
      userId: userId,
      cardId: factId,
      cardData: cardData,
    );

    // Enqueue the new record for background long-term memory sync (batched
    // + curated by MemoryAgent), same as the chat-mode save_timeline_card
    // tool. Best-effort — quick capture must not fail because of this.
    try {
      await MemorySyncService.instance.enqueueFact(userId, factId);
    } catch (e) {
      _logger.warning('Failed to enqueue memory sync for $factId: $e');
    }

    final reply = (decision['reply'] as String?)?.trim();
    return QuickCaptureResult.card(
      factId,
      replyText: (reply == null || reply.isEmpty) ? null : reply,
      goalSuggestions: goalSuggestions,
    );
  }
}
