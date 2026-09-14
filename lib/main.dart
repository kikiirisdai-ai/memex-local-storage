import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:memex/config/dependencies.dart';
import 'package:memex/config/app_config.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/insight/widgets/insight_screen.dart';
import 'package:memex/ui/knowledge/view_models/knowledge_base_viewmodel.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/ui/knowledge/widgets/knowledge_base_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/ui/app_lock/widgets/lock_screen_page.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/themes/app_theme.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:memex/ui/settings/widgets/ai_service_setup_page.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/file_import_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/agent_background_task_service.dart';
import 'package:memex/data/services/agent_queue_background_worker.dart';
import 'package:memex/data/services/file_logger_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/whisper_service.dart';
import 'package:memex/data/services/streaming_transcriber.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:workmanager/workmanager.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/ui/agent_activity/widgets/agent_activity_widget.dart';
import 'package:memex/ui/main_screen/widgets/ai_core_button.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/local_server_service.dart';
import 'package:memex/data/services/app_update_service.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/data/services/onboarding_service.dart';
import 'package:memex/data/services/daily_summary_service.dart';
import 'package:memex/data/services/archive_purge_service.dart';
import 'package:memex/data/services/rollup_periods.dart';
import 'package:memex/data/services/rollup_service.dart';
import 'package:memex/data/services/summary_notification_service.dart';
import 'package:memex/data/services/weekly_summary_service.dart';
import 'package:memex/data/services/demo_service.dart';
import 'package:memex/ui/core/widgets/demo_overlay.dart';
import 'package:memex/ui/main_screen/widgets/share_intent_handler.dart';
import 'package:memex/ui/settings/widgets/backup_restore_confirm_dialog.dart';
import 'package:memex/ui/settings/view_models/data_import_viewmodel.dart';
import 'package:memex/ui/settings/widgets/data_import_page.dart';
import 'package:memex/ui/chat/widgets/open_super_agent_dialog.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:memex/data/services/app_action_link_service.dart';
import 'package:memex/data/services/app_action_service.dart';
import 'package:memex/data/services/speech_transcription_service.dart';
import 'package:memex/utils/wakelock_manager.dart';
import 'package:memex/data/services/clipboard_preview_service.dart';
import 'package:memex/ui/main_screen/widgets/clipboard_preview_card.dart';
import 'package:memex/utils/result.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<RootShellState> rootShellKey = GlobalKey<RootShellState>();

// reversible: flip to true to restore the Knowledge base tab. When false,
// the bottom nav bar only shows Timeline + the center AI button; the
// Knowledge base tab, its `_currentTab == 1` state, and the onboarding demo
// step that points at it are all skipped/no-ops. The KnowledgeBaseScreen
// widget, its ViewModel/provider, and all knowledge code remain intact.
const bool kShowKnowledgeTab = false;

/// Workmanager's single global background-task entry point. MUST be a
/// top-level function. Currently only the agent-queue drain task runs
/// through here; unrecognized/legacy task names are treated as no-ops.
@pragma('vm:entry-point')
void callbackDispatcher() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    debugPrint(
      'BackgroundCallback: Starting... (Isolate: ${Isolate.current.debugName})',
    );

    final logger = getLogger('BackgroundCallback');
    try {
      await setupLogger();
    } catch (e) {
      debugPrint('BackgroundCallback: Logger setup failed: $e');
    }

    try {
      if (AgentQueueBackgroundWorker.isAgentQueueDrainTask(task)) {
        return await AgentQueueBackgroundWorker.run();
      }
      logger.info('BackgroundCallback: Unrecognized task "$task", ignoring.');
      return true;
    } catch (e) {
      logger.severe('Error in background task execution: $e');
      return false; // Retry if needed
    } finally {
      await FileLoggerService.instance.dispose();
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flavor from platform (set by --flavor flag)
  AppFlavor.init(appFlavor);

  await setupLogger();

  if (kDebugMode || AppFlavor.isDev) {
    await WakelockManager.acquire('debug_session');
  }

  // Initialize l10n
  await UserStorage.initL10n();

  // Initialize Workmanager (for background tasks)
  await Workmanager().initialize(callbackDispatcher);

  await AgentBackgroundTaskService.instance.initializeNativeBridge();

  // Initialize the summary-reminder local notification service and wire
  // tapping a reminder to bring the app to the home/timeline screen.
  SummaryNotificationService.instance.onReminderTapped = () {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    GoRouter.of(context).go(AppRoutes.home);
  };
  // Do NOT block app startup on notification init: if the local-notification
  // plugin init hangs or throws on device, it must not prevent the app from
  // launching. Run it fire-and-forget with its own error guard.
  unawaited(() async {
    try {
      await SummaryNotificationService.instance.init();
      await SummaryNotificationService.instance.maybeFirstLaunchEnable();
    } catch (e, st) {
      debugPrint('SummaryNotificationService init failed (non-fatal): $e\n$st');
    }
  }());

  // MemexRouter is provided via config/dependencies.dart and created on first read

  // Start local HTTP server
  await LocalServerService.start();

  // Set status bar style & enable edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final appRouter = createAppRouter(
    rootNavigatorKey,
    () => RootShell(key: rootShellKey),
  );

  // Initialize quick actions (app icon long-press shortcuts).
  const QuickActions quickActions = QuickActions();
  quickActions.initialize((String shortcutType) {
    AppActionService.instance.handleAction(
      shortcutType,
      source: 'quick_action',
    );
  });
  unawaited(AppActionLinkService.instance.initialize());

  runApp(
    MultiProvider(
      providers: dependencyProviders,
      child: MemexApp(router: appRouter),
    ),
  );
}

/// Root route content: user check then loading / UserSetupScreen / MainScreen (Compass-style).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> {
  bool _hasUser = false;
  bool _onboardingComplete = false;
  bool _isChecking = true;
  bool _isLoadingFromICloud = false;
  int _mainScreenEpoch =
      0; // incremented to force full rebuild on storage switch

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    var onboardingDone = await OnboardingService.isOnboardingComplete();

    // Migration: existing users who set up before the onboarding flag was added
    // should be treated as onboarding-complete.
    if (hasUser && !onboardingDone) {
      final configs = await UserStorage.getLLMConfigs();
      final hasValidConfig = configs.any((c) => c.isValid);
      if (hasValidConfig) {
        await OnboardingService.markOnboardingComplete();
        onboardingDone = true;
      }
    }

    if (mounted) {
      setState(() {
        _hasUser = hasUser;
        _onboardingComplete = onboardingDone;
        _isChecking = false;
      });
    }
  }

  void _onUserCreated() async {
    // Check iCloud BEFORE any other awaits to avoid timing issues
    final userId = await UserStorage.getUserId();
    bool isICloud = false;
    if (userId != null) {
      final loc = await UserStorage.getWorkspaceStorageLocation(userId);
      isICloud = loc == StorageLocation.icloud;
    }

    await OnboardingService.markOnboardingComplete();

    if (isICloud && mounted) {
      setState(() => _isLoadingFromICloud = true);
      // Wait for the loading UI to actually render before starting heavy work
      await Future.delayed(const Duration(milliseconds: 100));
      await MemexRouter().applyWorkspaceStorageChange();
      if (mounted) {
        setState(() {
          _isLoadingFromICloud = false;
          _hasUser = true;
          _onboardingComplete = true;
        });
      }
    } else if (mounted) {
      setState(() {
        _hasUser = true;
        _onboardingComplete = true;
      });
    }
  }

  /// Reset state and re-check user. Called after account deletion or storage switch.
  void resetAndRecheck() {
    setState(() {
      _hasUser = false;
      _onboardingComplete = false;
      _isChecking = true;
      _mainScreenEpoch++;
    });
    _checkUser();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: AgentLogoLoading()));
    }
    if (_isLoadingFromICloud) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AgentLogoLoading(),
              const SizedBox(height: 16),
              Text(
                UserStorage.l10n.loadingFromICloud,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hasUser || !_onboardingComplete) {
      return UserSetupScreen(onUserCreated: _onUserCreated);
    }
    return MultiProvider(
      key: ValueKey(_mainScreenEpoch),
      providers: [
        ChangeNotifierProvider<TimelineViewModel>(
          create: (c) =>
              TimelineViewModel(router: c.read<MemexRouter>())..init(),
        ),
        ChangeNotifierProvider<InsightViewModel>(
          create: (c) =>
              InsightViewModel(router: c.read<MemexRouter>())..loadData(),
        ),
        ChangeNotifierProvider<KnowledgeBaseViewModel>(
          create: (c) => KnowledgeBaseViewModel(router: c.read<MemexRouter>())
            ..fetchData(),
        ),
      ],
      child: const MainScreen(),
    );
  }
}

class MemexApp extends StatefulWidget {
  const MemexApp({super.key, required this.router});

  final GoRouter router;

  @override
  State<MemexApp> createState() => _MemexAppState();
}

class _MemexAppState extends State<MemexApp> with WidgetsBindingObserver {
  bool _hasUser = false;
  bool _isLocked = true; // Default to locked on start
  bool _requiresAuth = true; // Whether actual authentication is required
  DateTime? _lastPausedTime; // Track when app was paused

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUser();
    _checkLockSettings();
  }

  Future<void> _checkLockSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (mounted) {
      setState(() {
        // If lock is strictly required only when enabled, we update _isLocked.
        // Default _isLocked is true. If disabled, we unlock immediately.
        if (!isLockEnabled) {
          _isLocked = false;
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(
        LocalTaskExecutor.instance.recordGracefulShutdown(
          reason: 'app_lifecycle_paused',
        ),
      );
      unawaited(AgentBackgroundTaskService.instance.onAppPaused());
      _lastPausedTime = DateTime.now();
      _checkLockSettingsBeforeLocking();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(LocalTaskExecutor.instance.clearGracefulShutdownMarker());
      unawaited(AgentBackgroundTaskService.instance.onAppResumed());
      MemexRouter().scheduleAutoBackupCheck(trigger: 'foreground');
      _checkGracePeriod();
    } else if (state == AppLifecycleState.detached) {
      unawaited(
        LocalTaskExecutor.instance.recordGracefulShutdown(
          reason: 'app_lifecycle_detached',
        ),
      );
    }
  }

  Future<void> _checkLockSettingsBeforeLocking() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (isLockEnabled && mounted) {
      setState(() {
        _isLocked = true;
        _requiresAuth = false; // Just show privacy screen initially
      });
    }
  }

  Future<void> _checkGracePeriod() async {
    if (!_isLocked) return;

    if (_lastPausedTime != null) {
      final difference = DateTime.now().difference(_lastPausedTime!);
      // If less than 5 minutes, unlock automatically
      if (difference.inMinutes < 5) {
        if (mounted) {
          setState(() {
            _isLocked = false;
          });
        }
      } else {
        // More than 5 minutes, require auth
        if (mounted) {
          setState(() {
            _requiresAuth = true;
          });
        }
      }
    } else {
      // No pause time recorded (e.g. cold start), require auth
      if (mounted) {
        setState(() {
          _requiresAuth = true;
        });
      }
    }
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    if (mounted) {
      setState(() {
        _hasUser = hasUser;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: UserStorage.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp.router(
          title: 'Memex',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode
              .light, // Unified light mode, disabling adaptive dark mode
          locale: locale,
          routerConfig: widget.router,
          builder: (context, child) {
            return _AppActionReadiness(
              canHandleActions: !_isLocked,
              child: Stack(
                children: [
                  if (child != null) child,
                  const DemoOverlay(),
                  if (_isLocked && _hasUser)
                    _requiresAuth
                        ? LockScreen(
                            onUnlock: () {
                              setState(() {
                                _isLocked = false;
                              });
                            },
                          )
                        : const PrivacyScreen(),
                ],
              ),
            );
          },
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}

class _AppActionReadiness extends InheritedWidget {
  const _AppActionReadiness({
    required this.canHandleActions,
    required super.child,
  });

  final bool canHandleActions;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AppActionReadiness>()
            ?.canHandleActions ??
        true;
  }

  @override
  bool updateShouldNotify(_AppActionReadiness oldWidget) {
    return canHandleActions != oldWidget.canHandleActions;
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentTab = 0;
  final GlobalKey<TimelineScreenState> _timelineKey =
      GlobalKey<TimelineScreenState>();
  final GlobalKey<KnowledgeBaseScreenState> _knowledgeBaseKey =
      GlobalKey<KnowledgeBaseScreenState>();
  final MemexRouter _memexRouter = MemexRouter();
  final EventBusService _eventBus = EventBusService.instance;
  final ClipboardPreviewService _clipboardPreviewService =
      ClipboardPreviewService.instance;
  Timer? _memoryButtonTapTimer;
  int _memoryButtonTapCount = 0;
  bool _isRestoringExternalBackup = false;
  bool _isImportingSharedFiles = false;
  final Logger _logger = getLogger('MainScreen');

  // Quick voice recording state (mic nav button)
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;
  StreamingTranscriber? _quickTranscriber;
  StreamSubscription<Uint8List>? _quickAudioSub;
  final List<int> _quickPcmBuffer = [];
  String _quickTranscribedText = '';
  String? _quickAudioPath;
  final GlobalKey _aiButtonKey = GlobalKey();
  bool _isInvalidConfigDialogShowing = false;
  bool _isErrorNotificationDialogShowing = false;
  bool _earlyUpdateCheckStarted = false;
  late final ShareIntentHandler _shareIntentHandler;
  ClipboardPreviewCandidate? _homeClipboardCandidate;
  bool _isCheckingHomeClipboard = false;
  StreamSubscription<String>? _appActionSubscription;
  bool _canHandleAppActions = false;
  bool _hasRequestedInitialAppActionCheck = false;
  bool _isAppActionCheckScheduled = false;

  // Agent Button Position - REMOVED (Moved to Main App)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DemoService.instance.addListener(_onDemoChanged);
    // Init event bus connection and local DB (delay to ensure token is loaded)
    Future.delayed(const Duration(seconds: 1), () async {
      final userId = await UserStorage.getUserId();
      if (userId != null && !AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      _eventBus.connect();

      // Start onboarding demo on first launch
      if (userId != null) {
        DemoService.instance.start(userId);
      }

      // Catch-up check: generate the daily summary if one is due
      // (after 21:00 with none for today, or yesterday was missed).
      unawaited(DailySummaryService.instance.maybeSchedule());
      unawaited(WeeklySummaryService.instance.maybeSchedule());
      unawaited(RollupService.instance.maybeSchedule(monthlyRollup));
      unawaited(RollupService.instance.maybeSchedule(yearlyRollup));
      unawaited(ArchivePurgeService.instance.maybeSchedule());
      unawaited(SummaryNotificationService.instance.reschedule());
    });

    // Start auto input collection and quantity check
    _logger.info('initState: Starting Auto Input collection check...');

    _eventBus.addHandler(
      EventBusMessageType.invalidModelConfig,
      _handleInvalidModelConfig,
    );
    _eventBus.addHandler(
      EventBusMessageType.errorNotification,
      _handleErrorNotification,
    );
    _eventBus.addHandler(
      EventBusMessageType.memorySyncCompleted,
      _handleMemorySyncCompleted,
    );

    _shareIntentHandler = ShareIntentHandler(
      logger: _logger,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      onSharedDraft: (data) {
        if (!mounted) return;
        setState(() => _homeClipboardCandidate = null);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openSuperAgentDialog(
            initialDraftText: data.text,
            initialImages: data.images,
            initialImageOriginalFilenames:
                _originalFilenamesFromImages(data.images),
          );
        });
      },
      onBackupFileShared: _handleExternalBackupFile,
      onImportFilesShared: _handleSharedImportFiles,
    )..init();

    AppActionService.instance.attach();
    _appActionSubscription = AppActionService.instance.actionStream.listen((_) {
      _consumeAppActionIfReady(waitForLateAction: false);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkHomeClipboardPreview());
    });
    _scheduleEarlyUpdateCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final canHandleActions = _AppActionReadiness.of(context);
    _canHandleAppActions = canHandleActions;

    if (!_canHandleAppActions) return;
    if (!_hasRequestedInitialAppActionCheck) {
      _hasRequestedInitialAppActionCheck = true;
      _consumeAppActionIfReady(waitForLateAction: true);
      return;
    }
    if (AppActionService.instance.hasPendingAction) {
      _consumeAppActionIfReady(waitForLateAction: false);
    }
  }

  void _scheduleEarlyUpdateCheck() {
    final service = AppUpdateService.instance;
    if (!service.isSupported || _earlyUpdateCheckStarted) return;
    _earlyUpdateCheckStarted = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(_checkEarlyUpdateInBackground());
    });
  }

  Future<void> _checkEarlyUpdateInBackground() async {
    final service = AppUpdateService.instance;
    if (!await service.shouldRunAutoCheck()) return;

    try {
      final settings = await service.loadSettings();
      final result = await service.checkForUpdate(manual: false);
      if (!mounted || result.status != AppUpdateCheckStatus.updateAvailable) {
        return;
      }

      final update = result.update!;
      if (settings.autoDownloadAndInstall) {
        await _downloadAndInstallEarlyUpdate(update);
      } else {
        _showEarlyUpdateDialog(update);
      }
    } catch (e, st) {
      _logger.warning('Early update check failed: $e', e, st);
    }
  }

  void _showEarlyUpdateDialog(AppUpdateInfo update) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        final notes = update.releaseNotes.trim();
        return AlertDialog(
          title: Text(UserStorage.l10n.earlyUpdateDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserStorage.l10n.earlyUpdateFound(
                    update.versionName,
                    update.buildNumber,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    UserStorage.l10n.earlyUpdateReleaseNotes,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(notes, maxLines: 8, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(UserStorage.l10n.cancel),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_downloadAndInstallEarlyUpdate(update));
              },
              icon: const Icon(Icons.download, size: 18),
              label: Text(UserStorage.l10n.earlyUpdateDownloadAndInstall),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstallEarlyUpdate(AppUpdateInfo update) async {
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      ToastHelper.showInfo(
        context,
        UserStorage.l10n.earlyUpdateDownloadingPercent(0),
      );
    }

    try {
      final download = await AppUpdateService.instance.downloadUpdate(update);
      final install = await AppUpdateService.instance.installUpdate(
        download.apkPath,
      );
      switch (install.status) {
        case AppUpdateInstallStatus.started:
          ToastHelper.showSuccessWithKey(
            rootScaffoldMessengerKey,
            UserStorage.l10n.earlyUpdateInstallStarted,
          );
        case AppUpdateInstallStatus.permissionRequired:
          ToastHelper.showInfoWithKey(
            rootScaffoldMessengerKey,
            UserStorage.l10n.earlyUpdateInstallPermissionRequired,
          );
        case AppUpdateInstallStatus.unsupported:
          break;
      }
    } catch (e) {
      if (e is AppUpdateWifiRequiredException) {
        ToastHelper.showInfoWithKey(
          rootScaffoldMessengerKey,
          UserStorage.l10n.earlyUpdateSkippedMobile,
        );
      } else {
        ToastHelper.showErrorWithKey(rootScaffoldMessengerKey, e);
      }
    }
  }

  void _handleInvalidModelConfig(EventBusMessage message) {
    if (!mounted) return;
    if (message is! InvalidModelConfigMessage) return;

    // Check if dialog is already showing to prevent stacking
    if (_isInvalidConfigDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isInvalidConfigDialogShowing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.warning),
        content: Text(
          UserStorage.l10n.invalidModelConfigDetailed(
            message.agentId,
            message.configKey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isInvalidConfigDialogShowing = false);
              }
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isInvalidConfigDialogShowing = false);
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AppConfig.enableMemexModelService
                      ? const AiServiceSetupPage()
                      : const ModelConfigListPage(),
                ),
              );
            },
            child: Text(UserStorage.l10n.modelConfig),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isInvalidConfigDialogShowing = false);
      }
    });
  }

  void _handleMemorySyncCompleted(EventBusMessage message) {
    if (message is! MemorySyncCompletedMessage) return;
    ToastHelper.showSuccessWithKey(
      rootScaffoldMessengerKey,
      UserStorage.l10n.memorySyncCompletedToast,
    );
  }

  void _handleErrorNotification(EventBusMessage message) {
    if (!mounted) return;
    if (message is! ErrorNotificationMessage) return;
    if (_isErrorNotificationDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isErrorNotificationDialogShowing = true);

    final isAuthError = message.errorCategory == 'authenticationError';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.llmErrorDialogTitle),
        content: Text(message.errorMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isErrorNotificationDialogShowing = false);
              }
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          if (isAuthError)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  setState(() => _isErrorNotificationDialogShowing = false);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AppConfig.enableMemexModelService
                        ? const AiServiceSetupPage()
                        : const ModelConfigListPage(),
                  ),
                );
              },
              child: Text(UserStorage.l10n.goToModelConfig),
            ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _isErrorNotificationDialogShowing = false);
    });
  }

  void _onDemoChanged() {
    if (!mounted) return;
    final demo = DemoService.instance;

    // When demo advances to tapKnowledgeTab, refresh the knowledge base
    // so the demo-written guide file appears.
    if (demo.currentStep == DemoStep.tapKnowledgeTab) {
      if (!kShowKnowledgeTab) {
        // The Knowledge tab is hidden, so there's no way to tap through to
        // this step (its GestureDetector isn't rendered). Skip it so the
        // demo doesn't dead-end pointing at a nonexistent tab.
        demo.advance();
        return;
      }
      _knowledgeBaseKey.currentState?.scrollToTopAndRefresh();
    }

    setState(() {});
  }

  Future<void> _handleAICoreButtonTap() async {
    if (!mounted) return;

    if (DemoService.instance.currentStep == DemoStep.tapSend) {
      setState(() => _homeClipboardCandidate = null);
      _openSuperAgentDialog(initialDraftText: DemoService.instance.prefillText);
      return;
    }

    if (_homeClipboardCandidate != null) {
      setState(() => _homeClipboardCandidate = null);
    }

    _openSuperAgentDialog();
  }

  void _openSuperAgentDialog({
    String? initialDraftText,
    List<XFile> initialImages = const [],
    Map<String, String> initialImageOriginalFilenames = const {},
    String? initialAudioPath,
  }) {
    openSuperAgentDialog(
      context,
      initialDraftText: initialDraftText,
      initialImages: initialImages,
      initialImageOriginalFilenames: initialImageOriginalFilenames,
      initialAudioPath: initialAudioPath,
      onOpenScheduleTab: _openScheduleTabFromArtifact,
    );
  }

  void _openScheduleTabFromArtifact() {
    if (!mounted) return;
    setState(() => _currentTab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timelineKey.currentState?.openScheduleTab();
    });
  }

  Map<String, String> _originalFilenamesFromImages(List<XFile> images) {
    return {
      for (final image in images)
        if (image.name.trim().isNotEmpty) image.path: image.name,
    };
  }

  /// Mic button: first tap starts a quick voice recording, second tap
  /// stops it and opens the Super Agent dialog prefilled with the
  /// transcript (or the raw audio, if transcription produced nothing).
  Future<void> _handleMicButtonTap() async {
    if (!mounted) return;

    if (_recordingPath != null) {
      await _stopRecording(cancel: false);
      if (!mounted) return;
      if (_quickTranscribedText.isNotEmpty) {
        _openSuperAgentDialog(
          initialDraftText: _quickTranscribedText,
          initialAudioPath: _quickAudioPath,
        );
      } else if (_quickAudioPath != null) {
        ToastHelper.showInfo(context, UserStorage.l10n.speechNoResult);
      }
      _quickTranscribedText = '';
      _quickAudioPath = null;
      _recordingPath = null;
      if (mounted) setState(() {});
      return;
    }

    HapticFeedback.mediumImpact();
    await _startRecording();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DemoService.instance.removeListener(_onDemoChanged);
    WidgetsBinding.instance.removeObserver(this);
    _memoryButtonTapTimer?.cancel();
    _appActionSubscription?.cancel();
    AppActionService.instance.detach();
    _shareIntentHandler.dispose();
    _eventBus.removeHandler(
      EventBusMessageType.invalidModelConfig,
      _handleInvalidModelConfig,
    );
    _eventBus.removeHandler(
      EventBusMessageType.errorNotification,
      _handleErrorNotification,
    );
    _eventBus.removeHandler(
      EventBusMessageType.memorySyncCompleted,
      _handleMemorySyncCompleted,
    );
    // Note: do not disconnect event bus here; other screens may still use it
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final speechService = SpeechTranscriptionService.instance;

      _logger.info('Starting quick recording');
      // Check if local speech model needs downloading
      if (await speechService.requiresLocalModelDownload()) {
        if (!mounted) return;
        _showSpeechModelDownloadDialog();
        return;
      }

      if (await Permission.microphone.request().isGranted) {
        // Initialize streaming transcriber (only when local model is available)
        _quickTranscribedText = '';
        _quickPcmBuffer.clear();
        if (await speechService.supportsStreamingTranscription()) {
          _logger.info(
            'Initializing streaming transcriber for quick recording',
          );
          _quickTranscriber = StreamingTranscriber(
            onTextChanged: (fullText) {
              _quickTranscribedText = fullText;
              if (mounted) setState(() {});
            },
          );
          await _quickTranscriber!.init();
          _logger.info('Streaming transcriber initialized for quick recording');
        }

        // Start streaming PCM recording
        _logger.info('Starting PCM audio stream for quick recording');
        final audioStream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _quickAudioSub = audioStream.listen((chunk) {
          _quickPcmBuffer.addAll(chunk);
          _quickTranscriber?.addAudioChunk(chunk);
        });

        _recordingPath = 'streaming'; // marker that recording is active
      }
    } catch (e, stackTrace) {
      _logger.severe('Error starting quick recording', e, stackTrace);
    }
  }

  void _showSpeechModelDownloadDialog() {
    final sizeMB = WhisperService.modelSizeMB.toInt();

    // CN flavor: single download button
    if (AppFlavor.isCN) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(UserStorage.l10n.speechModelDownloadTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(UserStorage.l10n.speechModelDownloadDesc(sizeMB)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadSpeechModel(useChineseMirror: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(UserStorage.l10n.speechModelStartDownload),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(UserStorage.l10n.cancel),
            ),
          ],
        ),
      );
      return;
    }

    // Global flavor: two source options
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(UserStorage.l10n.speechModelDownloadTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(UserStorage.l10n.speechModelDownloadDesc(sizeMB)),
            const SizedBox(height: 20),
            Text(
              UserStorage.l10n.speechModelChooseSource,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadSpeechModel(useChineseMirror: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(UserStorage.l10n.speechModelChinaMirror),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadSpeechModel(useChineseMirror: false);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(UserStorage.l10n.speechModelGithub),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(UserStorage.l10n.cancel),
          ),
        ],
      ),
    );
  }

  double _speechDownloadProgress = 0;
  StateSetter? _speechDownloadSetState;

  Future<void> _downloadSpeechModel({required bool useChineseMirror}) async {
    final l10n = UserStorage.l10n;
    _speechDownloadProgress = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _speechDownloadSetState = setDialogState;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(l10n.speechModelDownloading),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _speechDownloadProgress > 0
                      ? _speechDownloadProgress
                      : null,
                  backgroundColor: AppColors.background,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  _speechDownloadProgress > 0
                      ? '${(_speechDownloadProgress * 100).toInt()}%'
                      : l10n.speechModelConnecting,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      await WhisperService.instance.downloadModel(
        useChineseMirror: useChineseMirror,
        onProgress: (p) {
          _speechDownloadSetState?.call(() {
            _speechDownloadProgress = p;
          });
        },
      );
    } catch (e) {
      _logger.severe('Speech model download failed: $e');
    } finally {
      _speechDownloadProgress = 0;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    try {
      await _quickAudioSub?.cancel();
      _quickAudioSub = null;
      await _audioRecorder.stop();

      _quickTranscriber?.dispose();
      _quickTranscriber = null;

      if (cancel) {
        _quickPcmBuffer.clear();
        _quickTranscribedText = '';
        _quickAudioPath = null;
        _recordingPath = null;
        return;
      }

      // Final calibration from accumulated PCM
      if (_quickPcmBuffer.isNotEmpty) {
        final useLocal =
            await SpeechTranscriptionService.instance.isUsingLocalModel();
        final aligned = Uint8List.fromList(_quickPcmBuffer);
        final int16Data = Int16List.view(aligned.buffer);
        final samples = Float32List(int16Data.length);
        for (int i = 0; i < int16Data.length; i++) {
          samples[i] = int16Data[i] / 32768.0;
        }

        if (useLocal) {
          final calibrated = await SpeechTranscriptionService.instance
              .transcribeSamples(samples);
          if (calibrated != null && calibrated.isNotEmpty) {
            _quickTranscribedText = calibrated;
          }
          // Keep the original audio alongside the transcription so the
          // resulting timeline card can play back the voice note.
          try {
            final directory = await getTemporaryDirectory();
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final wavPath = '${directory.path}/quick_audio_$timestamp.wav';
            await SpeechTranscriptionService.instance.savePcmAsWav(
              wavPath,
              Uint8List.fromList(_quickPcmBuffer),
            );
            _quickAudioPath = wavPath;
          } catch (e) {
            _logger.warning('Failed to persist quick recording audio: $e');
          }
        } else {
          // Cloud mode: save WAV and submit as audio file
          final directory = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final wavPath = '${directory.path}/quick_audio_$timestamp.wav';
          await SpeechTranscriptionService.instance.savePcmAsWav(
            wavPath,
            Uint8List.fromList(_quickPcmBuffer),
          );
          _quickAudioPath = wavPath;
        }
        _quickPcmBuffer.clear();
      }
    } catch (e) {
      _logger.severe('Error stopping recording: $e', e);
    }
  }

  /// Consume a pending app action (quick action or deep link) once the main UI
  /// is ready and the app-lock overlay is not active.
  void _consumeAppActionIfReady({required bool waitForLateAction}) {
    if (!_canHandleAppActions || _isAppActionCheckScheduled) return;
    _isAppActionCheckScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_canHandleAppActions) {
        _isAppActionCheckScheduled = false;
        return;
      }

      final action = waitForLateAction
          ? await AppActionService.instance.consumePendingAction()
          : AppActionService.instance.consumeIfPending();
      _isAppActionCheckScheduled = false;

      if (!mounted || !_canHandleAppActions) return;
      _handleAppAction(action);
    });
  }

  void _handleAppAction(String? action) {
    if (action == null) return;
    if (action != AppActionService.quickNoteAction) {
      _logger.info('Ignoring unsupported app action: $action');
      return;
    }

    _logger.info('Quick note app action: opening Super Agent');
    setState(() => _homeClipboardCandidate = null);
    _openSuperAgentDialog();
  }

  Future<void> _handleExternalBackupFile(String backupFilePath) async {
    if (_isRestoringExternalBackup) return;
    _isRestoringExternalBackup = true;

    try {
      final backupInfo = await BackupService.inspectBackup(backupFilePath);
      if (!mounted) return;

      final confirmed = await _confirmExternalBackupRestore(backupInfo);
      if (confirmed != true || !mounted) return;

      await _restoreExternalBackup(backupInfo.path);
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(context, UserStorage.l10n.restoreFailed(e));
      }
    } finally {
      _isRestoringExternalBackup = false;
    }
  }

  Future<void> _handleSharedImportFiles(List<String> filePaths) async {
    if (_isImportingSharedFiles) return;

    final importPaths = filePaths
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (importPaths.isEmpty) return;

    _isImportingSharedFiles = true;
    try {
      if (!mounted) return;
      final confirmed = await _confirmSharedFileImport();
      if (confirmed != true || !mounted) return;

      await _importSharedFiles(importPaths);
    } catch (e, stackTrace) {
      _logger.severe('Error importing shared files: $e', e, stackTrace);
      if (mounted) {
        ToastHelper.showError(context, UserStorage.l10n.operationFailed(e));
      }
    } finally {
      _isImportingSharedFiles = false;
    }
  }

  Future<bool?> _confirmSharedFileImport() {
    final dialogContext = rootNavigatorKey.currentContext ?? context;

    return showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(UserStorage.l10n.dataImportTitle),
        content: Text(UserStorage.l10n.dataImportDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UserStorage.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(UserStorage.l10n.confirmImport),
          ),
        ],
      ),
    );
  }

  Future<void> _importSharedFiles(List<String> filePaths) async {
    final dialogContext = rootNavigatorKey.currentContext ?? context;
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);
    var statusText = UserStorage.l10n.dataImportImporting;
    StateSetter? setProgressState;
    var progressDialogOpen = false;

    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setProgressState = setState;
          return AlertDialog(
            backgroundColor: Colors.white,
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(statusText)),
              ],
            ),
          );
        },
      ),
    );
    progressDialogOpen = true;

    try {
      final result = await _memexRouter.importFilesToUserSettingsImported(
        filePaths,
        onProgress: (status) {
          setProgressState?.call(() {
            statusText = status;
          });
        },
      );

      if (!mounted || !rootNavigator.mounted) return;
      if (progressDialogOpen) {
        rootNavigator.pop();
        progressDialogOpen = false;
      }

      await result.when<Future<void>>(
        onOk: (importResult) async {
          ToastHelper.showSuccess(context, UserStorage.l10n.dataImportSuccess);
          await _chooseSharedImportProcessing(importResult);
        },
        onError: (error, _) async {
          ToastHelper.showError(
            context,
            UserStorage.l10n.operationFailed(error),
          );
        },
      );
    } catch (_) {
      if (mounted && rootNavigator.mounted && progressDialogOpen) {
        rootNavigator.pop();
      }
      rethrow;
    }
  }

  Future<void> _chooseSharedImportProcessing(FileImportResult result) async {
    final dialogContext = rootNavigatorKey.currentContext ?? context;
    final options = await showDialog<ImportProcessingOptions>(
      context: dialogContext,
      builder: (context) => ImportProcessingOptionsDialog(result: result),
    );

    if (!mounted || options == null) return;

    if (!options.hasProcessing) {
      ToastHelper.showSuccess(context, UserStorage.l10n.dataImportOnlyStored);
      return;
    }

    final viewModel = DataImportViewModel(router: _memexRouter);
    final queued = await viewModel.startSuperAgentProcessing(result, options);
    if (!mounted) return;

    if (queued) {
      ToastHelper.showSuccess(context, UserStorage.l10n.dataImportQueued);
    } else {
      ToastHelper.showError(
        context,
        UserStorage.l10n.operationFailed(
          viewModel.errorMessage ?? 'Failed to queue processing',
        ),
      );
    }
  }

  Future<bool?> _confirmExternalBackupRestore(BackupFileInfo backupInfo) {
    final dialogContext = rootNavigatorKey.currentContext ?? context;

    return showDialog<bool>(
      context: dialogContext,
      builder: (_) => BackupRestoreConfirmDialog(backupInfo: backupInfo),
    );
  }

  Future<void> _restoreExternalBackup(String backupFilePath) async {
    final dialogContext = rootNavigatorKey.currentContext ?? context;
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);
    var statusText = UserStorage.l10n.restoreInProgress;
    StateSetter? setProgressState;

    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setProgressState = setState;
          return AlertDialog(
            backgroundColor: Colors.white,
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(statusText)),
              ],
            ),
          );
        },
      ),
    );

    try {
      await BackupService.restoreBackup(
        backupFilePath,
        onProgress: (status) {
          setProgressState?.call(() {
            statusText = status;
          });
        },
      );

      if (!mounted || !rootNavigator.mounted) return;
      rootNavigator.pop();
      await showDialog<void>(
        context: rootNavigator.context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(UserStorage.l10n.restoreComplete),
          content: Text(UserStorage.l10n.restoreRestartHint),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(UserStorage.l10n.ok),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted && rootNavigator.mounted) {
        rootNavigator.pop();
      }
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Reset consumed-action dedup so the same shortcut can be triggered
      // on the next foreground session.
      AppActionService.instance.resetConsumed();
    }
    // when app enters foreground, ensure event bus is connected
    if (state == AppLifecycleState.resumed) {
      if (!_eventBus.isConnected) {
        _eventBus.connect();
      }
      unawaited(DailySummaryService.instance.maybeSchedule());
      unawaited(WeeklySummaryService.instance.maybeSchedule());
      unawaited(RollupService.instance.maybeSchedule(monthlyRollup));
      unawaited(RollupService.instance.maybeSchedule(yearlyRollup));
      unawaited(ArchivePurgeService.instance.maybeSchedule());
      unawaited(SummaryNotificationService.instance.reschedule());
      // Consume any app action that arrived while in background. Use a
      // synchronous check because platform callbacks normally fire before
      // resumed; foreground link events are handled by actionStream.
      if (_canHandleAppActions && AppActionService.instance.hasPendingAction) {
        _consumeAppActionIfReady(waitForLateAction: false);
      } else {
        unawaited(_checkHomeClipboardPreview());
      }
    }
  }

  Future<void> _checkHomeClipboardPreview() async {
    if (_isCheckingHomeClipboard || DemoService.instance.isActive) {
      _logger.info(
        'Home clipboard preview check skipped: '
        'checking=$_isCheckingHomeClipboard, demo=${DemoService.instance.isActive}',
      );
      return;
    }

    _logger.info('Home clipboard preview check started');
    _isCheckingHomeClipboard = true;
    final candidate = await _clipboardPreviewService.fetchUnhandledCandidate();
    _isCheckingHomeClipboard = false;

    if (!mounted) return;
    _logger.info(
      'Home clipboard preview check result: '
      '${_describeHomeClipboardCandidate(candidate)}',
    );
    setState(() => _homeClipboardCandidate = candidate);
  }

  String _describeHomeClipboardCandidate(ClipboardPreviewCandidate? candidate) {
    if (candidate == null) return '<none>';
    if (candidate.isImage) {
      return 'image mime=${candidate.mimeType}, fileName=${candidate.fileName}, '
          'uri=${candidate.imageUri}';
    }
    return 'text len=${candidate.text?.runes.length ?? 0}, '
        'preview=${candidate.previewText}';
  }

  Future<void> _openHomeClipboardInSuperAgent() async {
    final candidate = _homeClipboardCandidate;
    if (candidate == null) return;

    if (candidate.isImage) {
      final image = await _clipboardPreviewService.materializeImage(candidate);
      if (image == null) {
        ToastHelper.showInfoWithKey(
          rootScaffoldMessengerKey,
          UserStorage.l10n.clipboardPreviewImageFailed,
        );
        return;
      }
      await _clipboardPreviewService.markHandled(candidate);
      if (!mounted) return;
      setState(() => _homeClipboardCandidate = null);
      final originalFileName = candidate.fileName;
      _openSuperAgentDialog(
        initialImages: [image],
        initialImageOriginalFilenames:
            originalFileName == null || originalFileName.trim().isEmpty
                ? const {}
                : {image.path: originalFileName},
      );
      return;
    }

    final text = candidate.text;
    if (text == null || text.isEmpty) return;

    await _clipboardPreviewService.markHandled(candidate);
    if (!mounted) return;
    setState(() => _homeClipboardCandidate = null);
    _openSuperAgentDialog(initialDraftText: text);
  }

  Future<void> _dismissHomeClipboardPreview() async {
    final candidate = _homeClipboardCandidate;
    if (candidate == null) return;

    await _clipboardPreviewService.markHandled(candidate);
    if (!mounted) return;
    setState(() => _homeClipboardCandidate = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Main content wrapped in SafeArea
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _currentTab,
                      children: [
                        TimelineScreen(
                          key: _timelineKey,
                          viewModel: context.watch<TimelineViewModel>(),
                          insightViewModel: context.watch<InsightViewModel>(),
                          onInputTap: () {
                            setState(() => _homeClipboardCandidate = null);
                            _openSuperAgentDialog();
                          },
                        ),
                        KnowledgeBaseScreen(
                          key: _knowledgeBaseKey,
                          viewModel: context.watch<KnowledgeBaseViewModel>(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_homeClipboardCandidate != null) _buildHomeClipboardPreview(),

            // Floating bottom bar overlay
            _buildBottomBar(),

            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: AgentActivityWidget(),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildHomeClipboardPreview() {
    final candidate = _homeClipboardCandidate;
    if (candidate == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 128,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: ClipboardPreviewCard(
          candidate: candidate,
          onPaste: _openHomeClipboardInSuperAgent,
          onDismiss: _dismissHomeClipboardPreview,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The 393x120.5 Figma Canvas scaled flawlessly to screen width
          FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 393,
              // PNG bounding box height: 120.5 (includes 20px top shadow + 80.5px white shape)
              height: 120.5,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Painted Native Vector Overlay
                  // Completely removing dependencies on Figma PNG/SVG transparent paddings!
                  Positioned.fill(
                    child: CustomPaint(painter: _NavBarPainter()),
                  ),

                  // Shadow occluder mask
                  // The Figma export's shadow has a giant blur that leaks downward.
                  // Placed OVER the image at exactly y=100.0 (where the white shape ends)
                  // It completely masks out the grey blur and extends solidly into the Safe Area.
                  Positioned(
                    top: 100.0,
                    bottom: -100.0,
                    left: 0,
                    right: 0,
                    child: Container(color: Colors.white),
                  ),

                  // Center Action Button (88x88 widget, 68x68 nested circle)
                  // Dialed down to -16.0 for a more subdued hover gap.
                  // Tap starts/stops a quick voice recording; the AI dialog
                  // entry point that used to live here moved to the Record
                  // button on the left (see _handleTimelineTabTap).
                  Positioned(
                    top: -16.0,
                    left: 156.0,
                    child: AICoreButton(
                      key: _aiButtonKey,
                      isRecording: _recordingPath != null,
                      onTap: _handleMicButtonTap,
                    ),
                  ),

                  // Timeline Icon
                  Positioned(
                    top: 46.63, // 26.63 local + 20px shadow
                    left: 64.17,
                    child: GestureDetector(
                      key: DemoService.instance.isActive
                          ? DemoService.instance.addButtonKey
                          : null,
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleTimelineTabTap,
                      child: SvgPicture.asset(
                        'assets/icons/tab_timeline_active.svg',
                        width: 22,
                        height: 23,
                        colorFilter: ColorFilter.mode(
                          _currentTab == 0
                              ? const Color(0xFF1F1F1F)
                              : const Color(0xFF99A1AF),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),

                  // Timeline Text
                  Positioned(
                    top: 76.0,
                    left: 25.17,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleTimelineTabTap,
                      child: SizedBox(
                        width:
                            100, // Widened from strict 58 to permit iOS text expansion
                        // Removed strict height boundary to prevent vertical ascender clipping
                        child: Text(
                          UserStorage.l10n.bottomNavTimeline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: _currentTab == 0
                                ? const Color(0xFF1F1F1F)
                                : const Color(0xFF99A1AF),
                            letterSpacing: 0.14,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Insight — bottom-right slot, mirrored to the Record tab
                  // on the left. Reuses the coordinates of the former
                  // Library button (now retired; see kShowKnowledgeTab
                  // near the top of the file for that dead code path).
                  // Pushes InsightScreen as a full page rather than
                  // swapping _currentTab, since Insight isn't one of the
                  // IndexedStack bodies.
                  Positioned(
                    top: 47.02,
                    left: 299.58,
                    child: GestureDetector(
                      key: DemoService.instance.knowledgeTabKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InsightScreen(
                              viewModel: context.read<InsightViewModel>(),
                            ),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/icon_agent_insight.svg',
                            width: 25.06,
                            height: 21.15,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF99A1AF),
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(height: 76.0 - 47.02 - 21.15),
                          Text(
                            UserStorage.l10n.insights,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF99A1AF),
                              letterSpacing: 0.14,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTimelineTabTap() {
    _memoryButtonTapCount++;
    if (_memoryButtonTapCount == 1) {
      _memoryButtonTapTimer?.cancel();
      _memoryButtonTapTimer = Timer(const Duration(milliseconds: 300), () {
        _memoryButtonTapCount = 0;
      });
      // Advance first so _handleAICoreButtonTap sees tapSend step for prefill
      DemoService.instance.tryAdvance(DemoStep.tapAddButton);
      _handleAICoreButtonTap();
    } else if (_memoryButtonTapCount == 2) {
      _memoryButtonTapTimer?.cancel();
      _memoryButtonTapCount = 0;
      _timelineKey.currentState?.scrollToTopAndRefresh();
    }
  }

}

class _NavBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path();
    path.moveTo(0, 20);
    path.lineTo(142.528, 20);
    path.cubicTo(148.501, 20, 153.977, 23.3275, 156.729, 28.6293);
    path.lineTo(164.497, 43.5965);
    path.cubicTo(179.426, 72.3609, 220.574, 72.3609, 235.503, 43.5966);
    path.lineTo(243.271, 28.6293);
    path.cubicTo(246.023, 23.3275, 251.499, 20, 257.472, 20);
    path.lineTo(size.width, 20);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, 20);
    path.close();

    // Custom drop shadow that doesn't bleed weirdly
    // We clip the bottom so the shadow never goes below the nav bar visually
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(-50, -50, size.width + 100, size.height + 50),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0),
    );
    canvas.restore();

    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
