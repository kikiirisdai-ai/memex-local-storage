import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/model/chat_artifact.dart';

void main() {
  group('ChatArtifact schema v2', () {
    test('parses a timeline card artifact with target uri metadata', () {
      final artifact = ChatArtifact.fromToolMetadata({
        'artifact': ChatArtifact.timelineCard(
          cardId: '2026/06/10.md#ts_3',
          title: '跑步',
          summary: '今天跑了 5 公里',
          imagePaths: ['fs://a.jpg', 'fs://b.jpg'],
          tags: ['Health'],
          updated: false,
          createdAt: DateTime.utc(2026, 6, 10),
        ).toJson(),
      });

      expect(artifact, isNotNull);
      expect(artifact!.version, ChatArtifact.schemaVersion);
      expect(artifact.kind, ChatArtifact.kindTimelineCard);
      expect(artifact.operation, ChatArtifact.operationCreate);
      expect(artifact.timelineCardId, '2026/06/10.md#ts_3');
      expect(artifact.summary, '今天跑了 5 公里');
      expect(artifact.imagePaths, ['fs://a.jpg', 'fs://b.jpg']);
      expect(artifact.tags, ['Health']);
    });

    test(
        'timelineCard with operation:reference cites an existing card '
        'as a source rather than marking it created/updated', () {
      final artifact = ChatArtifact.fromToolMetadata({
        'artifact': ChatArtifact.timelineCard(
          cardId: '2026/06/10.md#ts_3',
          title: '跑步',
          summary: '今天跑了 5 公里',
          updated: false,
          operation: ChatArtifact.operationReference,
          createdAt: DateTime.utc(2026, 6, 10),
        ).toJson(),
      });

      expect(artifact, isNotNull);
      expect(artifact!.operation, ChatArtifact.operationReference);
      expect(artifact.operation, isNot(ChatArtifact.operationCreate));
      expect(artifact.kind, ChatArtifact.kindTimelineCard);
      expect(artifact.timelineCardId, '2026/06/10.md#ts_3');
    });

    test('parses multiple artifacts and round-trips json', () {
      final artifacts = ChatArtifact.listFromToolMetadata({
        'artifacts': [
          ChatArtifact.knowledgeInsight(
            insightId: 'weekly-pattern',
            title: 'Weekly pattern',
            updated: false,
            createdAt: DateTime.utc(2026, 6, 10),
          ).toJson(),
          ChatArtifact.schedule(
            title: 'Schedule presentation',
            summary: 'Pending schedule items: 3',
            updated: true,
            createdAt: DateTime.utc(2026, 6, 10),
          ).toJson(),
        ],
      });

      expect(artifacts, hasLength(2));
      expect(artifacts.first.kind, ChatArtifact.kindKnowledgeInsight);
      expect(artifacts.last.kind, ChatArtifact.kindSchedule);
      expect(ChatArtifact.fromJson(artifacts.last.toJson())!.updated, isTrue);
    });

    test('normalizes knowledge file path for knowledge tab navigation', () {
      final artifact = ChatArtifact.knowledgeFile(
        path: '/PKM/Projects/memex.md',
        title: 'memex.md',
        updated: true,
      );

      expect(artifact.workspacePath, 'PKM/Projects/memex.md');
      expect(artifact.knowledgeFilePath, 'Projects/memex.md');
      expect(
        ChatArtifact.knowledgeFilePathFromWorkspacePath(
          r'\PKM\Areas\health.md',
        ),
        'Areas/health.md',
      );
      expect(
        ChatArtifact.knowledgeFilePathFromWorkspacePath(
          'Projects/memex.md',
        ),
        isNull,
      );
    });

    test('rejects missing, malformed, legacy, or unknown artifacts', () {
      expect(ChatArtifact.fromToolMetadata(null), isNull);
      expect(ChatArtifact.fromToolMetadata({}), isNull);
      expect(ChatArtifact.fromToolMetadata({'artifact': 'oops'}), isNull);
      expect(
        ChatArtifact.fromToolMetadata({
          'artifact': {'type': 'card', 'id': 'legacy'},
        }),
        isNull,
      );
      expect(
        ChatArtifact.fromToolMetadata({
          'artifact': {
            'version': ChatArtifact.schemaVersion,
            'artifact_id': 'x',
            'kind': 'alien',
            'operation': ChatArtifact.operationCreate,
          },
        }),
        isNull,
      );
    });

    test('goalSuggestion factory builds a stable id per (goalId, turnId) '
        'and round-trips json', () {
      final artifact = ChatArtifact.goalSuggestion(
        goalId: 'goal-1',
        goalTitle: '读书',
        goalType: 'quantitative',
        delta: 1,
        turnId: 'turn-1',
        createdAt: DateTime.utc(2026, 9, 11),
      );

      expect(artifact.kind, ChatArtifact.kindGoalSuggestion);
      expect(artifact.operation, ChatArtifact.operationReference);
      expect(artifact.goalSuggestionGoalId, 'goal-1');
      expect(artifact.goalSuggestionTitle, '读书');
      expect(artifact.goalSuggestionGoalType, 'quantitative');
      expect(artifact.goalSuggestionDelta, 1);

      final again = ChatArtifact.goalSuggestion(
        goalId: 'goal-1',
        goalTitle: '读书',
        goalType: 'quantitative',
        delta: 1,
        turnId: 'turn-1',
      );
      expect(again.artifactId, artifact.artifactId);

      final restored = ChatArtifact.fromJson(artifact.toJson());
      expect(restored, isNotNull);
      expect(restored!.goalSuggestionGoalId, 'goal-1');
      expect(restored.goalSuggestionDelta, 1);
    });

    test('goalSuggestion for a binary goal has a null delta', () {
      final artifact = ChatArtifact.goalSuggestion(
        goalId: 'goal-2',
        goalTitle: '学会游泳',
        goalType: 'binary',
        turnId: 'turn-1',
      );
      expect(artifact.goalSuggestionDelta, isNull);
      expect(artifact.goalSuggestionGoalType, 'binary');
    });

    test('goalSuggestion for a binary goal drops a garbage non-null delta '
        'passed by the caller', () {
      final artifact = ChatArtifact.goalSuggestion(
        goalId: 'goal-2',
        goalTitle: '学会游泳',
        goalType: 'binary',
        delta: 5.0,
        turnId: 'turn-1',
      );
      expect(artifact.goalSuggestionDelta, isNull);
      expect(artifact.goalSuggestionGoalType, 'binary');
    });

    test('different turnId produces a different artifact id for the same '
        'goal', () {
      final a = ChatArtifact.goalSuggestion(
        goalId: 'goal-1',
        goalTitle: '读书',
        goalType: 'quantitative',
        delta: 1,
        turnId: 'turn-1',
      );
      final b = ChatArtifact.goalSuggestion(
        goalId: 'goal-1',
        goalTitle: '读书',
        goalType: 'quantitative',
        delta: 1,
        turnId: 'turn-2',
      );
      expect(a.artifactId, isNot(b.artifactId));
    });
  });

  group('ChatTurnArtifactCollector', () {
    test('deduplicates by stable UI destination and adds source fields', () {
      final collector = ChatTurnArtifactCollector(sourceRunId: 'turn-1');

      final firstArtifacts = collector.addFromToolResult(
        sourceToolCallId: 'tool-1',
        metadata: {
          'artifact': ChatArtifact.timelineCard(
            cardId: '2026/06/10.md#ts_3',
            title: 'Draft',
            updated: false,
          ).toJson(),
        },
      );
      final secondArtifacts = collector.addFromToolResult(
        sourceToolCallId: 'tool-2',
        metadata: {
          'artifact': ChatArtifact.timelineCard(
            cardId: '2026/06/10.md#ts_3',
            title: 'Final',
            updated: true,
          ).toJson(),
        },
      );

      expect(firstArtifacts, hasLength(1));
      expect(secondArtifacts, isEmpty);
      expect(collector.artifacts, hasLength(1));
      expect(collector.artifacts.single.title, 'Final');
      expect(collector.artifacts.single.updated, isTrue);
      expect(collector.artifacts.single.sourceRunId, 'turn-1');
      expect(collector.artifacts.single.sourceToolCallId, 'tool-2');
    });
  });

  group('ChatArtifactSessionMigration', () {
    test('rewrites legacy session artifacts to schema v2 once', () {
      final session = <String, dynamic>{
        'messages': <dynamic>[
          {
            'role': 'ai',
            'turn_id': 'turn-legacy',
            'timestamp': '2026-06-10T12:00:00.000Z',
            'content': [
              {'type': 'text', 'text': 'done'},
            ],
            'artifacts': [
              {
                'type': 'file',
                'path': 'PKM/Projects/memex.md',
                'snippet': '# Memex',
                'updated': true,
              },
              {
                'type': 'schedule',
                'title': 'Schedule presentation',
                'updated': true,
              },
            ],
          },
        ],
      };

      final changed = ChatArtifactSessionMigration.migrateSessionData(session);

      expect(changed, isTrue);
      expect(
        session[ChatArtifactSessionMigration.schemaVersionKey],
        ChatArtifact.schemaVersion,
      );

      final message =
          (session['messages'] as List).single as Map<String, dynamic>;
      final artifacts = message['artifacts'] as List<dynamic>;
      expect(artifacts, hasLength(2));

      final fileArtifact = ChatArtifact.fromJson(
        Map<String, dynamic>.from(artifacts.first as Map),
      )!;
      expect(fileArtifact.kind, ChatArtifact.kindKnowledgeFile);
      expect(fileArtifact.workspacePath, 'PKM/Projects/memex.md');
      expect(fileArtifact.summary, '# Memex');
      expect(fileArtifact.sourceRunId, 'turn-legacy');

      final secondChanged =
          ChatArtifactSessionMigration.migrateSessionData(session);
      expect(secondChanged, isFalse);
    });
  });
}
