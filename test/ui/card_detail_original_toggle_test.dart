import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  CardDetailModel makeDetail({
    required String rawContent,
    Map<String, dynamic>? metadata,
  }) {
    return CardDetailModel(
      id: 'c',
      title: '',
      timestamp: DateTime(2026, 1, 1),
      address: '',
      tags: const [],
      rawContent: rawContent,
      insight: InsightData(text: '', relatedCards: const [], comments: const []),
      assets: const [],
      metadata: metadata,
    );
  }

  testWidgets('toggle swaps between polished body and original', (
    tester,
  ) async {
    final detail = makeDetail(
      rawContent: '润色版正文',
      metadata: const {
        'original_text': '原始输入',
        'polished_style': 'literary',
      },
    );

    await tester.pumpWidget(
      buildTestableWidget(TimelineCardDetailBodySection(detail: detail)),
    );

    expect(find.text('润色版正文'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('card_original_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('原始输入'), findsOneWidget);
  });

  testWidgets('no toggle when originalText null', (tester) async {
    final detail = makeDetail(rawContent: '正文', metadata: null);

    await tester.pumpWidget(
      buildTestableWidget(TimelineCardDetailBodySection(detail: detail)),
    );

    expect(find.byKey(const ValueKey('card_original_toggle')), findsNothing);
  });
}
