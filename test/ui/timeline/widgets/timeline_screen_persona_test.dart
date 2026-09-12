import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/character/widgets/persona_avatar_button.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser('persona_hide_test_user');
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_timeline_persona_');
    await FileSystemService.init(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'kShowPersonaChat is false, so the timeline header hides the companion button',
    (tester) async {
      // reversible: this documents/guards the flag; flipping kShowPersonaChat
      // back to true restores the persona chat entry point.
      expect(kShowPersonaChat, isFalse);

      final viewModel = TimelineViewModel.forTest();
      final insightViewModel = InsightViewModel(router: MemexRouter());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineScreen(
              viewModel: viewModel,
              insightViewModel: insightViewModel,
              onInputTap: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PersonaAvatarButton), findsNothing);

      viewModel.dispose();
      insightViewModel.dispose();
    },
  );
}
