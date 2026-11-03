import 'dart:async';

/// Serialize read/modify/write workers; failures never poison later retries.
class SerialWorkQueue {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() work) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await previous;
      try {
        return await work();
      } finally {
        done.complete();
      }
    }();
  }
}
