@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/src/authentication/scram_key_derivation_web.dart'
    as web_derivation;
import 'package:test/test.dart';

void main() {
  ScramKeyDerivationRequest request({
    String password = 'pencil',
    int memory = 100,
    int iterations = 4096,
    int saltMarker = 1,
  }) => ScramKeyDerivationRequest(
    password: Uint8List.fromList(utf8.encode(password)),
    salt: saltMarker == 1
        ? Uint8List.fromList(base64.decode('W22ZaJ0SNY7soEsUEjb6gQ=='))
        : Uint8List.fromList(List<int>.filled(16, saltMarker)),
    kdf: ScramAuthentication.kdfArgon,
    iterations: iterations,
    memory: memory,
    keyLength: 32,
  );

  test('web Worker Argon2id13 preserves the native SCRAM vector', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final result = await deriver
        .start(request(), timeout: const Duration(seconds: 30))
        .result;
    expect(
      base64.encode(result),
      '6AIVIE+fg84WuUMIH3cJilV2H1kpnf4SHlOHTqatIFA=',
    );
    expect(
      () => ScramAuthentication.deriveSaltedPassword(
        secret: 'pencil',
        salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
        kdf: ScramAuthentication.kdfArgon,
        iterations: 1,
        memory: 100,
      ),
      throwsUnsupportedError,
    );
  });

  test('64 MiB web derivation leaves the event loop responsive', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    var ticks = 0;
    var complete = false;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (!complete) ticks++;
    });
    final result = await deriver
        .start(
          request(memory: 65536, iterations: 1),
          timeout: const Duration(seconds: 60),
        )
        .result;
    complete = true;
    timer.cancel();
    expect(result, hasLength(32));
    expect(ticks, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('web worker preserves PBKDF2 and legacy short-salt output', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final pbkdf2 = await deriver
        .start(
          ScramKeyDerivationRequest(
            password: Uint8List.fromList(utf8.encode('pencil')),
            salt: Uint8List.fromList(
              base64.decode('W22ZaJ0SNY7soEsUEjb6gQ=='),
            ),
            kdf: ScramAuthentication.kdfPbkdf2,
            iterations: 4096,
            memory: 100,
            keyLength: 32,
          ),
        )
        .result;
    expect(
      base64.encode(pbkdf2),
      'xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0=',
    );

    final shortSalt = await deriver
        .start(
          ScramKeyDerivationRequest(
            password: Uint8List.fromList(utf8.encode('Richard')),
            salt: Uint8List.fromList(<int>[1]),
            kdf: ScramAuthentication.kdfArgon,
            iterations: 1,
            memory: 100,
            keyLength: 32,
          ),
        )
        .result;
    expect(
      base64.encode(shortSalt),
      'OK0sBORa2i8rCjIsvR2ZjJDbOKNRTTO2K4XELsMh9+c=',
    );
  });

  test('concurrent web workers cannot mix results', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final expected = <String>[];
    for (final input in <({String password, int marker})>[
      (password: 'one', marker: 1),
      (password: 'two', marker: 2),
      (password: 'three', marker: 3),
    ]) {
      expected.add(
        base64.encode(
          await deriver
              .start(
                request(
                  password: input.password,
                  iterations: 2,
                  saltMarker: input.marker,
                ),
              )
              .result,
        ),
      );
    }
    final results = await Future.wait(<Future<Uint8List>>[
      deriver.start(request(password: 'one', iterations: 2)).result,
      deriver
          .start(request(password: 'two', iterations: 2, saltMarker: 2))
          .result,
      deriver
          .start(request(password: 'three', iterations: 2, saltMarker: 3))
          .result,
    ]);
    expect(results.map(base64.encode), orderedEquals(expected));
  });

  test('a crashing web Worker fails closed', () async {
    final deriver =
        web_derivation.PlatformScramKeyDeriver.withWorkerSourceForTesting(
          'self.onmessage = function () { throw new Error("crash"); };',
        );
    addTearDown(deriver.dispose);
    await expectLater(
      deriver.start(request()).result,
      throwsA(isA<ScramKeyDerivationException>()),
    );
  });

  test(
    'web cancellation, timeout, worker failure, and disposal fail closed',
    () async {
      final cancelDeriver = ScramKeyDeriver();
      final cancelled = cancelDeriver.start(
        request(memory: 65536, iterations: 2),
      );
      final cancelledResult = expectLater(
        cancelled.result,
        throwsA(isA<ScramKeyDerivationCancelledException>()),
      );
      await cancelled.cancel();
      await cancelledResult;
      await cancelDeriver.dispose();

      final timeoutDeriver = ScramKeyDeriver();
      await expectLater(
        timeoutDeriver
            .start(
              request(memory: 65536, iterations: 2),
              timeout: Duration.zero,
            )
            .result,
        throwsA(isA<ScramKeyDerivationTimeoutException>()),
      );
      await timeoutDeriver.dispose();

      final failedDeriver = ScramKeyDeriver();
      await expectLater(
        failedDeriver
            .start(
              ScramKeyDerivationRequest(
                password: Uint8List.fromList(utf8.encode('password')),
                salt: Uint8List.fromList(List<int>.filled(16, 4)),
                kdf: 'unsupported',
                iterations: 1,
                memory: 100,
                keyLength: 32,
              ),
            )
            .result,
        throwsA(isA<ScramKeyDerivationException>()),
      );
      await failedDeriver.dispose();

      final disposeDeriver = ScramKeyDeriver();
      final disposed = disposeDeriver.start(
        request(memory: 65536, iterations: 2),
      );
      final disposedResult = expectLater(
        disposed.result,
        throwsA(isA<ScramKeyDerivationCancelledException>()),
      );
      await disposeDeriver.dispose();
      await disposedResult;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
