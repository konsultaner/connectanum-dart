part of '../router_runtime_test.dart';

void _httpBossOwnershipCases() {
  _httpBossTimeoutCases();
  group('HTTP boss ownership', () {
    for (final protocol in [
      NativeConnectionProtocol.http,
      NativeConnectionProtocol.http2,
      NativeConnectionProtocol.http3,
    ]) {
      for (final stage in ['method', 'body', 'observer']) {
        for (final releaseThrows in [false, true]) {
          test(
            '$protocol $stage failure releaseThrows=$releaseThrows',
            () async {
              final primary = StateError('controlled before-handoff failure');
              var entered = false;
              final fixture = _BossHttpFixture.start(
                onEvent: (event) {
                  if (stage == 'observer' &&
                      event['type'] == 'listener_http_request') {
                    entered = true;
                    throw primary;
                  }
                },
              );
              final handshake = _BossFailureHandshake(
                _bossRequest(protocol, 41001),
                stage: stage,
                fail: () {
                  entered = true;
                  throw primary;
                },
                releaseThrows: releaseThrows,
              );
              fixture.enqueue(protocol, 41001, handshake);
              await _waitUntil(() => entered);
              await Future<void>.delayed(Duration.zero);
              expect(fixture.errors, [same(primary)]);
              expect(
                handshake.releases,
                1,
                reason: 'The boss still owns a handshake before handoff.',
              );
              expect(fixture.runtime.httpResponses, isEmpty);
              expect(
                fixture.events.where(
                  (event) => event['type'] == 'http_request_dispatched',
                ),
                isEmpty,
              );
              final drainError = await fixture.drain();
              expect(
                drainError,
                same(primary),
                reason: 'The failed loop remains observable after cleanup.',
              );
              if (protocol == NativeConnectionProtocol.http3) {
                expect(fixture.runtime.connectionReleases, {41001: 1});
              }
              await fixture.dispose();
              expect(handshake.releases, 1);
            },
          );
        }
      }
    }

    for (final throwPending in [false, true]) {
      test(
        'pending observer=$throwPending cannot reclaim a handed-off request',
        () async {
          final primary = StateError('controlled after-handoff failure');
          final fixture = _BossHttpFixture.start(
            onEvent: (event) {
              if (throwPending &&
                  event['type'] == 'listener_protocol_pending' &&
                  event['connectionId'] == 41002) {
                throw primary;
              }
            },
          );
          final session = await fixture.binding.createInternalSession(
            realmUri: 'realm1',
          );
          final registration = await session.register('com.example.api.stream');
          final invoked = Completer<HttpInvocationContext>();
          registration.onInvoke((invocation) {
            invoked.complete(
              HttpInvocationContext.maybeFromInvocation(invocation)!,
            );
          });
          final handshake = _HttpEdgeHandshake(
            _bossRequest(NativeConnectionProtocol.http, 41002),
          );
          fixture.enqueue(NativeConnectionProtocol.http, 41002, handshake);
          final context = await invoked.future.timeout(
            const Duration(seconds: 3),
          );
          await Future<void>.delayed(Duration.zero);
          expect(fixture.errors, throwPending ? [same(primary)] : isEmpty);
          expect(
            handshake.releases,
            0,
            reason: 'Only the pending RPC now owns this handshake.',
          );
          context.sendText(body: 'owned reply', status: HttpStatus.accepted);
          await _waitUntil(
            () => fixture.runtime.httpResponses[41002]?.isNotEmpty ?? false,
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            fixture.runtime.httpResponses[41002]!.single.status,
            HttpStatus.accepted,
          );
          expect(handshake.releases, 1);
          expect(await fixture.drain(), throwPending ? same(primary) : isNull);
          await fixture.dispose();
          expect(handshake.releases, 1);
        },
      );
    }

    for (final failLoop in [false, true]) {
      for (final failRelease in [false, true]) {
        test(
          'shutdown loopFailure=$failLoop releaseFailure=$failRelease drains every HTTP3 owner',
          () async {
            final primary = StateError('controlled loop failure');
            var entered = false;
            final fixture = _BossHttpFixture.start(
              onEvent: (event) {
                if (failLoop && event['type'] == 'listener_http_request') {
                  entered = true;
                  throw primary;
                }
              },
            );
            fixture.runtime.failConnectionRelease = failRelease ? 41003 : null;
            fixture.enqueueHttp3Connection(41003);
            fixture.enqueueHttp3Connection(41004);
            await _waitUntil(
              () =>
                  fixture.events
                      .where(
                        (event) =>
                            event['type'] == 'listener_protocol_pending' &&
                            [41003, 41004].contains(event['connectionId']),
                      )
                      .length ==
                  2,
            );
            expect(fixture.runtime.connections, isEmpty);
            _HttpEdgeHandshake? request;
            if (failLoop) {
              request = _HttpEdgeHandshake(
                _bossRequest(NativeConnectionProtocol.http3, 41003),
              );
              fixture.runtime.enqueueHttp3Request(41003, request);
              await _waitUntil(() => entered);
              await Future<void>.delayed(Duration.zero);
            }
            final failure = await fixture.drain();
            expect(
              failure,
              failLoop
                  ? same(primary)
                  : failRelease
                  ? same(fixture.runtime.releaseError)
                  : isNull,
            );
            expect(
              fixture.runtime.connectionReleases,
              {41003: 1, 41004: 1},
              reason:
                  'A failed loop or release cannot strand another native owner.',
            );
            if (request != null) expect(request.releases, 1);
            await fixture.dispose();
            expect(fixture.runtime.connectionReleases, {41003: 1, 41004: 1});
          },
        );
      }
    }
  });
}

NativeHttpHandshake _bossRequest(
  NativeConnectionProtocol protocol,
  int handle,
) => NativeHttpHandshake.synthetic(
  handle: handle,
  method: 'GET',
  target: '/api/stream',
  path: '/api/stream',
  protocol: protocol == NativeConnectionProtocol.http3
      ? 'http/3'
      : protocol == NativeConnectionProtocol.http2
      ? 'h2'
      : 'http/1.1',
  headers: const {},
  body: Uint8List(0),
  realm: 'realm1',
  procedure: 'com.example.api.stream',
);

class _BossFailureHandshake extends _HttpEdgeHandshake {
  _BossFailureHandshake(
    super.delegate, {
    required this.stage,
    required this.fail,
    required this.releaseThrows,
  });
  final String stage;
  final Never Function() fail;
  final bool releaseThrows;
  final releaseError = StateError(
    'controlled secondary handshake release failure',
  );
  @override
  String get method => stage == 'method' ? fail() : super.method;
  @override
  NativeHttpRequestBody get body => stage == 'body' ? fail() : super.body;
  @override
  void release() {
    super.release();
    if (releaseThrows) throw releaseError;
  }
}

class _BossHttpRuntime extends _HandleRuntime {
  final connections = <int, NativeHttp3Connection>{};
  final connectionReleases = <int, int>{};
  int? failConnectionRelease;
  final releaseError = StateError(
    'controlled HTTP3 connection release failure',
  );
  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) =>
      connections.remove(connectionId);

  void prepareConnection(int id) {
    connectionReleases[id] = 0;
    connections[id] = NativeHttp3Connection(
      handle: id,
      release: () {
        connectionReleases[id] = connectionReleases[id]! + 1;
        if (failConnectionRelease == id) throw releaseError;
      },
    );
  }
}

class _BossHttpFixture {
  _BossHttpFixture(
    this.binding,
    this.runtime,
    this.zone,
    this.events,
    this.errors,
  );
  final RouterBinding binding;
  final _BossHttpRuntime runtime;
  final Zone zone;
  final List<Map<String, Object?>> events;
  final List<Object> errors;

  static _BossHttpFixture start({
    void Function(Map<String, Object?>)? onEvent,
    RouterWorkerEntryPoint? workerEntryPoint,
  }) {
    final runtime = _BossHttpRuntime();
    final events = <Map<String, Object?>>[];
    final errors = <Object>[];
    late Zone zone;
    final binding = runZonedGuarded(() {
      zone = Zone.current;
      return Router(
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
        workerEntryPoint: workerEntryPoint,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
            onEvent?.call(event);
          }
        },
      );
    }, (error, _) => errors.add(error))!;
    final fixture = _BossHttpFixture(binding, runtime, zone, events, errors);
    addTearDown(fixture.dispose);
    return fixture;
  }

  void enqueue(
    NativeConnectionProtocol protocol,
    int id,
    NativeHttpHandshake request,
  ) {
    if (protocol == NativeConnectionProtocol.http3) {
      enqueueHttp3Connection(id);
      runtime.enqueueHttp3Request(id, request);
    } else {
      runtime.setConnectionProtocol(id, protocol);
      runtime.enqueueHttpHandshake(
        binding.listeners.single.listenerId,
        id,
        request,
      );
    }
  }

  void enqueueHttp3Connection(int id) {
    runtime.prepareConnection(id);
    runtime.setConnectionProtocol(id, NativeConnectionProtocol.http3);
    runtime.enqueueHttp3Handshake(
      id,
      NativeHttp3Handshake.synthetic(
        handle: id,
        protocol: 'http/3',
        listenerProtocols: const ['http3'],
      ),
    );
    runtime.enqueueConnection(binding.listeners.single.listenerId, id);
  }

  Future<Object?> drain({Duration timeout = const Duration(seconds: 1)}) =>
      zone.run(() async {
        try {
          await binding.drain(drainTimeout: timeout);
          return null;
        } catch (error) {
          return error;
        }
      });

  Future<void> dispose() => zone.run(() async {
    try {
      await binding.dispose();
    } catch (_) {
      // Assertions inspect drain failures; teardown must not add kill credit.
    }
  });
}

void _httpBossTimeoutCases() {
  group('HTTP boss timeout precedence', () {
    for (final failLoop in [false, true]) {
      for (final failObserver in [false, true]) {
        test('loop=$failLoop timeoutObserver=$failObserver', () async {
          final primary = StateError('controlled loop failure before drain');
          final secondary = StateError('controlled timeout observer failure');
          var entered = false;
          final fixture = _BossHttpFixture.start(
            workerEntryPoint: _idleWorkerEntryPoint,
            onEvent: (event) {
              if (failLoop && event['type'] == 'listener_http_request') {
                entered = true;
                throw primary;
              }
              if (failObserver && event['type'] == 'worker_drain_timeout') {
                throw secondary;
              }
            },
          );
          fixture.runtime.enqueueConnection(
            fixture.binding.listeners.single.listenerId,
            42001,
          );
          await _waitUntil(
            () => fixture.events.any(
              (event) =>
                  event['type'] == 'worker_ready' &&
                  event['connectionId'] == 42001,
            ),
          );
          fixture.enqueueHttp3Connection(42002);
          await _waitUntil(
            () => fixture.events.any(
              (event) =>
                  event['type'] == 'listener_protocol_pending' &&
                  event['connectionId'] == 42002,
            ),
          );
          expect(fixture.runtime.connections, isEmpty);
          _HttpEdgeHandshake? request;
          if (failLoop) {
            request = _HttpEdgeHandshake(
              _bossRequest(NativeConnectionProtocol.http3, 42002),
            );
            fixture.runtime.enqueueHttp3Request(42002, request);
            await _waitUntil(() => entered);
            await Future<void>.delayed(Duration.zero);
            expect(fixture.errors, [same(primary)]);
          }
          final failure = await fixture.drain(
            timeout: const Duration(milliseconds: 25),
          );
          expect(
            fixture.events.where(
              (event) => event['type'] == 'worker_drain_timeout',
            ),
            hasLength(1),
          );
          expect(
            failure,
            failLoop
                ? same(primary)
                : failObserver
                ? same(secondary)
                : isNull,
          );
          expect(fixture.runtime.connectionReleases, {42002: 1});
          if (request != null) expect(request.releases, 1);
          await fixture.dispose();
          expect(fixture.runtime.connectionReleases, {42002: 1});
        });
      }
    }
  });
}
