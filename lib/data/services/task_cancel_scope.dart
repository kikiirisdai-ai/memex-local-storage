import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

/// Zone-scoped [CancelToken] for the task currently being executed.
///
/// [LocalTaskExecutor] installs the running task's token here so nested agent
/// runs (the parent chat turn, delegated children, comment/memory/companion
/// agents) can abort their in-flight LLM requests when the user terminates AI
/// work, without every intermediate call site threading the token through its
/// own signature. Mirrors the `DelegateProgressContext` pattern.
class TaskCancelScope {
  TaskCancelScope._();

  static final Object _zoneKey = Object();

  static CancelToken? get current => Zone.current[_zoneKey] as CancelToken?;

  static R run<R>(CancelToken token, R Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: token});
}
