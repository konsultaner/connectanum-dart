import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

enum _Handler { invocation, payload, lazy }

enum _Route { invocation, payload, lazy }

class _HandlerFailure implements Exception {
  const _HandlerFailure();

  @override
  String toString() => 'handler failed';
}

Invocation _invocation([int requestId = 101]) => Invocation(
  requestId,
  203,
  InvocationDetails(307, 'com.example.work', true)..timeout = 71,
  arguments: ['input'],
  argumentsKeywords: {'key': 'value'},
);

void _install(
  Registered registered,
  _Handler kind,
  FutureOr<void> Function() handler,
) {
  switch (kind) {
    case _Handler.invocation:
      expect(() => registered.onInvoke((_) => handler()), returnsNormally);
    case _Handler.payload:
      expect(
        () => registered.onInvokePayload((_) => handler()),
        returnsNormally,
      );
    case _Handler.lazy:
      expect(
        () => registered.onLazyInvokePayload((_) => handler()),
        returnsNormally,
      );
  }
}

void _send(Registered registered, _Route route, Invocation invocation) {
  switch (route) {
    case _Route.invocation:
      registered.addInvocation(invocation);
    case _Route.payload:
      registered.addInvocationPayload(invocation.toPayload());
    case _Route.lazy:
      registered.addLazyInvocationPayload(invocation.toLazyInvocationPayload());
  }
}

Future<void> _drainCallbacks() => Future<void>.delayed(Duration.zero);

void _expectUnknown(AbstractMessageWithPayload message, int requestId) {
  expect(message, isA<Error>());
  final error = message as Error;
  expect(error.id, 8);
  expect(error.requestTypeId, 68);
  expect(error.requestId, requestId);
  expect(error.error, 'wamp.error.unknown');
  expect(error.details, isEmpty);
  expect(error.arguments, ['handler failed']);
  expect(error.argumentsKeywords, isNull);
}

void main() {
  for (final kind in _Handler.values) {
    final routes = switch (kind) {
      _Handler.invocation => [_Route.invocation],
      _Handler.payload => [_Route.invocation, _Route.payload, _Route.lazy],
      _Handler.lazy => [_Route.invocation, _Route.lazy],
    };
    for (final route in routes) {
      group('${kind.name} handler via ${route.name}', () {
        for (final asynchronous in [false, true]) {
          test(
            'converts ${asynchronous ? "async" : "sync"} failure into one error',
            () async {
              final registered = Registered(17, 203);
              final invocation = _invocation();
              final responses = <AbstractMessageWithPayload>[];
              invocation.onResponse(responses.add);
              final gate = Completer<void>();
              var called = 0;
              if (asynchronous) {
                _install(registered, kind, () async {
                  called++;
                  await gate.future;
                  throw const _HandlerFailure();
                });
              } else {
                _install(registered, kind, () {
                  called++;
                  throw const _HandlerFailure();
                });
              }
              expect(
                () => _send(registered, route, invocation),
                returnsNormally,
              );
              expect(called, 1);
              if (asynchronous) {
                expect(responses, isEmpty);
                expect(invocation.responseClosed, isFalse);
                gate.complete();
              }
              await _drainCallbacks();
              expect(responses, hasLength(1));
              _expectUnknown(responses.single, 101);
              expect(invocation.responseClosed, isTrue);
              await registered.closeInvocationStream();
            },
          );
        }

        for (final finalError in [false, true]) {
          test(
            'does not answer twice after a final ${finalError ? "error" : "yield"}',
            () async {
              final registered = Registered(17, 203);
              final invocation = _invocation();
              final responses = <AbstractMessageWithPayload>[];
              invocation.onResponse(responses.add);
              final gate = Completer<void>();
              _install(registered, kind, () async {
                await gate.future;
                throw const _HandlerFailure();
              });
              final uncaught = <Object>[];
              runZonedGuarded(() {
                _send(registered, route, invocation);
                invocation.respondWith(
                  isError: finalError,
                  errorUri: finalError ? Error.notAuthorized : null,
                  arguments: ['first response'],
                );
              }, (error, stack) => uncaught.add(error));
              gate.complete();
              await _drainCallbacks();
              expect(uncaught, isEmpty);
              expect(invocation.responseClosed, isTrue);
              expect(responses, hasLength(1));
              expect(responses.single.arguments, ['first response']);
              expect(responses.single.id, finalError ? 8 : 70);
              await registered.closeInvocationStream();
            },
          );
        }

        test(
          'a progressive response still permits a terminal handler error',
          () async {
            final registered = Registered(17, 203);
            final invocation = _invocation();
            final responses = <AbstractMessageWithPayload>[];
            invocation.onResponse(responses.add);
            _install(registered, kind, () {
              invocation.respondWith(
                arguments: ['progress'],
                options: YieldOptions(progress: true),
              );
              expect(invocation.responseClosed, isFalse);
              throw const _HandlerFailure();
            });
            _send(registered, route, invocation);
            await _drainCallbacks();
            expect(responses, hasLength(2));
            final progress = responses.first as Yield;
            expect(progress.invocationRequestId, 101);
            expect(progress.options!.progress, isTrue);
            expect(progress.arguments, ['progress']);
            _expectUnknown(responses.last, 101);
            expect(invocation.responseClosed, isTrue);
            await registered.closeInvocationStream();
          },
        );

        test(
          'a failed invocation does not poison subsequent delivery',
          () async {
            final registered = Registered(17, 203);
            var called = 0;
            _install(registered, kind, () {
              if (called++ == 0) throw const _HandlerFailure();
            });
            final first = _invocation(101);
            final second = _invocation(109);
            final firstResponses = <AbstractMessageWithPayload>[];
            final secondResponses = <AbstractMessageWithPayload>[];
            first.onResponse(firstResponses.add);
            second.onResponse(secondResponses.add);
            _send(registered, route, first);
            _send(registered, route, second);
            await _drainCallbacks();
            expect(called, 2);
            expect(firstResponses, hasLength(1));
            _expectUnknown(firstResponses.single, 101);
            expect(secondResponses, isEmpty);
            expect(second.responseClosed, isFalse);
            await registered.closeInvocationStream();
          },
        );

        test(
          'out-of-order failures remain bound to their invocation',
          () async {
            final registered = Registered(17, 203);
            final gates = [Completer<void>(), Completer<void>()];
            var called = 0;
            _install(registered, kind, () async {
              final gate = gates[called++];
              await gate.future;
              throw const _HandlerFailure();
            });
            final first = _invocation(101);
            final second = _invocation(109);
            final firstResponses = <AbstractMessageWithPayload>[];
            final secondResponses = <AbstractMessageWithPayload>[];
            first.onResponse(firstResponses.add);
            second.onResponse(secondResponses.add);
            _send(registered, route, first);
            _send(registered, route, second);
            expect(called, 2);
            gates[1].complete();
            await _drainCallbacks();
            expect(firstResponses, isEmpty);
            expect(first.responseClosed, isFalse);
            expect(secondResponses, hasLength(1));
            _expectUnknown(secondResponses.single, 109);
            gates[0].complete();
            await _drainCallbacks();
            expect(firstResponses, hasLength(1));
            _expectUnknown(firstResponses.single, 101);
            expect(secondResponses, hasLength(1));
            await registered.closeInvocationStream();
          },
        );
      });
    }
  }

  group('Registered delivery and lifecycle', () {
    test('consumer flags track handlers and lazy stream allocation', () async {
      final registered = Registered(17, 203);
      expect(registered.id, 65);
      expect(registered.registerRequestId, 17);
      expect(registered.registrationId, 203);
      expect(registered.hasMaterializedInvocationConsumers, isFalse);
      expect(registered.hasPayloadInvocationHandler, isFalse);
      expect(registered.hasLazyPayloadInvocationHandler, isFalse);
      registered.onInvokePayload((_) {});
      expect(registered.hasPayloadInvocationHandler, isTrue);
      expect(registered.hasMaterializedInvocationConsumers, isFalse);
      registered.onLazyInvokePayload((_) {});
      expect(registered.hasLazyPayloadInvocationHandler, isTrue);
      expect(registered.hasMaterializedInvocationConsumers, isFalse);
      final stream = registered.invocationStream!;
      expect(stream.isBroadcast, isTrue);
      expect(registered.hasMaterializedInvocationConsumers, isTrue);
      await registered.closeInvocationStream();
      expect(registered.hasMaterializedInvocationConsumers, isFalse);
      registered.onInvoke((_) {});
      expect(registered.hasMaterializedInvocationConsumers, isTrue);
      await registered.closeInvocationStream();
    });

    test('fans out once to each handler and broadcast listener', () async {
      final registered = Registered(17, 203);
      final invocation = _invocation();
      final direct = <Invocation>[];
      final payloads = <InvocationPayload>[];
      final lazy = <LazyInvocationPayload>[];
      final streamedA = <Invocation>[];
      final streamedB = <Invocation>[];
      registered.onInvoke(direct.add);
      registered.onInvokePayload(payloads.add);
      registered.onLazyInvokePayload(lazy.add);
      final first = registered.invocationStream!.listen(streamedA.add);
      final second = registered.invocationStream!.listen(streamedB.add);
      registered.addInvocation(invocation);
      await _drainCallbacks();
      expect(direct, [same(invocation)]);
      expect(streamedA, [same(invocation)]);
      expect(streamedB, [same(invocation)]);
      expect(payloads, hasLength(1));
      expect(lazy, hasLength(1));
      for (final payload in [payloads.single, lazy.single.toPayload()]) {
        expect(payload.requestId, 101);
        expect(payload.registrationId, 203);
        expect(payload.caller, 307);
        expect(payload.procedure, 'com.example.work');
        expect(payload.receiveProgress, isTrue);
        expect(payload.timeout, 71);
        expect(payload.arguments, ['input']);
        expect(payload.argumentsKeywords, {'key': 'value'});
      }
      await first.cancel();
      await second.cancel();
      await registered.closeInvocationStream();
    });

    for (final route in [_Route.invocation, _Route.lazy]) {
      test(
        '${route.name} delivery stays lazy until a handler reads arguments',
        () async {
          final registered = Registered(17, 203);
          final invocation = _invocation();
          final bytes = Uint8List.fromList(utf8.encode('["encoded"]'));
          var decoded = 0;
          invocation.arguments = null;
          invocation.setLazyPayload(
            argumentsBytes: bytes,
            argumentsDecoder: (bytes) {
              decoded++;
              return jsonDecode(utf8.decode(bytes)) as List;
            },
            encoding: LazyPayloadEncoding.json,
          );
          LazyInvocationPayload? received;
          registered.onLazyInvokePayload((payload) => received = payload);
          _send(registered, route, invocation);
          expect(received, isNotNull);
          expect(received!.argumentsBytes, same(bytes));
          expect(decoded, 0);
          expect(received!.arguments, ['encoded']);
          expect(received!.arguments, ['encoded']);
          expect(decoded, 1);
          await registered.closeInvocationStream();
        },
      );
    }

    test('missing handlers do not force payload decoding', () async {
      final registered = Registered(17, 203);
      final invocation = _invocation();
      invocation.setLazyPayload(
        argumentsBytes: Uint8List(1),
        argumentsDecoder: (_) => throw StateError('must remain lazy'),
      );
      expect(() => registered.addInvocation(invocation), returnsNormally);
      expect(
        () => registered.addLazyInvocationPayload(
          invocation.toLazyInvocationPayload(),
        ),
        returnsNormally,
      );
      expect(
        () => registered.addInvocationPayload(_invocation().toPayload()),
        returnsNormally,
      );
      await registered.closeInvocationStream();
      await registered.closeInvocationStream();
    });

    for (final handlerFirst in [false, true]) {
      test(
        'attaches external stream once, handlerFirst=$handlerFirst',
        () async {
          var listened = 0;
          var cancelled = 0;
          final source = StreamController<Invocation>.broadcast(
            sync: true,
            onListen: () => listened++,
            onCancel: () => cancelled++,
          );
          final stream = source.stream;
          final registered = Registered(17, 203);
          final firstHandler = <Invocation>[];
          final nextHandler = <Invocation>[];
          addTearDown(() async {
            await registered.closeInvocationStream();
            await source.close();
          });
          if (handlerFirst) registered.onInvoke(firstHandler.add);
          registered.invocationStream = stream;
          if (!handlerFirst) {
            expect(source.hasListener, isFalse);
            registered.onInvoke(firstHandler.add);
          }
          expect(registered.invocationStream, same(stream));
          expect(listened, 1);
          final first = _invocation(101);
          source.add(first);
          registered.invocationStream = stream;
          registered.onInvoke(nextHandler.add);
          final second = _invocation(109);
          source.add(second);
          expect(listened, 1);
          expect(firstHandler, [same(first)]);
          expect(nextHandler, [same(second)]);
          await registered.closeInvocationStream();
          expect(source.hasListener, isFalse);
          expect(cancelled, 1);
          source.add(_invocation(113));
          expect(nextHandler, [same(second)]);
          await registered.closeInvocationStream();
          expect(cancelled, 1);
        },
      );
    }

    test(
      'close awaits asynchronous external subscription cancellation',
      () async {
        final cancelling = Completer<void>();
        final release = Completer<void>();
        var listened = false;
        final source = StreamController<Invocation>(
          onListen: () => listened = true,
          onCancel: () {
            cancelling.complete();
            return release.future;
          },
        );
        final registered = Registered(17, 203)
          ..invocationStream = source.stream;
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await registered.closeInvocationStream();
          // A never-listened single-subscription stream cannot finish closing.
          if (!listened) await source.stream.listen((_) {}).cancel();
          await source.close();
        });
        registered.onInvoke((_) {});
        expect(source.hasListener, isTrue);
        var closed = false;
        final closing = registered.closeInvocationStream().then(
          (_) => closed = true,
        );
        await _drainCallbacks();
        expect(cancelling.isCompleted, isTrue);
        expect(closed, isFalse);
        release.complete();
        await closing;
        expect(closed, isTrue);
      },
    );

    test(
      'cancel after dispatch retains delivered invocation and leaves peers active',
      () async {
        final registered = Registered(17, 203);
        final firstReceived = <Invocation>[];
        final secondReceived = <Invocation>[];
        final first = registered.invocationStream!.listen(firstReceived.add);
        final second = registered.invocationStream!.listen(secondReceived.add);
        addTearDown(() async {
          await first.cancel();
          await second.cancel();
          await registered.closeInvocationStream();
        });
        final invocation = _invocation(101);
        registered.addInvocation(invocation);
        await first.cancel();
        expect(firstReceived, [same(invocation)]);
        expect(secondReceived, [same(invocation)]);
        final next = _invocation(109);
        registered.addInvocation(next);
        await _drainCallbacks();
        expect(firstReceived, [same(invocation)]);
        expect(secondReceived, [same(invocation), same(next)]);
      },
    );

    test('closing broadcast delivery sends done to every listener', () async {
      final registered = Registered(17, 203);
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();
      final first = registered.invocationStream!.listen(
        (_) {},
        onDone: firstDone.complete,
      );
      final second = registered.invocationStream!.listen(
        (_) {},
        onDone: secondDone.complete,
      );
      await registered.closeInvocationStream();
      expect(firstDone.isCompleted, isTrue);
      expect(secondDone.isCompleted, isTrue);
      await first.cancel();
      await second.cancel();
      await registered.closeInvocationStream();
    });
  });
}
