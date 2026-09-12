import 'dart:async';
import 'package:flutter/material.dart';
import 'package:memex/data/services/local_task_executor.dart';

class AgentActivityWidget extends StatefulWidget {
  final bool forceVisible;
  final TaskActivitySnapshot initialTaskSnapshot;
  final Stream<TaskActivitySnapshot>? taskActivitySnapshotStream;

  const AgentActivityWidget({
    super.key,
    this.forceVisible = false,
    this.initialTaskSnapshot = const TaskActivitySnapshot.empty(),
    this.taskActivitySnapshotStream,
  });

  @override
  State<AgentActivityWidget> createState() => _AgentActivityWidgetState();
}

class _AgentActivityWidgetState extends State<AgentActivityWidget> {
  StreamSubscription<TaskActivitySnapshot>? _taskSubscription;
  Timer? _initRetryTimer;
  TaskActivitySnapshot _taskSnapshot = const TaskActivitySnapshot.empty();

  bool get _isActive {
    return widget.forceVisible || _taskSnapshot.hasActiveTasks;
  }

  @override
  void initState() {
    super.initState();
    _taskSnapshot = widget.initialTaskSnapshot;
    _subscribeToTaskStream();
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
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _initRetryTimer?.cancel();
    super.dispose();
  }

  /// Thin, non-interactive loading bar (browser-tab-style) instead of a
  /// pill with text — the pill sat over content and had to keep being
  /// repositioned. This is a status signal only, no tap target, no text.
  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();

    return const SizedBox(
      key: ValueKey('agent_activity_loading_bar'),
      height: 2,
      child: LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
      ),
    );
  }
}
