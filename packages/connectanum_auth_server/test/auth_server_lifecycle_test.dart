import 'dart:async';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/auth.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/callback_entry.dart';

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

  test('clock shutdown prevents authentication admission', () async {
    final settings = server.settings;
    await server.close();
    var intercepted = false;
    server = AuthServer(
      settings: settings,
      clock: () {
        if (!intercepted) {
          intercepted = true;
          unawaited(server.close());
        }
        return now;
      },
    );
    final response = await server.onHello(hello('clock-close'));
    expect(response.status, RemoteHelloStatus.failure);
    expect(response.failure?.message, 'Remote authentication service closed');
    expect(factory.calls, 0);
    expect(factory.authenticator.helloCalls, 0);
    expect(server.pendingAuthenticationCounts, isEmpty);
  });

  for (final failRead in [2, 3, 4]) {
    test(
      'clock failure during HELLO read $failRead releases admission',
      () async {
        final settings = server.settings;
        await server.close();
        var reads = 0;
        server = AuthServer(
          settings: settings,
          clock: () {
            if (++reads >= failRead) throw StateError('private clock detail');
            return now;
          },
        );
        final observed = await server
            .onHello(hello('clock-failure'))
            .then<Object>(
              (response) => response,
              onError: (Object error) => error,
            );
        expect(observed, isA<RemoteHelloResponse>());
        final response = observed as RemoteHelloResponse;
        expect(response.status, RemoteHelloStatus.failure);
        expect(response.failure?.message, 'Remote authentication rejected');
        await _drain();
        expect(server.pendingAuthenticationCounts, isEmpty);
        expect(factory.calls, failRead == 2 ? 0 : 1);
        expect(factory.authenticator.abortCalls, failRead == 2 ? 0 : 1);
      },
    );
  }

  test('clock failure before AUTHENTICATE releases the challenge', () async {
    final settings = server.settings;
    await server.close();
    var failClock = false;
    server = AuthServer(
      settings: settings,
      clock: () {
        if (failClock) throw StateError('private clock detail');
        return now;
      },
    );
    expect(
      (await server.onHello(hello('clock-authenticate'))).status,
      RemoteHelloStatus.challenge,
    );
    failClock = true;
    final observed = await server
        .onAuthenticate(authenticate('clock-authenticate'))
        .then<Object>((response) => response, onError: (Object error) => error);
    expect(observed, isA<RemoteAuthenticateResponse>());
    final response = observed as RemoteAuthenticateResponse;
    expect(response.status, RemoteAuthenticateStatus.failure);
    expect(response.failure?.message, 'Remote authentication rejected');
    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
    expect(factory.authenticator.authenticateCalls, 0);
    expect(factory.authenticator.abortCalls, 1);
  });

  test('clock reentry cannot authenticate the same challenge twice', () async {
    final settings = server.settings;
    await server.close();
    var reenter = false;
    Future<RemoteAuthenticateResponse>? nested;
    final provider = Completer<AuthResult>();
    addTearDown(() {
      if (!provider.isCompleted) provider.complete(_success());
    });
    factory.authenticator.authenticate = provider.future;
    server = AuthServer(
      settings: settings,
      clock: () {
        if (reenter) {
          reenter = false;
          nested = server.onAuthenticate(authenticate('clock-consume'));
        }
        return now;
      },
    );
    expect(
      (await server.onHello(hello('clock-consume'))).status,
      RemoteHelloStatus.challenge,
    );
    reenter = true;
    final outer = server.onAuthenticate(authenticate('clock-consume'));
    await _drain();
    provider.complete(_success());
    expect((await nested!).status, RemoteAuthenticateStatus.success);
    final response = await outer;
    expect(response.status, RemoteAuthenticateStatus.failure);
    expect(
      response.failure?.message,
      'Remote authentication transaction is not in the expected state',
    );
    expect(factory.authenticator.authenticateCalls, 1);
    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
  });

  for (final sameId in [false, true]) {
    test('clock reentry preserves admission limits: same ID $sameId', () async {
      final settings = server.settings;
      await server.close();
      Future<RemoteHelloResponse>? nested;
      var intercepted = false;
      final timers = <Timer>[];
      addTearDown(() {
        for (final timer in timers) {
          timer.cancel();
        }
      });
      server = AuthServer(
        settings: settings,
        clock: () {
          if (!intercepted) {
            intercepted = true;
            nested = server.onHello(hello(sameId ? 'outer' : 'inner'));
          }
          return now;
        },
      );
      final outer = await runZoned(
        () => server.onHello(hello('outer')),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      expect((await nested!).status, RemoteHelloStatus.challenge);
      expect(outer.status, RemoteHelloStatus.failure);
      expect(
        outer.failure?.message,
        sameId
            ? 'Remote authentication transaction is not in the expected state'
            : 'Remote authentication capacity exhausted',
      );
      expect(factory.calls, 1);
      expect(factory.authenticator.helloCalls, 1);
      expect(server.pendingAuthenticationCounts, {'realm1': 1});
      await abort(sameId ? 'outer' : 'inner');
      await _drain();
      expect(factory.authenticator.abortCalls, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
      expect(timers.every((timer) => !timer.isActive), isTrue);
    });
  }

  for (final cancellation in ['none', 'abort', 'close']) {
    test(
      'deadline construction failure preserves $cancellation and releases capacity',
      () async {
        final observed =
            await runZoned(
              () => server.onHello(hello('timer-failure')),
              zoneSpecification: ZoneSpecification(
                createTimer: (self, parent, zone, duration, callback) {
                  if (cancellation == 'abort') {
                    server.abort('timer-failure');
                  } else if (cancellation == 'close') {
                    unawaited(server.close());
                  }
                  throw StateError('private timer setup detail');
                },
              ),
            ).then<Object>(
              (response) => response,
              onError: (Object error) => error,
            );
        expect(observed, isA<RemoteHelloResponse>());
        final response = observed as RemoteHelloResponse;
        expect(response.status, RemoteHelloStatus.failure);
        expect(response.failure?.message, switch (cancellation) {
          'abort' => 'Remote authentication aborted',
          'close' => 'Remote authentication service closed',
          _ => 'Remote authentication rejected',
        });
        await _drain();
        expect(factory.calls, 0);
        expect(server.pendingAuthenticationCounts, isEmpty);
        if (cancellation != 'close') {
          expect(
            (await server.onHello(hello('timer-failure'))).status,
            RemoteHelloStatus.challenge,
          );
          expect(factory.calls, 1);
        } else {
          expect(
            (await server.onHello(hello('timer-failure'))).status,
            RemoteHelloStatus.failure,
          );
          expect(factory.calls, 0);
        }
      },
    );
  }

  for (final extra in [Duration.zero, const Duration(microseconds: 1)]) {
    test(
      'deadline elapsed during timer setup prevents provider entry: $extra',
      () async {
        final response = await runZoned(
          () => server.onHello(hello('setup-expired')),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              now = now.add(duration + extra);
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        expect(response.status, RemoteHelloStatus.failure);
        expect(
          response.failure?.message,
          'Remote authentication challenge expired',
        );
        await _drain();
        expect(factory.calls, 0);
        expect(factory.authenticator.helloCalls, 0);
        expect(server.pendingAuthenticationCounts, isEmpty);
      },
    );
  }

  for (final closeServer in [false, true]) {
    test(
      'cancellation during deadline setup prevents provider entry: $closeServer',
      () async {
        var intercepted = false;
        final timers = <Timer>[];
        addTearDown(() {
          for (final timer in timers) {
            timer.cancel();
          }
        });
        final response = runZoned(
          () => server.onHello(hello('deadline-setup')),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createTimer(zone, duration, callback);
              timers.add(timer);
              if (!intercepted) {
                intercepted = true;
                if (closeServer) {
                  unawaited(server.close());
                } else {
                  server.abort('deadline-setup');
                }
              }
              return timer;
            },
          ),
        );
        expect((await response).status, RemoteHelloStatus.failure);
        expect(intercepted, isTrue);
        await _drain();
        expect(factory.calls, 0);
        expect(factory.authenticator.helloCalls, 0);
        expect(server.pendingAuthenticationCounts, isEmpty);
        expect(timers, isNotEmpty);
        expect(timers.every((timer) => !timer.isActive), isTrue);
      },
    );
  }

  test(
    'abort during factory creation rejects late HELLO and cleans up',
    () async {
      final creation = Completer<Authenticator>();
      factory.creation = creation.future;
      final result = server.onHello(hello('factory'));
      await expectCallbackEntry(factory.entered.future, result);
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
    await expectCallbackEntry(
      factory.authenticator.helloEntered.future,
      result,
    );
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
    await expectCallbackEntry(
      factory.authenticator.authenticateEntered.future,
      result,
    );
    await abort('auth');
    pendingAuth.complete(_success());
    expect((await result).status, RemoteAuthenticateStatus.failure);
    await _drain();
    expect(factory.authenticator.abortCalls, 1);
  });

  for (final callbackBusy in [false, true]) {
    test(
      'reentrant cleanup runs once with busy callback $callbackBusy',
      () async {
        final callback = Completer<AuthResult>();
        final cleanup = Completer<void>();
        final cleanupEntered = Completer<void>();
        addTearDown(() async {
          if (!callback.isCompleted) callback.complete(_success());
          if (!cleanup.isCompleted) cleanup.complete();
          await _drain();
        });
        factory.authenticator.cleanup = cleanup.future;
        factory.authenticator.abortHook = () {
          cleanupEntered.complete();
          server.abort('reentrant');
          unawaited(server.close());
        };
        if (callbackBusy) factory.authenticator.hello = callback.future;
        final result = _HelloObservation(server.onHello(hello('reentrant')));
        await expectCallbackEntry(
          factory.authenticator.helloEntered.future,
          result.future,
        );
        if (!callbackBusy) {
          expect((await result.settled()).status, RemoteHelloStatus.challenge);
        }
        await abort('reentrant');
        if (callbackBusy) {
          final failure = (await result.settled()).failure;
          expect(failure?.reason, 'wamp.error.authentication_failed');
          expect(failure?.message, 'Remote authentication aborted');
          expect(factory.authenticator.abortCalls, 0);
          callback.complete(_success());
        }
        await _drain();
        expect(cleanupEntered.isCompleted, isTrue);
        expect(factory.authenticator.abortCalls, 1);
        expect(server.pendingAuthenticationCounts, {'realm1': 1});
        await abort('reentrant');
        await server.close();
        expect(factory.authenticator.abortCalls, 1);
        cleanup.complete();
        await _drain();
        expect(server.pendingAuthenticationCounts, isEmpty);
        expect(factory.authenticator.abortCalls, 1);
        expect(
          (await server.onHello(hello('closed'))).status,
          RemoteHelloStatus.failure,
        );
        expect(factory.calls, 1);
      },
    );
  }

  test('transaction ID cannot be reused until abort cleanup settles', () async {
    final cleanup = Completer<void>();
    factory.authenticator.cleanup = cleanup.future;
    expect(
      (await server.onHello(hello('reused'))).status,
      RemoteHelloStatus.challenge,
    );
    await abort('reused');
    final blocked = await server.onHello(hello('reused'));
    expect(blocked.failure?.reason, 'wamp.error.protocol_violation');
    expect(factory.calls, 1);
    expect(factory.authenticator.abortCalls, 1);
    expect(server.pendingAuthenticationCounts, {'realm1': 1});
    cleanup.complete();
    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
    factory.authenticator.cleanup = null;
    expect(
      (await server.onHello(hello('reused'))).status,
      RemoteHelloStatus.challenge,
    );
    expect(server.pendingAuthenticationCounts, {'realm1': 1});
    expect(
      (await server.onAuthenticate(authenticate('reused'))).status,
      RemoteAuthenticateStatus.success,
    );
    await _drain();
    expect(server.pendingAuthenticationCounts, isEmpty);
    expect(factory.calls, 2);
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
    await expectCallbackEntry(factory.entered.future, first);
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
      addTearDown(() async {
        if (!pendingHello.isCompleted) pendingHello.complete(_success());
        if (!cleanup.isCompleted) cleanup.complete();
        await _drain();
      });
      factory.authenticator.hello = pendingHello.future;
      factory.authenticator.cleanup = cleanup.future;
      final first = _HelloObservation(server.onHello(hello('first')));
      await expectCallbackEntry(
        factory.authenticator.helloEntered.future,
        first.future,
      );
      await abort('first');
      expect(
        (await first.settled()).status,
        RemoteHelloStatus.failure,
      );
      final second = _HelloObservation(server.onHello(hello('second')));
      expect(
        (await second.settled()).status,
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
      await expectCallbackEntry(factory.entered.future, first);
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
    await expectCallbackEntry(
      factory.authenticator.authenticateEntered.future,
      first,
    );
    RemoteAuthenticateResponse? duplicate;
    unawaited(
      server.onAuthenticate(authenticate('same')).then((value) {
        duplicate = value;
      }),
    );
    try {
      await _drain();
      expect(factory.authenticator.authenticateCalls, 1);
      expect(
        duplicate?.status,
        RemoteAuthenticateStatus.failure,
        reason:
            'A duplicate must be rejected while the first provider call is pending',
      );
    } finally {
      pendingAuth.complete(_success());
    }
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
      RemoteHelloResponse? closedResult;
      unawaited(
        result.then((value) {
          closedResult = value;
        }),
      );
      await expectCallbackEntry(factory.entered.future, result);
      await server.close();
      await server.close();
      try {
        await _drain();
        expect(
          closedResult?.status,
          RemoteHelloStatus.failure,
          reason:
              'Close must resolve HELLO without waiting for provider creation',
        );
        expect(
          (await server.onHello(hello('new'))).status,
          RemoteHelloStatus.failure,
        );
      } finally {
        creation.complete(factory.authenticator);
      }
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
      addTearDown(() async {
        if (!pendingHello.isCompleted) {
          pendingHello.completeError(StateError('credential material'));
        }
        await _drain();
      });
      factory.authenticator.hello = pendingHello.future;
      final result = _HelloObservation(server.onHello(hello('late-error')));
      await expectCallbackEntry(
        factory.authenticator.helloEntered.future,
        result.future,
      );
      await abort('late-error');
      expect((await result.settled()).status, RemoteHelloStatus.failure);
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
      await expectCallbackEntry(
        factory.authenticator.helloEntered.future,
        response,
      );
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
      await expectCallbackEntry(
        factory.authenticator.helloEntered.future,
        result,
      );
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

class _HelloObservation {
  _HelloObservation(this.future) {
    // Keep asynchronous errors visible to the test runner, including timeouts.
    unawaited(future.then((value) => _response = value));
  }

  final Future<RemoteHelloResponse> future;
  RemoteHelloResponse? _response;

  Future<RemoteHelloResponse> settled() async {
    await _drain();
    expect(
      _response,
      isNotNull,
      reason: 'HELLO must settle without releasing the held provider callback',
    );
    return _response!;
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
  void Function()? abortHook;
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
    abortHook?.call();
    if (cleanupError) throw StateError('private cleanup detail');
    await cleanup;
  }
}
