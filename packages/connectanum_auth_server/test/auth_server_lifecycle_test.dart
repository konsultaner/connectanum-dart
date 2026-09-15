import 'dart:async';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/auth.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  late _Factory factory;
  late AuthServer server;
  late RealmSettings realm;
  late DateTime now;

  setUp(() {
    AuthenticatorRegistry.clear();
    AuthSecurityTracker.reset();
    AuthAuditLogger.clearSink();
    factory = _Factory();
    AuthenticatorRegistry.registerFactory(factory);
    final settings =
        (RouterSettingsBuilder()..addRealmFromBuilder(
              RealmSettingsBuilder('realm1')
                ..addAuthMethod('controlled')
                ..setLimits(const RealmLimitSettings(maxPendingAuth: 1)),
            ))
            .build();
    realm = settings.realms.single;
    now = DateTime.utc(2026);
    server = AuthServer(settings: settings, clock: () => now);
  });

  tearDown(() => server.close());

  RemoteHelloRequest hello(String id) => RemoteHelloRequest(
    realmSettings: realm,
    context: _context(realm),
    options: const {},
    transactionId: id,
  );

  RemoteAuthenticateRequest authenticate(String id) =>
      RemoteAuthenticateRequest(
        realmSettings: realm,
        context: _context(realm),
        authId: 'user',
        authenticate: AuthenticateMessage(signature: 'proof'),
        options: const {},
        transactionId: id,
      );

  Future<void> abort(String id) => server.onAbort(
    RemoteAbortRequest(
      realmSettings: realm,
      context: _context(realm),
      authId: 'user',
      options: const {},
      transactionId: id,
    ),
  );

  test(
    'abort during factory creation rejects late HELLO and cleans up',
    () async {
      final creation = Completer<Authenticator>();
      factory.creation = creation.future;
      final result = server.onHello(hello('factory'));
      await factory.entered.future;
      await abort('factory');
      creation.complete(factory.authenticator);
      expect((await result).status, RemoteHelloStatus.failure);
      await _drain();
      expect(factory.authenticator.helloCalls, 0);
      expect(factory.authenticator.abortCalls, 1);
    },
  );

  test('abort during HELLO rejects late success', () async {
    final pendingHello = Completer<AuthResult>();
    factory.authenticator.hello = pendingHello.future;
    final result = server.onHello(hello('hello'));
    await factory.authenticator.helloEntered.future;
    await abort('hello');
    pendingHello.complete(_success());
    expect((await result).status, RemoteHelloStatus.failure);
    await _drain();
    expect(factory.authenticator.abortCalls, 1);
  });

  test('abort during AUTHENTICATE rejects late success', () async {
    final pendingAuth = Completer<AuthResult>();
    factory.authenticator.authenticate = pendingAuth.future;
    expect(
      (await server.onHello(hello('auth'))).status,
      RemoteHelloStatus.challenge,
    );
    final result = server.onAuthenticate(authenticate('auth'));
    await factory.authenticator.authenticateEntered.future;
    await abort('auth');
    pendingAuth.complete(_success());
    expect((await result).status, RemoteAuthenticateStatus.failure);
    await _drain();
    expect(factory.authenticator.abortCalls, 1);
  });

  test('duplicate HELLO cannot replace an existing challenge', () async {
    final local = AuthServer(
      settings:
          (RouterSettingsBuilder()..addRealmFromBuilder(
                RealmSettingsBuilder('realm1')
                  ..addAuthMethod('controlled')
                  ..setLimits(const RealmLimitSettings(maxPendingAuth: 2)),
              ))
              .build(),
    );
    addTearDown(local.close);
    expect(
      (await local.onHello(hello('same'))).status,
      RemoteHelloStatus.challenge,
    );
    final duplicate = await local.onHello(hello('same'));
    expect(duplicate.status, RemoteHelloStatus.failure);
    expect(duplicate.failure?.reason, 'wamp.error.protocol_violation');
    expect(local.pendingAuthenticationCounts, {'realm1': 1});
    expect(factory.calls, 1);
    expect(
      (await local.onAuthenticate(authenticate('same'))).status,
      RemoteAuthenticateStatus.success,
    );
  });

  test('closing an idle server prevents new provider creation', () async {
    await server.close();
    final response = await server.onHello(hello('after-close'));
    expect(response.status, RemoteHelloStatus.failure);
    expect(response.failure?.message, 'Remote authentication service closed');
    expect(factory.calls, 0);
    expect(server.pendingAuthenticationCounts, isEmpty);
  });

  test(
    'missing identities are rejected before the selected provider runs',
    () async {
      for (final authId in [null, '']) {
        final response = await server.onHello(
          RemoteHelloRequest(
            realmSettings: realm,
            context: AuthenticatorContext(
              realm: realm,
              sessionId: 1,
              transport: const TransportMetadata(connectionId: 1),
              helloDetails: {
                'authid': authId,
                'authmethods': ['controlled'],
              },
            ),
            options: const {},
            transactionId: 'missing-$authId',
          ),
        );
        expect(response.status, RemoteHelloStatus.failure);
        expect(
          response.failure?.message,
          'authid is required for remote authentication',
        );
        await _drain();
        expect(server.pendingAuthenticationCounts, isEmpty);
      }
      expect(factory.calls, 0);
    },
  );

  for (final timeout in [
    const Duration(milliseconds: 7),
    Duration.zero,
    const Duration(milliseconds: -1),
  ]) {
    test('explicit timeout $timeout overrides the realm deadline', () {
      fakeAsync((async) {
        final local = AuthServer(
          settings: server.settings,
          challengeTimeout: timeout,
          clock: () => now,
        );
        final creation = Completer<Authenticator>();
        factory.creation = creation.future;
        RemoteHelloResponse? response;
        local.onHello(hello('override')).then((value) => response = value);
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(timeout > Duration.zero ? 1 : 0));
        if (timeout > Duration.zero) {
          async.elapse(timeout - const Duration(milliseconds: 1));
          expect(response, isNull);
          async.elapse(const Duration(milliseconds: 1));
          expect(response?.status, RemoteHelloStatus.failure);
          expect(
            response?.failure?.message,
            'Remote authentication challenge expired',
          );
        } else {
          async.elapse(const Duration(days: 1));
          expect(response, isNull);
        }
        creation.complete(factory.authenticator);
        async.flushMicrotasks();
        expect(
          factory.authenticator.helloCalls,
          timeout > Duration.zero ? 0 : 1,
        );
        if (timeout <= Duration.zero) {
          expect(response?.status, RemoteHelloStatus.challenge);
        }
        local.close();
        async.flushMicrotasks();
        expect(local.pendingAuthenticationCounts, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  test('an unknown realm is rejected before provider creation', () async {
    final unknown = RealmSettingsBuilder('unknown').build();
    await expectLater(
      server.onHello(
        RemoteHelloRequest(
          realmSettings: unknown,
          context: _context(unknown),
          options: const {},
          transactionId: 'unknown-realm',
        ),
      ),
      throwsStateError,
    );
    expect(factory.calls, 0);
    expect(server.pendingAuthenticationCounts, isEmpty);
  });

  test('pending limit includes an unfinished factory', () async {
    final creation = Completer<Authenticator>();
    factory.creation = creation.future;
    final first = server.onHello(hello('first'));
    await factory.entered.future;
    final second = server.onHello(hello('second'));
    await _drain();
    creation.complete(factory.authenticator);
    await first;
    expect((await second).status, RemoteHelloStatus.failure);
    expect(factory.calls, 1);
    await abort('first');
  });

  test('challenge is expired exactly at its deadline', () async {
    expect(
      (await server.onHello(hello('expired'))).status,
      RemoteHelloStatus.challenge,
    );
    now = now.add(Duration(milliseconds: realm.limits.authTimeoutMs));
    expect(
      (await server.onAuthenticate(authenticate('expired'))).status,
      RemoteAuthenticateStatus.failure,
    );
    expect(factory.authenticator.authenticateCalls, 0);
    await _drain();
    expect(factory.authenticator.abortCalls, 1);
  });

  test(
    'abort replies promptly but holds capacity through callback and cleanup',
    () async {
      final pendingHello = Completer<AuthResult>();
      final cleanup = Completer<void>();
      factory.authenticator.hello = pendingHello.future;
      factory.authenticator.cleanup = cleanup.future;
      final first = server.onHello(hello('first'));
      await factory.authenticator.helloEntered.future;
      await abort('first');
      expect(
        (await first.timeout(const Duration(seconds: 1))).status,
        RemoteHelloStatus.failure,
      );
      expect(
        (await server.onHello(hello('second'))).status,
        RemoteHelloStatus.failure,
      );
      expect(server.pendingAuthenticationCounts, {'realm1': 1});
      pendingHello.complete(_success());
      await _drain();
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, {'realm1': 1});
      await abort('first');
      cleanup.complete();
      await _drain();
      expect(server.pendingAuthenticationCounts, isEmpty);
      factory.authenticator.hello = null;
      expect(
        (await server.onHello(hello('second'))).status,
        RemoteHelloStatus.challenge,
      );
      expect(factory.calls, 2);
    },
  );

  test(
    'duplicate HELLO during factory does not disturb first response',
    () async {
      final creation = Completer<Authenticator>();
      factory.creation = creation.future;
      final first = server.onHello(hello('same'));
      await factory.entered.future;
      expect(
        (await server.onHello(hello('same'))).status,
        RemoteHelloStatus.failure,
      );
      creation.complete(factory.authenticator);
      expect((await first).status, RemoteHelloStatus.challenge);
      expect(
        (await server.onAuthenticate(authenticate('same'))).status,
        RemoteAuthenticateStatus.success,
      );
      expect(factory.calls, 1);
    },
  );

  test('duplicate AUTHENTICATE cannot consume active attempt', () async {
    final pendingAuth = Completer<AuthResult>();
    factory.authenticator.authenticate = pendingAuth.future;
    await server.onHello(hello('same'));
    final first = server.onAuthenticate(authenticate('same'));
    await factory.authenticator.authenticateEntered.future;
    expect(
      (await server
              .onAuthenticate(authenticate('same'))
              .timeout(const Duration(seconds: 1)))
          .status,
      RemoteAuthenticateStatus.failure,
    );
    pendingAuth.complete(_success());
    expect((await first).status, RemoteAuthenticateStatus.success);
    expect(factory.authenticator.authenticateCalls, 1);
    expect(
      (await server.onAuthenticate(authenticate('same'))).status,
      RemoteAuthenticateStatus.failure,
    );
  });

  test(
    'a masked HELLO denial cannot be changed into provider success',
    () async {
      final local = AuthServer(
        settings: server.settings,
        fakeChallengeOnHelloFailure: true,
      );
      addTearDown(local.close);
      factory.authenticator.hello = Future.value(
        AuthResult.failure(
          const AuthFailure(
            reason: 'wamp.error.not_authorized',
            message: 'identity denied',
          ),
        ),
      );
      final challenge = await local.onHello(hello('masked'));
      expect(challenge.status, RemoteHelloStatus.challenge);
      expect(challenge.challenge?.extra, {'fake': true});
      final response = await local.onAuthenticate(authenticate('masked'));
      expect(response.status, RemoteAuthenticateStatus.failure);
      expect(response.failure?.reason, 'wamp.error.authentication_failed');
      expect(response.failure?.message, 'identity denied');
      expect(factory.authenticator.authenticateCalls, 0);
      await _drain();
      expect(factory.authenticator.abortCalls, 1);
      expect(local.pendingAuthenticationCounts, isEmpty);
    },
  );

  test(
    'malformed entries do not prevent selecting a valid auth method',
    () async {
      final response = await server.onHello(
        RemoteHelloRequest(
          realmSettings: realm,
          context: AuthenticatorContext(
            realm: realm,
            sessionId: 1,
            transport: const TransportMetadata(connectionId: 1),
            helloDetails: {
              'authid': 'user',
              'authmethods': [null, 42, '', <String, Object?>{}, 'controlled'],
            },
          ),
          options: const {},
          transactionId: 'method-selection',
        ),
      );
      expect(response.status, RemoteHelloStatus.challenge);
      expect(factory.calls, 1);
      expect(factory.authenticator.helloCalls, 1);
    },
  );

  test('authentication failure finalizes the pending attempt', () async {
    const failure = AuthFailure(
      reason: 'wamp.error.not_authorized',
      message: 'denied',
    );
    factory.authenticator.authenticate = Future.value(
      AuthResult.failure(failure),
    );
    expect(
      (await server.onHello(hello('rejected'))).status,
      RemoteHelloStatus.challenge,
    );

    final result = await server.onAuthenticate(authenticate('rejected'));

    expect(result.status, RemoteAuthenticateStatus.failure);
    expect(result.failure?.reason, failure.reason);
    expect(result.failure?.message, failure.message);
    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
    expect(factory.authenticator.abortCalls, 1);
  });

  test(
    'plugin result payloads cannot override their declared HELLO status',
    () async {
      for (final (id, result) in [
        (
          'extra-success',
          const _PluginResult(
            AuthStatus.challenge,
            challenge: AuthChallenge(extra: {}),
            success: AuthSuccess(authId: 'unexpected', authRole: 'admin'),
          ),
        ),
        (
          'extra-failure',
          const _PluginResult(
            AuthStatus.challenge,
            challenge: AuthChallenge(extra: {}),
            failure: AuthFailure(reason: 'unexpected'),
          ),
        ),
      ]) {
        factory.authenticator.hello = Future.value(result);
        final response = await server.onHello(hello(id));
        expect(response.status, RemoteHelloStatus.challenge);
        expect(response.success, isNull);
        server.abort(id);
        await _drain();
        expect(server.pendingAuthenticationCounts, isEmpty);
      }
    },
  );

  test(
    'an incomplete plugin HELLO result fails closed and releases capacity',
    () async {
      factory.authenticator.hello = Future.value(
        const _PluginResult(AuthStatus.success),
      );
      final response = await server.onHello(hello('incomplete'));
      expect(response.status, RemoteHelloStatus.failure);
      expect(
        response.failure?.message,
        'Authenticator did not produce a challenge',
      );
      await _drain();
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test(
    'an inconsistent plugin AUTHENTICATE result cannot authorize a session',
    () async {
      await server.onHello(hello('inconsistent'));
      factory.authenticator.authenticate = Future.value(
        const _PluginResult(
          AuthStatus.challenge,
          success: AuthSuccess(authId: 'unexpected', authRole: 'admin'),
        ),
      );
      final response = await server.onAuthenticate(
        authenticate('inconsistent'),
      );
      expect(response.status, RemoteAuthenticateStatus.failure);
      expect(response.success, isNull);
      await _drain();
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test('trusted abort helper releases a pending challenge', () async {
    expect(
      (await server.onHello(hello('trusted-abort'))).status,
      RemoteHelloStatus.challenge,
    );

    server.abort('trusted-abort');

    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
    expect(factory.authenticator.abortCalls, 1);
  });

  test(
    'wrong identity or transport cannot consume or abort a challenge',
    () async {
      await server.onHello(hello('owned'));
      for (final (identity, context) in [
        ('different-user', _context(realm)),
        (
          'user',
          AuthenticatorContext(
            realm: realm,
            sessionId: 2,
            transport: const TransportMetadata(connectionId: 1),
          ),
        ),
        (
          'user',
          AuthenticatorContext(
            realm: realm,
            sessionId: 1,
            transport: const TransportMetadata(connectionId: 2),
          ),
        ),
        (
          'user',
          AuthenticatorContext(
            realm: realm,
            sessionId: 1,
            transport: const TransportMetadata(
              connectionId: 1,
              isEncrypted: true,
            ),
          ),
        ),
      ]) {
        final rejected = await server.onAuthenticate(
          RemoteAuthenticateRequest(
            realmSettings: realm,
            context: context,
            authId: identity,
            authenticate: AuthenticateMessage(signature: 'proof'),
            options: const {},
            transactionId: 'owned',
          ),
        );
        expect(rejected.status, RemoteAuthenticateStatus.failure);
        await server.onAbort(
          RemoteAbortRequest(
            realmSettings: realm,
            context: context,
            authId: identity,
            options: const {},
            transactionId: 'owned',
          ),
        );
      }
      expect(
        (await server.onAuthenticate(authenticate('owned'))).status,
        RemoteAuthenticateStatus.success,
      );
    },
  );

  test(
    'close invalidates active work without waiting for the provider',
    () async {
      final creation = Completer<Authenticator>();
      factory.creation = creation.future;
      final result = server.onHello(hello('closing'));
      await factory.entered.future;
      await server.close();
      await server.close();
      expect(
        (await result.timeout(const Duration(seconds: 1))).status,
        RemoteHelloStatus.failure,
      );
      expect(
        (await server.onHello(hello('new'))).status,
        RemoteHelloStatus.failure,
      );
      creation.complete(factory.authenticator);
      await _drain();
      expect(factory.authenticator.helloCalls, 0);
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test(
    'late provider error after abort cannot change failure accounting',
    () async {
      final events = <AuthAuditEvent>[];
      AuthAuditLogger.registerSink(events.add);
      final pendingHello = Completer<AuthResult>();
      factory.authenticator.hello = pendingHello.future;
      final result = server.onHello(hello('late-error'));
      await factory.authenticator.helloEntered.future;
      await abort('late-error');
      await result;
      pendingHello.completeError(StateError('credential material'));
      await _drain();
      expect(events, isEmpty);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test(
    'provider and cleanup exceptions release capacity without disclosure',
    () async {
      final events = <AuthAuditEvent>[];
      AuthAuditLogger.registerSink(events.add);
      final failed = Completer<AuthResult>();
      factory.authenticator.hello = failed.future;
      factory.authenticator.cleanupError = true;
      final response = server.onHello(hello('throwing'));
      await factory.authenticator.helloEntered.future;
      failed.completeError(StateError('private credential'));
      final result = await response;
      expect(result.status, RemoteHelloStatus.failure);
      expect(result.failure?.message, isNot(contains('private credential')));
      await _drain();
      expect(server.pendingAuthenticationCounts, isEmpty);
      expect(events, hasLength(1));
      expect(events.single.outcome, AuthAuditOutcome.failure);
      expect(events.single.message, isNot(contains('private credential')));
      factory.authenticator.hello = null;
      expect(
        (await server.onHello(hello('retry'))).status,
        RemoteHelloStatus.challenge,
      );
    },
  );

  test(
    'provider failure at the deadline keeps the expiration reason',
    () async {
      final failed = Completer<AuthResult>();
      factory.authenticator.hello = failed.future;
      final result = server.onHello(hello('deadline-error'));
      await factory.authenticator.helloEntered.future;
      now = now.add(Duration(milliseconds: realm.limits.authTimeoutMs));
      failed.completeError(StateError('late credential error'));
      final response = await result;
      expect(response.status, RemoteHelloStatus.failure);
      expect(
        response.failure?.message,
        'Remote authentication challenge expired',
      );
      await _drain();
      expect(server.pendingAuthenticationCounts, isEmpty);
      expect(factory.authenticator.abortCalls, 1);
    },
  );

  test('deadline includes factory time and expires without a new request', () {
    fakeAsync((async) {
      final creation = Completer<Authenticator>();
      factory.creation = creation.future;
      RemoteHelloResponse? response;
      server.onHello(hello('slow')).then((value) => response = value);
      async.flushMicrotasks();
      final timeout = Duration(milliseconds: realm.limits.authTimeoutMs);
      now = now.add(timeout);
      async.elapse(timeout);
      expect(response?.status, RemoteHelloStatus.failure);
      expect(server.pendingAuthenticationCounts, {'realm1': 1});
      creation.complete(factory.authenticator);
      async.flushMicrotasks();
      expect(factory.authenticator.helloCalls, 0);
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('idle real and masked challenges expire and release capacity', () {
    for (final masked in [false, true]) {
      fakeAsync((async) {
        final local = AuthServer(
          settings: server.settings,
          fakeChallengeOnHelloFailure: masked,
          clock: () => now,
        );
        factory.authenticator.hello = masked
            ? Future.value(
                AuthResult.failure(
                  const AuthFailure(reason: 'wamp.error.not_authorized'),
                ),
              )
            : null;
        RemoteHelloResponse? response;
        local.onHello(hello('idle')).then((value) => response = value);
        async.flushMicrotasks();
        expect(response?.status, RemoteHelloStatus.challenge);
        expect(local.pendingAuthenticationCounts, {'realm1': 1});
        final timeout = Duration(milliseconds: realm.limits.authTimeoutMs);
        now = now.add(timeout);
        async.elapse(timeout);
        expect(local.pendingAuthenticationCounts, isEmpty);
        expect(async.pendingTimers, isEmpty);
        local.close();
        async.flushMicrotasks();
      });
    }
  });

  test(
    'realms have independent capacity and nonpositive limits disable it',
    () async {
      final settings =
          (RouterSettingsBuilder()
                ..addRealmFromBuilder(
                  RealmSettingsBuilder('one')
                    ..addAuthMethod('controlled')
                    ..setLimits(const RealmLimitSettings(maxPendingAuth: 1)),
                )
                ..addRealmFromBuilder(
                  RealmSettingsBuilder('two')
                    ..addAuthMethod('controlled')
                    ..setLimits(
                      const RealmLimitSettings(
                        maxPendingAuth: 0,
                        authTimeoutMs: 0,
                      ),
                    ),
                ))
              .build();
      final local = AuthServer(settings: settings);
      addTearDown(local.close);
      for (var i = 0; i < 4; i++) {
        final target = settings.realms[i == 0 ? 0 : 1];
        final result = await local.onHello(
          RemoteHelloRequest(
            realmSettings: target,
            context: _context(target),
            options: const {},
            transactionId: '$i',
          ),
        );
        expect(result.status, RemoteHelloStatus.challenge);
      }
      expect(local.pendingAuthenticationCounts, {'one': 1, 'two': 3});
    },
  );
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

AuthenticatorContext _context(RealmSettings realm) => AuthenticatorContext(
  realm: realm,
  sessionId: 1,
  transport: const TransportMetadata(connectionId: 1),
  helloDetails: const {
    'authid': 'user',
    'authmethods': ['controlled'],
  },
);

AuthResult _success() => AuthResult.success(
  const AuthSuccess(authId: 'user', authRole: 'member'),
);

class _Factory extends AuthenticatorFactory {
  final authenticator = _Authenticator();
  final entered = Completer<void>();
  Future<Authenticator>? creation;
  int calls = 0;

  @override
  String get method => 'controlled';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return creation ?? authenticator;
  }
}

// AuthResult is implementable by third-party authenticators. Exercise malformed
// plugin output through that public interface, without accessing private state.
class _PluginResult implements AuthResult {
  const _PluginResult(
    this.status, {
    this.challenge,
    this.success,
    this.failure,
  });

  @override
  final AuthStatus status;
  @override
  final AuthChallenge? challenge;
  @override
  final AuthSuccess? success;
  @override
  final AuthFailure? failure;
  @override
  bool get isChallenge => status == AuthStatus.challenge;
  @override
  bool get isSuccess => status == AuthStatus.success;
  @override
  bool get isFailure => status == AuthStatus.failure;
}

class _Authenticator extends Authenticator {
  Future<AuthResult>? hello;
  Future<AuthResult>? authenticate;
  Future<void>? cleanup;
  bool cleanupError = false;
  final helloEntered = Completer<void>();
  final authenticateEntered = Completer<void>();
  int helloCalls = 0;
  int authenticateCalls = 0;
  int abortCalls = 0;

  @override
  String get method => 'controlled';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    helloCalls++;
    if (!helloEntered.isCompleted) helloEntered.complete();
    return hello ?? AuthResult.challenge(const AuthChallenge(extra: {}));
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    authenticateCalls++;
    if (!authenticateEntered.isCompleted) authenticateEntered.complete();
    return authenticate ?? _success();
  }

  @override
  Future<void> onAbort(AuthenticatorContext context, {String? reason}) async {
    abortCalls++;
    if (cleanupError) throw StateError('private cleanup detail');
    await cleanup;
  }
}
