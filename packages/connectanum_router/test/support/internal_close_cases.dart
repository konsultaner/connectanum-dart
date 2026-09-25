part of '../router_runtime_test.dart';

void _internalCloseCases() {
  group('internal session close ownership', () {
    for (final registration in [false, true]) {
      for (final deferred in [false, true]) {
        test(
          'cancel callback can await close registration=$registration deferred=$deferred',
          () async {
            final fixture = _internalCloseFixture();
            final session = await fixture.binding.createInternalSession(
              realmUri: 'realm1',
            );
            final entered = Completer<void>();
            final rescue = Completer<void>();
            var reentrantCompleted = false;
            var cancellations = 0;
            Future<void> cancel() async {
              cancellations++;
              if (deferred) await Future<void>.value();
              final nested = session.close().then((_) {
                reentrantCompleted = true;
              });
              entered.complete();
              await Future.any([nested, rescue.future]);
            }

            final Future<void> Function() closeSource;
            if (registration) {
              final owner = await session.register('app.reentrant_close');
              final source = StreamController<core.Invocation>(
                onCancel: cancel,
              );
              owner.invocationStream = source.stream;
              owner.onInvoke((_) {});
              closeSource = source.close;
            } else {
              final owner = await session.subscribe('app.reentrant_close');
              final source = StreamController<Event>(onCancel: cancel);
              owner.eventStream = source.stream;
              owner.onEvent((_) {});
              closeSource = source.close;
            }
            addTearDown(closeSource);
            final closing = session.close();
            try {
              expect(session.close(), same(closing));
              await _assertInternalCloseCompletes(entered.future);
              // The controlled callback has no remaining I/O or timer work.
              await Future<void>(() {});
              expect(
                reentrantCompleted,
                isTrue,
                reason: 'Cancellation must not wait for its own owner shutdown',
              );
            } finally {
              // Release the original deadlock so a failing regression cleans up.
              rescue.complete();
              await closing;
            }
            expect(cancellations, 1);
            expect(session.close(), same(closing));
            expect(fixture.binding.internalSessionForRealm('realm1'), isNull);
            expect(fixture.errors, isEmpty);
          },
        );
      }
    }

    test('cleanup bypass is scoped to its own session', () async {
      final fixture = _internalCloseFixture();
      final first = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final second = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final enteredFirst = Completer<void>();
      final enteredSecond = Completer<void>();
      final releaseSecond = Completer<void>();
      final secondOwner = await second.subscribe('app.other_close');
      final secondSource = StreamController<Event>(
        onCancel: () {
          enteredSecond.complete();
          return releaseSecond.future;
        },
      );
      secondOwner.eventStream = secondSource.stream;
      secondOwner.onEvent((_) {});
      addTearDown(secondSource.close);
      final secondClosing = second.close();
      await _assertInternalCloseCompletes(enteredSecond.future);
      final firstOwner = await first.subscribe('app.first_close');
      Future<void>? observedOther;
      final firstSource = StreamController<Event>(
        onCancel: () {
          observedOther = second.close();
          enteredFirst.complete();
          return observedOther;
        },
      );
      firstOwner.eventStream = firstSource.stream;
      firstOwner.onEvent((_) {});
      addTearDown(firstSource.close);
      final firstClosing = first.close();
      var externalCompleted = false;
      final external = first.close().then((_) => externalCompleted = true);
      try {
        await _assertInternalCloseCompletes(enteredFirst.future);
        await Future<void>(() {});
        expect(observedOther, same(secondClosing));
        expect(externalCompleted, isFalse);
        expect(first.close(), same(firstClosing));
      } finally {
        releaseSecond.complete();
        await Future.wait([firstClosing, secondClosing, external]);
      }
      expect(externalCompleted, isTrue);
      expect(fixture.errors, isEmpty);
    });

    test('concurrent close waits for the first shutdown', () async {
      final fixture = _internalCloseFixture();
      final session = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      var firstCompleted = false;
      final first = session.close().then((_) => firstCompleted = true);
      addTearDown(() => first);
      await session.close();
      expect(
        firstCompleted,
        isTrue,
        reason: 'Every close waiter must observe completed shutdown',
      );
      await first;
      expect(fixture.errors, isEmpty);
    });

    for (final kind in ['registration', 'subscription']) {
      test('paused $kind consumer cannot hold shutdown open', () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        final done = Completer<void>();
        final StreamSubscription<Object?> consumer;
        if (kind == 'registration') {
          final registered = await session.register('app.close');
          consumer = registered.invocationStream!.listen(
            (_) => fail('No invocation was issued'),
            onDone: done.complete,
          );
        } else {
          final subscribed = await session.subscribe('app.close');
          consumer = subscribed.eventStream!.listen(
            (_) => fail('No event was published'),
            onDone: done.complete,
          );
        }
        consumer.pause();
        var completed = false;
        final closing = session.close().then((_) => completed = true);
        addTearDown(() async {
          consumer.resume();
          await consumer.cancel();
          await closing;
        });
        final deadline = Completer<void>();
        final timer = Timer(const Duration(seconds: 2), deadline.complete);
        addTearDown(timer.cancel);
        await Future.any<Object?>([closing, deadline.future]);
        expect(
          completed,
          isTrue,
          reason: 'Shutdown must finish without resuming application streams',
        );
        expect(done.isCompleted, isFalse);
        consumer.resume();
        await _assertInternalCloseCompletes(done.future);
        await closing;
        expect(fixture.errors, isEmpty);
      });
    }

    test('paused pending call cannot hold shutdown open', () async {
      final fixture = _internalCloseFixture();
      final session = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final callee = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final registered = await callee.register('app.pending_close');
      final invoked = Completer<void>();
      registered.onInvoke((_) => invoked.complete());
      final done = Completer<void>();
      final received = <Object>[];
      final consumer = session
          .call('app.pending_close')
          .listen(
            received.add,
            onError: (Object error) => received.add(error),
            onDone: done.complete,
          );
      addTearDown(consumer.cancel);
      await _assertInternalCloseCompletes(invoked.future);
      consumer.pause();
      var completed = false;
      final closing = session.close().then((_) => completed = true);
      addTearDown(() async {
        consumer.resume();
        await consumer.cancel();
        await closing;
      });
      final deadline = Completer<void>();
      final timer = Timer(const Duration(seconds: 2), deadline.complete);
      addTearDown(timer.cancel);
      await Future.any<Object?>([closing, deadline.future]);
      expect(
        completed,
        isTrue,
        reason: 'Paused calls cannot retain session ownership',
      );
      expect(done.isCompleted, isFalse);
      consumer.resume();
      await _assertInternalCloseCompletes(done.future);
      expect(received, isEmpty);
      expect(fixture.errors, isEmpty);
    });

    test('new commands are rejected as soon as close starts', () async {
      final fixture = _internalCloseFixture();
      final session = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      final closing = session.close();
      addTearDown(() => closing);
      await expectLater(session.register('app.late'), throwsStateError);
      await expectLater(session.subscribe('app.late'), throwsStateError);
      await _assertInternalCloseCompletes(closing);
      expect(() => session.call('app.late'), throwsStateError);
      expect(fixture.binding.internalSessionForRealm('realm1'), isNull);
      expect(fixture.errors, isEmpty);
    });

    test(
      'cleanup failure is shared and does not skip remaining owners',
      () async {
        final fixture = _internalCloseFixture();
        final session = await fixture.binding.createInternalSession(
          realmUri: 'realm1',
        );
        final registered = await session.register('app.failure_close');
        final subscribed = await session.subscribe('app.failure_close');
        final registrationDone = Completer<void>();
        final subscriptionDone = Completer<void>();
        final invocationListener = registered.invocationStream!.listen(
          (_) => fail('No invocation was issued'),
          onDone: registrationDone.complete,
        );
        final eventListener = subscribed.eventStream!.listen(
          (_) => fail('No event was published'),
          onDone: subscriptionDone.complete,
        );
        addTearDown(invocationListener.cancel);
        addTearDown(eventListener.cancel);
        final primary = StateError('first registration cancellation failure');
        final secondary = StateError('later event cancellation failure');
        final cancellationOrder = <String>[];
        Future<void>? reentered;
        final invocations = StreamController<core.Invocation>(
          onCancel: () {
            cancellationOrder.add('registration');
            reentered = session.close();
            throw primary;
          },
        );
        final events = StreamController<Event>(
          onCancel: () {
            cancellationOrder.add('subscription');
            throw secondary;
          },
        );
        registered.invocationStream = invocations.stream;
        registered.onInvoke((_) {});
        subscribed.eventStream = events.stream;
        subscribed.onEvent((_) {});
        addTearDown(invocations.close);
        addTearDown(events.close);
        addTearDown(() async {
          for (final close in [
            registered.closeInvocationStream,
            subscribed.closeEventStream,
          ]) {
            try {
              await close();
            } catch (error) {
              if (!identical(error, primary) && !identical(error, secondary))
                rethrow;
            }
          }
        });
        final closing = session.close();
        final first = expectLater(closing, throwsA(same(primary)));
        final second = expectLater(session.close(), throwsA(same(primary)));
        await Future.wait([first, second]);
        expect(reentered, isNotNull);
        await reentered;
        await expectLater(session.close(), throwsA(same(primary)));
        expect(cancellationOrder, ['registration', 'subscription']);
        await Future<void>.delayed(Duration.zero);
        expect(registrationDone.isCompleted, isTrue);
        expect(subscriptionDone.isCompleted, isTrue);
        expect(fixture.binding.internalSessionForRealm('realm1'), isNull);
        expect(fixture.errors, isEmpty);
        await expectLater(
          session.register('app.after_close'),
          throwsStateError,
        );
      },
    );
  });
}

_BossHttpFixture _internalCloseFixture() {
  final runtime = _BossHttpRuntime();
  final events = <Map<String, Object?>>[];
  final binding =
      Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      ).start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) events.add(event);
        },
      );
  // Keep teardown in the close future's error zone: an error future cannot
  // cross a runZonedGuarded boundary, even when the awaiting code catches it.
  final fixture = _BossHttpFixture(binding, runtime, Zone.current, events, []);
  addTearDown(fixture.dispose);
  // A deliberately failed close must not strand the fixture's native owners.
  addTearDown(() => fixture.drain(timeout: const Duration(milliseconds: 50)));
  return fixture;
}

Future<void> _assertInternalCloseCompletes(Future<void> future) async {
  final deadline = Completer<bool>();
  final timer = Timer(
    const Duration(seconds: 2),
    () => deadline.complete(false),
  );
  try {
    expect(
      await Future.any([future.then((_) => true), deadline.future]),
      isTrue,
      reason: 'Expected session lifecycle signal before the assertion deadline',
    );
  } finally {
    timer.cancel();
  }
}
