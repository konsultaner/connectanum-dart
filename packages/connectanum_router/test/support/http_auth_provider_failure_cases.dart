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
