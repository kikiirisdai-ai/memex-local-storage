import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/main.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/insight/widgets/insight_screen.dart';
import 'package:memex/ui/knowledge/view_models/knowledge_base_viewmodel.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The bottom-right nav slot (formerly the hidden Library tab) now always
// shows an "Insight" button that pushes InsightScreen as a full page,
// mirroring the "Timeline" button on the bottom-left.
void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('insight_bottom_nav_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_insight_nav_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'bottom-right nav slot shows Insight (not Library) and pushes '
    'InsightScreen on tap',
    (tester) async {
      final router = MemexRouter();
      final timelineViewModel = TimelineViewModel(router: router);
      final insightViewModel = InsightViewModel(router: router);
      final knowledgeBaseViewModel = KnowledgeBaseViewModel(router: router);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimelineViewModel>.value(
              value: timelineViewModel,
            ),
            ChangeNotifierProvider<InsightViewModel>.value(
              value: insightViewModel,
            ),
            ChangeNotifierProvider<KnowledgeBaseViewModel>.value(
              value: knowledgeBaseViewModel,
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MainScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // The Insight icon renders in the bottom-right slot; the old Library
      // icon never does.
      final insightIconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains('icon_agent_insight'),
      );
      expect(insightIconFinder, findsOneWidget);
      final libraryIconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains('tab_library'),
      );
      expect(libraryIconFinder, findsNothing);
      // "Insights" also appears as the existing Timeline tag chip — assert
      // at least the bottom-nav copy renders, but tap the icon (unique)
      // rather than the ambiguous text.
      expect(find.text('Insights'), findsAtLeastNWidgets(1));

      await tester.tap(insightIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(InsightScreen), findsOneWidget);
    },
  );
}
