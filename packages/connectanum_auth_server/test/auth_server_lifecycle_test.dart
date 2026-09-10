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
    expect(
      (await server.onHello(hello('same'))).status,
      RemoteHelloStatus.challenge,
    );
    final duplicate = await server.onHello(hello('same'));
    expect(duplicate.status, RemoteHelloStatus.failure);
    expect(factory.calls, 1);
    expect(
      (await server.onAuthenticate(authenticate('same'))).status,
      RemoteAuthenticateStatus.success,
    );
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
      (await server.onAuthenticate(authenticate('same'))).status,
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
      factory.authenticator.hello = null;
      expect(
        (await server.onHello(hello('retry'))).status,
        RemoteHelloStatus.challenge,
      );
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
