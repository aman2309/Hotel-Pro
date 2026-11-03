import 'dart:async';

/// Shares an initialization attempt; a failure is never cached as permanent.
class RetryableTask<T> {
  Future<T>? _future;
  void reset() => _future = null;
  Future<T> run(Future<T> Function() work) {
    final existing = _future;
    if (existing != null) return existing;
    final done = Completer<T>();
    final current = done.future;
    _future = current;
    () async {
      try {
        done.complete(await work());
      } catch (error, stack) {
        if (identical(_future, current)) _future = null;
        done.completeError(error, stack);
      }
    }();
    return current;
  }
}
