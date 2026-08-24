@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:test/test.dart';

void main() {
  test('native Argon2id13 worker preserves the SCRAM vector', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final result = await deriver
        .start(
          ScramKeyDerivationRequest(
            password: Uint8List.fromList(utf8.encode('pencil')),
            salt: Uint8List.fromList(
              base64.decode('W22ZaJ0SNY7soEsUEjb6gQ=='),
            ),
            kdf: ScramAuthentication.kdfArgon,
            iterations: 4096,
            memory: 100,
            keyLength: 32,
          ),
          timeout: const Duration(seconds: 20),
        )
        .result;
    expect(
      base64.encode(result),
      '6AIVIE+fg84WuUMIH3cJilV2H1kpnf4SHlOHTqatIFA=',
    );
  });

  test('native worker preserves PBKDF2 output', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final expected = ScramAuthentication.deriveSaltedPassword(
      secret: 'pencil',
      salt: 'W22ZaJ0SNY7soEsUEjb6gQ==',
      kdf: ScramAuthentication.kdfPbkdf2,
      iterations: 4096,
    );
    final actual = await deriver
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
    expect(actual, orderedEquals(expected));
  });

  test('native Argon2id13 preserves legacy short-salt output', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    final result = await deriver
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
      base64.encode(result),
      'OK0sBORa2i8rCjIsvR2ZjJDbOKNRTTO2K4XELsMh9+c=',
    );
  });

  test('concurrent native derivations cannot mix results', () async {
    final deriver = ScramKeyDeriver();
    addTearDown(deriver.dispose);
    ScramKeyDerivationTask start(int marker) => deriver.start(
      ScramKeyDerivationRequest(
        password: Uint8List.fromList(utf8.encode('password-$marker')),
        salt: Uint8List.fromList(List<int>.filled(16, marker)),
        kdf: ScramAuthentication.kdfArgon,
        iterations: 2,
        memory: 100,
        keyLength: 32,
      ),
    );

    final expected = <String>[];
    for (var marker = 1; marker <= 3; marker++) {
      expected.add(base64.encode(await start(marker).result));
    }
    final results = await Future.wait(<Future<Uint8List>>[
      start(1).result,
      start(2).result,
      start(3).result,
    ]);
    expect(results.map(base64.encode), orderedEquals(expected));
  });

  test('native cancellation, timeout, and disposal fail closed', () async {
    ScramKeyDerivationRequest expensive() => ScramKeyDerivationRequest(
      password: Uint8List.fromList(utf8.encode('password')),
      salt: Uint8List.fromList(List<int>.filled(16, 7)),
      kdf: ScramAuthentication.kdfArgon,
      iterations: 3,
      memory: 65536,
      keyLength: 32,
    );

    final cancelDeriver = ScramKeyDeriver();
    final cancelled = cancelDeriver.start(expensive());
    final cancelledResult = expectLater(
      cancelled.result,
      throwsA(isA<ScramKeyDerivationCancelledException>()),
    );
    await cancelled.cancel();
    await cancelledResult;
    await cancelDeriver.dispose();

    final timeoutDeriver = ScramKeyDeriver();
    final timedOut = timeoutDeriver.start(
      expensive(),
      timeout: Duration.zero,
    );
    await expectLater(
      timedOut.result,
      throwsA(isA<ScramKeyDerivationTimeoutException>()),
    );
    await timeoutDeriver.dispose();

    final disposeDeriver = ScramKeyDeriver();
    final disposedTask = disposeDeriver.start(expensive());
    final disposedResult = expectLater(
      disposedTask.result,
      throwsA(isA<ScramKeyDerivationCancelledException>()),
    );
    await disposeDeriver.dispose();
    await disposedResult;
    expect(() => disposeDeriver.start(expensive()), throwsStateError);
  });
}
