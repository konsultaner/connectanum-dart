import 'dart:async';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_router/src/router/auth/remote_authenticator.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    RemoteAuthenticatorRegistry.clear();
    RemoteAuthenticator.resetRateLimiter();
  });
  tearDown(() {
    RemoteAuthenticatorRegistry.clear();
    RemoteAuthenticator.resetRateLimiter();
  });

  test('registry snapshots cannot mutate or track future registrations', () {
    final delegate = _Delegate();
    RemoteAuthenticatorRegistry.register(delegate);
    final snapshot = RemoteAuthenticatorRegistry.delegates;
    expect(snapshot, {'default': same(delegate)});
    expect(() => snapshot.clear(), throwsUnsupportedError);
    RemoteAuthenticatorRegistry.unregister('default');
    expect(RemoteAuthenticatorRegistry.delegateFor('default'), isNull);
    expect(snapshot['default'], same(delegate));
  });
  test('unavailable exceptions expose only their supplied message', () {
    expect(
      _validRemoteValue(() => RemoteDelegateUnavailableException().toString()),
      'RemoteDelegateUnavailableException',
    );
    expect(RemoteDelegateUnavailableException('offline').toString(), 'offline');
  });
  test('a configured delegate can be constructed and challenged', () async {
    final delegate = _Delegate();
    final auth = _validRemoteValue(() => _auth([delegate]));
    final result = await _validRemoteCompletion(() => auth.onHello(_context()));
    expect(result.isChallenge, isTrue);
    expect(result.challenge?.challenge, {'nonce': 'challenge'});
    expect(delegate.helloRequests, hasLength(1));
    expect(delegate.authenticateRequests, isEmpty);
  });
  for (final stage in ['hello', 'authenticate']) {
    test(
      '$stage preserves a failure with absent optional payload fields',
      () async {
        final delegate = _Delegate();
        delegate.hello = () =>
            stage == 'hello' ? _rejectedHello() : _challenge();
        delegate.authenticate = () =>
            RemoteAuthenticateResponse.failure(_failure);
        final auth = _auth([delegate]);
        var result = await _validRemoteCompletion(
          () => auth.onHello(_context()),
        );
        if (stage == 'authenticate') {
          expect(result.isChallenge, isTrue);
          result = await _validRemoteCompletion(
            () => auth.onAuthenticate(_context(), _proof()),
          );
        }
        final failure = _expectFailure(result);
        expect(failure.reason, wamp.Error.authenticationFailed);
        expect(failure.message, 'denied');
        expect(failure.arguments, isNull);
        expect(failure.argumentsKeywords, isNull);
        expect(
          delegate.authenticateRequests,
          hasLength(stage == 'hello' ? 0 : 1),
        );
      },
    );
  }
  test(
    'sub-threshold failure does not block a subsequent valid identity',
    () async {
      final rejecting = _Delegate()..hello = _rejectedHello;
      final rejected = await _auth(
        [rejecting],
        options: {'rate_limit_max_attempts': 2},
      ).onHello(_context());
      expect(_expectFailure(rejected).message, 'denied');
      final healthy = _Delegate()
        ..hello = () => RemoteHelloResponse.success(_success);
      final auth = _auth([healthy], options: {'rate_limit_max_attempts': 2});
      final accepted = await _validRemoteCompletion(
        () => auth.onHello(_context()),
      );
      expect(accepted.isSuccess, isTrue);
      expect(accepted.success?.authId, 'user');
      expect(accepted.success?.authRole, 'member');
      expect(rejecting.helloRequests, hasLength(1));
      expect(healthy.helloRequests, hasLength(1));
    },
  );
  test(
    'unavailable delegate cannot receive a previously challenged proof',
    () async {
      final delegate = _Delegate();
      final auth = _auth([delegate]);
      expect((await auth.onHello(_context())).isChallenge, isTrue);
      delegate.hello = () =>
          throw RemoteDelegateUnavailableException('offline');
      final unavailable = _expectFailure(await auth.onHello(_context()));
      expect(unavailable.reason, wamp.Error.notAuthorized);
      expect(unavailable.message, 'Remote authentication service unavailable');
      final rejected = _expectFailure(
        await auth.onAuthenticate(_context(), _proof()),
      );
      expect(rejected.reason, wamp.Error.notAuthorized);
      expect(
        rejected.message,
        'Remote authenticator delegate temporarily unavailable',
      );
      expect(delegate.helloRequests, hasLength(2));
      expect(delegate.authenticateRequests, isEmpty);
      expect(
        _expectFailure(await auth.onAuthenticate(_context(), _proof())).reason,
        wamp.Error.protocolViolation,
      );
      expect(delegate.authenticateRequests, isEmpty);
    },
  );

  test('authenticator requires a delegate and preserves configured method', () {
    expect(() => _auth([]), throwsStateError);
    expect(
      _auth([_Delegate()], options: {'method': 'ticket'}).method,
      'ticket',
    );
  });

  group('remote response validation', () {
    final cases = <(AuthSuccess, String)>[
      (const AuthSuccess(authId: ' ', authRole: 'member'), 'empty authId'),
      (const AuthSuccess(authId: 'user', authRole: ' '), 'empty authRole'),
      (
        const AuthSuccess(authId: 'user', authRole: 'admin'),
        'rejected role',
      ),
      (
        const AuthSuccess(authId: 'user', authRole: 'member'),
        'rejected provider',
      ),
      (
        const AuthSuccess(
          authId: 'user',
          authRole: 'member',
          details: {'authprovider': 42},
        ),
        'rejected provider',
      ),
      (
        const AuthSuccess(
          authId: 'user',
          authRole: 'member',
          details: {'authprovider': 'untrusted', 'provider': 'trusted'},
        ),
        'rejected provider',
      ),
      (
        const AuthSuccess(authId: 'user', authRole: 'member', details: {'': 1}),
        'contains an empty key',
      ),
      (
        AuthSuccess(
          authId: 'user',
          authRole: 'member',
          details: {
            'nested': [DateTime.utc(2026)],
          },
        ),
        'unsupported value type DateTime',
      ),
    ];
    for (final stage in ['hello', 'authenticate']) {
      for (var index = 0; index < cases.length; index++) {
        final (success, message) = cases[index];
        test('$stage rejects malformed success $index', () async {
          final delegate = _Delegate();
          delegate.hello = () => stage == 'hello'
              ? RemoteHelloResponse.success(success)
              : _challenge();
          delegate.authenticate = () =>
              RemoteAuthenticateResponse.success(success);
          final auth = _auth(
            [delegate],
            options: {
              'allowed_roles': ['member'],
              'allowed_providers': ['trusted'],
            },
          );
          var result = await auth.onHello(_context());
          if (stage == 'authenticate') {
            expect(result.isChallenge, isTrue);
            result = await auth.onAuthenticate(_context(), _proof());
          }
          expect(result.isFailure, isTrue);
          expect(result.failure!.reason, wamp.Error.notAuthorized);
          expect(result.failure!.message, contains(message));
        });
      }
    }
    for (final malformed in [
      RemoteChallenge(authId: ' ', challenge: {}, extra: {}),
      RemoteChallenge(authId: 'user', challenge: {'': 'invalid'}, extra: {}),
      RemoteChallenge(authId: 'user', challenge: {}, extra: {'': 'invalid'}),
    ]) {
      test(
        'malformed challenge is rejected without pending state $malformed',
        () async {
          final delegate = _Delegate()
            ..hello = () => RemoteHelloResponse.challenge(malformed);
          final auth = _auth([delegate]);
          final result = await auth.onHello(_context());
          expect(result.isFailure, isTrue);
          expect(result.failure!.reason, wamp.Error.notAuthorized);
          expect(
            (await auth.onAuthenticate(_context(), _proof())).failure!.reason,
            wamp.Error.protocolViolation,
          );
          expect(delegate.authenticateRequests, isEmpty);
        },
      );
    }
    for (final stage in ['hello', 'authenticate']) {
      test('$stage copies failure data into deeply immutable values', () async {
        final nested = <String, Object?>{'value': 7};
        final arguments = <Object?>[null, true, 1.5, 'text', nested];
        final failure = AuthFailure(
          reason: wamp.Error.authenticationFailed,
          message: 'denied',
          details: {'source': nested},
          arguments: arguments,
          argumentsKeywords: {'nested': arguments},
        );
        final delegate = _Delegate();
        delegate.hello = () => stage == 'hello'
            ? RemoteHelloResponse.failure(failure)
            : _challenge();
        delegate.authenticate = () =>
            RemoteAuthenticateResponse.failure(failure);
        final auth = _auth([delegate]);
        var result = await auth.onHello(_context());
        if (stage == 'authenticate') {
          result = await auth.onAuthenticate(_context(), _proof());
        }
        final sanitized = _expectFailure(result);
        expect(sanitized.reason, wamp.Error.authenticationFailed);
        expect(sanitized.message, 'denied');
        expect(sanitized.arguments, [
          null,
          true,
          1.5,
          'text',
          {'value': 7},
        ]);
        expect(sanitized.argumentsKeywords, {'nested': arguments});
        nested['value'] = 99;
        arguments.clear();
        expect(sanitized.details, {
          'source': {'value': 7},
        });
        expect((sanitized.argumentsKeywords!['nested'] as List).length, 5);
        expect(() => sanitized.arguments!.clear(), throwsUnsupportedError);
        expect(
          () => (sanitized.arguments!.last as Map)['value'] = 2,
          throwsUnsupportedError,
        );
      });
    }
  });

  test('a challenge is consumed before awaiting the remote response', () async {
    final pending = Completer<RemoteAuthenticateResponse>();
    final delegate = _Delegate()..authenticate = () => pending.future;
    final auth = _auth([delegate]);
    expect((await auth.onHello(_context())).isChallenge, isTrue);
    final first = auth.onAuthenticate(_context(), _proof());
    final duplicate = await auth.onAuthenticate(_context(), _proof());
    expect(_expectFailure(duplicate).reason, wamp.Error.protocolViolation);
    expect(delegate.authenticateRequests, hasLength(1));
    expect(
      delegate.authenticateRequests.single.transactionId,
      delegate.helloRequests.single.transactionId,
    );
    expect(delegate.authenticateRequests.single.authId, 'user');
    pending.complete(RemoteAuthenticateResponse.success(_success));
    final completed = await first;
    expect(completed.isSuccess, isTrue);
    expect(completed.success?.authId, 'user');
    await auth.onAbort(_context());
    expect(delegate.abortRequests, isEmpty);
  });
  test(
    'expired challenges notify abort and never send a proof to the delegate',
    () async {
      final delegate = _Delegate();
      final auth = _auth([delegate], options: {'challenge_timeout_ms': 1});
      await auth.onHello(_context());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final expired = await auth.onAuthenticate(_context(), _proof());
      expect(expired.isFailure, isTrue);
      expect(expired.failure!.reason, wamp.Error.authenticationFailed);
      expect(
        expired.failure!.message,
        'Remote authentication challenge expired',
      );
      expect(delegate.authenticateRequests, isEmpty);
      expect(delegate.abortRequests, hasLength(1));
      expect(delegate.abortRequests.single.reason, 'challenge_timeout');
      expect(
        delegate.abortRequests.single.transactionId,
        delegate.helloRequests.single.transactionId,
      );
    },
  );
  test('another attempt can rate-limit an already-issued challenge', () async {
    final pendingDelegate = _Delegate();
    final pendingAuth = _auth([pendingDelegate]);
    await pendingAuth.onHello(_context());
    final rejecting = _Delegate()..hello = _rejectedHello;
    await _auth(
      [rejecting],
      options: {
        'rate_limit_max_attempts': 1,
        'backoff_base_ms': 600000,
        'backoff_max_ms': 600000,
        'rate_limit_window_ms': 600000,
      },
    ).onHello(_context());
    final blocked = await pendingAuth.onAuthenticate(_context(), _proof());
    expect(blocked.isFailure, isTrue);
    expect(blocked.failure!.reason, wamp.Error.notAuthorized);
    expect(
      blocked.failure!.message,
      startsWith('Remote authentication rate limited.'),
    );
    expect(pendingDelegate.authenticateRequests, isEmpty);
  });
  test('an expired failure window permits a fresh HELLO', () async {
    final rejecting = _Delegate()..hello = _rejectedHello;
    await _auth(
      [rejecting],
      options: {
        'rate_limit_max_attempts': 1,
        'backoff_base_ms': 600000,
        'backoff_max_ms': 600000,
      },
    ).onHello(_context());
    final healthy = _Delegate()
      ..hello = () => RemoteHelloResponse.success(_success);
    final auth = _auth([healthy], options: {'rate_limit_window_ms': 1});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await auth.onHello(_context())).isSuccess, isTrue);
    expect(healthy.helloRequests, hasLength(1));
  });
  test(
    'a delayed failure starts a new rate-limit window instead of accumulating',
    () async {
      final pending = Completer<RemoteAuthenticateResponse>();
      final delegate = _Delegate()..authenticate = () => pending.future;
      final auth = _auth(
        [delegate],
        options: {
          'rate_limit_max_attempts': 2,
          'rate_limit_window_ms': 1,
          'backoff_base_ms': 600000,
          'backoff_max_ms': 600000,
        },
      );
      await auth.onHello(_context());
      final inFlight = auth.onAuthenticate(_context(), _proof());
      final rejecting = _Delegate()..hello = _rejectedHello;
      await _auth(
        [rejecting],
        options: {'rate_limit_max_attempts': 2},
      ).onHello(_context());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pending.complete(RemoteAuthenticateResponse.failure(_failure));
      expect(_expectFailure(await inFlight).message, 'denied');
      final healthy = _Delegate()
        ..hello = () => RemoteHelloResponse.success(_success);
      expect(
        (await _auth(
          [healthy],
          options: {'rate_limit_window_ms': 600000},
        ).onHello(_context())).isSuccess,
        isTrue,
      );
      expect(healthy.helloRequests, hasLength(1));
    },
  );
  test('delegates may rely on the default no-op abort handler', () async {
    final auth = _auth([_DefaultAbortDelegate()]);
    await auth.onHello(_context());
    await auth.onAbort(_context());
    expect(
      _expectFailure(await auth.onAuthenticate(_context(), _proof())).reason,
      wamp.Error.protocolViolation,
    );
    expect((await auth.onHello(_context())).isChallenge, isTrue);
  });
  for (final unavailable in [true, false]) {
    test(
      'hello exception ($unavailable) backs off and uses the next delegate',
      () async {
        final failed = _Delegate()
          ..hello = () => throw unavailable
              ? RemoteDelegateUnavailableException()
              : StateError('delegate error');
        final healthy = _Delegate()
          ..hello = () => RemoteHelloResponse.success(_success);
        final auth = _auth([failed, healthy]);
        expect((await auth.onHello(_context())).isSuccess, isTrue);
        expect((await auth.onHello(_context())).isSuccess, isTrue);
        expect(failed.helloRequests, hasLength(1));
        expect(healthy.helloRequests, hasLength(2));
      },
    );
    test(
      'authenticate exception ($unavailable) consumes the pending challenge',
      () async {
        final delegate = _Delegate()
          ..authenticate = () => throw unavailable
              ? RemoteDelegateUnavailableException()
              : StateError('sensitive delegate error');
        final auth = _auth([delegate]);
        await auth.onHello(_context());
        final failed = await auth.onAuthenticate(_context(), _proof());
        expect(failed.isFailure, isTrue);
        expect(failed.failure!.reason, wamp.Error.notAuthorized);
        expect(failed.failure!.message, isNot(contains('sensitive')));
        expect(
          _expectFailure(
            await auth.onAuthenticate(_context(), _proof()),
          ).reason,
          wamp.Error.protocolViolation,
        );
        expect(
          _expectFailure(await auth.onHello(_context())).reason,
          wamp.Error.notAuthorized,
        );
        expect(delegate.helloRequests, hasLength(1));
        expect(delegate.authenticateRequests, hasLength(1));
      },
    );
    test(
      'abort exception ($unavailable) clears state and backs off the delegate',
      () async {
        final delegate = _Delegate()
          ..abort = () => throw unavailable
              ? RemoteDelegateUnavailableException()
              : StateError('abort error');
        final auth = _auth([delegate]);
        await auth.onHello(_context());
        await auth.onAbort(_context(), reason: 'client_closed');
        await auth.onAbort(_context(), reason: 'duplicate');
        expect(delegate.abortRequests, hasLength(1));
        expect(delegate.abortRequests.single.reason, 'client_closed');
        expect(
          delegate.abortRequests.single.transactionId,
          delegate.helloRequests.single.transactionId,
        );
        expect(
          _expectFailure(
            await auth.onAuthenticate(_context(), _proof()),
          ).reason,
          wamp.Error.protocolViolation,
        );
        expect((await auth.onHello(_context())).isFailure, isTrue);
        expect(delegate.helloRequests, hasLength(1));
      },
    );
  }

  group('remote authentication policy boundaries', () {
    for (final providerKey in ['authprovider', 'provider']) {
      for (final stage in ['hello', 'authenticate']) {
        test('$stage accepts the allowed $providerKey', () async {
          final success = AuthSuccess(
            authId: 'user',
            authRole: 'member',
            details: {providerKey: 'trusted'},
          );
          final delegate = _Delegate();
          delegate.hello = () => stage == 'hello'
              ? RemoteHelloResponse.success(success)
              : _challenge();
          delegate.authenticate = () =>
              RemoteAuthenticateResponse.success(success);
          final auth = _auth(
            [delegate],
            options: {
              'allowed_roles': ['member'],
              'allowed_providers': ['trusted'],
            },
          );
          var result = await auth.onHello(_context());
          if (stage == 'authenticate') {
            expect(result.isChallenge, isTrue);
            result = await auth.onAuthenticate(_context(), _proof());
          }
          expect(result.isSuccess, isTrue);
          expect(result.success!.authId, 'user');
          expect(result.success!.authRole, 'member');
          expect(result.success!.details, {providerKey: 'trusted'});
        });
      }
    }
    test(
      'fake challenges retain identity and can never authenticate',
      () async {
        final delegate = _Delegate()..hello = _rejectedHello;
        final auth = _auth(
          [delegate],
          options: {'fake_challenge_on_hello_failure': true},
        );
        final first = await auth.onHello(_context());
        expect(first.isChallenge, isTrue);
        expect(first.challenge!.extra, {'fake': true});
        final payload =
            jsonDecode(first.challenge!.challenge['challenge']! as String)
                as Map;
        expect(payload['authid'], 'user');
        expect(payload['realm'], 'consumer.realm');
        expect(payload['session'], 42);
        expect(base64Url.decode(payload['nonce'] as String), hasLength(32));
        await auth.onAbort(_context(), reason: 'closed');
        expect(delegate.abortRequests, hasLength(1));
        expect(delegate.abortRequests.single.authId, 'user');
        await auth.onHello(_context());
        final denied = await auth.onAuthenticate(_context(), _proof());
        expect(denied.isFailure, isTrue);
        expect(denied.failure!.reason, wamp.Error.authenticationFailed);
        expect(denied.failure!.message, 'denied');
        expect(delegate.authenticateRequests, isEmpty);
      },
    );
    test(
      'zero challenge timeout disables expiry rather than expiring immediately',
      () async {
        final delegate = _Delegate();
        final auth = _auth([delegate], options: {'challenge_timeout_ms': 0});
        await auth.onHello(_context());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          (await auth.onAuthenticate(_context(), _proof())).isSuccess,
          isTrue,
        );
        expect(delegate.abortRequests, isEmpty);
        expect(delegate.authenticateRequests, hasLength(1));
      },
    );
    test(
      'explicitly disabled rate limiting neither blocks nor records failures',
      () async {
        final rejecting = _Delegate()..hello = _rejectedHello;
        await _auth(
          [rejecting],
          options: {
            'rate_limit_max_attempts': 1,
            'backoff_base_ms': 600000,
            'backoff_max_ms': 600000,
          },
        ).onHello(_context());
        final disabled = _auth([rejecting], rateLimitMaxAttempts: 0);
        expect(
          _expectFailure(await disabled.onHello(_context())).message,
          'denied',
        );
        expect(rejecting.helloRequests, hasLength(2));
        RemoteAuthenticator.resetRateLimiter();
        expect(
          _expectFailure(await disabled.onHello(_context())).message,
          'denied',
        );
        final healthy = _Delegate()
          ..hello = () => RemoteHelloResponse.success(_success);
        expect((await _auth([healthy]).onHello(_context())).isSuccess, isTrue);
        expect(healthy.helloRequests, hasLength(1));
      },
    );
    test('overlapping failed attempts accumulate exponential backoff', () async {
      final responses = List.generate(
        2,
        (_) => Completer<RemoteAuthenticateResponse>(),
      );
      final results = <Future<AuthResult>>[];
      for (final response in responses) {
        final delegate = _Delegate()..authenticate = () => response.future;
        final auth = _auth(
          [delegate],
          options: {
            'rate_limit_max_attempts': 1,
            'rate_limit_window_ms': 600000,
            'backoff_base_ms': 100000,
            'backoff_factor': 3,
            'backoff_max_ms': 500000,
          },
        );
        await auth.onHello(_context());
        results.add(auth.onAuthenticate(_context(), _proof()));
      }
      // Both proofs enter before either failure. No sleep through backoff is needed.
      for (var index = 0; index < responses.length; index++) {
        responses[index].complete(RemoteAuthenticateResponse.failure(_failure));
        expect(_expectFailure(await results[index]).message, 'denied');
        final observer = _Delegate();
        final blocked = await _auth(
          [observer],
          options: {
            'rate_limit_window_ms': 600000,
          },
        ).onHello(_context());
        expect(observer.helloRequests, isEmpty);
        expect(blocked.isFailure, isTrue);
        final match = RegExp(
          r'^Remote authentication rate limited\. Retry in (\d+)ms$',
        ).firstMatch(blocked.failure!.message!);
        expect(match, isNotNull);
        final remaining = int.parse(match!.group(1)!);
        final expected = index == 0 ? 100000 : 300000;
        expect(remaining, inInclusiveRange(expected * 0.8, expected));
      }
    });
  });

  group('remote assertion controls', () {
    test('success assertions preserve values and evaluate once', () async {
      var calls = 0;
      final value = Object();
      expect(
        _validRemoteValue(() {
          calls++;
          return value;
        }),
        same(value),
      );
      expect(calls, 1);
      expect(
        await _validRemoteCompletion(() async {
          calls++;
          return value;
        }),
        same(value),
      );
      expect(calls, 2);
      expect(_validRemoteValue<Object?>(() => null), isNull);
      expect(await _validRemoteCompletion<Object?>(() async => null), isNull);
    });
    for (final (error, isContractFailure) in <(Object, bool)>[
      (TypeError(), true),
      (StateError('missing configured delegate'), true),
      (ArgumentError('invalid configured delegate'), true),
      (TimeoutException('deadline'), false),
      (UnsupportedError('infrastructure unavailable'), false),
      (const StackOverflowError(), false),
      (const OutOfMemoryError(), false),
      (TestFailure('original assertion'), false),
      (Object(), false),
    ]) {
      test('sync ${error.runtimeType} retains its classification', () {
        var calls = 0;
        final matcher = isContractFailure
            ? isA<TestFailure>().having(
                (e) => e.message,
                'message',
                contains('Valid remote authentication'),
              )
            : same(error);
        expect(
          () => _validRemoteValue<void>(() {
            calls++;
            throw error;
          }),
          throwsA(matcher),
        );
        expect(calls, 1);
      });
      for (final asyncFailure in [false, true]) {
        test(
          'async ${error.runtimeType} retains classification deferred=$asyncFailure',
          () async {
            var calls = 0;
            final matcher = isContractFailure
                ? isA<TestFailure>().having(
                    (e) => e.message,
                    'message',
                    contains('Valid remote authentication'),
                  )
                : same(error);
            await expectLater(
              _validRemoteCompletion<void>(() {
                calls++;
                if (asyncFailure) return Future<void>.error(error);
                throw error;
              }),
              throwsA(matcher),
            );
            expect(calls, 1);
          },
        );
      }
    }
    test('failure assertion preserves identity and rejects other statuses', () {
      expect(_expectFailure(AuthResult.failure(_failure)), same(_failure));
      for (final result in [
        AuthResult.success(_success),
        AuthResult.challenge(const AuthChallenge(challenge: {}, extra: {})),
      ]) {
        expect(() => _expectFailure(result), throwsA(isA<TestFailure>()));
      }
    });
  });

  group('remote configuration', () {
    test('delegate list trims entries and detaches the caller list', () {
      final ids = [' first ', 'second'];
      final config = _validRemoteValue(
        () => RemoteAuthenticatorConfig.parse({
          'delegates': ids,
        }, _realm),
      );
      expect(config.delegateIds, ['first', 'second']);
      ids[0] = 'changed';
      expect(config.delegateIds, ['first', 'second']);
      expect(() => config.delegateIds.add('third'), throwsUnsupportedError);
    });
    test('challenge timeout is clamped between disabled and ten minutes', () {
      expect(
        RemoteAuthenticatorConfig.parse({
          'challenge_timeout_ms': -1,
        }, _realm).challengeTimeoutMs,
        0,
      );
      expect(
        RemoteAuthenticatorConfig.parse({
          'challenge_timeout_ms': 700000,
        }, _realm).challengeTimeoutMs,
        600000,
      );
    });
    for (final value in [0, -1, 4.5]) {
      test(
        'numeric option $value preserves positive values or documented defaults',
        () {
          final config = RemoteAuthenticatorConfig.parse({
            'rate_limit_max_attempts': value,
            'rate_limit_window_ms': value,
            'backoff_base_ms': value,
            'backoff_max_ms': value,
            'delegate_retry_ms': value,
            'backoff_factor': value,
          }, _realm);
          expect(config.rateLimitMaxAttempts, value > 0 ? 4 : 5);
          expect(config.rateLimitWindowMs, value > 0 ? 4 : 10000);
          expect(config.backoffBaseMs, value > 0 ? 4 : 500);
          expect(config.backoffMaxMs, value > 0 ? 4 : 30000);
          expect(
            config.delegateRetryDelay,
            Duration(milliseconds: value > 0 ? 4 : 5000),
          );
          expect(config.backoffFactor, value > 0 ? 4.5 : 2.0);
        },
      );
    }
    test(
      'RPC factory resolves its delegate without a local registry entry',
      () async {
        final options = <String, Object?>{
          'method': 'ticket',
          'challenge_timeout_ms': 123,
          'rpc': <String, Object?>{
            'transport': <String, Object?>{
              'type': 'websocket',
              'url': 'wss://localhost/auth',
            },
          },
        };
        final config = RemoteAuthenticatorConfig.parse(options, _realm);
        expect(config.delegateIds, isEmpty);
        expect(config.rpcDelegate, isNotNull);
        expect(config.challengeTimeoutMs, 123);
        expect(config.options, isEmpty);
        final auth = await _validRemoteCompletion(
          () => const RemoteAuthenticatorFactory().create(_realm, options),
        );
        expect(auth.method, 'ticket');
        expect(RemoteAuthenticatorRegistry.delegates, isEmpty);
      },
    );
    for (final invalid in [
      false,
      '',
      '  ',
      ', ,',
      <String>[],
      [1, true],
    ]) {
      test('rejects unusable delegate selector $invalid', () {
        expect(
          () => RemoteAuthenticatorConfig.parse({'delegates': invalid}, _realm),
          throwsArgumentError,
        );
      });
    }
    test('delegate aliases preserve order and trim comma-separated IDs', () {
      final config = _validRemoteValue(
        () => RemoteAuthenticatorConfig.parse({
          'delegates': ' first, , second ',
        }, _realm),
      );
      expect(config.delegateIds, ['first', 'second']);
      expect(() => config.delegateIds.add('third'), throwsUnsupportedError);
    });
    for (final key in ['allowed_roles', 'allowed_providers']) {
      test('$key must be a list', () {
        expect(
          () => RemoteAuthenticatorConfig.parse({key: 'member'}, _realm),
          throwsArgumentError,
        );
      });
    }
    for (final key in [
      'rate_limit_max_attempts',
      'rate_limit_window_ms',
      'backoff_base_ms',
      'backoff_max_ms',
      'delegate_retry_ms',
      'backoff_factor',
    ]) {
      test('$key rejects non-numeric values', () {
        expect(
          () => RemoteAuthenticatorConfig.parse({key: '1'}, _realm),
          throwsArgumentError,
        );
      });
    }
  });
}

AuthFailure _expectFailure(AuthResult result) {
  expect(result.status, AuthStatus.failure);
  expect(result.failure, isNotNull);
  expect(result.success, isNull);
  expect(result.challenge, isNull);
  return result.failure!;
}

T _validRemoteValue<T>(T Function() operation) {
  try {
    return operation();
  } on TypeError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  } on StateError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  } on ArgumentError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  }
}

Future<T> _validRemoteCompletion<T>(FutureOr<T> Function() operation) async {
  try {
    return await operation();
  } on TypeError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  } on StateError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  } on ArgumentError catch (error) {
    fail('Valid remote authentication operation must return: $error');
  }
}

const _realm = RealmSettings(
  name: 'consumer.realm',
  auth: RealmAuthSettings(methods: ['remote']),
  roles: [],
  limits: RealmLimitSettings(),
);
const _success = AuthSuccess(authId: 'user', authRole: 'member');
const _failure = AuthFailure(
  reason: wamp.Error.authenticationFailed,
  message: 'denied',
);
RemoteHelloResponse _rejectedHello() => RemoteHelloResponse.failure(_failure);

AuthenticatorContext _context() => AuthenticatorContext(
  realm: _realm,
  sessionId: 42,
  transport: const TransportMetadata(connectionId: 7),
  helloDetails: const {'authid': 'user'},
);
AuthenticateMessage _proof() => AuthenticateMessage(signature: 'proof');
RemoteHelloResponse _challenge() => RemoteHelloResponse.challenge(
  RemoteChallenge(authId: 'user', challenge: {'nonce': 'challenge'}, extra: {}),
);
RemoteAuthenticator _auth(
  List<RemoteAuthenticatorDelegate> delegates, {
  Map<String, Object?> options = const {},
  int? rateLimitMaxAttempts,
}) {
  var config = RemoteAuthenticatorConfig.parse({
    'fake_challenge_on_hello_failure': false,
    'delegate_retry_ms': 600000,
    ...options,
  }, _realm);
  if (rateLimitMaxAttempts != null) {
    config = RemoteAuthenticatorConfig(
      realm: config.realm,
      options: config.options,
      method: config.method,
      delegateIds: config.delegateIds,
      challengeTimeoutMs: config.challengeTimeoutMs,
      allowedRoles: config.allowedRoles,
      allowedProviders: config.allowedProviders,
      fakeChallengeOnHelloFailure: config.fakeChallengeOnHelloFailure,
      rpcDelegate: config.rpcDelegate,
      rateLimitMaxAttempts: rateLimitMaxAttempts,
      rateLimitWindowMs: config.rateLimitWindowMs,
      backoffBaseMs: config.backoffBaseMs,
      backoffFactor: config.backoffFactor,
      backoffMaxMs: config.backoffMaxMs,
      delegateRetryDelay: config.delegateRetryDelay,
    );
  }
  return RemoteAuthenticator(
    config,
    delegates,
    delegateIds: [for (var i = 0; i < delegates.length; i++) 'delegate-$i'],
  );
}

class _Delegate extends RemoteAuthenticatorDelegate {
  FutureOr<RemoteHelloResponse> Function() hello = _challenge;
  FutureOr<RemoteAuthenticateResponse> Function() authenticate = () =>
      RemoteAuthenticateResponse.success(_success);
  FutureOr<void> Function() abort = () {};
  final helloRequests = <RemoteHelloRequest>[];
  final authenticateRequests = <RemoteAuthenticateRequest>[];
  final abortRequests = <RemoteAbortRequest>[];

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    helloRequests.add(request);
    return hello();
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    authenticateRequests.add(request);
    return authenticate();
  }

  @override
  Future<void> onAbort(RemoteAbortRequest request) async {
    abortRequests.add(request);
    await abort();
  }
}

class _DefaultAbortDelegate extends RemoteAuthenticatorDelegate {
  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async =>
      _challenge();

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async => RemoteAuthenticateResponse.success(_success);
}
