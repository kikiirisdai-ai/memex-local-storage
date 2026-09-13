import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/timeline/widgets/media_status_badge.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

CardDetailModel _detail({Map<String, dynamic>? metadata}) {
  return CardDetailModel(
    id: 'c1',
    title: 't',
    timestamp: DateTime(2026, 9, 7),
    address: '',
    tags: const [],
    rawContent: '',
    insight: InsightData.fromJson(const {}),
    assets: const [],
    metadata: metadata,
  );
}

Widget _buildTestableWidget(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() async {
    AppFlavor.init('global');
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  group('MediaStatusBadge', () {
    testWidgets('renders nothing for a non-media card', (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(MediaStatusBadge(detail: _detail())),
      );
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders status pill and taps', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaStatusBadge(
            detail: _detail(
                metadata: {'media_type': 'tv', 'media_status': 'doing'}),
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.byType(GestureDetector), findsOneWidget);
      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue);
    });

    testWidgets(
        'shows nothing when there is no status and no onTap (static context)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaStatusBadge(detail: _detail(metadata: {'media_type': 'tv'})),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(MediaStatusBadge),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('shows the placeholder pill with onTap even without a status',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaStatusBadge(
            detail: _detail(metadata: {'media_type': 'tv'}),
            onTap: () {},
          ),
        ),
      );
      expect(find.text('No status set'), findsOneWidget);
    });

    testWidgets('still renders the pill for a real status even without onTap',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaStatusBadge(
            detail: _detail(
                metadata: {'media_type': 'tv', 'media_status': 'doing'}),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(MediaStatusBadge),
          matching: find.byType(Container),
        ),
        findsOneWidget,
      );
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('MediaStatusPicker pops the tapped status', (tester) async {
      String? picked;
      await tester.pumpWidget(
        _buildTestableWidget(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<String>(
                  context: context,
                  builder: (_) =>
                      const MediaStatusPicker(currentStatus: 'want'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      expect(picked, 'done');
    });
  });

  group('MediaRatingBadge', () {
    testWidgets('renders nothing for a non-media card', (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(MediaRatingBadge(detail: _detail())),
      );
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders rating and comment', (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaRatingBadge(
            detail: _detail(metadata: {
              'media_type': 'book',
              'media_rating': 8,
              'media_comment': '很好看',
            }),
          ),
        ),
      );
      expect(find.textContaining('8'), findsOneWidget);
      expect(find.textContaining('很好看'), findsOneWidget);
    });

    testWidgets('shows nothing when unrated and no onTap (static context)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaRatingBadge(detail: _detail(metadata: {'media_type': 'book'})),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(MediaRatingBadge),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('shows the localized unrated placeholder with onTap',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaRatingBadge(
            detail: _detail(metadata: {'media_type': 'book'}),
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('Not rated yet'), findsOneWidget);
    });

    testWidgets('still renders the pill for a real rating even without onTap',
        (tester) async {
      await tester.pumpWidget(
        _buildTestableWidget(
          MediaRatingBadge(
            detail: _detail(metadata: {
              'media_type': 'book',
              'media_rating': 8,
              'media_comment': '很好看',
            }),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(MediaRatingBadge),
          matching: find.byType(Container),
        ),
        findsOneWidget,
      );
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('MediaRatingEditor pops the selected rating, no comment field',
        (tester) async {
      int? result;
      await tester.pumpWidget(
        _buildTestableWidget(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<int>(
                  context: context,
                  builder: (_) => const MediaRatingEditor(currentRating: 5),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('9'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, 9);
    });
  });
}
