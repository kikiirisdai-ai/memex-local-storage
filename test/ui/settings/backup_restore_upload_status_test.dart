import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/external_backup_channel.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'icloud-upload-status-test-user';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    await UserStorage.saveUser(userId);
    EventBusService.instance.clearHandlers();
    await EventBusService.instance.connect();
  });

  testWidgets(
    'iOS: shows per-file badges for uploaded, uploading and not-uploaded',
    (tester) async {
      await _pumpBackupPage(
        tester,
        uploadStatus: () async => const [
          ICloudUploadStatus(
            name: 'synced.memex',
            uploaded: true,
            uploading: false,
            hasError: false,
          ),
          ICloudUploadStatus(
            name: 'uploading.memex',
            uploaded: false,
            uploading: true,
            hasError: false,
          ),
          ICloudUploadStatus(
            name: 'stuck.memex',
            uploaded: false,
            uploading: false,
            hasError: false,
          ),
          ICloudUploadStatus(
            name: 'errored.memex',
            uploaded: false,
            uploading: false,
            hasError: true,
          ),
        ],
      );

      expect(find.text('synced.memex'), findsOneWidget);
      expect(find.text('uploading.memex'), findsOneWidget);
      expect(find.text('stuck.memex'), findsOneWidget);
      expect(find.text('errored.memex'), findsOneWidget);

      expect(find.text(UserStorage.l10n.iCloudSynced), findsOneWidget);
      expect(find.text(UserStorage.l10n.iCloudUploading), findsOneWidget);
      // Both "stuck" (no flags set) and "errored" (hasError) render as
      // not-uploaded in v1.
      expect(find.text(UserStorage.l10n.iCloudNotUploaded), findsNWidgets(2));
    },
  );

  testWidgets(
    'iOS: not configured never loads or shows upload status rows',
    (tester) async {
      var calls = 0;
      await _pumpBackupPage(
        tester,
        configured: false,
        uploadStatus: () async {
          calls += 1;
          return const [
            ICloudUploadStatus(
              name: 'synced.memex',
              uploaded: true,
              uploading: false,
              hasError: false,
            ),
          ];
        },
      );

      expect(calls, 0);
      expect(find.text('synced.memex'), findsNothing);
    },
  );

  testWidgets(
    'iOS: refresh button re-runs the upload status load',
    (tester) async {
      var calls = 0;
      await _pumpBackupPage(
        tester,
        uploadStatus: () async {
          calls += 1;
          return const [
            ICloudUploadStatus(
              name: 'synced.memex',
              uploaded: true,
              uploading: false,
              hasError: false,
            ),
          ];
        },
      );

      final initialCalls = calls;
      expect(initialCalls, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('icloud-upload-status-refresh')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(calls, greaterThan(initialCalls));
    },
  );

  testWidgets(
    'iOS: auto-polls while uploading and stops once synced',
    (tester) async {
      var callCount = 0;
      await _pumpBackupPage(
        tester,
        uploadStatus: () async {
          callCount += 1;
          if (callCount == 1) {
            return const [
              ICloudUploadStatus(
                name: 'file.memex',
                uploaded: false,
                uploading: true,
                hasError: false,
              ),
            ];
          }
          return const [
            ICloudUploadStatus(
              name: 'file.memex',
              uploaded: true,
              uploading: false,
              hasError: false,
            ),
          ];
        },
      );

      expect(find.text(UserStorage.l10n.iCloudUploading), findsOneWidget);
      expect(find.text(UserStorage.l10n.iCloudSynced), findsNothing);

      // Advance past the 3s poll tick; the fake loader now returns
      // "uploaded" so the badge should flip to synced.
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text(UserStorage.l10n.iCloudSynced), findsOneWidget);
      expect(find.text(UserStorage.l10n.iCloudUploading), findsNothing);
      expect(callCount, 2);

      // No more uploading files, so the timer should have stopped: pumping
      // further ticks must not trigger additional loads.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(callCount, 2);
    },
  );

  testWidgets(
    'iOS: dispose cancels the poll timer without a pending-timer failure',
    (tester) async {
      await _pumpBackupPage(
        tester,
        uploadStatus: () async => const [
          ICloudUploadStatus(
            name: 'file.memex',
            uploaded: false,
            uploading: true,
            hasError: false,
          ),
        ],
      );

      expect(find.text(UserStorage.l10n.iCloudUploading), findsOneWidget);

      // Let one poll tick elapse so the periodic timer is definitely
      // running, then tear the widget down. If dispose() didn't cancel the
      // timer, flutter_test's pending-timer check would fail this test.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'iOS: disposing while a second upload-status fetch is in flight after '
    'the poll cap stopped the Timer starts no new timer',
    (tester) async {
      // This reproduces the exact pre-fix bug: the poll-cap stops the Timer
      // (setting the timer field back to null) WITHOUT touching
      // `_uploadStatuses` (it returns before ever fetching again), so the
      // last known status still reports uploading:true. If a *second*,
      // still-in-flight fetch (e.g. a manual refresh) then resolves after
      // dispose, the pre-fix code's unconditional `_syncUploadStatusPolling()`
      // reads that stale uploading:true and calls `_startUploadStatusPolling`
      // — and because the Timer field is null (cap already stopped it),
      // the guard `if (_uploadStatusPollTimer != null) return;` does NOT
      // stop it, so it creates a BRAND NEW Timer on the disposed State.
      // (Disposing while the Timer is still actively running does NOT
      // reproduce the bug: `dispose()` cancels the Timer but leaves the
      // field non-null, so `_startUploadStatusPolling`'s "already running"
      // guard would coincidentally suppress a new one anyway.)
      var callCount = 0;
      final pendingFetchCompleter = Completer<List<ICloudUploadStatus>>();
      var pendingFetchStarted = false;

      const uploadingStatus = [
        ICloudUploadStatus(
          name: 'file.memex',
          uploaded: false,
          uploading: true,
          hasError: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupRestorePage(
            isIOSOverride: true,
            estimateBackupSize: () async => 0,
            currentBackupLocationLabel: () async => '/tmp/Backups',
            listStoredBackups: () async => const [],
            icloudStatus: () async => const ICloudFolderStatus(
              configured: true,
              displayName: 'MemexBackups',
            ),
            uploadStatus: () {
              callCount += 1;
              // Every call up to and including the poll-cap resolves
              // immediately with the same "uploading" status, so the file
              // never finishes and the Timer only ever stops via the cap.
              // Once the cap has stopped the Timer, the *next* call (the
              // manual refresh triggered below) hangs on a Completer.
              if (!pendingFetchStarted) {
                return Future.value(uploadingStatus);
              }
              return pendingFetchCompleter.future;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // Sanity: the first load completed, the poll Timer is running.
      expect(find.text(UserStorage.l10n.iCloudUploading), findsOneWidget);
      final callsAfterFirstLoad = callCount;
      expect(callsAfterFirstLoad, 1);

      // Drive the auto-poll Timer until the ~30s cap stops it (the file
      // keeps reporting "uploading", so nothing else would ever stop it).
      // Once a tick no longer increases callCount, the cap fired without
      // fetching and the Timer field is back to null.
      var lastCallCount = callCount;
      var capped = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 3));
        if (callCount == lastCallCount) {
          capped = true;
          break;
        }
        lastCallCount = callCount;
      }
      expect(
        capped,
        isTrue,
        reason: 'expected the poll cap to stop the Timer within 20 ticks',
      );
      final callsAtCap = callCount;

      // Now trigger a fresh, still-pending fetch via the manual refresh
      // button — this is the "second in-flight fetch" the reviewer asked
      // for, issued only after the Timer has already been stopped by the
      // cap (so its field is null, not just cancelled-but-non-null as
      // dispose() would leave it).
      pendingFetchStarted = true;
      await tester.tap(
        find.byKey(const ValueKey('icloud-upload-status-refresh')),
      );
      await tester.pump();
      expect(callCount, callsAtCap + 1);

      // Dispose the page while that refresh fetch is still in flight.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Resolve the stale fetch with another "uploading" status after
      // dispose. With the fix, the mounted guard covers
      // `_syncUploadStatusPolling()` too, so nothing (re)starts and this
      // completes cleanly. Without the fix, this recreates a Timer on the
      // disposed State and flutter_test's pending-timer check fails the
      // test at teardown.
      pendingFetchCompleter.complete(uploadingStatus);
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _pumpBackupPage(
  WidgetTester tester, {
  bool configured = true,
  Future<List<ICloudUploadStatus>> Function()? uploadStatus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BackupRestorePage(
        isIOSOverride: true,
        estimateBackupSize: () async => 0,
        currentBackupLocationLabel: () async => '/tmp/Backups',
        listStoredBackups: () async => const [],
        icloudStatus: () async => ICloudFolderStatus(
          configured: configured,
          displayName: configured ? 'MemexBackups' : null,
        ),
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
