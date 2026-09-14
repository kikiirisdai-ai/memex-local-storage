import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/cards/templates/quantifiable/mood_curve_card.dart';

Widget _host(Map<String, dynamic> data) => MaterialApp(
      home: Scaffold(
        body: MoodCurveCard(data: data),
      ),
    );

void main() {
  testWidgets('renders weekday labels and the average', (tester) async {
    await tester.pumpWidget(_host({
      'scores': [7, null, 5, 8, null, 6, 9],
      'labels': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
      'average': 7,
    }));

    expect(find.text('情绪曲线'), findsOneWidget);
    expect(find.text('均值 7/10'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
  });

  testWidgets('all-null scores renders without throwing and hides the average',
      (tester) async {
    await tester.pumpWidget(_host({
      'scores': [null, null, null, null, null, null, null],
      'labels': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
      'average': null,
    }));

    expect(find.text('情绪曲线'), findsOneWidget);
    expect(find.textContaining('均值'), findsNothing);
  });

  testWidgets('a single present score renders a lone dot without throwing',
      (tester) async {
    await tester.pumpWidget(_host({
      'scores': [null, 6, null],
      'labels': ['周一', '周二', '周三'],
      'average': 6,
    }));

    expect(find.text('均值 6/10'), findsOneWidget);
  });
}
