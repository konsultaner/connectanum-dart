@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:test/test.dart';

void main() {
  for (final variant in ['stream', 'single', 'payload', 'lazy', 'lazy-input']) {
    for (final succeeds in [false, true]) {
      test('$variant call preserves wire data, success=$succeeds', () async {
        final peer = await _WirePeer.start();
        addTearDown(peer.close);
        final session = await peer.connect();
        addTearDown(session.close);
        final options = wamp.CallOptions(timeout: 1234);
        const args = [11, 'query'];
        const kwargs = <String, Object?>{'optional': null, 'label': 'request'};
        final Future<dynamic> result = switch (variant) {
          'stream' =>
            session
                .call(
                  'bench.echo',
                  arguments: args,
                  argumentsKeywords: kwargs,
                  options: options,
                )
                .then((stream) => stream.single),
          'single' => session.callSingle(
            'bench.echo',
            arguments: args,
            argumentsKeywords: kwargs,
            options: options,
          ),
          'payload' => session.callSinglePayload(
            'bench.echo',
            arguments: args,
            argumentsKeywords: kwargs,
            options: options,
          ),
          'lazy' => session.callSingleLazyPayload(
            'bench.echo',
            arguments: args,
            argumentsKeywords: kwargs,
            options: options,
          ),
          _ => session.callSingleWithLazyPayload(
            'bench.echo',
            payload: wamp.LazyMessagePayload.materialized(
              arguments: args,
              argumentsKeywords: kwargs,
            ),
            options: options,
          ),
        };
        final errorExpectation = succeeds
            ? null
            : expectLater(
                result,
                throwsA(
                  isA<wamp.Error>().having(
                    (e) => e.error,
                    'error URI',
                    'com.example.denied',
                  ),
                ),
              );
        final call = await peer.next();
        expect(call, [
          48,
          isA<int>(),
          {'timeout': 1234},
          'bench.echo',
          args,
          kwargs,
        ]);
        if (succeeds) {
          peer.send([
            50,
            call[1],
            {},
            [22, 'answer'],
            {'optional': null, 'result': true},
          ]);
          final dynamic value = await result;
          expect(value.callRequestId, call[1]);
          expect(value.arguments, [22, 'answer']);
          expect(value.argumentsKeywords, {'optional': null, 'result': true});
        } else {
          peer.send([8, 48, call[1], {}, 'com.example.denied']);
          await errorExpectation;
        }
      });
    }
  }

  for (final lazy in [false, true]) {
    test(
      'publish lazy=$lazy forwards payload/options and waits for ack',
      () async {
        final peer = await _WirePeer.start();
        addTearDown(peer.close);
        final session = await peer.connect();
        addTearDown(session.close);
        final options = wamp.PublishOptions(
          acknowledge: true,
          excludeMe: false,
          retain: true,
        );
        const args = [7];
        const kwargs = <String, Object?>{'value': null};
        var acknowledged = false;
        final sent =
            (lazy
                    ? session.publishLazyPayload(
                        'bench.topic',
                        payload: wamp.LazyMessagePayload.materialized(
                          arguments: args,
                          argumentsKeywords: kwargs,
                        ),
                        options: options,
                      )
                    : session.publish(
                        'bench.topic',
                        arguments: args,
                        argumentsKeywords: kwargs,
                        options: options,
                      ))
                .then((_) => acknowledged = true);
        final publish = await peer.next();
        expect(publish, [
          16,
          isA<int>(),
          {'acknowledge': true, 'exclude_me': false, 'retain': true},
          'bench.topic',
          args,
          kwargs,
        ]);
        expect(acknowledged, isFalse);
        peer.send([17, publish[1], 801]);
        await sent;
        expect(acknowledged, isTrue);
      },
    );
  }

  for (final variant in ['event-stream', 'event-callback', 'payload', 'lazy']) {
    for (final revoked in [false, true]) {
      test('$variant subscription lifecycle, revoked=$revoked', () async {
        final peer = await _WirePeer.start();
        addTearDown(peer.close);
        final session = await peer.connect();
        addTearDown(session.close);
        final options = wamp.SubscribeOptions(
          match: 'prefix',
          getRetained: true,
        );
        final pending = switch (variant) {
          'payload' => session.subscribePayload(
            'bench.topic',
            options: options,
          ),
          'lazy' => session.subscribeLazyPayload(
            'bench.topic',
            options: options,
          ),
          _ => session.subscribe('bench.topic', options: options),
        };
        final subscribe = await peer.next();
        expect(subscribe, [
          32,
          isA<int>(),
          {'match': 'prefix', 'get_retained': true},
          'bench.topic',
        ]);
        peer.send([33, subscribe[1], 901]);
        final subscription = await pending;
        expect(subscription.id, 901);
        final delivered = Completer<wamp.LazyEventPayload>();
        final Future<wamp.LazyEventPayload> event;
        if (variant == 'event-stream') {
          expect(subscription.events, same(subscription.events));
          event = subscription.events.first;
        } else {
          subscription.onEvent(delivered.complete);
          event = delivered.future;
        }
        peer.send([
          36,
          901,
          902,
          {'publisher': 903, 'topic': 'bench.topic.child'},
          [9],
          {'nullable': null},
        ]);
        final received = await event;
        expect(received.subscriptionId, 901);
        expect(received.publicationId, 902);
        expect(received.publisher, 903);
        expect(received.topic, 'bench.topic.child');
        expect(received.arguments, [9]);
        expect(received.argumentsKeywords, {'nullable': null});
        if (revoked) {
          final revocation = subscription.onRevoke;
          expect(revocation, isNotNull);
          peer.send([
            35,
            0,
            {'subscription': 901, 'reason': 'com.example.revoked'},
          ]);
          await revocation;
        } else {
          final cancelled = subscription.cancel();
          final unsubscribe = await peer.next();
          expect(unsubscribe, [34, isA<int>(), 901]);
          peer.send([35, unsubscribe[1]]);
          await cancelled;
        }
      });
    }
  }

  test(
    'registration forwards lazy invocation and removes the correct id',
    () async {
      final peer = await _WirePeer.start();
      addTearDown(peer.close);
      final session = await peer.connect();
      addTearDown(session.close);
      final invoked = Completer<wamp.LazyInvocationPayload>();
      final pending = session.registerLazyPayloadHandler('bench.echo', (
        invocation,
      ) {
        invoked.complete(invocation);
        invocation.respondWith(
          arguments: [42],
          argumentsKeywords: {'answer': true},
        );
      }, options: wamp.RegisterOptions(match: 'prefix', invoke: 'roundrobin'));
      final register = await peer.next();
      expect(register, [
        64,
        isA<int>(),
        {'match': 'prefix', 'invoke': 'roundrobin'},
        'bench.echo',
      ]);
      peer.send([65, register[1], 991]);
      final registration = await pending;
      expect(registration.id, 991);
      peer.send([
        68,
        992,
        991,
        {'caller': 4322, 'procedure': 'bench.echo.child'},
        [41],
        {'input': null},
      ]);
      final invocation = await invoked.future;
      expect(invocation.requestId, 992);
      expect(invocation.registrationId, 991);
      expect(invocation.caller, 4322);
      expect(invocation.procedure, 'bench.echo.child');
      expect(invocation.arguments, [41]);
      expect(invocation.argumentsKeywords, {'input': null});
      expect(await peer.next(), [
        70,
        992,
        {},
        [42],
        {'answer': true},
      ]);
      expect(invocation.isResponseClosed(), isTrue);
      final cancelled = registration.cancel();
      final unregister = await peer.next();
      expect(unregister, [66, isA<int>(), 991]);
      peer.send([67, unregister[1]]);
      await cancelled;
    },
  );

  for (final finalArguments in <List<dynamic>?>[
    null,
    [3],
  ]) {
    test(
      'progressive facade forwards chunks and terminal $finalArguments',
      () async {
        final peer = await _WirePeer.start();
        addTearDown(peer.close);
        final session = await peer.connect();
        addTearDown(session.close);
        final call = session.startProgressiveCall(
          'bench.stream',
          arguments: [1],
          argumentsKeywords: {'trace': true},
          options: wamp.CallOptions(receiveProgress: true),
        );
        final results = call.results.toList();
        final initial = await peer.next();
        expect(initial, [
          48,
          isA<int>(),
          {'progress': true, 'receive_progress': true},
          'bench.stream',
          [1],
          {'trace': true},
        ]);
        call.sendChunk(arguments: [2]);
        expect(await peer.next(), [
          48,
          initial[1],
          {'progress': true},
          'bench.stream',
          [2],
        ]);
        peer.send([
          50,
          initial[1],
          {'progress': true},
          [10],
        ]);
        call.finish(arguments: finalArguments);
        expect(await peer.next(), [
          48,
          initial[1],
          {'progress': false},
          'bench.stream',
          ?finalArguments,
        ]);
        peer.send([
          50,
          initial[1],
          {},
          [20],
          {'done': true},
        ]);
        final received = await results;
        expect(received, hasLength(2));
        expect(received.map((result) => result.callRequestId), [
          initial[1],
          initial[1],
        ]);
        expect(received.map((result) => result.arguments), [
          [10],
          [20],
        ]);
        expect(received.map((result) => result.isProgressive()), [true, false]);
        expect(received.last.argumentsKeywords, {'done': true});
        expect(() => call.sendChunk(arguments: [99]), throwsStateError);
        expect(() => call.finish(), throwsStateError);
      },
    );
  }

  test('disconnect during cancellation cannot be counted as success', () async {
    final peer = await _WirePeer.start();
    addTearDown(peer.close);
    final session = await peer.connect();
    addTearDown(session.close);
    expect(session.id, 4321);
    final outcome = expectLater(
      session.cancelingCall('bench.pending', cancelMode: 'killnowait'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Session transport closed',
        ),
      ),
    );
    final call = await peer.next();
    expect(await peer.next(), [
      49,
      call[1],
      {'mode': 'killnowait'},
    ]);
    await peer.disconnect();
    await outcome;
    await session.onDisconnect;
    await session.close();
    await session.close();
  });

  test(
    'concurrent cancellation outcomes stay isolated and allow recovery',
    () async {
      final peer = await _WirePeer.start();
      addTearDown(peer.close);
      final session = await peer.connect();
      addTearDown(session.close);
      var firstFinished = false;
      final first = session
          .cancelingCall('bench.first', cancelMode: 'killnowait')
          .then((_) => firstFinished = true);
      final second = expectLater(
        session.cancelingCall('bench.second', cancelMode: 'killnowait'),
        throwsA(
          isA<wamp.Error>().having(
            (e) => e.error,
            'error URI',
            'wamp.error.not_authorized',
          ),
        ),
      );
      final frames = [
        await peer.next(),
        await peer.next(),
        await peer.next(),
        await peer.next(),
      ];
      final calls = frames.where((frame) => frame[0] == 48).toList();
      expect(calls.map((frame) => frame[3]), ['bench.first', 'bench.second']);
      expect(calls[0][1], isNot(calls[1][1]));
      expect(
        frames.where((frame) => frame[0] == 49),
        unorderedEquals([
          [
            49,
            calls[0][1],
            {'mode': 'killnowait'},
          ],
          [
            49,
            calls[1][1],
            {'mode': 'killnowait'},
          ],
        ]),
      );
      peer.send([8, 48, calls[1][1], {}, 'wamp.error.not_authorized']);
      await second;
      expect(firstFinished, isFalse);
      peer.send([8, 48, calls[0][1], {}, 'wamp.error.canceled']);
      await first;
      peer.send([
        50,
        calls[0][1],
        {},
        ['late cancelled result'],
      ]);
      final recovery = session.callSingle('bench.echo', arguments: ['fresh']);
      final call = await peer.next();
      expect(call, [
        48,
        isA<int>(),
        {},
        'bench.echo',
        ['fresh'],
      ]);
      expect(calls.map((frame) => frame[1]), isNot(contains(call[1])));
      peer.send([
        50,
        call[1],
        {},
        ['fresh answer'],
      ]);
      final wamp.Result result = await recovery;
      expect(result.arguments, ['fresh answer']);
    },
  );

  for (final mode in ['skip', 'kill', 'killnowait']) {
    for (final errorUri in [
      'wamp.error.canceled',
      'wamp.error.invocation_canceled',
      'wamp.error.not_authorized',
      'wamp.error.no_such_procedure',
      'wamp.error.timeout',
      'wamp.error.runtime_error',
      'com.example.failure',
    ]) {
      test('cancel $mode classifies $errorUri', () async {
        final peer = await _WirePeer.start();
        addTearDown(peer.close);
        final session = await peer.connect();
        addTearDown(session.close);
        final cancelled = session.cancelingCall(
          'bench.pending',
          arguments: [17],
          argumentsKeywords: {'label': 'cancel-check'},
          cancelMode: mode,
          options: wamp.CallOptions(timeout: 1234),
        );
        final isCancellation =
            errorUri == 'wamp.error.canceled' ||
            errorUri == 'wamp.error.invocation_canceled';
        final outcome = expectLater(
          cancelled,
          isCancellation
              ? completes
              : throwsA(
                  isA<wamp.Error>()
                      .having((e) => e.error, 'error URI', errorUri)
                      .having((e) => e.arguments, 'arguments', [
                        'failed operation',
                      ])
                      .having((e) => e.argumentsKeywords, 'keywords', {
                        'code': 19,
                      }),
                ),
        );
        final call = await peer.next();
        expect(call, [
          48,
          isA<int>(),
          {'timeout': 1234},
          'bench.pending',
          [17],
          {'label': 'cancel-check'},
        ]);
        expect(await peer.next(), [
          49,
          call[1],
          {'mode': mode},
        ]);
        peer.send([
          8,
          48,
          call[1],
          {},
          errorUri,
          ['failed operation'],
          {'code': 19},
        ]);
        await outcome;
      });
    }
  }

  test('cancel benchmark rejects a successful result', () async {
    final peer = await _WirePeer.start();
    addTearDown(peer.close);
    final session = await peer.connect();
    addTearDown(session.close);
    final outcome = expectLater(
      session.cancelingCall('bench.pending', cancelMode: 'killnowait'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Cancelled call unexpectedly produced a result',
        ),
      ),
    );
    final call = await peer.next();
    expect(call.take(1), [48]);
    expect(await peer.next(), [
      49,
      call[1],
      {'mode': 'killnowait'},
    ]);
    peer.send([
      50,
      call[1],
      {},
      ['completed'],
    ]);
    await outcome;
  });
}

class _WirePeer {
  _WirePeer(this.server) {
    _requests = server.listen((request) async {
      try {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('wamp.2.json') ? 'wamp.2.json' : null,
        );
        _socket = socket;
        _messages = socket.listen((data) {
          final message = (jsonDecode(data as String) as List).cast<dynamic>();
          if (message[0] == 1) {
            expect(message[1], 'bench.control');
            send([
              2,
              4321,
              {
                'roles': {
                  'dealer': {
                    'features': {
                      'call_canceling': true,
                      'progressive_call_results': true,
                      'progressive_call_invocations': true,
                    },
                  },
                  'broker': {
                    'features': {'subscription_revocation': true},
                  },
                },
              },
            ]);
          } else if (message[0] == 6) {
            send([6, {}, 'wamp.close.goodbye_and_out']);
          } else {
            _frames.add(message);
          }
        }, onError: _frames.addError);
      } catch (error, stack) {
        _frames.addError(error, stack);
      }
    });
  }

  static Future<_WirePeer> start() async =>
      _WirePeer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  final _frames = StreamController<List<dynamic>>();
  late final _queue = StreamIterator<List<dynamic>>(_frames.stream);
  late final StreamSubscription<HttpRequest> _requests;
  StreamSubscription<dynamic>? _messages;
  WebSocket? _socket;

  Future<WampSession> connect() => WebSocketWampSessionFactory(
    url: 'ws://127.0.0.1:${server.port}/wamp',
    realmUri: 'bench.control',
    clientImplementation: WampClientImplementation.dart,
    serializer: WampSerializer.json,
  ).call();

  Future<List<dynamic>> next() async {
    if (!await _queue.moveNext().timeout(const Duration(seconds: 3))) {
      throw StateError('Peer closed before the expected WAMP frame');
    }
    return _queue.current;
  }

  void send(List<dynamic> frame) => _socket!.add(jsonEncode(frame));

  Future<void> disconnect() async => _socket?.close();

  Future<void> close() async {
    await _queue.cancel();
    await _messages?.cancel();
    await _socket?.close();
    await _requests.cancel();
    await server.close(force: true);
    await _frames.close();
  }
}
