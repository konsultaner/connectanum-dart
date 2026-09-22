part of '../router_runtime_test.dart';

void _httpEarlyCleanupCases() {
  group('HTTP early ownership', () {
    test(
      'valid session profile overrides an unconfigured requested realm',
      () async {
        final binding = _earlyCleanupRouter().start(_HandleRuntime());
        addTearDown(binding.dispose);
        RouterSession? session;
        Object? failure;
        try {
          session = await binding.createInternalSession(
            realmUri: 'absent',
            sessionProfile: 'configured',
          );
        } catch (error) {
          failure = error;
        }
        expect(
          failure,
          isNull,
          reason: 'The configured profile realm must win.',
        );
        expect(session?.realmUri, 'realm1');
        await session!.close();
      },
    );
    for (final realm in ['absent', '']) {
      test('internal session rejects unconfigured realm "$realm"', () async {
        final binding = _earlyCleanupRouter().start(_HandleRuntime());
        addTearDown(binding.dispose);
        await expectLater(
          binding.createInternalSession(realmUri: realm),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Realm $realm is not configured',
            ),
          ),
        );
        expect(binding.internalSessionForRealm(realm), isNull);
        final valid = await binding.createInternalSession(realmUri: 'realm1');
        expect(valid.realmUri, 'realm1');
        await valid.close();
      });
    }
    for (final (label, realm, procedure, path, eventType) in [
      (
        'missing native handle',
        'realm1',
        'api.echo',
        '/absent',
        'http_response_send_unsupported',
      ),
      (
        'null realm',
        null,
        'api.echo',
        '/api/echo',
        'http_request_unmapped_realm',
      ),
      (
        'empty realm',
        '',
        'api.echo',
        '/api/echo',
        'http_request_unmapped_realm',
      ),
      (
        'null procedure',
        'realm1',
        null,
        '/api/echo',
        'http_request_unmapped_procedure',
      ),
      (
        'empty procedure',
        'realm1',
        '',
        '/api/echo',
        'http_request_unmapped_procedure',
      ),
      (
        'unknown realm',
        'absent',
        'api.echo',
        '/api/echo',
        'http_request_session_error',
      ),
      (
        'missing handler',
        'realm1',
        'api.echo',
        '/missing',
        'http_handler_missing',
      ),
    ]) {
      for (final throwObserver in [false, true]) {
        test(
          '$label observer=$throwObserver releases before error reporting',
          () async {
            final runtime = _HandleRuntime();
            final events = <Map<String, Object?>>[];
            final observerError = StateError(
              'controlled early HTTP observer failure',
            );
            final escaped = <Object>[];
            final releaseCountsAtError = <int>[];
            final handshake = _HttpEdgeHandshake(
              NativeHttpHandshake.synthetic(
                handle: label == 'missing native handle' ? 0 : 32101,
                method: 'GET',
                target: path,
                path: path,
                protocol: 'http/1.1',
                headers: const {},
                body: Uint8List(0),
                realm: realm,
                procedure: procedure,
              ),
            );
            final binding = runZonedGuarded(
              () => _earlyCleanupRouter().start(
                runtime,
                onEvent: (event) {
                  if (event is! Map<String, Object?>) return;
                  events.add(event);
                  if (event['type'] == 'http_request_handler_error') {
                    releaseCountsAtError.add(handshake.releases);
                  }
                  if (throwObserver && event['type'] == eventType) {
                    throw observerError;
                  }
                },
              ),
              (error, _) => escaped.add(error),
            )!;
            addTearDown(binding.dispose);
            await Future<void>.delayed(Duration.zero);
            runtime.setConnectionProtocol(32101, NativeConnectionProtocol.http);
            runtime.enqueueHttpHandshake(
              binding.listeners.single.listenerId,
              32101,
              handshake,
            );
            await _waitUntil(
              () => events.any((event) => event['type'] == eventType),
            );
            await Future<void>.delayed(Duration.zero);
            expect(
              handshake.releases,
              1,
              reason: 'A rejected request retains no native handshake.',
            );
            expect(escaped, isEmpty);
            if (throwObserver) {
              final reported = events.where(
                (event) => event['type'] == 'http_request_handler_error',
              );
              expect(reported, hasLength(1));
              expect(reported.single['error'], observerError.toString());
              expect(releaseCountsAtError, [1]);
              expect(runtime.httpResponses[32101], isNull);
            } else {
              expect(releaseCountsAtError, isEmpty);
              if (label == 'missing handler') {
                expect(
                  runtime.httpResponses[32101]!.single.status,
                  HttpStatus.notImplemented,
                );
              } else {
                expect(runtime.httpResponses[32101], isNull);
              }
            }
            await binding.dispose();
            expect(
              handshake.releases,
              1,
              reason: 'Disposal cannot release a rejected request twice.',
            );
          },
        );
      }
    }

    for (final throwObserver in [false, true]) {
      test(
        'successful dispatch observer=$throwObserver retains ownership until the reply',
        () async {
          final runtime = _HandleRuntime();
          late _HttpEdgeHandshake handshake;
          final releaseCountsAtError = <int>[];
          final binding = _earlyCleanupRouter().start(
            runtime,
            onEvent: (event) {
              if (event is! Map<String, Object?>) return;
              if (event['type'] == 'http_request_handler_error') {
                releaseCountsAtError.add(handshake.releases);
              }
              if (throwObserver && event['type'] == 'http_request_dispatched') {
                throw StateError('controlled dispatch observer failure');
              }
            },
          );
          addTearDown(binding.dispose);
          final session = await binding.createInternalSession(
            realmUri: 'realm1',
          );
          final registration = await session.register('api.echo');
          final invoked = Completer<HttpInvocationContext>();
          registration.onInvoke((invocation) {
            invoked.complete(
              HttpInvocationContext.maybeFromInvocation(invocation)!,
            );
          });
          handshake = _HttpEdgeHandshake(
            NativeHttpHandshake.synthetic(
              handle: 32102,
              method: 'GET',
              target: '/api/echo',
              path: '/api/echo',
              protocol: 'http/1.1',
              headers: const {},
              body: Uint8List(0),
              realm: 'realm1',
              procedure: 'api.echo',
            ),
          );
          runtime.setConnectionProtocol(32102, NativeConnectionProtocol.http);
          runtime.enqueueHttpHandshake(
            binding.listeners.single.listenerId,
            32102,
            handshake,
          );
          final context = await invoked.future.timeout(
            const Duration(seconds: 3),
          );
          await Future<void>.delayed(Duration.zero);
          expect(releaseCountsAtError, throwObserver ? [0] : isEmpty);
          expect(
            handshake.releases,
            0,
            reason: 'The pending call owns the handshake.',
          );
          expect(runtime.httpResponses[32102], isNull);
          context.sendText(body: 'reply', status: HttpStatus.accepted);
          await _waitUntil(() => handshake.releases > 0);
          expect(
            runtime.httpResponses[32102]!.single.status,
            HttpStatus.accepted,
          );
          expect(handshake.releases, 1);
          await binding.dispose();
          expect(handshake.releases, 1);
        },
      );
    }

    for (final (path, status) in [
      ('/absent', HttpStatus.notFound),
      ('/method', HttpStatus.methodNotAllowed),
      ('/protocol', HttpStatus.upgradeRequired),
      ('/missing', HttpStatus.notImplemented),
    ]) {
      for (final failSend in [false, true]) {
        test('response $status send failure=$failSend releases once', () async {
          final handshake = _HttpEdgeHandshake(
            NativeHttpHandshake.synthetic(
              handle: 32103,
              method: 'GET',
              target: path,
              path: path,
              protocol: 'http/1.1',
              headers: const {},
              body: Uint8List(0),
              realm: 'realm1',
              procedure: 'api.echo',
            ),
          );
          final runtime = _EarlyResponseFailureRuntime(
            failSend,
            () => handshake.releases,
          );
          final events = <Map<String, Object?>>[];
          final releasedAtError = <int>[];
          final binding = _earlyCleanupRouter().start(
            runtime,
            onEvent: (event) {
              if (event is! Map<String, Object?>) return;
              events.add(event);
              if (event['type'] == 'http_request_handler_error') {
                releasedAtError.add(handshake.releases);
              }
            },
          );
          addTearDown(binding.dispose);
          await Future<void>.delayed(Duration.zero);
          runtime.setConnectionProtocol(32103, NativeConnectionProtocol.http);
          runtime.enqueueHttpHandshake(
            binding.listeners.single.listenerId,
            32103,
            handshake,
          );
          await _waitUntil(() => runtime.attempts.isNotEmpty);
          await Future<void>.delayed(Duration.zero);
          expect(runtime.attempts.single.status, status);
          expect(runtime.releasesAtSend, [
            0,
          ], reason: 'The response requires a live handshake.');
          expect(
            handshake.releases,
            1,
            reason: 'Response-send errors cannot leak handshake ownership.',
          );
          if (failSend) {
            expect(releasedAtError, [1]);
            expect(
              events
                  .where(
                    (event) => event['type'] == 'http_request_handler_error',
                  )
                  .single['error'],
              runtime.error.toString(),
            );
            expect(runtime.httpResponses[32103], isNull);
          } else {
            expect(releasedAtError, isEmpty);
            expect(runtime.httpResponses[32103]!.single.status, status);
          }
          await binding.dispose();
          expect(handshake.releases, 1);
        });
      }
    }

    for (final failureStage in ['observer', 'send']) {
      test('cleanup failure preserves primary $failureStage error', () async {
        final path = failureStage == 'send' ? '/absent' : '/api/echo';
        final handshake = _ThrowingEarlyHandshake(
          NativeHttpHandshake.synthetic(
            handle: 32105,
            method: 'GET',
            target: path,
            path: path,
            protocol: 'http/1.1',
            headers: const {},
            body: Uint8List(0),
            realm: null,
            procedure: 'api.echo',
          ),
        );
        final runtime = _EarlyResponseFailureRuntime(
          failureStage == 'send',
          () => handshake.releases,
        );
        final observerError = StateError('controlled primary observer failure');
        final errors = <Map<String, Object?>>[];
        final binding = _earlyCleanupRouter().start(
          runtime,
          onEvent: (event) {
            if (event is! Map<String, Object?>) return;
            if (event['type'] == 'http_request_handler_error') {
              errors.add(event);
            }
            if (event['type'] == 'http_request_unmapped_realm') {
              throw observerError;
            }
          },
        );
        addTearDown(binding.dispose);
        await Future<void>.delayed(Duration.zero);
        runtime.setConnectionProtocol(32105, NativeConnectionProtocol.http);
        runtime.enqueueHttpHandshake(
          binding.listeners.single.listenerId,
          32105,
          handshake,
        );
        await _waitUntil(() => errors.isNotEmpty);
        expect(
          errors.single['error'],
          (failureStage == 'send' ? runtime.error : observerError).toString(),
        );
        expect(handshake.releases, 1);
        expect(runtime.attempts, hasLength(failureStage == 'send' ? 1 : 0));
        expect(runtime.httpResponses[32105], isNull);
        await binding.dispose();
        expect(handshake.releases, 1);
      });
    }

    test(
      'a throwing release is attempted once and its error remains visible',
      () async {
        final handshake = _ThrowingEarlyHandshake(
          NativeHttpHandshake.synthetic(
            handle: 32104,
            method: 'GET',
            target: '/missing',
            path: '/missing',
            protocol: 'http/1.1',
            headers: const {},
            body: Uint8List(0),
            realm: 'realm1',
            procedure: 'api.echo',
          ),
        );
        final runtime = _HandleRuntime();
        final errors = <Map<String, Object?>>[];
        final binding = _earlyCleanupRouter().start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?> &&
                event['type'] == 'http_request_handler_error') {
              errors.add(event);
            }
          },
        );
        addTearDown(binding.dispose);
        await Future<void>.delayed(Duration.zero);
        runtime.setConnectionProtocol(32104, NativeConnectionProtocol.http);
        runtime.enqueueHttpHandshake(
          binding.listeners.single.listenerId,
          32104,
          handshake,
        );
        await _waitUntil(
          () => runtime.httpResponses[32104]?.isNotEmpty ?? false,
        );
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(1));
        expect(errors.single['error'], handshake.error.toString());
        expect(
          runtime.httpResponses[32104]!.single.status,
          HttpStatus.notImplemented,
        );
        expect(handshake.releases, 1);
        await binding.dispose();
        expect(handshake.releases, 1);
      },
    );
  });
}

class _ThrowingEarlyHandshake extends _HttpEdgeHandshake {
  _ThrowingEarlyHandshake(super.delegate);
  final error = StateError('controlled handshake release failure');

  @override
  void release() {
    super.release();
    throw error;
  }
}

class _EarlyResponseFailureRuntime extends _HandleRuntime {
  _EarlyResponseFailureRuntime(this.failSend, this.releases);
  final bool failSend;
  final int Function() releases;
  final error = StateError('controlled HTTP response failure');
  final attempts = <NativeHttpResponse>[];
  final releasesAtSend = <int>[];

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    attempts.add(response);
    releasesAtSend.add(releases());
    if (failSend) throw error;
    super.sendHttpResponse(
      handshakeHandle: handshakeHandle,
      connectionId: connectionId,
      response: response,
    );
  }
}

Router _earlyCleanupRouter() {
  final settings =
      (RouterSettingsBuilder()
            ..addSessionProfileFromBuilder(
              SessionProfileSettingsBuilder('configured')..setRealm('realm1'),
            )
            ..addRealmFromBuilder(
              RealmSettingsBuilder('realm1')
                ..addAuthMethod('anonymous')
                ..addRoleFromBuilder(
                  RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
                    PermissionSettingsBuilder('')
                      ..setMatchPolicy(PermissionMatchPolicy.prefix)
                      ..allowOperations(['call', 'register', 'unregister']),
                  ),
                ),
            )
            ..addListenerFromBuilder(
              ListenerSettingsBuilder('http', '127.0.0.1:0')
                ..addProtocol(ListenerProtocol.http)
                ..setHttpOptions(
                  const HttpListenerSettings(
                    routes: [
                      HttpRouteSettings(
                        match: HttpRouteMatch(
                          path: '/method',
                          methods: ['POST'],
                        ),
                        action: HttpRouteAction(
                          type: HttpRouteActionType.rpc,
                          procedure: 'api.echo',
                        ),
                      ),
                      HttpRouteSettings(
                        match: HttpRouteMatch(
                          path: '/protocol',
                          protocols: ['h2'],
                        ),
                        action: HttpRouteAction(
                          type: HttpRouteActionType.rpc,
                          procedure: 'api.echo',
                        ),
                      ),
                      HttpRouteSettings(
                        match: HttpRouteMatch(prefix: '/api/'),
                        action: HttpRouteAction(
                          type: HttpRouteActionType.rpc,
                          procedure: 'api.echo',
                        ),
                      ),
                      HttpRouteSettings(
                        match: HttpRouteMatch(path: '/missing'),
                        action: HttpRouteAction(
                          type: HttpRouteActionType.handler,
                          delegate: 'absent',
                        ),
                      ),
                    ],
                  ),
                ),
            ))
          .build();
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
    settings: settings,
  );
}
