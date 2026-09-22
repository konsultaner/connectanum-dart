import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  test('existing zero-argument close overrides remain compatible', () async {
    final registered = _CustomRegistered();
    final subscribed = _CustomSubscribed();
    await registered.closeInvocationStream();
    await subscribed.closeEventStream();
    expect(registered.closeCalls, 1);
    expect(subscribed.closeCalls, 1);
  });

  for (final registration in [false, true]) {
    test(
      'owner close preserves queued delivery registration=$registration',
      () async {
        final received = <Object>[];
        final done = Completer<void>();
        final StreamSubscription<Object?> listener;
        final Future<void> Function() close;
        final Object message;
        if (registration) {
          final registered = Registered(1, 2);
          listener = registered.invocationStream!.listen(
            received.add,
            onDone: done.complete,
          );
          listener.pause();
          message = Invocation(
            3,
            2,
            InvocationDetails(null, null, false),
            arguments: ['buffered'],
          );
          registered.addInvocation(message as Invocation);
          close = () => closeInvocationStreamForOwner(registered);
        } else {
          final subscribed = Subscribed(1, 2);
          listener = subscribed.eventStream!.listen(
            received.add,
            onDone: done.complete,
          );
          listener.pause();
          message = Event(2, 3, EventDetails(), arguments: ['buffered']);
          subscribed.addEvent(message as Event);
          close = () => closeEventStreamForOwner(subscribed);
        }
        addTearDown(listener.cancel);
        final closing = close();
        addTearDown(() async {
          listener.resume();
          await listener.cancel();
          await closing;
        });
        await _assertStreamCloseCompletes(closing);
        expect(received, isEmpty);
        expect(done.isCompleted, isFalse);
        listener.resume();
        await _assertStreamCloseCompletes(done.future);
        expect(received, [same(message)]);
      },
    );

    test(
      'cancel failure still closes owned stream registration=$registration',
      () async {
        final failure = StateError('controlled stream cancellation failure');
        var done = false;
        final StreamSubscription<Object?> listener;
        final Future<void> Function() close;
        final Future<void> Function() closeSource;
        if (registration) {
          final registered = Registered(1, 2);
          listener = registered.invocationStream!.listen(
            (_) {},
            onDone: () => done = true,
          );
          final source = StreamController<Invocation>(
            onCancel: () => throw failure,
          );
          registered.invocationStream = source.stream;
          registered.onInvoke((_) {});
          close = registered.closeInvocationStream;
          closeSource = source.close;
        } else {
          final subscribed = Subscribed(1, 2);
          listener = subscribed.eventStream!.listen(
            (_) {},
            onDone: () => done = true,
          );
          final source = StreamController<Event>(onCancel: () => throw failure);
          subscribed.eventStream = source.stream;
          subscribed.onEvent((_) {});
          close = subscribed.closeEventStream;
          closeSource = source.close;
        }
        addTearDown(listener.cancel);
        addTearDown(closeSource);
        await expectLater(close(), throwsA(same(failure)));
        await Future<void>.delayed(Duration.zero);
        expect(
          done,
          isTrue,
          reason: 'Cancellation failure cannot skip owned-stream closure',
        );
      },
    );

    for (final waitForListeners in [true, false]) {
      for (final failCancel in [false, true]) {
        test(
          'stream close registration=$registration waits=$waitForListeners failure=$failCancel',
          () async {
            final cancelStarted = Completer<void>();
            final cancelReady = Completer<void>();
            final done = Completer<void>();
            final failure = StateError('controlled cancellation rejection');
            Future<void> cancel() {
              cancelStarted.complete();
              return cancelReady.future;
            }

            final StreamSubscription<Object?> listener;
            final Future<void> Function() close;
            final Future<void> Function() closeSource;
            if (registration) {
              final registered = Registered(1, 2);
              listener = registered.invocationStream!.listen(
                (_) => fail('No invocation was issued'),
                onDone: done.complete,
              );
              final source = StreamController<Invocation>(onCancel: cancel);
              registered.invocationStream = source.stream;
              registered.onInvoke((_) {});
              close = waitForListeners
                  ? registered.closeInvocationStream
                  : () => closeInvocationStreamForOwner(registered);
              closeSource = source.close;
            } else {
              final subscribed = Subscribed(1, 2);
              listener = subscribed.eventStream!.listen(
                (_) => fail('No event was published'),
                onDone: done.complete,
              );
              final source = StreamController<Event>(onCancel: cancel);
              subscribed.eventStream = source.stream;
              subscribed.onEvent((_) {});
              close = waitForListeners
                  ? subscribed.closeEventStream
                  : () => closeEventStreamForOwner(subscribed);
              closeSource = source.close;
            }
            listener.pause();
            var closed = false;
            Object? closeError;
            // An outstanding expectLater would delay teardown after an earlier
            // assertion fails, preventing teardown from resuming the listener.
            final closing = close().then<void>(
              (_) => closed = true,
              onError: (Object error) {
                closeError = error;
                closed = true;
              },
            );
            addTearDown(() async {
              if (!cancelReady.isCompleted) cancelReady.complete();
              listener.resume();
              await listener.cancel();
              await closing;
              await closeSource();
            });
            await _assertStreamCloseCompletes(cancelStarted.future);
            expect(
              closed,
              isFalse,
              reason: 'Even owner mode must await override cancellation',
            );
            expect(done.isCompleted, isFalse);
            if (failCancel) {
              cancelReady.completeError(failure);
            } else {
              cancelReady.complete();
            }
            await Future<void>.delayed(Duration.zero);
            expect(
              closed,
              !waitForListeners,
              reason: 'Only the default mode waits for application listeners',
            );
            expect(done.isCompleted, isFalse);
            listener.resume();
            await _assertStreamCloseCompletes(done.future);
            await closing;
            expect(closed, isTrue);
            expect(closeError, failCancel ? same(failure) : isNull);
          },
        );
      }
    }
  }
}

Future<void> _assertStreamCloseCompletes(Future<void> future) async {
  final deadline = Completer<bool>();
  final timer = Timer(
    const Duration(seconds: 2),
    () => deadline.complete(false),
  );
  try {
    expect(
      await Future.any([future.then((_) => true), deadline.future]),
      isTrue,
      reason: 'Expected stream lifecycle signal without application resumption',
    );
  } finally {
    timer.cancel();
  }
}

class _CustomRegistered extends Registered {
  _CustomRegistered() : super(1, 2);
  int closeCalls = 0;
  @override
  Future<void> closeInvocationStream() async {
    closeCalls++;
    await super.closeInvocationStream();
  }
}

class _CustomSubscribed extends Subscribed {
  _CustomSubscribed() : super(1, 2);
  int closeCalls = 0;
  @override
  Future<void> closeEventStream() async {
    closeCalls++;
    await super.closeEventStream();
  }
}
