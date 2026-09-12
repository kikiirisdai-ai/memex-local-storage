import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/search_cards_tool.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/services/card_retriever.dart';

class _FakeCardRetriever implements CardRetriever {
  _FakeCardRetriever(this.hits);

  final List<CardHit> hits;
  String? lastQuery;
  int? lastLimit;
  DateTime? lastDateFrom;
  DateTime? lastDateTo;
  List<String>? lastTags;

  @override
  Future<List<CardHit>> search(
    String query, {
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? tags,
  }) async {
    lastQuery = query;
    lastLimit = limit;
    lastDateFrom = dateFrom;
    lastDateTo = dateTo;
    lastTags = tags;
    return hits;
  }
}

void main() {
  group('buildSearchCardsTool', () {
    test('returns tappable timeline_card artifacts for each hit', () async {
      final fake = _FakeCardRetriever([
        CardHit(
          cardId: 'card-1',
          title: 'Trip to Kyoto',
          snippet: 'Visited <b>Kyoto</b> temples',
          date: DateTime(2026, 5, 1),
          tags: const ['travel'],
        ),
        CardHit(
          cardId: 'card-2',
          title: 'Ramen dinner',
          snippet: 'Had <b>ramen</b> at a local shop',
          date: DateTime(2026, 5, 2),
          tags: const ['food'],
        ),
      ]);

      final tool = buildSearchCardsTool(retriever: fake);

      final result = await tool.executable!(
        'kyoto',
        5,
        '2026-05-01',
        '2026-05-31',
        ['travel'],
      ) as AgentToolResult;

      expect(fake.lastQuery, 'kyoto');
      expect(fake.lastLimit, 5);
      expect(fake.lastDateFrom, DateTime.tryParse('2026-05-01'));
      expect(fake.lastDateTo, DateTime.tryParse('2026-05-31'));
      expect(fake.lastTags, ['travel']);

      final artifacts = result.metadata?['artifacts'] as List;
      expect(artifacts, hasLength(2));
      for (final artifact in artifacts) {
        final map = artifact as Map;
        expect(map['kind'], 'timeline_card');
        expect(map['target_uri'], contains('card-'));
        expect(
          map['operation'],
          ChatArtifact.operationReference,
          reason:
              'search_cards artifacts cite pre-existing cards as sources; '
              'they must not be labeled as newly created cards.',
        );
      }
      expect(map0(artifacts[0])['target_uri'], contains('card-1'));
      expect(map0(artifacts[1])['target_uri'], contains('card-2'));

      final text = (result.content as TextPart).text;
      expect(text, contains('Trip to Kyoto'));
      expect(text, contains('Ramen dinner'));
    });

    test('returns no-hits message and empty artifacts when nothing found',
        () async {
      final fake = _FakeCardRetriever(const []);
      final tool = buildSearchCardsTool(retriever: fake);

      final result = await tool.executable!(
        'nonexistent',
        null,
        null,
        null,
        null,
      ) as AgentToolResult;

      final text = (result.content as TextPart).text;
      expect(text, contains('没有找到'));

      final artifacts = result.metadata?['artifacts'] as List?;
      expect(artifacts ?? const [], isEmpty);
    });
  });
}

Map<String, dynamic> map0(dynamic v) => Map<String, dynamic>.from(v as Map);
