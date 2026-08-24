import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/connectanum_core.dart' show Details, Extra;
import 'package:test/test.dart';

void main() {
  const salt = 'W22ZaJ0SNY7soEsUEjb6gQ==';

  Future<({Extra challenge, String clientNonce})> prepare(
    ScramAuthentication authentication, {
    String authId = 'user',
    String challengeSalt = salt,
    String kdf = ScramAuthentication.kdfPbkdf2,
    int iterations = 2,
    int? memory,
  }) async {
    final details = Details.forHello()..authid = authId;
    await authentication.hello('com.realm', details);
    final clientNonce = details.authextra!['nonce']! as String;
    return (
      challenge: Extra(
        salt: challengeSalt,
        kdf: kdf,
        iterations: iterations,
        memory: memory,
        nonce: '${clientNonce}server',
      ),
      clientNonce: clientNonce,
    );
  }

  test(
    'challenge derives asynchronously and verifies the server signature',
    () async {
      final authentication = ScramAuthentication('pencil');
      addTearDown(authentication.dispose);
      final attempt = await prepare(authentication, iterations: 4096);
      final authenticate = await authentication.challenge(attempt.challenge);
      final authMessage = ScramAuthentication.createAuthMessage(
        'user',
        attempt.clientNonce,
        HashMap<String, Object?>.from(authenticate.extra!),
        attempt.challenge,
      );
      final secrets = ScramAuthentication.deriveServerSecrets(
        secret: 'pencil',
        salt: salt,
        iterations: 4096,
      );
      final verifier = ScramAuthentication.createServerSignature(
        serverKey: base64.decode(secrets.serverKey),
        authMessage: authMessage,
      );
      await authentication.verifyFinal(
        authId: 'user',
        authMethod: 'wamp-scram',
        authExtra: <String, Object?>{'verifier': verifier},
      );
      await expectLater(
        authentication.verifyFinal(
          authId: 'user',
          authMethod: 'wamp-scram',
          authExtra: <String, Object?>{'verifier': verifier},
        ),
        throwsStateError,
      );
    },
  );

  test('missing and incorrect server signatures fail closed', () async {
    final cases = <({String authId, String method, String? verifier})>[
      (authId: 'user', method: 'wamp-scram', verifier: null),
      (
        authId: 'user',
        method: 'wamp-scram',
        verifier: base64.encode(List<int>.filled(32, 9)),
      ),
      (authId: 'user', method: 'wamp-scram', verifier: 'not-base64'),
      (
        authId: 'other-user',
        method: 'wamp-scram',
        verifier: base64.encode(List<int>.filled(32, 9)),
      ),
      (
        authId: 'user',
        method: 'wampcra',
        verifier: base64.encode(List<int>.filled(32, 9)),
      ),
    ];
    for (final testCase in cases) {
      final authentication = ScramAuthentication('pencil');
      final attempt = await prepare(authentication);
      await authentication.challenge(attempt.challenge);
      await expectLater(
        authentication.verifyFinal(
          authId: testCase.authId,
          authMethod: testCase.method,
          authExtra: testCase.verifier == null
              ? const <String, Object?>{}
              : <String, Object?>{'verifier': testCase.verifier},
        ),
        throwsStateError,
      );
      await authentication.dispose();
    }
  });

  test('reconnect cancels stale derivation responses', () async {
    final deriver = _ControlledDeriver();
    final authentication = ScramAuthentication('pencil', keyDeriver: deriver);
    final first = await prepare(authentication);
    final firstResult = authentication.challenge(first.challenge);
    await _waitForTasks(deriver, 1);
    final firstExpectation = expectLater(
      firstResult,
      throwsA(isA<ScramKeyDerivationCancelledException>()),
    );

    final second = await prepare(authentication);
    await firstExpectation;
    final secondResult = authentication.challenge(second.challenge);
    await _waitForTasks(deriver, 2);
    deriver.tasks[1].complete(Uint8List(32)..fillRange(0, 32, 2));
    expect((await secondResult).signature, isNotEmpty);
    await authentication.dispose();
  });

  test(
    'cache is reused only for an identical derivation fingerprint',
    () async {
      final unchangedDeriver = _ControlledDeriver();
      final unchanged = ScramAuthentication(
        'pencil',
        reuseClientKey: true,
        keyDeriver: unchangedDeriver,
      );
      final first = await prepare(unchanged);
      final firstResult = unchanged.challenge(first.challenge);
      await _waitForTasks(unchangedDeriver, 1);
      unchangedDeriver.tasks.single.complete(
        Uint8List(32)..fillRange(0, 32, 1),
      );
      await firstResult;
      final second = await prepare(unchanged);
      await unchanged.challenge(second.challenge);
      expect(unchangedDeriver.tasks, hasLength(1));
      await unchanged.dispose();

      final changes = <String, Map<String, Object?>>{
        'salt': <String, Object?>{
          'challengeSalt': base64.encode(List<int>.filled(16, 3)),
        },
        'kdf': <String, Object?>{
          'kdf': ScramAuthentication.kdfArgon,
          'memory': 100,
        },
        'iterations': <String, Object?>{'iterations': 3},
        'memory': <String, Object?>{
          'kdf': ScramAuthentication.kdfArgon,
          'memory': 101,
        },
        'auth identity': <String, Object?>{'authId': 'other-user'},
      };
      for (final entry in changes.entries) {
        final deriver = _ControlledDeriver();
        final authentication = ScramAuthentication(
          'pencil',
          reuseClientKey: true,
          keyDeriver: deriver,
        );
        final initialKdf = entry.key == 'memory'
            ? ScramAuthentication.kdfArgon
            : ScramAuthentication.kdfPbkdf2;
        final initial = await prepare(
          authentication,
          kdf: initialKdf,
          memory: initialKdf == ScramAuthentication.kdfArgon ? 100 : null,
        );
        final initialResult = authentication.challenge(initial.challenge);
        await _waitForTasks(deriver, 1);
        deriver.tasks[0].complete(Uint8List(32)..fillRange(0, 32, 1));
        await initialResult;

        final values = entry.value;
        final changed = await prepare(
          authentication,
          authId: values['authId'] as String? ?? 'user',
          challengeSalt: values['challengeSalt'] as String? ?? salt,
          kdf: values['kdf'] as String? ?? initialKdf,
          iterations: values['iterations'] as int? ?? 2,
          memory: values.containsKey('memory')
              ? values['memory'] as int?
              : (initialKdf == ScramAuthentication.kdfArgon ? 100 : null),
        );
        final changedResult = authentication.challenge(changed.challenge);
        await _waitForTasks(deriver, 2);
        deriver.tasks[1].complete(Uint8List(32)..fillRange(0, 32, 2));
        await changedResult;
        expect(deriver.tasks, hasLength(2), reason: entry.key);
        await authentication.dispose();
      }
    },
  );

  test(
    'worker initialization, crash, cancellation, and disposal fail closed',
    () async {
      final initializationFailure = _ControlledDeriver(
        failInitialization: true,
      );
      final initializationAuth = ScramAuthentication(
        'pencil',
        keyDeriver: initializationFailure,
      );
      final initializationAttempt = await prepare(initializationAuth);
      await expectLater(
        initializationAuth.challenge(initializationAttempt.challenge),
        throwsA(isA<ScramKeyDerivationException>()),
      );
      await initializationAuth.dispose();

      final crashDeriver = _ControlledDeriver();
      final crashAuth = ScramAuthentication('pencil', keyDeriver: crashDeriver);
      final crashAttempt = await prepare(crashAuth);
      final crashed = crashAuth.challenge(crashAttempt.challenge);
      await _waitForTasks(crashDeriver, 1);
      crashDeriver.tasks.single.fail(
        const ScramKeyDerivationException('worker failed'),
      );
      await expectLater(crashed, throwsA(isA<ScramKeyDerivationException>()));
      await crashAuth.dispose();

      final disposeDeriver = _ControlledDeriver();
      final disposeAuth = ScramAuthentication(
        'pencil',
        keyDeriver: disposeDeriver,
      );
      final disposeAttempt = await prepare(disposeAuth);
      final disposed = disposeAuth.challenge(disposeAttempt.challenge);
      await _waitForTasks(disposeDeriver, 1);
      final disposedExpectation = expectLater(
        disposed,
        throwsA(isA<ScramKeyDerivationCancelledException>()),
      );
      await disposeAuth.dispose();
      await disposedExpectation;
    },
  );
}

Future<void> _waitForTasks(_ControlledDeriver deriver, int count) async {
  for (var i = 0; i < 20 && deriver.tasks.length < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(deriver.tasks.length, greaterThanOrEqualTo(count));
}

final class _ControlledDeriver implements ScramKeyDeriver {
  _ControlledDeriver({this.failInitialization = false});

  final bool failInitialization;
  final List<_ControlledTask> tasks = <_ControlledTask>[];
  bool disposed = false;

  @override
  ScramKeyDerivationTask start(
    ScramKeyDerivationRequest request, {
    Duration? timeout,
  }) {
    if (failInitialization) {
      throw const ScramKeyDerivationException('worker initialization failed');
    }
    final task = _ControlledTask();
    tasks.add(task);
    return task;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await Future.wait(tasks.map((task) => task.cancel()));
  }
}

final class _ControlledTask implements ScramKeyDerivationTask {
  final Completer<Uint8List> _completer = Completer<Uint8List>();

  @override
  Future<Uint8List> get result => _completer.future;

  void complete(Uint8List value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void fail(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }

  @override
  Future<void> cancel() async {
    fail(const ScramKeyDerivationCancelledException());
  }
}
