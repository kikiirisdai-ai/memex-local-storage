import 'dart:async';
import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

/// How long AI work must stay active before the manual terminate button
/// appears. Shorter than [taskExecutionTimeout] so the escape hatch is
/// reachable before the first execution timeout even fires.
const Duration kStuckAiTasksThreshold = Duration(minutes: 2);

class AgentActivityWidget extends StatefulWidget {
  final bool forceVisible;
  final TaskActivitySnapshot initialTaskSnapshot;
  final Stream<TaskActivitySnapshot>? taskActivitySnapshotStream;

  /// Overrides the terminate action; defaults to the router. For tests.
  final Future<int> Function()? onTerminateTasks;

  const AgentActivityWidget({
    super.key,
    this.forceVisible = false,
    this.initialTaskSnapshot = const TaskActivitySnapshot.empty(),
    this.taskActivitySnapshotStream,
    this.onTerminateTasks,
  });

  @override
  State<AgentActivityWidget> createState() => _AgentActivityWidgetState();
}

class _AgentActivityWidgetState extends State<AgentActivityWidget> {
  StreamSubscription<TaskActivitySnapshot>? _taskSubscription;
  Timer? _initRetryTimer;
  TaskActivitySnapshot _taskSnapshot = const TaskActivitySnapshot.empty();
  Timer? _stuckTicker;

  bool get _isActive {
    return widget.forceVisible || _taskSnapshot.hasActiveTasks;
  }

  /// True once the oldest active task has been around longer than the
  /// threshold, which is when waiting stops being normal and the user needs a
  /// way out.
  bool get _isStuck {
    if (!_taskSnapshot.hasActiveTasks) return false;
    final since = _taskSnapshot.oldestActiveSince;
    if (since == null) return false;
    return DateTime.now().difference(since) >= kStuckAiTasksThreshold;
  }

  @override
  void initState() {
    super.initState();
    _taskSnapshot = widget.initialTaskSnapshot;
    _subscribeToTaskStream();
    _syncStuckTicker();
  }

  void _scheduleInitRetry() {
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer(
      const Duration(seconds: 1),
      () {
        if (mounted) _subscribeToTaskStream();
      },
    );
  }

  void _subscribeToTaskStream() {
    _initRetryTimer?.cancel();
    _initRetryTimer = null;
    var needsRetry = false;

    try {
      final taskStream = widget.taskActivitySnapshotStream ??
          LocalTaskExecutor.instance.taskActivitySnapshotStream;
      _taskSubscription ??= taskStream.listen((snapshot) {
        if (mounted) {
          setState(() => _taskSnapshot = snapshot);
          _syncStuckTicker();
        }
      });
    } catch (_) {
      needsRetry = true;
    }

    unawaited(_loadCurrentState());
    if (needsRetry) _scheduleInitRetry();
  }

  Future<void> _loadCurrentState() async {
    try {
      if (widget.taskActivitySnapshotStream == null) {
        final snapshot =
            await LocalTaskExecutor.instance.getTaskActivitySnapshot();
        if (mounted) {
          setState(() => _taskSnapshot = snapshot);
          _syncStuckTicker();
        }
      }
    } catch (_) {}
  }

  /// The stuck state is time-based, so it needs a periodic re-render while
  /// work is active. No active work means no ticker.
  void _syncStuckTicker() {
    if (_taskSnapshot.hasActiveTasks && !_isStuck) {
      _stuckTicker ??= Timer.periodic(
        const Duration(seconds: 10),
        (_) {
          setState(() {});
          // Stuck is a one-way flip, so stop re-rendering once it is true
          // rather than ticking on until the next snapshot arrives.
          if (_isStuck) _syncStuckTicker();
        },
      );
    } else {
      _stuckTicker?.cancel();
      _stuckTicker = null;
    }
  }

  Future<void> _terminateTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.cancelAllAiTasks),
        content: Text(UserStorage.l10n.cancelAllAiTasksConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(UserStorage.l10n.cancelAllAiTasks),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final terminate = widget.onTerminateTasks ??
          context.read<MemexRouter>().cancelAllActiveAiTasks;
      final cancelled = await terminate();
      if (!mounted) return;
      if (cancelled > 0) {
        ToastHelper.showSuccess(
          context,
          UserStorage.l10n.cancelAllAiTasksDone(cancelled),
        );
      } else {
        ToastHelper.showInfo(context, UserStorage.l10n.cancelAllAiTasksNone);
      }
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError(
        context,
        UserStorage.l10n.cancelAllAiTasksFailed(e),
      );
    }
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _initRetryTimer?.cancel();
    _stuckTicker?.cancel();
    super.dispose();
  }

  /// Thin, non-interactive loading bar (browser-tab-style) instead of a
  /// pill with text — the pill sat over content and had to keep being
  /// repositioned. This is a status signal only, no tap target, no text.
  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          key: ValueKey('agent_activity_loading_bar'),
          height: 2,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
        if (_isStuck) _buildTerminateButton(),
      ],
    );
  }

  Widget _buildTerminateButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Material(
          key: const ValueKey('agent_activity_terminate_button'),
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _terminateTasks,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.stop_circle_outlined,
                    size: 16,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    UserStorage.l10n.aiTasksStuckTerminate,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
