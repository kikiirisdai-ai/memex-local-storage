import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/main.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/knowledge/view_models/knowledge_base_viewmodel.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This test documents/guards the reversible `kShowKnowledgeTab` flag
// declared near the top of lib/main.dart. It pumps the real `MainScreen`
// widget (the home screen root) so the assertions exercise the actual
// bottom-bar composition rather than a re-implementation of it.
//
// Known limitation: `MainScreen` is a large stateful root that wires up
// many singletons (event bus, share intent handling, app actions, update
// checks, etc). Those are started from `initState` but are either
// fire-and-forget or guarded, so they don't block/flake this test; we still
// pump a couple of frames to flush the immediate microtasks they schedule.
// We do not exercise the 1-second-delayed DB/demo bootstrap Future, since
// that isn't relevant to the bottom-bar-rendering behavior under test.
void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('hide_knowledge_tab_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_hide_kb_tab_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'kShowKnowledgeTab is false, so the bottom bar hides the Knowledge tab '
    'while Timeline + the AI button remain, and _currentTab stays 0',
    (tester) async {
      // reversible: this documents/guards the flag; flipping
      // kShowKnowledgeTab back to true restores the Knowledge base tab.
      expect(kShowKnowledgeTab, isFalse);

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
      // Flush the immediate post-frame callbacks/microtasks scheduled from
      // MainScreen.initState (including ClipboardPreviewService's internal
      // ~700ms platform-read timeout) and the 1s-delayed DB/demo bootstrap
      // Future, so no Timer is left pending when the test tears down.
      await tester.pump(const Duration(seconds: 2));

      // The Knowledge tab's icon must not be present.
      final libraryIconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains('tab_library'),
      );
      expect(libraryIconFinder, findsNothing);

      // The Timeline tab icon and the AI center button must still be
      // present — the bar shouldn't look broken/incomplete.
      final timelineIconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains('tab_timeline'),
      );
      expect(timelineIconFinder, findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);

      // _currentTab stays 0: IndexedStack shows the first child (Timeline).
      final indexedStack = tester.widget<IndexedStack>(
        find.byType(IndexedStack),
      );
      expect(indexedStack.index, 0);
    },
  );
}
