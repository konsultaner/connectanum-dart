part of '../router_runtime_test.dart';

void _internalCallLifecycleCases() {
  group('internal call lifecycle', () {
    test(
      'transfer callback cannot admit a call after starting close',
      () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        addTearDown(session.close);
        Future<void>? closing;
        final options = CallOptions();
        options.custom['nested'] = _ClosingInternalTransferMap(() {
          closing ??= session.close();
        });
        final uncaught = <Object>[];
        StreamSubscription<core.Result>? consumer;
        var rejected = false;
        runZonedGuarded(() {
          try {
            consumer = session
                .call('app.transfer_close', options: options)
                .listen(
                  (_) {},
                  onError: (Object error) => uncaught.add(error),
                );
          } on StateError {
            rejected = true;
          }
        }, (error, stack) => uncaught.add(error));
        addTearDown(() => consumer?.cancel());
        expect(closing, isNotNull);
        await closing;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          rejected,
          isTrue,
          reason: 'Transfer callbacks cannot bypass closed-session admission',
        );
        expect(uncaught, isEmpty);
      },
    );

    for (final lazy in [false, true]) {
      test('failed isolate send leaves no pending error lazy=$lazy', () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        addTearDown(session.close);
        final unsendable = ReceivePort();
        addTearDown(unsendable.close);
        final uncaught = <Object>[];
        var rejected = false;
        runZonedGuarded(() {
          try {
            if (lazy) {
              session.callLazyPayload(
                'app.invalid',
                payload: LazyMessagePayload.materialized(
                  arguments: [unsendable],
                ),
              );
            } else {
              session.call('app.invalid', arguments: [unsendable]);
            }
          } on ArgumentError {
            rejected = true;
          }
        }, (error, stack) => uncaught.add(error));
        expect(rejected, isTrue);
        await session.close();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          uncaught,
          isEmpty,
          reason: 'A synchronous send failure must roll back pending ownership',
        );
      });
    }

    for (final lazy in [false, true]) {
      for (final waitForClose in [false, true]) {
        test('closed admission lazy=$lazy completed=$waitForClose', () async {
          final fixture = _internalCloseFixture();
          final session = await fixture.binding.createInternalSession(
            realmUri: 'realm1',
          );
          final closing = session.close();
          addTearDown(() => closing);
          if (waitForClose) await closing;
          final options = _ObservedInternalCallOptions();
          expect(
            () => lazy
                ? session.callLazyPayload(
                    'app.closed',
                    payload: LazyMessagePayload.materialized(arguments: [1]),
                    options: options,
                  )
                : session.call('app.closed', options: options),
            throwsA(isA<StateError>()),
          );
          expect(
            options.reads,
            0,
            reason: 'Closed admission must precede application option getters',
          );
          await closing;
        });
      }
    }

    for (final terminal in ['closed', 'result', 'consumer cancelled']) {
      for (final cancellationError in [false, true]) {
        test('late cancel after $terminal error=$cancellationError', () async {
          final fixture = _internalCloseFixture();
          final session = await fixture.binding.createInternalSession(
            realmUri: 'realm1',
          );
          final callee = await fixture.binding.createInternalSession(
            realmUri: 'realm1',
          );
          addTearDown(session.close);
          addTearDown(callee.close);
          final registered = await callee.register('app.late_cancel');
          final invoked = Completer<void>();
          registered.onInvoke((invocation) {
            invoked.complete();
            if (terminal == 'result') {
              invocation.respondWith(arguments: ['completed']);
            }
          });
          final probe = _InternalCallProbe(session, 'app.late_cancel');
          addTearDown(probe.consumer.cancel);
          await _assertInternalCloseCompletes(invoked.future);
          if (terminal == 'closed') {
            await session.close();
            await _assertInternalCloseCompletes(probe.done.future);
          } else if (terminal == 'result') {
            await _assertInternalCloseCompletes(probe.done.future);
            expect(probe.results.single.arguments, ['completed']);
          } else {
            await probe.consumer.cancel();
          }
          final errorsBefore = List<Object>.of(probe.errors);
          if (cancellationError) {
            probe.cancellation.completeError(StateError('late cancellation'));
          } else {
            probe.cancellation.complete(core.CancelOptions.modeKillNoWait);
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            probe.uncaught,
            isEmpty,
            reason: 'A completed call no longer owns a cancellation outcome',
          );
          expect(probe.errors, errorsBefore);
          expect(fixture.errors, isEmpty);
        });
      }
    }

    test('active cancellation failure reaches only its call stream', () async {
      final fixture = _internalCloseFixture();
      final session = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final callee = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      addTearDown(session.close);
      addTearDown(callee.close);
      final registered = await callee.register('app.cancel_failure');
      final invoked = Completer<void>();
      final otherInvoked = Completer<void>();
      final invocations = <core.Invocation>[];
      registered.onInvoke((invocation) {
        invocations.add(invocation);
        if (invocations.length == 1) {
          invoked.complete();
        } else {
          otherInvoked.complete();
        }
      });
      final probe = _InternalCallProbe(session, 'app.cancel_failure');
      addTearDown(probe.consumer.cancel);
      await _assertInternalCloseCompletes(invoked.future);
      final other = _InternalCallProbe(session, 'app.cancel_failure');
      addTearDown(other.consumer.cancel);
      await _assertInternalCloseCompletes(otherInvoked.future);
      final failure = StateError('cancellation source failed');
      final stack = StackTrace.current;
      probe.cancellation.completeError(failure, stack);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(probe.uncaught, isEmpty);
      expect(probe.errors, [same(failure)]);
      expect(probe.stacks.single, same(stack));
      await _assertInternalCloseCompletes(probe.done.future);
      expect(other.errors, isEmpty);
      expect(other.results, isEmpty);
      expect(other.done.isCompleted, isFalse);
      invocations.last.respondWith(arguments: ['independent']);
      await _assertInternalCloseCompletes(other.done.future);
      expect(other.results.single.arguments, ['independent']);
      expect(other.errors, isEmpty);
      other.cancellation.completeError(StateError('already completed'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(other.uncaught, isEmpty);
    });

    for (final mode in [
      core.CancelOptions.modeSkip,
      core.CancelOptions.modeKillNoWait,
    ]) {
      test('active $mode cancellation retains WAMP error', () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        final callee = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        addTearDown(session.close);
        addTearDown(callee.close);
        final registered = await callee.register('app.cancel_mode');
        final invoked = Completer<void>();
        registered.onInvoke((_) => invoked.complete());
        final probe = _InternalCallProbe(session, 'app.cancel_mode');
        addTearDown(probe.consumer.cancel);
        await _assertInternalCloseCompletes(invoked.future);
        probe.cancellation.complete(mode);
        await _assertInternalCloseCompletes(probe.done.future);
        expect(probe.results, isEmpty);
        expect(probe.errors, hasLength(1));
        expect(
          probe.errors.single,
          isA<core.Error>().having(
            (error) => error.error,
            'WAMP error URI',
            core.Error.errorInvocationCanceled,
          ),
        );
        expect(probe.uncaught, isEmpty);
      });
    }

    for (final lazy in [false, true]) {
      test('successful binary payload round trip lazy=$lazy', () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        final callee = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        addTearDown(session.close);
        addTearDown(callee.close);
        final registered = await callee.register('app.binary_echo');
        final bytes = Uint8List.fromList([0, 127, 128, 255]);
        final received = <core.Invocation>[];
        registered.onInvoke((invocation) {
          received.add(invocation);
          invocation.respondWith(
            arguments: invocation.arguments,
            argumentsKeywords: invocation.argumentsKeywords,
          );
        });
        final arguments = <dynamic>[bytes, 'payload'];
        final argumentsKeywords = <String, dynamic>{'count': 4};
        final results =
            await (lazy
                    ? session.callLazyPayload(
                        'app.binary_echo',
                        payload: LazyMessagePayload.materialized(
                          arguments: arguments,
                          argumentsKeywords: argumentsKeywords,
                        ),
                      )
                    : session.call(
                        'app.binary_echo',
                        arguments: arguments,
                        argumentsKeywords: argumentsKeywords,
                      ))
                .toList();
        expect(received.single.arguments, arguments);
        expect(received.single.argumentsKeywords, argumentsKeywords);
        expect(results.single.arguments, arguments);
        expect(results.single.argumentsKeywords, argumentsKeywords);
        expect(fixture.errors, isEmpty);
      });
    }
  });
}

class _ObservedInternalCallOptions extends CallOptions {
  int reads = 0;

  @override
  bool? get receiveProgress {
    reads++;
    return null;
  }
}

class _ClosingInternalTransferMap extends MapBase<String, Object?> {
  final void Function() onRead;

  _ClosingInternalTransferMap(this.onRead);

  @override
  Iterable<MapEntry<String, Object?>> get entries {
    onRead();
    return const [];
  }

  @override
  Iterable<String> get keys => const [];

  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read');

  @override
  void clear() => throw UnsupportedError('read');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read');
}

class _InternalCallProbe {
  final results = <core.Result>[];
  final errors = <Object>[];
  final stacks = <StackTrace>[];
  final uncaught = <Object>[];
  final done = Completer<void>();
  late final Completer<String> cancellation;
  late final StreamSubscription<core.Result> consumer;

  _InternalCallProbe(RouterSession session, String procedure) {
    // Construct and observe the cancellation future in one error zone. Capture
    // unhandled errors as assertion data, never count a test crash as evidence.
    runZonedGuarded(() {
      cancellation = Completer<String>();
      consumer = session
          .call(procedure, cancelCompleter: cancellation)
          .listen(
            results.add,
            onError: (Object error, StackTrace stack) {
              errors.add(error);
              stacks.add(stack);
            },
            onDone: done.complete,
          );
    }, (error, stack) => uncaught.add(error));
  }
}
