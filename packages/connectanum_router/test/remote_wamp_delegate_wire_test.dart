@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart'
    show AbstractAuthentication;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/src/router/auth/remote_wamp_delegate.dart';
import 'package:test/test.dart';

void main() {
  tearDown(RemoteWampDelegateRegistry.clear);
  tearDown(RemoteAuthenticator.resetRateLimiter);

  test(
    'old fingerprint completion reuses a completed rotated session',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final temp = Directory.systemTemp.createTempSync('remote-fingerprint-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final secret = File('${temp.path}/secret')
        ..writeAsStringSync('first-secret');
      final config = _FingerprintGate(
        RemoteWampDelegateConfig.parse({
          'rpc': {
            'connect_timeout_ms': 1000,
            'call_timeout_ms': 1000,
            'transport': service.transportConfig,
            'service_auth_method': 'ticket',
            'service_auth_secret_file': secret.path,
          },
        }, _realm),
      );
      final delegate = WampRemoteAuthenticatorDelegate(config);
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      final entered = Completer<void>();
      final release = Completer<void>();
      config.holdNextFingerprint = () async {
        entered.complete();
        await release.future;
      };
      final delayed = delegate.onHello(_hello(id: 'delayed'));
      try {
        await Future.any([
          entered.future,
          delayed,
        ]).timeout(const Duration(seconds: 3));
        expect(entered.isCompleted, isTrue);
        secret.writeAsStringSync('second-secret');
        expect(
          _helloSuccess(await delegate.onHello(_hello(id: 'rotated'))).authId,
          'alice',
        );
        expect(service.callConnections, [0, 1]);
        release.complete();
        expect(_helloSuccess(await delayed).authId, 'alice');
        expect(service.callConnections, [0, 1, 1]);
        expect(service.hellos, hasLength(2));
      } finally {
        if (!release.isCompleted) release.complete();
        await delayed;
      }
    },
  );

  test(
    'reset during connection preparation opens no stale service socket',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final delegate = service.delegate();
      final first = delegate.warmUpSession();
      RemoteWampDelegateRegistry.clear();
      await first;
      expect(service.hellos, isEmpty);
      expect(service.calls, isEmpty);
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      expect(service.hellos, hasLength(1));
      expect(service.callConnections, [0]);
    },
  );

  for (final operation in ['warmup', 'hello', 'authenticate', 'abort']) {
    for (final reply in ['welcome', 'abort']) {
      test(
        'retired $operation $reply cannot replace or close the current session',
        () async {
          final service = await _Service.start();
          addTearDown(service.close);
          final firstHello = Completer<void>();
          void Function()? releaseOld;
          service.rejectHello = reply == 'abort';
          service.scheduleWelcome = (send) {
            if (service.hellos.length == 1) {
              releaseOld = send;
              firstHello.complete();
            } else {
              send();
            }
          };
          final delegate = service.delegate();
          final first = switch (operation) {
            'warmup' => delegate.warmUpSession(),
            'abort' => delegate.onAbort(_abort()),
            'hello' => expectLater(
              delegate.onHello(_hello()),
              throwsA(isA<RemoteDelegateUnavailableException>()),
            ),
            _ => expectLater(
              delegate.onAuthenticate(_authenticate()),
              throwsA(isA<RemoteDelegateUnavailableException>()),
            ),
          };
          try {
            await Future.any<void>([
              firstHello.future,
              first,
            ]).timeout(const Duration(seconds: 3));
            expect(service.hellos, hasLength(1));
            RemoteWampDelegateRegistry.clear();
            service.rejectHello = false;
            await delegate.warmUpSession();
            expect(service.hellos, hasLength(2));
            expect(
              _helloSuccess(await delegate.onHello(_hello())).authId,
              'alice',
            );
            expect(service.callConnections, [1]);
            releaseOld!();
            releaseOld = null;
            await first;
            expect(
              _helloSuccess(await delegate.onHello(_hello())).authId,
              'alice',
            );
            expect(service.callConnections, [1, 1]);
            expect(service.hellos, hasLength(2));
            await service.sockets.first.done.timeout(
              const Duration(seconds: 3),
            );
          } finally {
            releaseOld?.call();
            await first;
          }
        },
      );
    }
  }

  test(
    'concurrent credential rotation shares one replacement session',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final temp = Directory.systemTemp.createTempSync('remote-wire-rotation-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final secret = File('${temp.path}/secret')
        ..writeAsStringSync('first-secret');
      final delegate = service.delegate(
        rpc: {
          'service_auth_method': 'ticket',
          'service_auth_secret_file': secret.path,
        },
      );
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      secret.writeAsStringSync('second-secret');
      final replies = await Future.wait([
        for (var i = 0; i < 8; i++) delegate.onHello(_hello(id: 'rotated-$i')),
      ]);
      expect(
        replies.map((reply) => _helloSuccess(reply).authId),
        everyElement('alice'),
      );
      expect(service.hellos, hasLength(2));
      expect(service.callConnections, [0, ...List<int>.filled(8, 1)]);
    },
  );

  // All branch payloads are well-formed so a wrong discriminator is observed
  // as the wrong authentication result, not an incidental missing-field error.
  for (final status in ['success', 'challenge', 'failure', 'invalid', null]) {
    test(
      'HELLO discriminates $status before considering other payload fields',
      () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.respond = (call) => _result(call, {
          'status': ?status,
          'authId': 'alice',
          'authRole': 'member',
          'auth_id': 'wrong-alias',
          'auth_role': 'wrong-role',
          'challenge': {'nonce': 'fixture'},
          'reason': 'fixture.denied',
          'message': 'denied',
        });
        final response = await service.delegate().onHello(_hello());
        final expected = switch (status) {
          'success' => RemoteHelloStatus.success,
          'challenge' || null => RemoteHelloStatus.challenge,
          _ => RemoteHelloStatus.failure,
        };
        expect(response.status, expected);
        expect(
          response.success,
          expected == RemoteHelloStatus.success ? isNotNull : isNull,
        );
        expect(
          response.challenge,
          expected == RemoteHelloStatus.challenge ? isNotNull : isNull,
        );
        expect(
          response.failure,
          expected == RemoteHelloStatus.failure ? isNotNull : isNull,
        );
        if (expected == RemoteHelloStatus.success) {
          expect(response.success!.authId, 'alice');
          expect(response.success!.authRole, 'member');
        } else if (expected == RemoteHelloStatus.challenge) {
          expect(response.challenge!.authId, 'alice');
          expect(response.challenge!.challenge, {'nonce': 'fixture'});
        } else {
          expect(
            response.failure!.reason,
            status == 'failure'
                ? 'fixture.denied'
                : 'wamp.error.not_authorized',
          );
        }
      },
    );
  }
  for (final status in ['success', 'failure', 'invalid', null]) {
    test(
      'AUTHENTICATE discriminates $status before considering identity fields',
      () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.respond = (call) => _result(call, {
          'status': ?status,
          'authId': 'alice',
          'authRole': 'member',
          'auth_id': 'wrong-alias',
          'auth_role': 'wrong-role',
          'reason': 'fixture.denied',
        });
        final response = await service.delegate().onAuthenticate(
          _authenticate(),
        );
        final success = status == 'success' || status == null;
        expect(
          response.status,
          success
              ? RemoteAuthenticateStatus.success
              : RemoteAuthenticateStatus.failure,
        );
        expect(response.success, success ? isNotNull : isNull);
        expect(response.failure, success ? isNull : isNotNull);
        if (success) {
          expect(response.success!.authId, 'alice');
          expect(response.success!.authRole, 'member');
        } else {
          expect(
            response.failure!.reason,
            status == 'failure'
                ? 'fixture.denied'
                : 'wamp.error.not_authorized',
          );
        }
      },
    );
  }

  test(
    'warmup recovers after repairing a malformed service key file',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final temp = Directory.systemTemp.createTempSync('remote-wire-key-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final key = File('${temp.path}/key')..writeAsStringSync('not-base64!');
      final delegate = service.delegate(
        rpc: {
          'service_auth_method': 'cryptosign',
          'service_private_key_file': key.path,
        },
      );
      await delegate.warmUpSession();
      expect(service.hellos, isEmpty);
      key.writeAsStringSync(base64Encode(List<int>.filled(32, 7)));
      await delegate.warmUpSession();
      expect(service.hellos, hasLength(1));
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      expect(service.hellos, hasLength(1));
    },
  );

  test(
    'an old failed warmup cannot clear a newer pending connection',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final firstHello = Completer<void>();
      final secondHello = Completer<void>();
      final releases = <void Function()>[];
      final warming = <Future<void>>[];
      service.rejectHello = true;
      service.scheduleWelcome = (send) {
        if (service.hellos.length == 1) {
          releases.add(send);
          firstHello.complete();
        } else if (service.hellos.length == 2) {
          releases.add(send);
          secondHello.complete();
        } else {
          send();
        }
      };
      final delegate = service.delegate();
      final first = delegate.warmUpSession();
      warming.add(first);
      try {
        await Future.any<void>([
          firstHello.future,
          first,
        ]).timeout(const Duration(seconds: 3));
        expect(service.hellos, hasLength(1));
        RemoteWampDelegateRegistry.clear();
        service.rejectHello = false;
        final second = delegate.warmUpSession();
        warming.add(second);
        await Future.any<void>([
          secondHello.future,
          second,
        ]).timeout(const Duration(seconds: 3));
        expect(service.hellos, hasLength(2));
        releases.removeAt(0)();
        await first;
        warming.add(delegate.warmUpSession());
        releases.removeAt(0)();
        await Future.wait(warming);
        expect(service.hellos, hasLength(2));
        expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
        expect(service.hellos, hasLength(2));
      } finally {
        for (final release in releases) {
          release();
        }
        await Future.wait(warming);
      }
    },
  );

  for (final phase in ['hello', 'authenticate']) {
    for (final variant in [
      'result-minimal',
      'result-invalid-arguments',
      'result-detailed',
      'error-empty',
      'error-invalid-details',
      'error-positional',
    ]) {
      test('authenticator preserves $phase denial from $variant', () async {
        final service = await _Service.start();
        addTearDown(service.close);
        final detailed = variant == 'result-detailed';
        final resultPayload = <String, Object?>{
          'status': 'failure',
          'reason': 'fixture.denied',
          'authId': 'must-not-authorize',
          'authRole': 'admin',
          if (variant != 'result-minimal') 'message': 'Denied',
          if (variant == 'result-invalid-arguments')
            'arguments': {'ignored': true},
          if (detailed) ...{
            'details': {'retry': false},
            'arguments': ['diagnostic', 17],
            'argumentsKeywords': {'trace': 'public-fixture'},
          },
        };
        final errorArguments = <Object?>[
          if (variant == 'error-positional') 'positional reason',
        ];
        final errorKeywords = <String, Object?>{
          if (variant == 'error-invalid-details') ...{
            'message': 'Denied',
            'details': 'not-a-map',
          },
          if (variant == 'error-positional') 'details': {'retry': false},
        };
        service.respond = (call) {
          if (phase == 'authenticate' && service.calls.length == 1) {
            return _result(call, {
              'status': 'challenge',
              'authId': 'alice',
              'challenge': {'nonce': 'fixture'},
            });
          }
          return variant.startsWith('result')
              ? _result(call, resultPayload)
              : [
                  8,
                  48,
                  call[1],
                  {},
                  'fixture.denied',
                  errorArguments,
                  errorKeywords,
                ];
        };
        final rpc = <String, Object?>{
          'transport': service.transportConfig,
          'connect_timeout_ms': 1000,
          'call_timeout_ms': 1000,
          'hello_procedure': 'fixture.hello',
          'authenticate_procedure': 'fixture.authenticate',
        };
        service.delegate(rpc: rpc);
        final authenticator = await const RemoteAuthenticatorFactory().create(
          _realm,
          {
            'fake_challenge_on_hello_failure': false,
            'rpc': rpc,
          },
        );
        final context = _context(details: {'authid': 'alice'});
        var result = await authenticator.onHello(context);
        if (phase == 'authenticate') {
          expect(result.status, AuthStatus.challenge);
          expect(result.challenge!.challenge, {'nonce': 'fixture'});
          result = await authenticator.onAuthenticate(
            context,
            AuthenticateMessage(signature: 'proof'),
          );
        }
        expect(result.status, AuthStatus.failure);
        expect(result.success, isNull);
        expect(result.challenge, isNull);
        expect(result.failure, isNotNull);
        final failure = result.failure!;
        expect(failure.reason, 'fixture.denied');
        expect(failure.message, switch (variant) {
          'result-minimal' || 'error-empty' => null,
          'error-positional' => 'positional reason',
          _ => 'Denied',
        });
        expect(
          failure.details,
          detailed || variant == 'error-positional' ? {'retry': false} : {},
        );
        expect(
          failure.arguments,
          variant.startsWith('error')
              ? errorArguments
              : detailed
              ? ['diagnostic', 17]
              : null,
        );
        expect(
          failure.argumentsKeywords,
          variant.startsWith('error')
              ? errorKeywords
              : detailed
              ? {'trace': 'public-fixture'}
              : null,
        );
        expect(service.hellos, hasLength(1));
        expect(service.calls.map((call) => call[3]), [
          'fixture.hello',
          if (phase == 'authenticate') 'fixture.authenticate',
        ]);
      });
    }
  }

  for (final operation in ['hello', 'authenticate']) {
    test(
      '$operation legacy camel fields take precedence over snake aliases',
      () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.respond = (call) => _result(call, {
          'authId': 'camel',
          'auth_id': 'snake',
          'authRole': 'member',
          'auth_role': 'wrong-role',
        });
        final delegate = service.delegate();
        final success = operation == 'hello'
            ? (await delegate.onHello(_hello())).success
            : (await delegate.onAuthenticate(_authenticate())).success;
        expect(success, isNotNull);
        expect(success!.authId, 'camel');
        expect(success.authRole, 'member');
      },
    );
  }

  test('legacy challenge prefers camel identity over snake alias', () async {
    final service = await _Service.start();
    addTearDown(service.close);
    service.respond = (call) => _result(call, {
      'authId': 'camel',
      'auth_id': 'snake',
      'challenge': {'nonce': 'fixture'},
    });
    final response = await service.delegate().onHello(_hello());
    expect(response.status, RemoteHelloStatus.challenge);
    expect(response.challenge, isNotNull);
    expect(response.success, isNull);
    expect(response.failure, isNull);
    expect(response.challenge!.authId, 'camel');
  });

  test(
    'registry warmup settles started connections before a later configuration error',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final receivedHello = Completer<void>();
      void Function()? releaseWelcome;
      service.scheduleWelcome = (send) {
        releaseWelcome = send;
        receivedHello.complete();
      };
      final builder = RouterSettingsBuilder();
      for (final valid in [true, false]) {
        final name = valid ? 'valid' : 'invalid';
        builder.addAuthenticator(
          name,
          AuthenticatorDefinition(
            type: 'remote',
            options: {
              'rpc': {
                'transport': valid
                    ? service.transportConfig
                    : <String, Object?>{},
                'connect_timeout_ms': 3000,
              },
            },
          ),
        );
        builder.addRealmFromBuilder(
          RealmSettingsBuilder(name)..addAuthMethod(
            'ticket',
            options: {
              'authenticator': name,
            },
          ),
        );
      }
      var finished = false;
      Object? failure;
      final warmup =
          RemoteWampDelegateRegistry.warmUpForSettings(
            builder.build(),
          ).then<void>(
            (_) {
              finished = true;
            },
            onError: (Object error, StackTrace stackTrace) {
              if (error is TimeoutException) {
                Error.throwWithStackTrace(error, stackTrace);
              }
              failure = error;
              finished = true;
            },
          );
      try {
        // Early configuration failure must not leave us waiting for no HELLO.
        await Future.any<void>([
          receivedHello.future,
          warmup,
        ]).timeout(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        expect(service.hellos, hasLength(1));
      } finally {
        releaseWelcome?.call();
        await warmup;
      }
      expect(finished, isTrue);
      expect(failure, isA<ArgumentError>());
    },
  );

  test('registry warmup reuses the configured service session', () async {
    final service = await _Service.start();
    addTearDown(service.close);
    final settings = RouterSettingsBuilder()
        .addAuthenticator(
          'fixture',
          AuthenticatorDefinition(
            type: 'remote',
            options: {
              'rpc': {
                'transport': service.transportConfig,
                'call_timeout_ms': 1000,
                'connect_timeout_ms': 1000,
              },
            },
          ),
        )
        .addRealmFromBuilder(
          RealmSettingsBuilder('consumer.realm')
            ..addAuthMethod('ticket', options: {'authenticator': 'fixture'}),
        )
        .build();
    // Use the same bounded credential source for warmup and subsequent calls.
    service.delegate();
    await RemoteWampDelegateRegistry.warmUpForSettings(settings);
    expect(service.hellos, hasLength(1));
    expect(service.calls, isEmpty);
    expect(
      _helloSuccess(await service.delegate().onHello(_hello())).authRole,
      'member',
    );
    expect(service.hellos, hasLength(1));
  });

  for (final transport in ['rawsocket', 'websocket']) {
    test(
      'rejects unsupported $transport serializer before opening a socket',
      () async {
        final service = await _Service.start(
          rawSocket: transport == 'rawsocket',
        );
        addTearDown(service.close);
        final delegate = service.delegate(
          rpc: {
            'transport': {...service.transportConfig, 'serializer': 'invalid'},
          },
        );
        await expectLater(delegate.onHello(_hello()), throwsArgumentError);
        expect(service.hellos, isEmpty);
        expect(service.senders, isEmpty);
      },
    );
  }

  test(
    'rotated colliding service secrets reconnect without invalidating the replacement',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final temp = Directory.systemTemp.createTempSync('remote-wire-secret-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final secret = File('${temp.path}/secret')
        ..writeAsStringSync('remote-fixture-jobs5j');
      final delegate = service.delegate(
        rpc: {
          'service_auth_method': 'ticket',
          'service_auth_secret_file': secret.path,
        },
      );
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      secret.writeAsStringSync('remote-fixture-16bqabh');
      expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
      expect(
        _authenticateSuccess(
          await delegate.onAuthenticate(_authenticate()),
        ).authRole,
        'member',
      );
      expect(service.hellos, hasLength(2));
    },
  );

  for (final rawSocket in [false, true]) {
    for (final serializer in ['json', 'msgpack', 'cbor']) {
      test(
        'remote RPC round trip rawSocket=$rawSocket serializer=$serializer',
        () async {
          final service = await _Service.start(
            rawSocket: rawSocket,
            serializer: serializer,
          );
          addTearDown(service.close);
          final delegate = service.delegate();
          expect(
            _helloSuccess(await delegate.onHello(_hello())).authId,
            'alice',
          );
          expect(
            _authenticateSuccess(
              await delegate.onAuthenticate(_authenticate()),
            ).authRole,
            'member',
          );
          expect(service.hellos, hasLength(1));
          expect(service.calls, hasLength(2));
          expect(service.calls[0][5], {
            'transactionId': 'transaction',
            'hello': {
              'realm': 'consumer.realm',
              'sessionId': 71,
              'details': {},
              'transport': {'connectionId': 91, 'isEncrypted': false},
            },
          });
          expect(service.calls[1][5], {
            'transactionId': 'transaction',
            'authenticate': {'signature': 'proof'},
          });
        },
      );
    }
  }

  test(
    'concurrent calls share connection and correlate out-of-order replies',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final received = Completer<void>();
      service.respond = (call) {
        if (service.calls.length == 2) received.complete();
        return null;
      };
      final delegate = service.delegate();
      final first = delegate.onHello(_hello(id: 'first'));
      final second = delegate.onAuthenticate(_authenticate(id: 'second'));
      final replies = Future.wait<Object>([first, second]);
      addTearDown(() => replies);
      addTearDown(RemoteWampDelegateRegistry.clear);
      await Future.any([
        received.future,
        replies,
      ]).timeout(const Duration(seconds: 3));
      expect(service.calls, hasLength(2));
      expect(service.senders, hasLength(1));
      for (final call in service.calls.reversed) {
        service.senders.single(
          _result(call, {
            'status': 'success',
            'authId': (call[5] as Map)['transactionId'],
            'authRole': 'member',
          }),
        );
      }
      expect(_helloSuccess(await first).authId, 'first');
      expect(_authenticateSuccess(await second).authId, 'second');
      expect(service.hellos, hasLength(1));
    },
  );

  for (final operation in ['hello', 'authenticate', 'abort']) {
    test(
      '$operation timeout releases failed session and permits retry',
      () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.respond = (_) => null;
        final delegate = service.delegate(rpc: {'call_timeout_ms': 30});
        if (operation == 'abort') {
          await delegate.onAbort(_abort());
        } else {
          await expectLater(
            operation == 'hello'
                ? delegate.onHello(_hello())
                : delegate.onAuthenticate(_authenticate()),
            throwsA(
              isA<RemoteDelegateUnavailableException>().having(
                (error) => error.message,
                'message',
                contains('$operation call timed out'),
              ),
            ),
          );
        }
        service.respond = (call) => _result(call, {
          'status': 'success',
          'authId': 'after-timeout',
          'authRole': 'member',
        });
        expect(
          _helloSuccess(await delegate.onHello(_hello())).authId,
          'after-timeout',
        );
        expect(service.hellos, hasLength(2));
        if (operation == 'abort') {
          expect(service.calls.first[5], {'transactionId': 'transaction'});
        }
      },
    );

    test(
      '$operation handles handshake ABORT without caching rejection',
      () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.rejectHello = true;
        final delegate = service.delegate();
        await delegate.warmUpSession();
        if (operation == 'abort') {
          await delegate.onAbort(_abort());
        } else {
          await expectLater(
            operation == 'hello'
                ? delegate.onHello(_hello())
                : delegate.onAuthenticate(_authenticate()),
            throwsA(isA<RemoteDelegateUnavailableException>()),
          );
        }
        service.rejectHello = false;
        expect(_helloSuccess(await delegate.onHello(_hello())).authId, 'alice');
        expect(service.calls, hasLength(1));
      },
    );
  }

  for (final status in <Object?>['denied', '', null, true, 7, [], {}]) {
    for (final operation in ['hello', 'authenticate']) {
      for (final shape in ['challenge', 'camel', 'snake']) {
        test(
          '$operation rejects explicit invalid status ${jsonEncode(status)} with $shape fields',
          () async {
            final service = await _Service.start();
            addTearDown(service.close);
            service.respond = (call) => _result(call, {
              'status': status,
              shape == 'snake' ? 'auth_id' : 'authId': 'alice',
              shape == 'snake' ? 'auth_role' : 'authRole': 'member',
              if (shape == 'challenge') 'challenge': {'nonce': 'untrusted'},
            });
            final delegate = service.delegate();
            if (operation == 'hello') {
              final response = await delegate.onHello(_hello());
              expect(response.status, RemoteHelloStatus.failure);
              expect(response.success, isNull);
              expect(response.challenge, isNull);
              expect(response.failure!.reason, 'wamp.error.not_authorized');
            } else {
              final response = await delegate.onAuthenticate(_authenticate());
              expect(response.status, RemoteAuthenticateStatus.failure);
              expect(response.success, isNull);
              expect(response.failure!.reason, 'wamp.error.not_authorized');
            }
          },
        );
      }
    }
  }

  for (final operation in ['hello', 'authenticate']) {
    for (final legacy in [false, true]) {
      for (final positional in [false, true]) {
        test(
          '$operation decodes success legacy=$legacy positional=$positional',
          () async {
            final service = await _Service.start();
            addTearDown(service.close);
            final payload = <String, Object?>{
              if (!legacy) 'status': 'success',
              legacy ? 'auth_id' : 'authId': 'alice',
              legacy ? 'auth_role' : 'authRole': 'member',
              'details': {
                'authprovider': 'fixture',
                'nested': [1, true],
              },
            };
            service.respond = (call) => positional
                ? [
                    50,
                    call[1],
                    <String, Object?>{},
                    [payload],
                  ]
                : _result(call, payload);
            final delegate = service.delegate();
            final success = operation == 'hello'
                ? (await delegate.onHello(_hello())).success
                : (await delegate.onAuthenticate(_authenticate())).success;
            expect(success, isNotNull);
            expect(success!.authId, 'alice');
            expect(success.authRole, 'member');
            expect(success.details, payload['details']);
            expect(service.calls.single[3], 'authenticate.$operation');
          },
        );
      }
    }

    for (final payload in <Map<String, Object?>>[
      {},
      {'status': 'challenge', 'authId': 'alice', 'authRole': 'member'},
    ]) {
      if (operation == 'hello' && payload.isNotEmpty) continue;
      test('$operation rejects malformed response $payload', () async {
        final service = await _Service.start();
        addTearDown(service.close);
        service.respond = (call) => _result(call, payload);
        final delegate = service.delegate();
        final failure = operation == 'hello'
            ? (await delegate.onHello(_hello())).failure
            : (await delegate.onAuthenticate(_authenticate())).failure;
        expect(failure, isNotNull);
        expect(failure!.reason, 'wamp.error.not_authorized');
        expect(failure.message, 'Malformed remote $operation response');
      });
    }

    for (final payload in <Map<String, Object?>>[
      {'status': 'success', 'authId': 'alice'},
      {'status': 'success', 'authRole': 'member'},
      {'auth_role': 'member', 'auth_id': ''},
      if (operation == 'hello') {'status': 'challenge', 'authId': 'alice'},
    ]) {
      test(
        '$operation fails closed on missing required fields $payload',
        () async {
          final service = await _Service.start();
          addTearDown(service.close);
          service.respond = (call) => _result(call, payload);
          final delegate = service.delegate();
          await expectLater(
            operation == 'hello'
                ? delegate.onHello(_hello())
                : delegate.onAuthenticate(_authenticate()),
            throwsA(isA<RemoteDelegateUnavailableException>()),
          );
          service.respond = (call) => _result(call, {
            'status': 'success',
            'authId': 'retry',
            'authRole': 'member',
          });
          final success = operation == 'hello'
              ? (await delegate.onHello(_hello())).success
              : (await delegate.onAuthenticate(_authenticate())).success;
          expect(success, isNotNull);
          expect(success!.authId, 'retry');
        },
      );
    }

    for (final detailed in [false, true]) {
      test(
        '$operation preserves explicit failure detailed=$detailed',
        () async {
          final service = await _Service.start();
          addTearDown(service.close);
          service.respond = (call) => _result(call, {
            'status': 'failure',
            'authId': 'must-not-authorize',
            'authRole': 'admin',
            if (detailed) ...{
              'reason': 'fixture.denied',
              'message': 'Denied',
              'details': {'retry': false},
              'arguments': ['diagnostic', 17],
              'argumentsKeywords': {'trace': 'public-fixture'},
            },
          });
          final delegate = service.delegate();
          final failure = operation == 'hello'
              ? (await delegate.onHello(_hello())).failure
              : (await delegate.onAuthenticate(_authenticate())).failure;
          expect(failure, isNotNull);
          expect(
            failure!.reason,
            detailed ? 'fixture.denied' : 'wamp.error.not_authorized',
          );
          expect(failure.message, detailed ? 'Denied' : null);
          expect(failure.details, detailed ? {'retry': false} : {});
          expect(failure.arguments, detailed ? ['diagnostic', 17] : null);
          expect(
            failure.argumentsKeywords,
            detailed ? {'trace': 'public-fixture'} : null,
          );
        },
      );
    }

    for (final source in ['keywords', 'arguments', 'absent']) {
      test('$operation maps WAMP call errors from $source', () async {
        final service = await _Service.start();
        addTearDown(service.close);
        final args = source == 'absent' ? <Object?>[] : ['fallback'];
        final kwargs = <String, Object?>{
          if (source == 'keywords') 'message': 'authoritative',
          if (source != 'absent') 'details': {'retry': false},
        };
        service.respond = (call) => [
          8,
          48,
          call[1],
          {},
          'fixture.denied',
          args,
          kwargs,
        ];
        final delegate = service.delegate();
        final failure = operation == 'hello'
            ? (await delegate.onHello(_hello())).failure
            : (await delegate.onAuthenticate(_authenticate())).failure;
        expect(failure, isNotNull);
        expect(failure!.reason, 'fixture.denied');
        expect(failure.message, switch (source) {
          'keywords' => 'authoritative',
          'arguments' => 'fallback',
          _ => null,
        });
        expect(failure.details, source == 'absent' ? {} : {'retry': false});
        expect(failure.arguments, args);
        expect(failure.argumentsKeywords, kwargs);
      });
    }
  }

  for (final legacy in [false, true]) {
    test('hello challenge preserves fields legacy=$legacy', () async {
      final service = await _Service.start();
      addTearDown(service.close);
      service.respond = (call) => _result(call, {
        if (!legacy) 'status': 'challenge',
        legacy ? 'auth_id' : 'authId': 'alice',
        'challenge': {'nonce': 'nonce', 'salt': 'salt'},
        'extra': {'provider': 'fixture'},
      });
      final response = await service.delegate().onHello(_hello());
      expect(response.status, RemoteHelloStatus.challenge);
      expect(response.success, isNull);
      expect(response.challenge!.authId, 'alice');
      expect(response.challenge!.challenge, {'nonce': 'nonce', 'salt': 'salt'});
      expect(response.challenge!.extra, {'provider': 'fixture'});
    });
  }

  test(
    'forwards minimal HELLO, proof and abort payloads on one session',
    () async {
      final service = await _Service.start();
      addTearDown(service.close);
      final delegate = service.delegate(
        rpc: {
          'realm': 'service.realm',
          'service_auth_id': 'edge',
          'service_auth_role': 'service',
          'service_auth_extra': {'node': 'one'},
          'auth_token': 'shared-token',
          'hello_procedure': 'custom.hello',
          'authenticate_procedure': 'custom.authenticate',
          'abort_procedure': 'custom.abort',
        },
      );
      final context = AuthenticatorContext(
        realm: _realm,
        sessionId: 71,
        transport: const TransportMetadata(
          connectionId: 91,
          peerAddress: '127.0.0.1',
          isEncrypted: true,
        ),
        helloDetails: {
          'authid': 'alice',
          'authmethods': ['ticket', '', 17, 'wamp-scram'],
          'authextra': {'nonce': 'nonce'},
          'unrelated': 'not-forwarded',
        },
      );
      await delegate.onHello(
        RemoteHelloRequest(
          realmSettings: _realm,
          context: context,
          options: const {},
          transactionId: 'one',
        ),
      );
      await delegate.onAuthenticate(
        RemoteAuthenticateRequest(
          realmSettings: _realm,
          context: context,
          authId: 'alice',
          options: const {},
          transactionId: 'one',
          authenticate: AuthenticateMessage(
            signature: 'proof',
            extra: {'channel': 'binding'},
          ),
        ),
      );
      await delegate.onAbort(
        RemoteAbortRequest(
          realmSettings: _realm,
          context: context,
          authId: 'alice',
          options: const {},
          transactionId: 'one',
          reason: 'consumer.closed',
        ),
      );
      expect(service.hellos, hasLength(1));
      expect(service.hellos.single[1], 'service.realm');
      expect(service.hellos.single[2], containsPair('authid', 'edge'));
      expect(service.hellos.single[2], containsPair('authrole', 'service'));
      expect(
        service.hellos.single[2],
        containsPair('authextra', {'node': 'one'}),
      );
      expect(service.calls.map((c) => c[3]), [
        'custom.hello',
        'custom.authenticate',
        'custom.abort',
      ]);
      expect(service.calls[0][5], {
        'transactionId': 'one',
        'auth_token': 'shared-token',
        'hello': {
          'realm': 'consumer.realm',
          'sessionId': 71,
          'details': {
            'authid': 'alice',
            'authmethods': ['ticket', 'wamp-scram'],
            'authextra': {'nonce': 'nonce'},
          },
          'transport': {
            'connectionId': 91,
            'peerAddress': '127.0.0.1',
            'isEncrypted': true,
          },
        },
      });
      expect(service.calls[1][5], {
        'transactionId': 'one',
        'auth_token': 'shared-token',
        'authenticate': {
          'signature': 'proof',
          'extra': {'channel': 'binding'},
        },
      });
      expect(service.calls[2][5], {
        'transactionId': 'one',
        'auth_token': 'shared-token',
        'reason': 'consumer.closed',
      });
    },
  );
}

AuthSuccess _helloSuccess(RemoteHelloResponse response) {
  expect(response.status, RemoteHelloStatus.success);
  expect(response.success, isNotNull);
  expect(response.challenge, isNull);
  expect(response.failure, isNull);
  return response.success!;
}

AuthSuccess _authenticateSuccess(RemoteAuthenticateResponse response) {
  expect(response.status, RemoteAuthenticateStatus.success);
  expect(response.success, isNotNull);
  expect(response.failure, isNull);
  return response.success!;
}

final _realm = RealmSettingsBuilder('consumer.realm').build();

AuthenticatorContext _context({Map<String, Object?> details = const {}}) =>
    AuthenticatorContext(
      realm: _realm,
      sessionId: 71,
      transport: const TransportMetadata(connectionId: 91),
      helloDetails: details,
    );

RemoteHelloRequest _hello({String id = 'transaction'}) => RemoteHelloRequest(
  realmSettings: _realm,
  context: _context(),
  options: const {},
  transactionId: id,
);

RemoteAuthenticateRequest _authenticate({String id = 'transaction'}) =>
    RemoteAuthenticateRequest(
      realmSettings: _realm,
      context: _context(),
      authId: 'alice',
      authenticate: AuthenticateMessage(signature: 'proof'),
      options: const {},
      transactionId: id,
    );

RemoteAbortRequest _abort() => RemoteAbortRequest(
  realmSettings: _realm,
  context: _context(),
  authId: 'alice',
  options: const {},
  transactionId: 'transaction',
);

List<Object?> _result(List<dynamic> call, Map<String, Object?> payload) => [
  50,
  call[1],
  <String, Object?>{},
  <Object?>[],
  payload,
];

// Delay real credential I/O without mocking its fingerprint or authentication.
class _FingerprintGate implements RemoteWampDelegateConfig {
  _FingerprintGate(this.inner) {
    addTearDown(() {
      expect(
        fingerprintReads,
        lessThanOrEqualTo(_readBudget),
        reason:
            'Session lookup must converge instead of rereading credentials '
            'indefinitely without another rotation',
      );
    });
  }

  final RemoteWampDelegateConfig inner;
  Future<void> Function()? holdNextFingerprint;
  int fingerprintReads = 0;
  // Fixture safety ceiling, not a production limit. Even the concurrent case
  // performs fewer than 16 reads; bounded I/O lets its assertion finish.
  static const _readBudget = 32;

  @override
  Future<String> connectionFingerprint() async {
    if (++fingerprintReads > _readBudget) {
      throw StateError('Credential fixture read budget exhausted');
    }
    final hold = holdNextFingerprint;
    holdNextFingerprint = null;
    final fingerprint = await inner.connectionFingerprint();
    await hold?.call();
    return fingerprint;
  }

  @override
  String get realm => inner.realm;
  @override
  RemoteWampTransportConfig get transport => inner.transport;
  @override
  String get helloProcedure => inner.helloProcedure;
  @override
  String get authenticateProcedure => inner.authenticateProcedure;
  @override
  String get abortProcedure => inner.abortProcedure;
  @override
  Duration get callTimeout => inner.callTimeout;
  @override
  Duration get connectTimeout => inner.connectTimeout;
  @override
  String? get authId => inner.authId;
  @override
  String? get authRole => inner.authRole;
  @override
  Map<String, dynamic>? get authExtra => inner.authExtra;
  @override
  String cacheKey() => inner.cacheKey();
  @override
  Future<List<AbstractAuthentication>> buildAuthenticationMethods() =>
      inner.buildAuthenticationMethods();
  @override
  Future<String?> resolveAuthToken() => inner.resolveAuthToken();
}

/// A wire-level peer keeps the response oracle independent of the delegate.
class _Service {
  _Service(this.server, this.rawServer, this.serializer);

  final HttpServer? server;
  final ServerSocket? rawServer;
  final String serializer;
  final sockets = <WebSocket>[];
  final rawSockets = <Socket>[];
  final senders = <void Function(List<Object?>)>[];
  final calls = <List<dynamic>>[];
  final callConnections = <int>[];
  final hellos = <List<dynamic>>[];
  bool rejectHello = false;
  void Function(void Function())? scheduleWelcome;
  int get port => server?.port ?? rawServer!.port;
  Map<String, Object?> get transportConfig => {
    'type': rawServer != null ? 'rawsocket' : 'websocket',
    'serializer': serializer,
    if (rawServer != null) ...{
      'host': '127.0.0.1',
      'port': port,
    } else
      'url': 'ws://127.0.0.1:$port/auth',
    'allow_insecure_transport': true,
  };
  late final core.AbstractSerializer codec = switch (serializer) {
    'msgpack' => msgpack.Serializer(),
    'cbor' => cbor.Serializer(),
    _ => json.Serializer(),
  };
  final jsonCodec = json.Serializer();
  List<Object?>? Function(List<dynamic>) respond = (call) => _result(call, {
    'status': 'success',
    'authId': 'alice',
    'authRole': 'member',
  });

  static Future<_Service> start({
    bool rawSocket = false,
    String serializer = 'json',
  }) async {
    final service = _Service(
      rawSocket ? null : await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      rawSocket
          ? await ServerSocket.bind(InternetAddress.loopbackIPv4, 0)
          : null,
      serializer,
    );
    service.rawServer?.listen((socket) {
      service.rawSockets.add(socket);
      var handshake = false;
      final pending = <int>[];
      void send(List<Object?> frame) {
        final encoded = service.encode(frame);
        final bytes = encoded is String
            ? utf8.encode(encoded)
            : encoded as Uint8List;
        socket.add([
          0,
          bytes.length >> 16,
          (bytes.length >> 8) & 255,
          bytes.length & 255,
          ...bytes,
        ]);
      }

      service.senders.add(send);
      socket.listen((bytes) {
        pending.addAll(bytes);
        if (!handshake) {
          if (pending.length < 4) return;
          final id = ['json', 'msgpack', 'cbor'].indexOf(serializer) + 1;
          expect(pending[0], 0x7f);
          expect(pending[1] & 15, id);
          socket.add([0x7f, 0xf0 | id, 0, 0]);
          pending.removeRange(0, 4);
          handshake = true;
        }
        while (pending.length >= 4) {
          final length = (pending[1] << 16) | (pending[2] << 8) | pending[3];
          if (pending.length < length + 4) return;
          expect(pending[0], 0);
          final frame = service.decode(
            Uint8List.fromList(pending.sublist(4, 4 + length)),
          );
          pending.removeRange(0, 4 + length);
          service.handle(frame, send);
        }
      });
    });
    service.server?.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) => 'wamp.2.$serializer',
      );
      service.sockets.add(socket);
      void send(List<Object?> frame) => socket.add(service.encode(frame));
      service.senders.add(send);
      socket.listen((data) {
        service.handle(service.decode(data), send);
      });
    });
    return service;
  }

  dynamic encode(List<Object?> frame) => serializer == 'json'
      ? jsonEncode(frame)
      : codec.serialize(jsonCodec.deserializeFromString(jsonEncode(frame))!);

  List<dynamic> decode(dynamic data) {
    if (data is String) return jsonDecode(data) as List<dynamic>;
    final bytes = Uint8List.fromList(data as List<int>);
    return jsonDecode(
          serializer == 'json'
              ? utf8.decode(bytes)
              : jsonCodec.serializeToString(codec.deserialize(bytes)!),
        )
        as List<dynamic>;
  }

  void handle(List<dynamic> frame, void Function(List<Object?>) send) {
    switch (frame[0]) {
      case 1:
        hellos.add(frame);
        final response = rejectHello
            ? [3, {}, 'wamp.error.not_authorized']
            : [
                2,
                hellos.length,
                {
                  'roles': {'dealer': <String, Object?>{}},
                },
              ];
        final schedule = scheduleWelcome;
        if (schedule == null) {
          send(response);
        } else {
          schedule(() => send(response));
        }
      case 48:
        calls.add(frame);
        callConnections.add(senders.indexOf(send));
        final reply = respond(frame);
        if (reply != null) send(reply);
      case 6:
        send([6, <String, Object?>{}, 'wamp.close.goodbye_and_out']);
      default:
        fail('Unexpected remote service frame: ${frame[0]}');
    }
  }

  WampRemoteAuthenticatorDelegate delegate({
    Map<String, Object?> rpc = const {},
  }) {
    return RemoteWampDelegateRegistry.forConfig(
      _FingerprintGate(
        RemoteWampDelegateConfig.parse({
          'rpc': {
            'connect_timeout_ms': 1000,
            'call_timeout_ms': 1000,
            'transport': transportConfig,
            ...rpc,
          },
        }, _realm),
      ),
    );
  }

  Future<void> close() async {
    RemoteWampDelegateRegistry.clear();
    for (final socket in sockets) {
      await socket.close().timeout(const Duration(seconds: 3));
    }
    for (final socket in rawSockets) {
      socket.destroy();
    }
    await server?.close(force: true);
    await rawServer?.close();
  }
}
