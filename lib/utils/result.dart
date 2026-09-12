// Copyright 2024 The Memex team. All rights reserved.
// Result type for explicit success/error handling (Compass-style).
// Use with: switch (result) { case Ok(): ... case Error(): ... }

sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  /// For Result<void>; use as Ok.v.
  const Ok.v() : value = null as T;
}

final class Error<T> extends Result<T> {
  const Error(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;
}

extension ResultExtension<T> on Result<T> {
  R when<R>({
    required R Function(T value) onOk,
    required R Function(Object error, StackTrace? stackTrace) onError,
  }) {
    return switch (this) {
      Ok(:final value) => onOk(value),
      Error(:final error, :final stackTrace) => onError(error, stackTrace),
    };
  }

  T get valueOrThrow {
    return switch (this) {
      Ok(:final value) => value,
      Error(:final error) => throw error,
    };
  }

  bool get isOk => this is Ok<T>;
  bool get isError => this is Error<T>;
}

/// Wraps a throwing [Future] into [Future<Result<T>>].
Future<Result<T>> runResult<T>(Future<T> Function() f) async {
  try {
    final value = await f();
    return Ok(value);
  } catch (e, st) {
    return Error<T>(e, st);
  }
}

/// Wraps a throwing [Future<void>] into [Future<Result<void>>].
Future<Result<void>> runResultVoid(Future<void> Function() f) async {
  try {
    await f();
    return const Ok.v();
  } catch (e, st) {
    return Error<void>(e, st);
  }
}
