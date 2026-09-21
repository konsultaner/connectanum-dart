part of '../router_runtime_test.dart';

const _initialAuthHello = <String, Object?>{
  'realm': 'realm1',
  'authid': 'user-1',
  'authmethod': 'ticket',
  'authextra': {'origin': 'consumer'},
};

Future<NativeHttpResponse> _terminalAuthResponse(
  _HttpRoundFixture fixture,
  Map<String, Object?> body, {
  String target = '/auth',
}) async {
  final connection = fixture.nextConnection++;
  _enqueueSyntheticHttpRequest(
    runtime: fixture.runtime,
    listenerId: fixture.binding.listeners.single.listenerId,
    connectionId: connection,
    handle: connection,
    method: 'POST',
    target: target,
    headers: const {'content-type': 'application/json'},
    body: body,
    realm: 'router.http',
    procedure: 'router.http.auth',
  );
  // Observe either terminal outcome, so a handler exception is an explicit
  // missing-response assertion rather than a polling timeout.
  await _waitUntil(
    () =>
        (fixture.runtime.httpResponses[connection]?.isNotEmpty ?? false) ||
        fixture.events.any(
          (event) =>
              event['type'] == 'http_request_handler_error' &&
              event['connectionId'] == connection,
        ),
  );
  final responses = fixture.runtime.httpResponses[connection] ?? [];
  expect(responses, hasLength(1), reason: 'Auth must send a terminal response');
  return responses.single;
}

void _httpInitialAuthenticationTests() {
  group('initial HTTP authentication', () {
    setUp(AuthSecurityTracker.reset);
    tearDown(AuthSecurityTracker.reset);

    test(
      'immediate success issues a refreshable provider-bound grant',
      () async {
        final auth = _RoundAuthenticator()
          ..hello = () async => AuthResult.success(
            const AuthSuccess(
              authId: 'verified-user',
              authRole: 'member',
              details: {'authprovider': 'verified-provider', 'verified': true},
            ),
          );
        final fixture = await _HttpRoundFixture.start([auth]);
        final response = await _terminalAuthResponse(
          fixture,
          _initialAuthHello,
        );
        expect(response.status, HttpStatus.ok);
        final grant = _jsonResponseBody(response);
        for (final (key, value) in [
          ('status', 'ok'),
          ('realm', 'realm1'),
          ('authid', 'verified-user'),
          ('authrole', 'member'),
          ('authmethod', 'ticket'),
          ('authprovider', 'verified-provider'),
        ]) {
          expect(grant[key], value);
        }
        expect(grant['details'], {
          'authprovider': 'verified-provider',
          'verified': true,
        });
        expect(grant['access_token'], isNotEmpty);
        expect(grant['refresh_token'], isNotEmpty);
        expect(grant, isNot(contains('state')));
        expect(auth.messages, isEmpty);
        final refresh = await _terminalAuthResponse(fixture, {
          'grant_type': 'refresh_token',
          'refresh_token': grant['refresh_token'],
        });
        expect(refresh.status, HttpStatus.ok);
        final rotated = _jsonResponseBody(refresh);
        expect(rotated['authid'], 'verified-user');
        expect(rotated['authprovider'], 'verified-provider');
        expect(rotated['details'], grant['details']);
        expect(rotated['access_token'], isNot(grant['access_token']));
        expect(rotated['refresh_token'], isNot(grant['refresh_token']));
        _expectRoundError(
          await _terminalAuthResponse(fixture, {
            'grant_type': 'refresh_token',
            'refresh_token': grant['refresh_token'],
          }),
          'invalid_refresh_token',
        );
        expect(auth.abortReasons, isEmpty);
      },
    );

    for (final duringHello in [true, false]) {
      for (final failAbort in [false, true]) {
        for (final message in <String?>[null, 'Credentials rejected']) {
          test(
            'failure records lockout hello=$duringHello cleanupError=$failAbort message=$message',
            () async {
              final auth = _RoundAuthenticator()..failAbort = failAbort;
              Future<AuthResult> failure() async => AuthResult.failure(
                AuthFailure(
                  reason: 'wamp.error.not_authorized',
                  message: message,
                ),
              );
              if (duringHello) {
                auth.hello = failure;
              } else {
                auth.authenticate = failure;
              }
              final replacement = _RoundAuthenticator()
                ..hello = () async => _RoundAuthenticator.success();
              final fixture = await _HttpRoundFixture.start(
                [auth, replacement],
                settings: _buildRouterSettingsWithHttpAuthBridge(
                  maxFailedAuth: 1,
                ),
              );
              final body = duringHello
                  ? _initialAuthHello
                  : <String, Object?>{
                      'state': _expectRoundChallenge(await fixture.hello(), 1),
                      'signature': 'rejected-proof',
                    };
              final denied = await _terminalAuthResponse(fixture, body);
              _expectRoundError(denied, 'wamp.error.not_authorized');
              expect(
                denied.headers[HttpHeaders.wwwAuthenticateHeader],
                'Bearer',
              );
              expect(_jsonResponseBody(denied), {
                'status': 'error',
                'reason': 'wamp.error.not_authorized',
                'message': ?message,
              });
              expect(auth.abortContexts, [same(auth.helloContext)]);
              expect(auth.abortReasons, [
                duringHello
                    ? 'wamp.error.not_authorized'
                    : 'authenticate_failed',
              ]);
              _expectRoundError(
                await _terminalAuthResponse(fixture, _initialAuthHello),
                'auth_locked_out',
                status: HttpStatus.tooManyRequests,
              );
              expect(auth.messages, hasLength(duringHello ? 0 : 1));
              expect(replacement.helloContext, isNull);
              _expectAuthAbortDiagnostic(fixture, failAbort);
              await fixture.binding.dispose();
              expect(auth.abortReasons, hasLength(1));
            },
          );
        }
      }
    }

    for (final failAbort in [false, true]) {
      test(
        'rechecks grant capacity after hello cleanupError=$failAbort',
        () async {
          final result = Completer<AuthResult>();
          addTearDown(() {
            if (!result.isCompleted) {
              result.complete(_RoundAuthenticator.success());
            }
          });
          final pendingAuth = _RoundAuthenticator()
            ..failAbort = failAbort
            ..hello = () => result.future;
          final competing = _RoundAuthenticator()
            ..hello = () async => _RoundAuthenticator.success();
          final fixture = await _HttpRoundFixture.start(
            [pendingAuth, competing],
            settings: _buildRouterSettingsWithHttpAuthBridge(
              maxHttpAuthGrants: 1,
            ),
          );
          final connection = fixture.nextConnection;
          final pending = _terminalAuthResponse(fixture, _initialAuthHello);
          // Observe immediately and still await the original future below and at
          // teardown. Early fixture failure must not orphan a pending request.
          unawaited(
            pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
          addTearDown(() async {
            if (!result.isCompleted) {
              result.complete(_RoundAuthenticator.success());
            }
            await pending;
          });
          await _waitUntil(() => pendingAuth.helloContext != null);
          expect(fixture.runtime.httpResponses[connection], isNull);
          expect((await fixture.hello()).status, HttpStatus.ok);
          result.complete(_RoundAuthenticator.success());
          _expectRoundError(
            await pending,
            'auth_grant_capacity_exhausted',
            status: HttpStatus.serviceUnavailable,
          );
          expect(pendingAuth.abortReasons, [
            'http_auth_grant_capacity_exhausted',
          ]);
          expect(pendingAuth.messages, isEmpty);
          expect(competing.abortReasons, isEmpty);
          _expectAuthAbortDiagnostic(fixture, failAbort);
          await fixture.binding.dispose();
          expect(pendingAuth.abortReasons, hasLength(1));
        },
      );
    }
  });
}
