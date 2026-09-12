import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/cards/templates/media/media_card_widget.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> data,
    {VoidCallback? onTap}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MediaCardWidget(data: data, onTap: onTap)),
    ),
  );
}

void main() {
  testWidgets('renders title and type icon', (tester) async {
    await _pump(tester, {'media_type': 'movie', 'title': '奥本海默'});
    expect(find.text('奥本海默'), findsOneWidget);
    expect(find.text('🎬'), findsOneWidget);
  });

  testWidgets('renders comment and rating when present', (tester) async {
    await _pump(tester, {
      'media_type': 'book',
      'title': '三体',
      'comment': '很震撼',
      'rating': 9,
    });
    expect(find.text('📖'), findsOneWidget);
    expect(find.textContaining('很震撼'), findsOneWidget);
    expect(find.textContaining('9'), findsOneWidget);
  });

  testWidgets('renders status label when present', (tester) async {
    await _pump(tester, {
      'media_type': 'tv',
      'title': '三体',
      'media_status': 'doing',
    });
    expect(find.text('📺'), findsOneWidget);
  });

  testWidgets('tap invokes onTap', (tester) async {
    var tapped = false;
    await _pump(tester, {'media_type': 'other', 'title': 'x'},
        onTap: () => tapped = true);
    await tester.tap(find.byType(MediaCardWidget));
    expect(tapped, isTrue);
  });
}
