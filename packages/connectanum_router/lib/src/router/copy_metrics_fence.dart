import 'dart:async';

/// Fence previously submitted asynchronous operations before a synchronous
/// snapshot, and hold subsequent operations until that snapshot is captured.
class CopyMetricsFence {
  final Set<Future<void>> _pending = {};
  Future<void>? _barrier;
  bool _failed = false;

  Future<void> submit(Future<void> Function() operation) {
    final previousBarrier = _barrier;
    late final Future<void> tracked;
    final running = previousBarrier == null
        ? Future<void>.sync(operation)
        : previousBarrier.then((_) => operation());
    tracked = running.then<void>(
      (_) => _pending.remove(tracked),
      onError: (Object error, StackTrace trace) {
        _failed = true;
        _pending.remove(tracked);
        Error.throwWithStackTrace(error, trace);
      },
    );
    _pending.add(tracked);
    return tracked;
  }

  Future<T> snapshot<T>(
    T Function() read, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final previousBarrier = _barrier;
    final prior = List<Future<void>>.of(_pending);
    final prerequisites = _failed
        ? Future<List<void>>.error(
            StateError('Copy observation already failed'),
          )
        : Future.wait<void>([
            ?previousBarrier,
            ...prior,
          ]).timeout(
            timeout,
            onTimeout: () {
              _failed = true;
              throw TimeoutException(
                'Copy observation did not settle',
                timeout,
              );
            },
          );
    final result = prerequisites.then((_) {
      if (_failed) throw StateError('Copy observation lost a failed operation');
      return read();
    });
    // This non-failing gate still releases later work if observation fails.
    final release = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    late final Future<void> gate;
    gate =
        (previousBarrier == null
                ? release
                : Future.wait<void>([
                    previousBarrier,
                    release,
                  ]).then<void>((_) {}))
            .whenComplete(() {
              if (identical(_barrier, gate)) _barrier = null;
            });
    _barrier = gate;
    return result;
  }
}
