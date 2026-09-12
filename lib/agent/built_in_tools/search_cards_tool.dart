import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/data/services/hybrid_card_retriever.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

/// Build a tool that lets an agent search the user's own Timeline Cards
/// (their past records/journal) and answer questions grounded in the
/// results.
///
/// Returns an [AgentToolResult] rather than a plain string so the matched
/// cards are surfaced as tappable `timeline_card` artifacts in chat (see
/// [ChatArtifact.timelineCard]); the chat UI renders `metadata['artifacts']`
/// automatically, no extra wiring needed.
Tool buildSearchCardsTool({CardRetriever? retriever}) {
  final cardRetriever = retriever ?? HybridCardRetriever.instance;

  return Tool(
    name: 'search_cards',
    description: '''Search the user's own Timeline Cards (their past records / journal entries) by keyword, optionally filtered by date range and tags.

Use this when the user asks about their own past records, e.g. "What did I do last week?", "Find my notes about X", "When did I last see the dentist?".

Always answer grounded in what this tool actually returns:
- If it returns matches, cite the source cards you used (they are also surfaced to the user as tappable cards).
- If it returns no matches, say so honestly. Do NOT fabricate or guess at content the tool didn't return.

Parameters:
- query (required): keyword(s) to search for.
- limit: max number of cards to return (default 8).
- date_from / date_to: optional date range filter, format "YYYY-MM-DD".
- tags: optional list of tags to filter by.
''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Keyword(s) to search for in the user\'s cards.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of cards to return (default: 8).',
        },
        'date_from': {
          'type': 'string',
          'description':
              'Optional start date filter, format "YYYY-MM-DD" (inclusive).',
        },
        'date_to': {
          'type': 'string',
          'description':
              'Optional end date filter, format "YYYY-MM-DD" (inclusive).',
        },
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Optional list of tags to filter by.',
        },
      },
      'required': ['query'],
    },
    executable: (
      String query,
      int? limit,
      String? dateFrom,
      String? dateTo,
      List<dynamic>? tags,
    ) async {
      final parsedDateFrom = dateFrom == null ? null : DateTime.tryParse(dateFrom);
      final parsedDateTo = dateTo == null ? null : DateTime.tryParse(dateTo);
      final parsedTags = tags?.map((t) => t.toString()).toList();

      final hits = await cardRetriever.search(
        query,
        limit: limit ?? 8,
        dateFrom: parsedDateFrom,
        dateTo: parsedDateTo,
        tags: parsedTags,
      );

      if (hits.isEmpty) {
        return AgentToolResult(
          content: TextPart('没有找到相关的记录。'),
          metadata: const {'artifacts': <Map<String, dynamic>>[]},
        );
      }

      final buffer = StringBuffer('找到 ${hits.length} 条:\n');
      for (final hit in hits) {
        buffer.writeln(
          '- ${hit.title}（${_dateFormat.format(hit.date)}）：${hit.snippet}',
        );
      }

      final artifacts = hits
          .map((hit) => ChatArtifact.timelineCard(
                cardId: hit.cardId,
                title: hit.title,
                summary: hit.snippet,
                tags: hit.tags,
                updated: false,
                operation: ChatArtifact.operationReference,
              ).toJson())
          .toList();

      return AgentToolResult(
        content: TextPart(buffer.toString().trimRight()),
        metadata: {'artifacts': artifacts},
      );
    },
  );
}
