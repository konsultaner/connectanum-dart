part of '../router_runtime_test.dart';

const _providerExceptionDetail = 'private-provider-diagnostic-token';

class _ThrowingHttpAuthenticator extends _RoundAuthenticator {
  _ThrowingHttpAuthenticator({
    required this.duringHello,
    required this.asyncFailure,
  });

  final bool duringHello;
  final bool asyncFailure;

  Future<AuthResult> _fail() {
    final error = StateError(_providerExceptionDetail);
    if (asyncFailure) return Future<AuthResult>.error(error);
    throw error;
  }

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) {
    if (!duringHello) return super.onHello(context);
    helloContext = context;
    return _fail();
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) {
    contexts.add(context);
    messages.add(message);
    return _fail();
  }
}

void _httpAuthProviderFailureTests() {
  for (final allowedMethod in ['ticket', 'jwt']) {
    test('external JWT provider obeys route method $allowedMethod', () async {
      final runtime = _HandleRuntime();
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
            settings: _buildRouterSettingsWithHttpJwtProvider(
              authMethods: [allowedMethod],
            ),
          ).start(
            runtime,
            onEvent: (event) {
              if (event is Map<String, Object?>) events.add(event);
            },
          );
      addTearDown(binding.dispose);
      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'service',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      final registration = await callee.register('com.example.api.jwt');
      var invocations = 0;
      registration.onInvoke((invocation) {
        invocations++;
        HttpInvocationContext.maybeFromInvocation(
          invocation,
        )!.sendText(body: 'authorized');
      });
      final jwt = _encodeHs256Jwt(
        secret: 'jwt-secret',
        claims: {
          'sub': 'method-user',
          'role': 'member',
          'iss': 'https://issuer.example',
          'aud': ['connectanum-http'],
          'exp':
              DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000,
        },
      );
      final handshake = _HttpEdgeHandshake(
        NativeHttpHandshake.synthetic(
          handle: 32400,
          method: 'GET',
          target: '/api/jwt',
          path: '/api/jwt',
          protocol: 'http/1.1',
          headers: {'authorization': 'Bearer $jwt'},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.jwt',
        ),
      );
      runtime.setConnectionProtocol(32400, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        binding.listeners.single.listenerId,
        32400,
        handshake,
      );
      await _waitUntil(() => runtime.httpResponses[32400]?.isNotEmpty ?? false);
      final response = runtime.httpResponses[32400]!.single;
      if (allowedMethod == 'ticket') {
        expect(response.status, HttpStatus.unauthorized);
        expect(_jsonResponseBody(response)['reason'], 'wrong_authmethod');
        expect(invocations, 0);
        expect(
          events.where((event) => event['type'] == 'http_request_dispatched'),
          isEmpty,
        );
      } else {
        expect(response.status, HttpStatus.ok);
        expect((response.body as NativeHttpResponseText).text, 'authorized');
        expect(invocations, 1);
      }
      await _waitUntil(() => handshake.releases > 0);
      expect(handshake.releases, 1);
      await binding.dispose();
      expect(handshake.releases, 1);
    });
  }
  group('HTTP auth provider exceptions', () {
    setUp(AuthSecurityTracker.reset);
    tearDown(AuthSecurityTracker.reset);

    for (final duringHello in [true, false]) {
      for (final asyncFailure in [false, true]) {
        for (final failAbort in [false, true]) {
          test(
            'hello=$duringHello async=$asyncFailure cleanupError=$failAbort',
            () async {
              final auth = _ThrowingHttpAuthenticator(
                duringHello: duringHello,
                asyncFailure: asyncFailure,
              )..failAbort = failAbort;
              final replacement = _RoundAuthenticator()
                ..hello = () async => _RoundAuthenticator.success();
              final fixture = await _HttpRoundFixture.start(
                [auth, replacement],
                settings: _buildRouterSettingsWithHttpAuthBridge(
                  maxFailedAuth: 1,
                ),
              );
              final state = duringHello
                  ? null
                  : _expectRoundChallenge(await fixture.hello(), 1);
              final response = await _terminalAuthResponse(
                fixture,
                duringHello
                    ? _initialAuthHello
                    : {'state': state, 'signature': 'provider-error-proof'},
              );
              _expectRoundError(response, 'wamp.error.not_authorized');
              expect(_jsonResponseBody(response), {
                'status': 'error',
                'reason': 'wamp.error.not_authorized',
                'message': 'Authentication provider failed',
              });
              expect(
                response.headers[HttpHeaders.wwwAuthenticateHeader],
                'Bearer',
              );
              expect(
                jsonEncode(_jsonResponseBody(response)),
                isNot(contains(_providerExceptionDetail)),
              );
              expect(auth.abortReasons, hasLength(1));
              expect(auth.abortContexts, [same(auth.helloContext)]);
              expect(auth.messages, hasLength(duringHello ? 0 : 1));
              if (state != null) {
                _expectRoundError(await fixture.reply(state), 'invalid_state');
              }
              _expectRoundError(
                await fixture.hello(),
                'auth_locked_out',
                status: HttpStatus.tooManyRequests,
              );
              expect(replacement.helloContext, isNull);
              expect(replacement.abortReasons, isEmpty);
              expect(replacement.messages, isEmpty);
              expect(
                jsonEncode(fixture.events),
                isNot(contains(_providerExceptionDetail)),
              );
              _expectAuthAbortDiagnostic(fixture, failAbort);
              await fixture.binding.dispose();
              expect(auth.abortReasons, hasLength(1));
            },
          );
        }
      }
    }
  });
}
