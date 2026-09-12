import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/external_backup_channel.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'icloud-backup-test-user';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    EventBusService.instance.clearHandlers();
    await EventBusService.instance.connect();
  });

  testWidgets(
    'iOS: not configured shows iCloudNotConfigured and choose-folder button',
    (tester) async {
      await _pumpBackupPage(
        tester,
        icloudStatus: () async =>
            const ICloudFolderStatus(configured: false),
      );

      expect(find.text(UserStorage.l10n.iCloudNotConfigured), findsOneWidget);
      expect(
        find.widgetWithText(
          OutlinedButton,
          UserStorage.l10n.iCloudPickFolder,
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          UserStorage.l10n.iCloudChangeFolder,
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'iOS: configured shows folder label, last backup and change-folder button',
    (tester) async {
      await UserStorage.setICloudBackupFolderLabel(userId, 'MemexBackups');
      await UserStorage.setLastICloudDailyBackupYmd(userId, '2026-09-05');

      await _pumpBackupPage(
        tester,
        icloudStatus: () async => const ICloudFolderStatus(
          configured: true,
          displayName: 'MemexBackups',
        ),
        uploadStatus: () async => const [],
      );

      expect(
        find.text(UserStorage.l10n.iCloudFolderLabel('MemexBackups')),
        findsOneWidget,
      );
      expect(
        find.text(UserStorage.l10n.iCloudLastBackup('2026-09-05')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          UserStorage.l10n.iCloudChangeFolder,
        ),
        findsOneWidget,
      );
      expect(find.text(UserStorage.l10n.iCloudNeedsRepick), findsNothing);
    },
  );

  testWidgets('iOS: needsRepick shows red warning text', (tester) async {
    await UserStorage.setICloudBackupFolderLabel(userId, 'MemexBackups');
    await UserStorage.setICloudBackupNeedsRepick(userId, true);

    await _pumpBackupPage(
      tester,
      icloudStatus: () async => const ICloudFolderStatus(
        configured: true,
        displayName: 'MemexBackups',
      ),
      uploadStatus: () async => const [],
    );

    final finder = find.text(UserStorage.l10n.iCloudNeedsRepick);
    expect(finder, findsOneWidget);
    final textWidget = tester.widget<Text>(finder);
    expect(textWidget.style?.color, const Color(0xFFDC2626));
  });

  testWidgets(
    'iOS: hides retention-days and max-size dropdowns, shows rolling note',
    (tester) async {
      await _pumpBackupPage(
        tester,
        icloudStatus: () async =>
            const ICloudFolderStatus(configured: false),
      );

      expect(
        find.byKey(const ValueKey('auto-backup-retention-menu')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('auto-backup-max-size-menu')),
        findsNothing,
      );
      expect(find.text(UserStorage.l10n.iCloudRollingNote), findsOneWidget);
    },
  );

  testWidgets(
    'non-iOS: still shows retention-days and max-size dropdowns',
    (tester) async {
      await _pumpBackupPage(tester, isIOS: false);

      expect(
        find.byKey(const ValueKey('auto-backup-retention-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('auto-backup-max-size-menu')),
        findsOneWidget,
      );
      expect(find.text(UserStorage.l10n.iCloudRollingNote), findsNothing);
    },
  );

  testWidgets(
    'iOS: picking a folder configures it and refreshes the card',
    (tester) async {
      var configureCalls = 0;
      var triggeredBackup = false;
      var configured = false;

      await _pumpBackupPage(
        tester,
        icloudStatus: () async => ICloudFolderStatus(
          configured: configured,
          displayName: configured ? 'MemexBackups' : null,
        ),
        configureICloudFolder: (uid) async {
          configureCalls += 1;
          expect(uid, userId);
          configured = true;
          return const ExternalFolder(
            path: '/icloud/MemexBackups',
            displayName: 'MemexBackups',
          );
        },
        maybeCreateICloudDailyBackup: ({required userId, bool force = false}) async {
          triggeredBackup = true;
          expect(force, isTrue);
          return true;
        },
        uploadStatus: () async => const [],
      );

      expect(find.text(UserStorage.l10n.iCloudNotConfigured), findsOneWidget);

      final pickButtonFinder = find.widgetWithText(
        OutlinedButton,
        UserStorage.l10n.iCloudPickFolder,
      );
      await tester.ensureVisible(pickButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(pickButtonFinder);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(configureCalls, 1);
      expect(triggeredBackup, isTrue);
      expect(
        find.text(UserStorage.l10n.iCloudFolderLabel('MemexBackups')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'iOS: a non-cancelled configureFolder failure shows an error toast, not a crash',
    (tester) async {
      await _pumpBackupPage(
        tester,
        icloudStatus: () async =>
            const ICloudFolderStatus(configured: false),
        configureICloudFolder: (uid) async {
          throw PlatformException(code: 'boom', message: 'nope');
        },
      );

      final pickButtonFinder = find.widgetWithText(
        OutlinedButton,
        UserStorage.l10n.iCloudPickFolder,
      );
      await tester.ensureVisible(pickButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(pickButtonFinder);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Did not crash and reverted to the not-configured state.
      expect(find.text(UserStorage.l10n.iCloudNotConfigured), findsOneWidget);
    },
  );
}

Future<void> _pumpBackupPage(
  WidgetTester tester, {
  bool isIOS = true,
  Future<ICloudFolderStatus> Function()? icloudStatus,
  Future<ExternalFolder?> Function(String userId)? configureICloudFolder,
  Future<bool> Function({required String userId, bool force})?
      maybeCreateICloudDailyBackup,
  Future<List<ICloudUploadStatus>> Function()? uploadStatus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BackupRestorePage(
        isIOSOverride: isIOS,
        estimateBackupSize: () async => 0,
        currentBackupLocationLabel: () async => '/tmp/Backups',
        listStoredBackups: () async => const [],
        icloudStatus: icloudStatus,
        configureICloudFolder: configureICloudFolder,
        maybeCreateICloudDailyBackup: maybeCreateICloudDailyBackup,
        uploadStatus: uploadStatus,
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}
