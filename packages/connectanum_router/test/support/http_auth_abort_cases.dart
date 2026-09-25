part of '../router_runtime_test.dart';

void _expectAuthAbortDiagnostic(_HttpRoundFixture fixture, bool failed) {
  expect(
    fixture.events.where((event) => event['type'] == 'http_auth_abort_failed'),
    failed
        ? [
            {
              'source': 'binding',
              'type': 'http_auth_abort_failed',
              'reason': 'authentication_abort',
            },
          ]
        : isEmpty,
  );
  expect(
    fixture.events.where(
      (event) => event['type'] == 'http_request_handler_error',
    ),
    isEmpty,
  );
}

void _httpAuthAbortTests() {
  group('HTTP authentication cleanup', () {
    setUp(AuthSecurityTracker.reset);
    tearDown(AuthSecurityTracker.reset);

    for (final failAbort in [false, true]) {
      for (final profile in [false, true]) {
        for (final rotated in [false, true]) {
          test(
            'rejects crossed ${profile ? 'profile' : 'route'} rotated=$rotated cleanupError=$failAbort',
            () async {
              final auth = _RoundAuthenticator()
                ..failAbort = failAbort
                ..authenticate = () async => _RoundAuthenticator.challenge(2);
              final fixture = await _HttpRoundFixture.start(
                [auth],
                settings: profile
                    ? _buildRouterSettingsWithHttpAuthProfileIsolation()
                    : _buildRouterSettingsWithHttpAuthRouteIsolation(),
              );
              var state = _expectRoundChallenge(await fixture.hello(), 1);
              if (rotated) {
                state = _expectRoundChallenge(await fixture.reply(state), 2);
              }
              final reason = profile
                  ? 'wrong_session_profile'
                  : 'wrong_auth_route';
              final response = await _terminalAuthResponse(fixture, {
                'state': state,
                'signature': 'proof-not-for-this-route',
              }, target: '/auth/alternate');
              _expectRoundError(response, reason);
              expect(auth.abortReasons, [reason]);
              expect(auth.abortContexts, [same(auth.helloContext)]);
              expect(auth.messages, hasLength(rotated ? 1 : 0));
              _expectRoundError(await fixture.reply(state), 'invalid_state');
              _expectAuthAbortDiagnostic(fixture, failAbort);
              await fixture.binding.dispose();
              expect(auth.abortReasons, [reason]);
            },
          );
        }
      }

      for (final signature in <String?>[null, '']) {
        test(
          'signature=$signature preserves rejection semantics cleanupError=$failAbort',
          () async {
            final auth = _RoundAuthenticator()..failAbort = failAbort;
            final replacement = _RoundAuthenticator();
            final fixture = await _HttpRoundFixture.start(
              [auth, replacement],
              settings: _buildRouterSettingsWithHttpAuthBridge(
                maxPendingAuth: 1,
              ),
            );
            final state = _expectRoundChallenge(await fixture.hello(), 1);
            if (signature != null) {
              _expectRoundError(
                await _terminalAuthResponse(fixture, {
                  'state': state,
                  'signature': signature,
                }),
                'invalid_auth_parameter',
                status: HttpStatus.badRequest,
              );
              expect(auth.abortReasons, isEmpty);
              expect(auth.messages, isEmpty);
              expect((await fixture.reply(state)).status, HttpStatus.ok);
              _expectAuthAbortDiagnostic(fixture, false);
              return;
            }
            _expectRoundError(
              await _terminalAuthResponse(fixture, {
                'state': state,
              }),
              'missing_signature',
              status: HttpStatus.badRequest,
            );
            expect(auth.abortReasons, ['missing_signature']);
            expect(auth.messages, isEmpty);
            _expectRoundError(await fixture.reply(state), 'invalid_state');
            final next = _expectRoundChallenge(await fixture.hello(), 1);
            expect((await fixture.reply(next)).status, HttpStatus.ok);
            expect(replacement.messages, hasLength(1));
            expect(replacement.abortReasons, isEmpty);
            _expectAuthAbortDiagnostic(fixture, failAbort);
            await fixture.binding.dispose();
            expect(auth.abortReasons, ['missing_signature']);
          },
        );
      }

      test('locked-out state is consumed cleanupError=$failAbort', () async {
        final auth = _RoundAuthenticator()..failAbort = failAbort;
        final settings = _buildRouterSettingsWithHttpAuthBridge(
          maxFailedAuth: 1,
        );
        final fixture = await _HttpRoundFixture.start([
          auth,
        ], settings: settings);
        final state = _expectRoundChallenge(await fixture.hello(), 1);
        AuthSecurityTracker.recordFailure(
          'realm1',
          'user-1',
          settings.realms.single.limits,
        );
        _expectRoundError(
          await _terminalAuthResponse(fixture, {
            'state': state,
            'signature': 'valid-proof-for-locked-out-identity',
          }),
          'auth_locked_out',
          status: HttpStatus.tooManyRequests,
        );
        expect(auth.abortReasons, ['http_auth_locked_out']);
        expect(auth.messages, isEmpty);
        _expectRoundError(await fixture.reply(state), 'invalid_state');
        _expectAuthAbortDiagnostic(fixture, failAbort);
        await fixture.binding.dispose();
        expect(auth.abortReasons, ['http_auth_locked_out']);
      });

      for (final duringHello in [true, false]) {
        for (final grant in [false, true]) {
          // The initial grant-capacity race is covered in the initial cases.
          if (duringHello && grant) continue;
          test(
            'capacity hello=$duringHello grant=$grant cleanupError=$failAbort',
            () async {
              final result = Completer<AuthResult>();
              addTearDown(() {
                if (!result.isCompleted) {
                  result.complete(_RoundAuthenticator.success());
                }
              });
              final auth = _RoundAuthenticator()..failAbort = failAbort;
              if (duringHello) {
                auth.hello = () => result.future;
              } else {
                auth.authenticate = () => result.future;
              }
              final competing = _RoundAuthenticator();
              final fixture = await _HttpRoundFixture.start(
                [auth, competing],
                settings: _buildRouterSettingsWithHttpAuthBridge(
                  maxPendingAuth: 1,
                  maxHttpAuthGrants: grant ? 1 : 2,
                ),
              );
              final first = duringHello
                  ? null
                  : _expectRoundChallenge(await fixture.hello(), 1);
              final connection = fixture.nextConnection;
              final pending = _terminalAuthResponse(
                fixture,
                duringHello
                    ? _initialAuthHello
                    : {'state': first, 'signature': 'pending-proof'},
              );
              unawaited(
                pending.then<void>(
                  (_) {},
                  onError: (Object _, StackTrace _) {},
                ),
              );
              addTearDown(() async {
                if (!result.isCompleted) {
                  result.complete(_RoundAuthenticator.success());
                }
                await pending;
              });
              await _waitUntil(
                () => duringHello
                    ? auth.helloContext != null
                    : auth.messages.isNotEmpty,
              );
              expect(fixture.runtime.httpResponses[connection], isNull);
              final other = _expectRoundChallenge(await fixture.hello(), 1);
              if (grant) {
                expect((await fixture.reply(other)).status, HttpStatus.ok);
              }
              result.complete(
                grant
                    ? _RoundAuthenticator.success()
                    : _RoundAuthenticator.challenge(2),
              );
              final reason = grant
                  ? 'http_auth_grant_capacity_exhausted'
                  : 'http_auth_capacity_exhausted';
              _expectRoundError(
                await pending,
                grant
                    ? 'auth_grant_capacity_exhausted'
                    : 'auth_capacity_exhausted',
                status: grant
                    ? HttpStatus.serviceUnavailable
                    : HttpStatus.tooManyRequests,
              );
              expect(auth.abortReasons, [reason]);
              expect(auth.messages, hasLength(duringHello ? 0 : 1));
              if (first != null) {
                _expectRoundError(await fixture.reply(first), 'invalid_state');
              }
              if (!grant) {
                expect((await fixture.reply(other)).status, HttpStatus.ok);
              }
              expect(competing.abortReasons, isEmpty);
              _expectAuthAbortDiagnostic(fixture, failAbort);
              await fixture.binding.dispose();
              expect(auth.abortReasons, [reason]);
            },
          );
        }
      }

      test('expired state records lockout cleanupError=$failAbort', () async {
        final auth = _RoundAuthenticator()..failAbort = failAbort;
        final replacement = _RoundAuthenticator();
        final fixture = await _HttpRoundFixture.start(
          [auth, replacement],
          settings: _buildRouterSettingsWithHttpAuthBridge(
            authTimeoutMs: 500,
            maxPendingAuth: 1,
            maxFailedAuth: 1,
          ),
        );
        final state = _expectRoundChallenge(await fixture.hello(), 1);
        await Future<void>.delayed(const Duration(milliseconds: 650));
        _expectRoundError(
          await _terminalAuthResponse(fixture, {
            'state': state,
            'signature': 'expired-proof',
          }),
          'invalid_state',
        );
        expect(auth.abortReasons, ['http_auth_timeout']);
        expect(auth.messages, isEmpty);
        _expectRoundError(
          await fixture.hello(),
          'auth_locked_out',
          status: HttpStatus.tooManyRequests,
        );
        expect(replacement.helloContext, isNull);
        // Another identity can still claim the released pending capacity.
        final next = _expectRoundChallenge(
          await _terminalAuthResponse(fixture, {
            ..._initialAuthHello,
            'authid': 'user-2',
          }),
          1,
        );
        expect((await fixture.reply(next)).status, HttpStatus.ok);
        _expectAuthAbortDiagnostic(fixture, failAbort);
        await fixture.binding.dispose();
        expect(auth.abortReasons, ['http_auth_timeout']);
      });
    }
  });
}
