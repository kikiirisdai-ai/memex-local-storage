import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:memex/data/repositories/get_schedule_briefing_timeline_card.dart'
    as schedule_briefing_endpoint;
import 'package:memex/data/repositories/migrate_cards_fact_assets.dart';
import 'package:memex/data/repositories/update_card_ui_config.dart'
    as update_config_endpoint;
import 'package:memex/data/repositories/update_card_title.dart';
import 'package:memex/data/services/search_service.dart';
import 'package:memex/data/services/embedding_index_service.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/external_backup_channel.dart';
import 'package:memex/data/services/icloud_daily_backup_service.dart';
import 'package:memex/utils/backup_safety.dart';
import 'package:memex/data/services/file_import_service.dart';
import 'package:memex/data/services/user_stats_service.dart';
import 'package:memex/data/repositories/hydrate_card.dart';
import 'package:memex/data/services/table_change_notifier.dart';
import 'package:memex/data/services/card_attachment_service.dart';
import 'package:memex/data/services/card_detail_notifier.dart';
import 'package:memex/data/services/agent_background_coordinator.dart';
import 'package:memex/data/services/agent_background_task_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/app_update_service.dart';
import 'package:memex/data/services/user_notification_service.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/repositories/get_timeline_card.dart'; // Import for fetchTimelineCard
import 'package:logging/logging.dart';
import 'package:memex/data/services/card_renderer.dart';
import 'package:memex/data/services/event_handlers/calendar_sync_on_card_change_handler.dart';
import 'package:memex/data/services/event_handlers/schedule_state_on_card_change_handler.dart';
import 'package:memex/data/services/schedule_state_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/tag_model.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/domain/models/insight_detail_model.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/agent_config.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/chat_service.dart';
import 'package:memex/data/services/chat_session_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/services/task_handlers/daily_summary_handler.dart';
import 'package:memex/data/services/task_handlers/archive_purge_handler.dart';
import 'package:memex/data/services/archive_purge_service.dart';
import 'package:memex/data/services/task_handlers/monthly_summary_handler.dart';
import 'package:memex/data/services/task_handlers/weekly_summary_handler.dart';
import 'package:memex/data/services/task_handlers/yearly_summary_handler.dart';
import 'package:memex/data/services/task_handlers/fts_index_handler.dart';
import 'package:memex/data/services/task_handlers/embedding_index_handler.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/data/services/task_handlers/comment_agent_handler.dart';
import 'package:memex/data/services/task_handlers/reprocess_comments_handler.dart';
import 'package:memex/data/services/task_handlers/custom_agent_task_handler.dart';
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/repositories/get_tags.dart';
import 'package:memex/data/repositories/get_timeline_cards.dart';
import 'package:memex/data/repositories/get_archived_cards.dart';
import 'package:memex/data/repositories/get_aggregated_timeline.dart';
import 'package:memex/data/repositories/get_cards_by_ids.dart';
import 'package:memex/data/repositories/card.dart';
import 'package:memex/data/repositories/post_comment.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/data/repositories/pin_insight.dart';
import 'package:memex/data/repositories/character.dart';
import 'package:memex/data/repositories/pkm.dart' as pkm_endpoint;
import 'package:memex/domain/models/knowledge_insight_card.dart';
import 'package:memex/data/repositories/get_knowledge_insight_detail.dart';
import 'package:memex/data/repositories/chat.dart' as chat_endpoint;
import 'package:memex/data/services/llm_call_record_service.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/avatar_media_service.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/agent/skills/knowledge_insight/native_widgets.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/domain/models/user_stats_model.dart';

/// Local data service for Memex. Handles all data operations via local storage (FileSystemService, DB).
class MemexRouter {
  static final MemexRouter _instance = MemexRouter._();
  factory MemexRouter() => _instance;

  final Logger _logger = getLogger('MemexRouter');

  Future<void>? _initFuture;

  FileSystemService get fileSystemService => FileSystemService.instance;

  MemexRouter._() {
    AgentActivityService.setInstance(LocalAgentActivityService.instance);
    _ensureInitialized();
  }

  Future<void> _init() async {
    try {
      // 1. Resolve data root for current user (per-user workspace storage; logs/DB stay in app dir)
      final userId = await UserStorage.getUserId();
      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);

      if (userId == null) {
        _logger.warning(
          'No user ID found during initialization. Local DB will NOT be initialized until login.',
        );
        return; // Do not initialize DB yet.
      }

      // Use userId to init DB (drift_flutter handles path isolation via name)
      _logger.info('Initializing Local DB for user: $userId');
      await ChatSessionStorage.instance.ensureMigrated(userId);

      // Safety snapshot before a schema migration runs. The snapshot must
      // happen while the DB file is on disk and NOT open yet
      // (createSafetySnapshot zips the DB file), i.e. strictly before
      // AppDatabase.init runs the migration. setLastSchemaVersion is only
      // persisted after AppDatabase.init completes successfully, so a
      // failed/partial migration is never mistaken for a completed one on
      // the next startup. Snapshot failures are best-effort and never block
      // startup; migration failures propagate (handled by the outer
      // try/catch below).
      await maybeSnapshotBeforeMigration(
        getStored: UserStorage.getLastSchemaVersion,
        code: AppDatabase.latestSchemaVersion,
        snapshot: (reason) => BackupService.createSafetySnapshot(
          reason: reason,
        ),
        migrate: () => AppDatabase.init(userId),
        setStored: UserStorage.setLastSchemaVersion,
      );

      _registerTaskHandlers(LocalTaskExecutor.instance);
      await LocalTaskExecutor.instance.start(userId: userId);

      // Start table change notifier (binlog-style listener for Drift tables)
      TableChangeNotifier.instance.init();
      // Register attachment table watchers
      CardAttachmentService.instance.init();
      // Register user notification table watch (must precede CardDetailNotifier)
      UserNotificationService.instance.init();
      // Register card-detail change notifier (subscribes to GlobalEventBus)
      CardDetailNotifier.instance.init();

      // Register event subscriptions after task handlers are ready.
      _registerEventSubscriptions();

      // Initialize custom agent handler and register user-defined agents.
      initCustomAgentHandler();
      registerBuiltInEventSerializers();
      await CustomAgentConfigService.instance.registerAll(userId);
      await AgentBackgroundTaskService.instance.startMonitoring();
      AgentBackgroundCoordinator.instance.start(
        executor: LocalTaskExecutor.instance,
        activityService: LocalAgentActivityService.instance,
      );

      // Register file change callback and FTS event subscriptions.
      // Also triggers a one-time full rebuild when FTS tables were just created
      // via migration (existing users upgrading to schema v10).
      SearchService.instance.init(userId);

      // Register embedding-update event subscriptions for semantic search.
      // Also triggers a one-time full backfill when card_embeddings was just
      // created via migration (existing users upgrading to schema v17).
      EmbeddingIndexService.instance.init(userId);

      // One-time migration: backfill legacy cards' fact/assets/created_at
      // fields from their Facts files. Runs after SearchService subscribes so
      // migrated card facts are incrementally reflected in FTS.
      await migrateCardsToFactAssets(userId);

      await ScheduleStateService.instance.ensureInitialized(userId);

      scheduleAutoBackupCheck(trigger: 'app_start');
    } catch (e) {
      _logger.severe('Failed to initialize MemexRouter: $e');
      // Reset future to allow retry if needed, or keep failed state
      // _initFuture = null;
      rethrow;
    }
  }

  String?
      _targetUserIdForInit; // Track the user ID we are currently initializing for

  void _registerEventSubscriptions() {
    final eventBus = GlobalEventBus.instance;

    // Capture happens inside SuperAgent. After a new card is saved,
    // SuperAgent re-publishes this event so independent consumers such as
    // comment_agent can react through the persistent task queue.
    eventBus.subscribe(
      eventType: SystemEventTypes.userInputSubmitted,
      subscription: EventTaskSubscription(
        subscriptionId: 'comment_agent',
        taskType: 'comment_agent_task',
        payloadBuilder: (_, event) {
          final p = event.payload as UserInputSubmittedPayload;
          return Future.value({
            'fact_id': p.factId,
            'combined_text': p.combinedText,
            'created_at_ts': p.createdAtTs,
            'location_context_reminder': p.locationContextReminder,
          });
        },
      ),
    );

    eventBus.subscribe(
      eventType: SystemEventTypes.cardCommentPosted,
      subscription: EventTaskSubscription(
        subscriptionId: 'ai_reply',
        taskType: 'process_ai_reply',
        payloadBuilder: (_, event) {
          final p = event.payload as CardCommentPostedPayload;
          return Future.value({
            'card_id': p.cardId,
            'content': p.content,
            'comment_id': p.commentId,
            if (p.createdAtTs != null) 'created_at_ts': p.createdAtTs,
            if (p.replyToId != null) 'reply_to_id': p.replyToId,
            'location_context_reminder': p.locationContextReminder,
          });
        },
      ),
    );

    eventBus.subscribeSync<DataChangeRecord>(
      eventType: SystemEventTypes.dataChanged,
      subscription: EventSyncSubscription<DataChangeRecord>(
        subscriptionId: 'schedule_state_on_card_change',
        handler: handleScheduleStateOnCardChanged,
      ),
    );

    eventBus.subscribeSync<CardUiConfigUpdatedPayload>(
      eventType: SystemEventTypes.cardUiConfigUpdated,
      subscription: EventSyncSubscription<CardUiConfigUpdatedPayload>(
        subscriptionId: 'schedule_state_on_card_ui_config_update',
        handler: handleScheduleStateOnCardUiConfigUpdated,
      ),
    );

    eventBus.subscribeSync<DataChangeRecord>(
      eventType: SystemEventTypes.dataChanged,
      subscription: EventSyncSubscription<DataChangeRecord>(
        subscriptionId: 'calendar_sync_on_card_change',
        handler: handleCalendarSyncOnCardChanged,
      ),
    );

    eventBus.subscribeSync<CardUiConfigUpdatedPayload>(
      eventType: SystemEventTypes.cardUiConfigUpdated,
      subscription: EventSyncSubscription<CardUiConfigUpdatedPayload>(
        subscriptionId: 'calendar_sync_on_card_ui_config_update',
        handler: handleCalendarSyncOnCardUiConfigUpdated,
      ),
    );
  }

  Future<void> _ensureInitialized() async {
    // We double check if a user is logged in now, and if we need to re-init.
    final currentUser = await UserStorage.getUserId();

    // If we are already initializing (or have initialized) for this user, return the existing future.
    // This prevents infinite loops when multiple calls happen while initialization is in progress.
    if (_targetUserIdForInit == currentUser && _initFuture != null) {
      return _initFuture!;
    }

    _logger.info(
      'Re-initializing MemexRouter. Previous Target: $_targetUserIdForInit, New Target: $currentUser',
    );

    _targetUserIdForInit = currentUser;
    _initFuture = _init();
    return _initFuture!;
  }

  Future<void> ensureInitialized() => _ensureInitialized();

  /// Initializes only the task queue pieces needed from a WorkManager callback
  /// isolate.
  ///
  /// Keep this as a background-only entry point. It deliberately avoids
  /// front-end observers, UI notifiers, event subscriptions, search startup, and
  /// platform background surfaces that are already owned by the foreground
  /// isolate.
  static Future<void> ensureTaskQueueInitializedForBackgroundTask(
    String userId, {
    LocalTaskExecutor? executor,
  }) async {
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    await ChatSessionStorage.instance.ensureMigrated(userId);
    await AppDatabase.init(userId);

    final taskExecutor = executor ?? LocalTaskExecutor.instance;
    AgentActivityService.setInstance(LocalAgentActivityService.instance);
    _registerTaskHandlers(taskExecutor);
    initCustomAgentHandler();
    registerBuiltInEventSerializers();
    await CustomAgentConfigService.instance.registerAll(userId);
  }

  static void _registerTaskHandlers(LocalTaskExecutor executor) {
    // LocalTaskExecutor handles this map; re-registering overwrites which is fine.
    executor.registerHandler(
      'super_agent_chat_turn_task',
      ChatService.instance.handleSuperAgentChatTurnTask,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'fts_index_update',
      handleFtsIndexUpdateImpl,
    );
    executor.registerHandler(
      'embedding_index_update',
      handleEmbeddingIndexUpdateImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'comment_agent_task',
      handleCommentAgentImpl,
    );
    executor.registerHandler(
      'reprocess_comments_task',
      handleReprocessCommentsImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'process_ai_reply',
      handleProcessAiReplyImpl,
    );
    executor.registerHandler(
      'daily_summary_task',
      handleDailySummaryImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      archivePurgeTaskType,
      handleArchivePurgeImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'weekly_summary_task',
      handleWeeklySummaryImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'monthly_summary_task',
      handleMonthlySummaryImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    executor.registerHandler(
      'yearly_summary_task',
      handleYearlySummaryImpl,
      concurrencyPolicy: TaskConcurrencyPolicy.byUser(),
    );
    for (final taskType in [
      'comment_agent_task',
      'reprocess_comments_task',
      'process_ai_reply',
    ]) {
      executor.registerFailureHandler(
        taskType,
        handleGenericAgentFailure,
      );
    }
  }

  /// External hook to force switch user (e.g. on login)
  Future<void> switchUser(String userId) async {
    _logger.info('Switching user to $userId');
    _targetUserIdForInit = null;
    _initFuture = null;
    await _ensureInitialized();
  }

  /// Apply latest per-user workspace storage configuration immediately.
  /// Rebuilds card cache for current user so reads reflect new workspace root.
  Future<void> applyWorkspaceStorageChange() async {
    final userId = await UserStorage.getUserId();
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    if (userId != null && userId.isNotEmpty) {
      await ChatSessionStorage.instance.ensureMigrated(userId);
      try {
        await FileSystemService.instance.rebuildCardCache(userId);
      } catch (e) {
        _logger.warning('Failed to rebuild cache after storage switch: $e');
      }
    }
  }

  Future<BackupSnapshot?> maybeRunAutoBackup({
    required String trigger,
    bool force = false,
  }) async {
    await _ensureInitialized();
    if (Platform.isIOS) {
      // On iOS, the iCloud daily backup fully replaces the sandbox
      // auto-backup: if no iCloud folder is configured, we must NOT fall
      // back to writing a sandbox backup. This entire branch must be
      // best-effort: any failure (e.g. a MissingPluginException/
      // PlatformException from the channel) is logged and swallowed here,
      // not just by the sole current caller's .catchError, so any future
      // direct caller is protected too.
      try {
        final userId = await UserStorage.getUserId();
        final status = await ExternalBackupChannel().icloudStatus();
        if (userId != null && status.configured) {
          await ICloudDailyBackupService()
              .maybeCreateDailyBackup(userId: userId, force: force);
        }
      } catch (e, st) {
        _logger.warning('iOS auto-backup check failed: $e', e, st);
      }
      return null;
    }
    return BackupService.maybeCreateAutoBackup(trigger: trigger, force: force);
  }

  void scheduleAutoBackupCheck({required String trigger}) {
    unawaited(
      maybeRunAutoBackup(trigger: trigger).catchError((
        Object e,
        StackTrace st,
      ) {
        _logger.warning('Automatic backup check failed: $e', e, st);
        return null;
      }),
    );
  }

  /// Clear init state and stop executor on logout so next login re-inits for new user.
  void resetForLogout() {
    _logger.info('Resetting MemexRouter for logout');
    _targetUserIdForInit = null;
    _initFuture = null;
    unawaited(AgentBackgroundCoordinator.instance.stop());
    unawaited(AgentBackgroundTaskService.instance.stopMonitoring(
      reason: 'logout',
    ));
    LocalTaskExecutor.instance.stop();
    SearchService.instance.reset();
    EmbeddingIndexService.instance.reset();
  }

  void dispose() {
    unawaited(AgentBackgroundCoordinator.instance.stop());
    unawaited(AgentBackgroundTaskService.instance.stopMonitoring(
      reason: 'router_dispose',
    ));
    LocalTaskExecutor.instance.stop();
  }

  AgentActivityService get agentActivityService =>
      LocalAgentActivityService.instance;

  Future<String?> getToken() async {
    return null;
  }

  Future<List<String>> checkProcessedHashes(List<String> hashes) async {
    await _ensureInitialized();
    if (hashes.isEmpty) return [];

    final userId = await UserStorage.getUserId();
    if (userId == null) return hashes;

    return fileSystemService.checkUnprocessedHashes(userId, hashes);
  }

  Future<void> recordProcessedHashes(List<String> hashes) async {
    await _ensureInitialized();
    if (hashes.isEmpty) return;

    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    await fileSystemService.recordProcessedHashes(userId, hashes);
  }

  Future<Result<List<TagModel>>> fetchTags() async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: fetchTags called');
      return getTags();
    });
  }

  Future<List<TagModel>> fetchTagsByPeriod({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: fetchTagsByPeriod called: dateFrom=$dateFrom, dateTo=$dateTo',
    );

    // Get all cards in the period with a large limit to capture all tags
    final cards = await getTimelineCards(
      page: 1,
      limit: 1000, // Large limit to get all cards in period
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    // Extract unique tag names from cards
    final Set<String> uniqueTagNames = {};
    for (final card in cards) {
      uniqueTagNames.addAll(card.tags);
    }

    // Get all tag definitions
    final allTags = await getTags();

    // Filter to only tags that exist in the period
    return allTags.where((tag) => uniqueTagNames.contains(tag.name)).toList();
  }

  Future<Result<List<TimelineCardModel>>> fetchTimelineCards({
    int page = 1,
    int limit = 20,
    List<String>? tags,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchTimelineCards called: page=$page, limit=$limit, tags=$tags, dateFrom=$dateFrom, dateTo=$dateTo',
      );
      return getTimelineCards(
        page: page,
        limit: limit,
        tags: tags,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
    });
  }

  Future<Result<TimelineCardModel?>> fetchScheduleBriefingCard() {
    return runResult(() async {
      await _ensureInitialized();
      return schedule_briefing_endpoint.getScheduleBriefingTimelineCard();
    });
  }

  Future<Result<Map<String, dynamic>>> fetchAggregatedTimeline({
    required String groupBy,
    int page = 1,
    int limit = 20,
    List<String>? tags,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchAggregatedTimeline called: groupBy=$groupBy, page=$page, limit=$limit, tags=$tags',
      );
      return getAggregatedTimeline(
        groupBy: groupBy,
        page: page,
        limit: limit,
        tags: tags,
      );
    });
  }

  Future<List<TimelineCardModel>> fetchCardByIds(List<String> ids) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCardByIds called: ids=$ids');
    return getCardsByIds(ids);
  }

  Future<TimelineCardModel?> fetchTimelineCard(String cardId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchTimelineCard called: cardId=$cardId');
    return getTimelineCard(cardId);
  }

  Future<CardDetailModel> fetchCardDetail(String cardId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCardDetail called: cardId=$cardId');
    return getCardDetail(cardId);
  }

  Future<Map<String, dynamic>> postComment(
    String cardId,
    String content, {
    String? replyToId,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: postComment called: cardId=$cardId');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User not logged in, cannot submit comment');
      }

      return await postCommentEndpoint(
        cardId,
        userId,
        content,
        replyToId: replyToId,
      );
    } catch (e) {
      _logger.severe('Failed to post comment for card $cardId: $e');
      rethrow;
    }
  }

  /// Load per-user comment settings.
  Future<CommentSettings> getCommentSettings() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return const CommentSettings();
    return CommentSettingsService.load(userId);
  }

  /// Save per-user comment settings.
  Future<void> saveCommentSettings(CommentSettings settings) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await CommentSettingsService.save(userId, settings);
  }

  Future<AppUpdateSettings> getAppUpdateSettings() {
    return AppUpdateService.instance.loadSettings();
  }

  Future<void> saveAppUpdateSettings(AppUpdateSettings settings) {
    return AppUpdateService.instance.saveSettings(settings);
  }

  Future<Result<AppUpdateCheckResult>> checkEarlyUpdate({
    bool manual = false,
    bool respectWifi = false,
  }) {
    return runResult(() {
      return AppUpdateService.instance.checkForUpdate(
        manual: manual,
        respectWifi: respectWifi,
      );
    });
  }

  Future<Result<AppUpdateDownloadResult>> downloadEarlyUpdate(
    AppUpdateInfo update, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) {
    return runResult(() {
      return AppUpdateService.instance.downloadUpdate(
        update,
        onProgress: onProgress,
      );
    });
  }

  Future<Result<AppUpdateInstallResult>> installEarlyUpdate(String apkPath) {
    return runResult(() => AppUpdateService.instance.installUpdate(apkPath));
  }

  Future<void> enqueueTask({
    required String taskType,
    required Map<String, dynamic> payload,
    String? bizId,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: enqueueTask called: type=$taskType, bizId=$bizId');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      await LocalTaskExecutor.instance.enqueueTask(
        userId: userId,
        taskType: taskType,
        payload: payload,
        bizId: bizId,
      );
    } catch (e) {
      _logger.severe('Failed to enqueue task $taskType: $e');
      rethrow;
    }
  }

  /// Terminates every queued and running task, aborting in-flight LLM
  /// requests. Returns the number of tasks terminated.
  Future<int> cancelAllActiveAiTasks() async {
    await _ensureInitialized();
    return LocalTaskExecutor.instance.cancelAllActiveTasks();
  }

  /// Clears all workspace data for the current user.
  Future<void> clearData() async {
    await _ensureInitialized();
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) throw Exception('User not logged in');

      final workspacePath = fileSystemService.getWorkspacePath(userId);
      final workspaceDir = Directory(workspacePath);
      if (!await workspaceDir.exists()) return;

      await for (final entity in workspaceDir.list(followLinks: false)) {
        if (entity is Directory) {
          try {
            await entity.delete(recursive: true);
            _logger.info('Deleted directory: ${entity.path}');
          } catch (e) {
            _logger.warning('Failed to delete ${entity.path}: $e');
          }
        }
      }

      // Clear card cache
      await AppDatabase.instance.cardDao.clearCache();
    } catch (e) {
      _logger.severe('Failed to clear data locally: $e');
      rethrow;
    }
  }

  Future<int> clearFailedAgentConversationContexts() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) throw Exception('User not logged in');

    final deleted = await deleteAgentStatesWhere(userId, (sessionId, metadata) {
      final scene = metadata['scene']?.toString();
      return scene == 'insight' || scene == 'schedule_aggregation';
    });
    _logger.info(
      'Cleared ${deleted.length} failed agent conversation context(s): $deleted',
    );
    return deleted.length;
  }

  // Native widget IDs are now dynamically loaded from nativeWidgets definition

  Future<Result<List<KnowledgeInsightCard>>> fetchKnowledgeInsights() async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: fetchKnowledgeInsights called');

      final userId = await UserStorage.getUserId();
      if (userId == null) return [];

      final cardsData = await fileSystemService.listKnowledgeInsightCards(
        userId,
      );
      final insights = <KnowledgeInsightCard>[];

      for (final card in cardsData) {
        final id = card['id'] as String? ?? 'unknown';
        final templateId = card['template_id'] as String? ?? '';
        final isNative = nativeWidgets.any((w) => w.id == templateId);

        final title = card['title'] as String?;

        int createdAt = DateTime.now().millisecondsSinceEpoch;
        if (card.containsKey('updated_at')) {
          createdAt = DateTime.parse(card['updated_at']).millisecondsSinceEpoch;
        }

        String? chartHtml;
        if (!isNative) {
          chartHtml = await _renderInsightCardHtml(userId, card);
        }

        Map<String, dynamic>? widgetData;
        if (isNative) {
          widgetData = Map<String, dynamic>.from(card);
          if (card['data'] is Map) {
            widgetData.addAll((card['data'] as Map).cast<String, dynamic>());
          }
          widgetData.remove('data');
          widgetData = await replaceFsInData(widgetData, userId);
        }

        insights.add(
          KnowledgeInsightCard(
            id: id,
            title: title,
            html: chartHtml ?? '',
            createdAt: createdAt,
            isPinned: card['pinned'] == true,
            sortOrder: (card['sort_order'] as num? ?? 0).toInt(),
            tags: (card['tags'] as List?)?.cast<String>() ?? const [],
            widgetType: isNative ? 'native' : 'html',
            widgetTemplate: isNative ? templateId : null,
            widgetData: widgetData,
          ),
        );
      }

      insights.sort((a, b) {
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        if (sortCompare != 0) return sortCompare;
        return b.createdAt.compareTo(a.createdAt);
      });

      return insights;
    });
  }

  Future<Result<UserStatsSnapshot>> fetchUserStats({
    required UserStatsDateRange range,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchUserStats called: start=${range.start}, end=${range.end}',
      );
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        return UserStatsSnapshot.empty(range);
      }
      return UserStatsService(
        fileSystemService: fileSystemService,
      ).fetchSnapshot(userId: userId, range: range);
    });
  }

  Future<String> _renderInsightCardHtml(
    String userId,
    Map<String, dynamic> card,
  ) async {
    final templateId = card['template_id'] as String? ?? '';
    final title = card['title'] as String? ?? '';
    final insight = card['insight'] as String? ?? '';
    final data = card['data'] as Map<String, dynamic>? ?? {};

    final htmlTemplate = await fileSystemService
        .readKnowledgeInsightCardTemplateHtml(userId, templateId);

    if (htmlTemplate != null && htmlTemplate.isNotEmpty) {
      try {
        final templateData = <String, dynamic>{
          'title': title,
          'insight': insight,
        };
        templateData.addAll(data);

        final renderedHtml = fileSystemService.renderHtmlTemplate(
          htmlTemplate,
          templateData,
        );
        return await fileSystemService.replaceFsInHtml(renderedHtml, userId);
      } catch (e) {
        _logger.warning(
          'Failed to render insight card template $templateId: $e',
        );
      }
    }
    // Fallback? Currently returns empty if failed or no template
    return '';
  }

  Future<Result<bool>> unpinInsight(String id) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: unpinInsight called: id=$id');
      return await unpinInsightEndpoint(id);
    });
  }

  Future<Result<bool>> pinInsight(String id) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: pinInsight called: id=$id');
      return await pinInsightEndpoint(id);
    });
  }

  Future<Result<bool>> deleteKnowledgeInsight(String id) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: deleteKnowledgeInsight called: id=$id');
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        _logger.warning('No user logged in, cannot delete insight');
        return false;
      }
      final cardFileName = '$id.yaml';
      final success = await fileSystemService.deleteKnowledgeInsightCard(
        userId,
        cardFileName,
      );
      if (success) {
        try {
          final cardPath = 'KnowledgeInsights/Cards/$cardFileName';
          await fileSystemService.eventLogService.logEvent(
            userId: userId,
            eventType: 'user_action',
            description: 'User deleted knowledge insight card',
            filePath: cardPath,
            metadata: {'action': 'delete', 'card_id': id},
          );
        } catch (e) {
          _logger.warning('Failed to log delete insight event: $e');
        }
      }
      return success;
    });
  }

  Future<Result<bool>> updateInsightCardSortOrder(
    List<String> sortedIds,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: updateInsightCardSortOrder called with ${sortedIds.length} ids',
      );
      final userId = await UserStorage.getUserId();
      if (userId == null) return false;
      for (int i = 0; i < sortedIds.length; i++) {
        final id = sortedIds[i];
        try {
          final cardData = await fileSystemService.readKnowledgeInsightCard(
            userId,
            id,
          );
          if (cardData != null) {
            final currentSortOrder =
                (cardData['sort_order'] as num? ?? 0).toInt();
            if (currentSortOrder != i) {
              cardData['sort_order'] = i;
              await fileSystemService.writeKnowledgeInsightCard(
                userId,
                id,
                cardData,
              );
            }
          }
        } catch (e) {
          _logger.warning('Failed to update sort order for card $id: $e');
        }
      }
      return true;
    });
  }

  Future<List<String>> fetchInsightTags() async {
    await _ensureInitialized();
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return [];
      return await fileSystemService.readInsightTags(userId);
    } catch (e) {
      _logger.severe('Failed to fetch insight tags: $e');
      return [];
    }
  }

  Future<bool> deleteCard(String id) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteCard called: id=$id');

    try {
      return await deleteCardEndpoint(id);
    } catch (e) {
      _logger.severe('Failed to delete card $id: $e');
      return false;
    }
  }

  /// Archives a card (removes it from the main timeline into the Archive
  /// list) by stamping `archived_at`. The card file is kept, not deleted.
  Future<bool> archiveCard(String id) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return false;

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final updated = await FileSystemService.instance.updateCardFile(
        userId,
        id,
        (card) => card.copyWith(archivedAt: now),
      );
      return updated != null;
    } catch (e) {
      _logger.severe('Failed to archive card $id: $e');
      return false;
    }
  }

  /// Restores an archived card back to the main timeline.
  Future<bool> unarchiveCard(String id) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return false;

    try {
      final updated = await FileSystemService.instance.updateCardFile(
        userId,
        id,
        (card) => card.copyWith(clearArchivedAt: true),
      );
      return updated != null;
    } catch (e) {
      _logger.severe('Failed to unarchive card $id: $e');
      return false;
    }
  }

  Future<Result<List<TimelineCardModel>>> fetchArchivedCards() async {
    return runResult(() async {
      await _ensureInitialized();
      return getArchivedCards();
    });
  }

  /// Corrects a card's title (AI-written wording the user wants changed).
  /// A blank title clears it.
  Future<bool> updateCardTitle(String cardId, String title) async {
    await _ensureInitialized();
    _logger.info('LocalMode: updateCardTitle called: cardId=$cardId');

    try {
      return await updateCardTitleEndpoint(cardId, title);
    } catch (e) {
      _logger.severe('Failed to update card title for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardUiConfig(
    String cardId,
    int configIndex,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardUiConfig called: cardId=$cardId, index=$configIndex',
    );

    try {
      return await update_config_endpoint.updateCardUiConfigEndpoint(
        cardId,
        configIndex,
        data,
      );
    } catch (e) {
      _logger.severe('Failed to update card ui config for $cardId: $e');
      return false;
    }
  }

  Future<Result<void>> completeScheduleItem(String itemId) =>
      runResultVoid(() async {
        await _ensureInitialized();
        final userId = await UserStorage.getUserId();
        if (userId == null) {
          throw Exception('User not logged in');
        }

        await ScheduleStateService.instance.completePendingItem(
          userId: userId,
          pendingId: itemId,
        );
        EventBusService.instance.emitEvent(
          ScheduleAggregationUpdatedMessage(aggregationId: 'schedule_state'),
        );
      });

  Future<Result<void>> restoreScheduleItem(String itemId) =>
      runResultVoid(() async {
        await _ensureInitialized();
        final userId = await UserStorage.getUserId();
        if (userId == null) {
          throw Exception('User not logged in');
        }

        await ScheduleStateService.instance.restoreCompletedItem(
          userId: userId,
          completedId: itemId,
        );
        EventBusService.instance.emitEvent(
          ScheduleAggregationUpdatedMessage(aggregationId: 'schedule_state'),
        );
      });

  Future<Result<void>> setScheduleSubtaskCompletion({
    required String itemId,
    required String subtaskTitle,
    required bool completed,
  }) =>
      runResultVoid(() async {
        await _ensureInitialized();
        final userId = await UserStorage.getUserId();
        if (userId == null) {
          throw Exception('User not logged in');
        }

        await ScheduleStateService.instance.setSubtaskCompletion(
          userId: userId,
          pendingId: itemId,
          subtaskTitle: subtaskTitle,
          completed: completed,
        );
        EventBusService.instance.emitEvent(
          ScheduleAggregationUpdatedMessage(aggregationId: 'schedule_state'),
        );
      });

  Future<bool> updateCardTime(String cardId, int timestamp) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardTime called: cardId=$cardId, timestamp=$timestamp',
    );

    try {
      return await updateCardTimeEndpoint(cardId, timestamp);
    } catch (e) {
      _logger.severe('Failed to update card time for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardMood(String cardId, int score) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardMood called: cardId=$cardId, score=$score',
    );

    try {
      return await updateCardMoodEndpoint(cardId, score);
    } catch (e) {
      _logger.severe('Failed to update card mood for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardMediaStatus(String cardId, String status) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardMediaStatus called: cardId=$cardId, status=$status',
    );

    try {
      return await updateCardMediaStatusEndpoint(cardId, status);
    } catch (e) {
      _logger.severe('Failed to update media status for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardMediaRating(
    String cardId,
    int rating,
    String? comment,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardMediaRating called: cardId=$cardId, rating=$rating',
    );

    try {
      return await updateCardMediaRatingEndpoint(cardId, rating, comment);
    } catch (e) {
      _logger.severe('Failed to update media rating for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardLocation(
    String cardId,
    double lat,
    double lng,
    String name,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardLocation called: cardId=$cardId, lat=$lat, lng=$lng, name=$name',
    );

    try {
      return await updateCardLocationEndpoint(cardId, lat, lng, name);
    } catch (e) {
      _logger.severe('Failed to update card location for $cardId: $e');
      return false;
    }
  }

  Future<InsightDetailModel> fetchInsightDetail(String insightId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchInsightDetail called: insightId=$insightId');

    try {
      // Knowledge insight
      return await getKnowledgeInsightDetail(insightId);
    } catch (e) {
      _logger.severe('Failed to fetch insight detail $insightId: $e');
      rethrow;
    }
  }

  Future<Result<List<Map<String, dynamic>>>> fetchChatSessions({
    String? agentName,
    int? limit,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchChatSessions called: agentName=$agentName, limit=$limit',
      );
      return await chat_endpoint.fetchChatSessionsEndpoint(
        agentName: agentName,
        limit: limit,
      );
    });
  }

  Future<Map<String, dynamic>> fetchChatSessionDetail(
    String sessionId, {
    int? messageLimit,
    String? messageBeforeCursor,
  }) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: fetchChatSessionDetail called: sessionId=$sessionId',
    );

    try {
      return await chat_endpoint.fetchChatSessionDetailEndpoint(
        sessionId,
        messageLimit: messageLimit,
        messageBeforeCursor: messageBeforeCursor,
      );
    } catch (e) {
      _logger.severe('Failed to fetch chat session detail: $e');
      rethrow;
    }
  }

  Future<bool> deleteChatSession(String sessionId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteChatSession called: sessionId=$sessionId');

    try {
      return await chat_endpoint.deleteChatSessionEndpoint(sessionId);
    } catch (e) {
      _logger.severe('Failed to delete chat session: $e');
      return false;
    }
  }

  Future<Result<List<CharacterModel>>> fetchCharacters() async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: fetchCharacters called');
      return await getCharacters();
    });
  }

  Future<CharacterModel> fetchCharacter(String characterId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCharacter called: characterId=$characterId');

    try {
      return await getCharacter(characterId);
    } catch (e) {
      _logger.severe('Failed to fetch character $characterId: $e');
      rethrow;
    }
  }

  Future<CharacterModel> createCharacter({
    required String name,
    required List<String> tags,
    required String persona,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: createCharacter called: name=$name');

    try {
      return await createCharacterEndpoint(
        name: name,
        tags: tags,
        persona: persona,
      );
    } catch (e) {
      _logger.severe('Failed to create character: $e');
      rethrow;
    }
  }

  Future<CharacterModel> updateCharacter({
    required String characterId,
    String? name,
    List<String>? tags,
    String? persona,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: updateCharacter called: characterId=$characterId');

    try {
      return await updateCharacterEndpoint(
        characterId: characterId,
        name: name,
        tags: tags,
        persona: persona,
      );
    } catch (e) {
      _logger.severe('Failed to update character $characterId: $e');
      rethrow;
    }
  }

  Future<bool> deleteCharacter(String characterId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteCharacter called: characterId=$characterId');

    try {
      return await deleteCharacterEndpoint(characterId);
    } catch (e) {
      _logger.severe('Failed to delete character $characterId: $e');
      rethrow;
    }
  }

  Future<Result<bool>> setCharacterEnabled(
    String characterId,
    bool enabled,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: setCharacterEnabled called: characterId=$characterId, enabled=$enabled',
      );
      return await setCharacterEnabledEndpoint(characterId, enabled);
    });
  }

  Stream<ChatEvent> sendMessage(
    String message, {
    String? sessionId,
    String? agentName = 'memex_agent',
    String? scene = 'assistant',
    String? sceneId,
    List<Map<String, String>>? refs,
    List<XFile> images = const [],
    Map<String, String>? imageOriginalFilenames,
    String? audioPath,
    bool isQuickQuery = false,
    String runMode = 'auto',
    String? originalText,
    String? polishedStyle,
    bool verbatimText = false,
  }) async* {
    await _ensureInitialized();
    yield* ChatService.instance.sendMessage(
      message,
      sessionId: sessionId,
      agentName: agentName,
      scene: scene,
      sceneId: sceneId,
      refs: refs,
      images: images,
      imageOriginalFilenames: imageOriginalFilenames,
      audioPath: audioPath,
      isQuickQuery: isQuickQuery,
      runMode: runMode,
      originalText: originalText,
      polishedStyle: polishedStyle,
      verbatimText: verbatimText,
    );
  }

  /// Whether the session has an in-memory run or a persisted chat turn waiting
  /// to resume after app restart.
  Future<bool> hasActiveChatRun(String? sessionId) =>
      ChatService.instance.hasActiveRun(sessionId);

  /// Re-attaches to an in-flight chat run: replays missed events, then
  /// continues live.
  Stream<ChatEvent> attachToChatRun(String sessionId) =>
      ChatService.instance.attachToActiveRun(sessionId);

  Future<Result<String>> refreshSuperAgentChatState(String sessionId) {
    return runResult(() async {
      await _ensureInitialized();
      return ChatService.instance.refreshAgentStateForSession(sessionId);
    });
  }

  Future<Result<Map<String, dynamic>>> getMemory() async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final systemPath = fileSystemService.getSystemPath(userId);
      final memoryPath = path.join(systemPath, 'memory', 'memory.json');
      final file = File(memoryPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          return {'archived_memory': '', 'recent_buffer': []};
        }
        return jsonDecode(content) as Map<String, dynamic>;
      }
      return {'archived_memory': '', 'recent_buffer': []};
    });
  }

  /// Forces the recent memory buffer to consolidate into the archived
  /// profile right now, regardless of the normal size threshold. Returns
  /// whether there was anything in the buffer to consolidate.
  Future<Result<bool>> forceConsolidateMemory() async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final memoryManagement = await MemoryManagement.createDefault(
        userId: userId,
        sourceAgent: 'memory_agent',
      );
      return memoryManagement.forceConsolidate();
    });
  }

  /// Creates a new timeline card carrying a `media_card` ui_config directly
  /// (no LLM involved), for manually adding a 书影音 entry that quick-capture
  /// never saw. Mirrors the same metadata that [TimelineCardSkill] writes
  /// for LLM-created media cards, so the entry shows up identically in both
  /// the Media Library and the card detail page's media badges.
  Future<Result<String>> createMediaLibraryEntry({
    required String title,
    required String mediaType,
    String? mediaStatus,
    int? rating,
    String? comment,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final trimmedTitle = title.trim();
      final trimmedComment =
          (comment?.trim().isEmpty ?? true) ? null : comment!.trim();

      final data = {
        'media_type': mediaType,
        'title': trimmedTitle,
        if (mediaStatus != null) 'media_status': mediaStatus,
        if (rating != null) 'rating': rating,
        if (trimmedComment != null) 'comment': trimmedComment,
      };

      final factId = await FileSystemService.instance.allocateCardFactId(userId);
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: trimmedTitle,
          fact: trimmedComment ?? trimmedTitle,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          uiConfigs: [UiConfig(templateId: 'media_card', data: data)],
          metadata: mediaMetadataFromUiConfigData(data),
        ),
      );
      return factId;
    });
  }

  /// Creates a new timeline card carrying a `task` ui_config directly (no
  /// LLM involved), for manually adding a to-do that quick-capture's
  /// judgment call on whether to use the task template never saw.
  Future<Result<String>> createTaskEntry({
    required String title,
    DateTime? dueDate,
    String? priority,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final trimmedTitle = title.trim();
      final data = {
        'title': trimmedTitle,
        'is_completed': false,
        if (dueDate != null) 'due_date': dueDate.toIso8601String(),
        if (priority != null) 'priority': priority,
      };

      final factId = await FileSystemService.instance.allocateCardFactId(userId);
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        createIfNotExists: true,
        (card) => card.copyWith(
          status: 'completed',
          title: trimmedTitle,
          fact: trimmedTitle,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          uiConfigs: [UiConfig(templateId: 'task', data: data)],
        ),
      );
      return factId;
    });
  }

  Future<Result<List<Map<String, dynamic>>>> getRecentPkmFiles({
    int limit = 10,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: getRecentPkmFiles called: limit=$limit');
      final userId = await UserStorage.getUserId();
      if (userId == null) return <Map<String, dynamic>>[];
      return await fileSystemService.getRecentPkmFiles(userId, limit: limit);
    });
  }

  Future<Result<Map<String, int>>> countPkmItems(List<String> paths) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <String, int>{};
      return await fileSystemService.countPkmItems(userId, paths);
    });
  }

  Future<Result<Map<String, dynamic>>> listPkmDirectory({String? path}) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: listPkmDirectory called: path=$path');
      return await pkm_endpoint.listPkmDirectory(path: path);
    });
  }

  Future<Result<List<Map<String, dynamic>>>> searchPkmFiles(
    String query,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <Map<String, dynamic>>[];
      return await SearchService.instance.searchPkmFiles(userId, query);
    });
  }

  /// Search timeline cards using FTS5 full-text search.
  ///
  /// Returns hydrated [TimelineCardModel] list, same format as [fetchTimelineCards].
  Future<Result<List<TimelineCardModel>>> searchCards(
    String query, {
    int limit = 50,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <TimelineCardModel>[];

      final ftsResults = await SearchService.instance.searchCards(
        query,
        limit: limit,
      );

      final cards = <TimelineCardModel>[];
      for (final r in ftsResults) {
        final factId = r['fact_id'] as String;
        try {
          final card = await hydrateCard(userId, factId);
          if (card != null) cards.add(card);
        } catch (e) {
          _logger.warning('Failed to hydrate search result: $e');
        }
      }
      return cards;
    });
  }

  /// Search timeline cards using FTS5, returning each hydrated card
  /// alongside a readable snippet built from its own raw text/title.
  ///
  /// Order follows FTS `rank` (best match first), same as [searchCards].
  /// Intended for retrieval consumers (e.g. `CardRetriever`) that need the
  /// snippet text in addition to the hydrated model.
  ///
  /// Deliberately does NOT use FTS5's `content_snippet` column: that column
  /// is built from the jieba-tokenized index text (space-joined, with
  /// overlapping sub-word duplicates from `cutForSearch`), so it renders as
  /// garbled text like "今天 又 散步 了 十分 分钟 十分钟" instead of the
  /// original "今天又散步了十分钟". The hydrated card's own raw text is the
  /// only reliable source for a human-readable preview.
  Future<Result<List<({TimelineCardModel card, String snippet})>>>
      searchCardHits(
    String query, {
    int limit = 50,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <({TimelineCardModel card, String snippet})>[];

      final ftsResults = await SearchService.instance.searchCards(
        query,
        limit: limit,
      );

      final hits = <({TimelineCardModel card, String snippet})>[];
      for (final r in ftsResults) {
        final factId = r['fact_id'] as String;
        try {
          final card = await hydrateCard(userId, factId);
          if (card != null) {
            hits.add((
              card: card,
              snippet: _buildRawSnippet(card, query),
            ));
          }
        } catch (e) {
          _logger.warning('Failed to hydrate search result: $e');
        }
      }
      return hits;
    });
  }

  /// Rebuild the PKM FTS index (e.g. after import or manual trigger).
  Future<void> rebuildPkmFtsIndex() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await SearchService.instance.rebuildPkmFtsIndex(userId);
  }

  Future<Result<FileImportResult>> importFilesToUserSettingsImported(
    List<String> sourcePaths, {
    void Function(String status)? onProgress,
  }) {
    return runResult(() async {
      await _ensureInitialized();
      return FileImportService.instance.importToUserSettingsImported(
        sourcePaths,
        onProgress: onProgress,
      );
    });
  }

  /// Rebuild all FTS indexes (card + PKM). Intended for debugging / manual trigger.
  Future<void> rebuildAllFtsIndexes() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await SearchService.instance.rebuildAll(userId);
  }

  Future<Map<String, dynamic>> readPkmFile(String filePath) async {
    await _ensureInitialized();
    _logger.info('LocalMode: readPkmFile called: path=$filePath');

    try {
      return await pkm_endpoint.readPkmFileEndpoint(filePath);
    } catch (e) {
      _logger.severe('Failed to read PKM file: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAggregatedStatistics({
    DateTime? startDate,
    DateTime? endDate,
    String? scene,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: getAggregatedStatistics called');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        _logger.warning(
          'getAggregatedStatistics called without logged in user, returning empty',
        );
        return {};
      }

      return await LLMCallRecordService.instance.getAggregatedStatistics(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        scene: scene,
      );
    } catch (e) {
      _logger.severe('Failed to get aggregated statistics: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getAgentUsages({
    DateTime? startDate,
    DateTime? endDate,
    String? scene,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: getAgentUsages called');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        return [];
      }

      return await LLMCallRecordService.instance.getAllRecords(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        scene: scene,
      );
    } catch (e) {
      _logger.severe('Failed to get agent usages: $e');
      return [];
    }
  }

  Future<bool> uploadWorkspace(String targetUserId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: uploadWorkspace not supported (client-only)');
    return false;
  }

  Future<List<Map<String, dynamic>>> listSharedWorkspaces() async {
    await _ensureInitialized();
    return [];
  }

  Future<bool> downloadWorkspace(
    String workspaceName, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: downloadWorkspace not supported (client-only)');
    return false;
  }

  Future<List<LLMConfig>> getLLMConfigs() => UserStorage.getLLMConfigs();

  Future<String?> getUserAvatar() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) return null;

    final meta = await fileSystemService.readProfileMeta(userId);
    var avatar = meta['avatar'] as String?;
    if (avatar == null || avatar.isEmpty) {
      final legacyAvatar = await UserStorage.getUserAvatar();
      if (legacyAvatar != null && legacyAvatar.isNotEmpty) {
        meta['avatar'] = legacyAvatar;
        await fileSystemService.writeProfileMeta(userId, meta);
        avatar = legacyAvatar;
      }
    }
    if (avatar == null || avatar.isEmpty) {
      return null;
    }

    return AvatarMediaService.resolveAvatarPath(
      avatar,
      fileSystemService: fileSystemService,
    );
  }

  Future<void> updateUserAvatar(String avatar) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('User not logged in');
    }

    final meta = await fileSystemService.readProfileMeta(userId);
    meta['avatar'] = avatar;
    await fileSystemService.writeProfileMeta(userId, meta);
    AvatarMediaService.precacheDiceBearAvatar(avatar);
    EventBusService.instance.emitEvent(
      ProfileUpdatedMessage(userId: userId, avatar: avatar),
    );
  }

  Future<void> saveLLMConfigs(List<LLMConfig> configs) async {
    await UserStorage.saveLLMConfigs(configs);
    _emitLLMConfigChanged(configs, reason: 'saved');
  }

  Future<void> resetLLMConfigs() async {
    await UserStorage.resetLLMConfigs();
    final configs = await UserStorage.getLLMConfigs();
    _emitLLMConfigChanged(configs, reason: 'reset');
  }

  Future<String> getDefaultLLMConfigKey() =>
      UserStorage.getDefaultLLMConfigKey();

  Future<void> setDefaultLLMConfigKey(String configKey) async {
    await UserStorage.setDefaultLLMConfigKey(configKey);
    final configs = await UserStorage.getLLMConfigs();
    _emitLLMConfigChanged(configs, reason: 'default_changed');
  }

  void _emitLLMConfigChanged(
    List<LLMConfig> configs, {
    required String reason,
  }) {
    EventBusService.instance.emitEvent(
      LLMConfigChangedMessage(
        hasValidConfig: configs.any((c) => c.isValid),
        reason: reason,
      ),
    );
  }

  Future<AgentConfig> getAgentConfig(String agentId) =>
      UserStorage.getAgentConfig(agentId);

  Future<void> saveAgentConfig(String agentId, AgentConfig config) =>
      UserStorage.saveAgentConfig(agentId, config);

  Future<void> saveOpenAiAuth(Map<String, dynamic> authData) async {
    // local_todo: to be implemented
    // Usually local mode doesn't need to sync to backend, but we can implement it as a no-op
    // or log it here.
    return;
  }

  Future<void> resetAllAgentConfigs() => UserStorage.resetAllAgentConfigs();

  Future<List<Task>> getTasks({int limit = 10, int offset = 0}) =>
      LocalTaskExecutor.instance.getTasks(limit: limit, offset: offset);

  Future<TaskActivitySnapshot> getTaskActivitySnapshot() async {
    await _ensureInitialized();
    return LocalTaskExecutor.instance.getTaskActivitySnapshot();
  }

  // ---------------------------------------------------------------------------
  // Card-detail notification helpers
  // ---------------------------------------------------------------------------

  /// Resolve the [CardData] for a notification's subject card.
  /// Returns `null` if the card no longer exists or the user is not logged in.
  Future<CardData?> resolveCardForNotification(String factId) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    return FileSystemService.instance.readCardFile(userId, factId);
  }

  /// Dismiss a user notification by its primary key.
  Future<void> dismissNotification(String id) async {
    await _ensureInitialized();
    await UserNotificationService.instance.dismiss(id);
  }

  /// Register a card detail page as viewing [factId] (foreground suppression).
  void registerCardDetailForeground(String factId) {
    CardDetailNotifier.instance.registerForeground(factId);
  }

  /// Unregister a card detail page for [factId].
  void unregisterCardDetailForeground(String factId) {
    CardDetailNotifier.instance.unregisterForeground(factId);
  }

  /// Dismiss any pending card-detail notification after the user has viewed
  /// the card's latest content.
  Future<void> dismissCardDetailOnViewed(String factId) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await CardDetailNotifier.instance.dismissOnViewed(userId, factId);
  }
}

/// Builds a human-readable search-result snippet from a card's own raw
/// text/title, centred on [query] when it appears. Never reads the FTS
/// tokenized index text (see [MemexRouter.searchCardHits] for why).
@visibleForTesting
String buildRawSnippet(TimelineCardModel card, String query, {int maxLen = 80}) =>
    _buildRawSnippet(card, query, maxLen: maxLen);

String _buildRawSnippet(TimelineCardModel card, String query, {int maxLen = 80}) {
  final text = (card.rawText?.trim().isNotEmpty ?? false)
      ? card.rawText!.trim()
      : (card.title?.trim() ?? '');
  if (text.isEmpty) return '';

  final idx = text.toLowerCase().indexOf(query.trim().toLowerCase());
  if (idx < 0) {
    return text.length <= maxLen ? text : '${text.substring(0, maxLen)}...';
  }

  final start = (idx - 20).clamp(0, text.length);
  final end = (idx + query.trim().length + 60).clamp(0, text.length);
  final prefix = start > 0 ? '...' : '';
  final suffix = end < text.length ? '...' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}
