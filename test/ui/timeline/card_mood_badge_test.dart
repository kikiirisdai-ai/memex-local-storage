import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/timeline/widgets/card_mood_badge.dart';

CardDetailModel _detail({Map<String, dynamic>? metadata}) {
  return CardDetailModel(
    id: 'c1',
    title: 't',
    timestamp: DateTime(2026, 7, 18),
    address: '',
    tags: const [],
    rawContent: '',
    insight: InsightData.fromJson(const {}),
    assets: const [],
    metadata: metadata,
  );
}

Future<void> _pump(WidgetTester tester, CardDetailModel detail) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: CardMoodBadge(detail: detail))),
  );
}

void main() {
  testWidgets('renders label, score, and derived emoji', (tester) async {
    await _pump(
        tester, _detail(metadata: {'mood_score': 7, 'mood_label': '满足'}));
    expect(find.text('🙂 满足 · 7/10'), findsOneWidget);
  });

  testWidgets('label with its own emoji gets no derived emoji',
      (tester) async {
    await _pump(
        tester, _detail(metadata: {'mood_score': 8, 'mood_label': '惬意 🌞'}));
    expect(find.text('惬意 🌞 · 8/10'), findsOneWidget);
  });

  testWidgets('score without label still renders', (tester) async {
    await _pump(tester, _detail(metadata: {'mood_score': 3}));
    expect(find.text('😕 3/10'), findsOneWidget);
  });

  testWidgets('renders nothing without mood metadata', (tester) async {
    await _pump(tester, _detail());
    expect(find.byType(Text), findsNothing);

    await _pump(tester, _detail(metadata: {'mood_score': 99}));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('user rating overrides AI score and hides the AI label',
      (tester) async {
    await _pump(
      tester,
      _detail(metadata: {
        'mood_score': 7,
        'mood_label': '满足',
        'user_mood_score': 3,
      }),
    );
    expect(find.text('😕 3/10'), findsOneWidget);
  });

  testWidgets('mood-less card with onTap shows the ghost pill and taps',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardMoodBadge(detail: _detail(), onTap: () => tapped = true),
        ),
      ),
    );
    expect(find.text('😶'), findsOneWidget);
    await tester.tap(find.text('😶'));
    expect(tapped, isTrue);
  });

  testWidgets('MoodScorePicker pops the tapped score', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<int>(
                  context: context,
                  builder: (_) => const MoodScorePicker(currentScore: 7),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    expect(picked, 9);
  });

  test('emojiForScore covers the full range', () {
    expect(CardMoodBadge.emojiForScore(10), '😄');
    expect(CardMoodBadge.emojiForScore(6), '🙂');
    expect(CardMoodBadge.emojiForScore(5), '😐');
    expect(CardMoodBadge.emojiForScore(2), '😕');
    expect(CardMoodBadge.emojiForScore(1), '😞');
  });
}
