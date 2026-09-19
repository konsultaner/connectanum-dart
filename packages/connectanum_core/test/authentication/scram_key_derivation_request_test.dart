import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:test/test.dart';

void main() {
  for (final field in ['iterations', 'memory', 'keyLength']) {
    for (final invalid in [0, -1]) {
      test('rejects $field=$invalid without modifying caller buffers', () {
        final password = Uint8List.fromList([1, 2, 3]);
        final salt = Uint8List.fromList([4, 5, 6]);
        expect(
          () => ScramKeyDerivationRequest(
            password: password,
            salt: salt,
            kdf: ScramAuthentication.kdfArgon,
            iterations: field == 'iterations' ? invalid : 1,
            memory: field == 'memory' ? invalid : 1,
            keyLength: field == 'keyLength' ? invalid : 1,
          ),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'parameter', field)
                .having((error) => error.invalidValue, 'invalid value', invalid)
                .having(
                  (error) => error.message,
                  'message',
                  'must be positive',
                ),
          ),
        );
        expect(password, [1, 2, 3]);
        expect(salt, [4, 5, 6]);
      });
    }
  }

  for (final kdf in [
    ScramAuthentication.kdfArgon,
    ScramAuthentication.kdfPbkdf2,
  ]) {
    test('preserves positive lower bounds and the selected $kdf', () {
      final request = ScramKeyDerivationRequest(
        password: Uint8List.fromList([255]),
        salt: Uint8List.fromList([128]),
        kdf: kdf,
        iterations: 1,
        memory: 1,
        keyLength: 1,
      );
      expect(request.kdf, kdf);
      expect(request.iterations, 1);
      expect(request.memory, 1);
      expect(request.keyLength, 1);
      expect(request.password, [255]);
      expect(request.salt, [128]);
    });
  }

  test('takes independent copies of overlapping caller buffer views', () {
    final source = Uint8List.fromList([90, 1, 2, 3, 4, 5, 91]);
    final request = ScramKeyDerivationRequest(
      password: Uint8List.sublistView(source, 1, 4),
      salt: Uint8List.sublistView(source, 3, 6),
      kdf: ScramAuthentication.kdfArgon,
      iterations: 3,
      memory: 65536,
      keyLength: 32,
    );
    source.fillRange(0, source.length, 42);
    expect(request.password, [1, 2, 3]);
    expect(request.salt, [3, 4, 5]);
    request.password.fillRange(0, request.password.length, 0);
    expect(request.salt, [3, 4, 5]);
    request.salt.fillRange(0, request.salt.length, 0);
    expect(source, everyElement(42));
    expect(request.iterations, 3);
    expect(request.memory, 65536);
    expect(request.keyLength, 32);
  });

  test('retains typed failures and their fixed diagnostics', () {
    const cancelled = ScramKeyDerivationCancelledException();
    const timeout = ScramKeyDerivationTimeoutException();
    const failure = ScramKeyDerivationException('worker failed');
    for (final (error, message) in [
      (cancelled, 'key derivation was cancelled'),
      (timeout, 'key derivation timed out'),
      (failure, 'worker failed'),
    ]) {
      expect(error, isA<Exception>());
      expect(error, isA<ScramKeyDerivationException>());
      expect(error.message, message);
      expect(error.toString(), 'ScramKeyDerivationException: $message');
    }
    expect(cancelled, isNot(isA<ScramKeyDerivationTimeoutException>()));
    expect(timeout, isNot(isA<ScramKeyDerivationCancelledException>()));
  });
}
