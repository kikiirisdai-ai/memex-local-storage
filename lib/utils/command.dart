// Copyright 2024 The Memex team. All rights reserved.
// Command pattern for async operations with running/error/completed state (Compass-style).
// UI can ListenableBuilder(listenable: viewModel.load) for loading/error/retry.

import 'package:flutter/foundation.dart';
import 'package:memex/utils/result.dart';

abstract class Command<T> extends ChangeNotifier {
  Command();

  bool _running = false;
  Result<T>? _result;

  bool get running => _running;
  bool get error => _result is Error<T>;
  bool get completed => _result is Ok<T>;
  Result<T>? get result => _result;

  Future<void> _execute(Future<Result<T>> Function() action) async {
    if (_running) return;
    _running = true;
    _result = null;
    notifyListeners();

    try {
      _result = await action();
    } catch (e, st) {
      _result = Error<T>(e, st);
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// Command with no parameters (e.g. load, refresh).
class Command0<T> extends Command<T> {
  Command0(this._action);

  final Future<Result<T>> Function() _action;

  Future<void> execute() => _execute(_action);
}

/// Command with one parameter (e.g. deleteBooking(id)).
class Command1<T, A> extends Command<T> {
  Command1(this._action);

  final Future<Result<T>> Function(A a) _action;

  Future<void> execute(A a) => _execute(() => _action(a));
}
