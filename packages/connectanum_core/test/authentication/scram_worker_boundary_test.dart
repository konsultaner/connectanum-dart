@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/src/authentication/scram_key_derivation_web.dart';
import 'package:test/test.dart';

ScramKeyDerivationRequest request({int length = 32, int marker = 7}) =>
    ScramKeyDerivationRequest(
      password: Uint8List.fromList([1, 2, 3]),
      salt: Uint8List.fromList([marker, 2, 3, 4]),
      kdf: ScramAuthentication.kdfArgon,
      iterations: 2,
      memory: 100,
      keyLength: length,
    );

void main() {
  for (final payload in [
    'null',
    'undefined',
    '[]',
    '"private-worker-diagnostic"',
    '({error: "private-worker-diagnostic"})',
    'new Uint16Array(32)',
    'new ArrayBuffer(32)',
  ]) {
    test('rejects non-byte-array worker reply $payload', () async {
      final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting(
        'self.onmessage = () => self.postMessage($payload);',
      );
      addTearDown(deriver.dispose);
      await expectLater(
        deriver.start(request()).result,
        throwsA(
          isA<ScramKeyDerivationException>().having(
            (error) => error.message,
            'sanitized message',
            'worker returned no result',
          ),
        ),
      );
    });
  }

  for (final length in [0, 1, 31, 33, 64]) {
    test('rejects $length bytes for a requested 32-byte key', () async {
      final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting(
        'self.onmessage = () => self.postMessage(new Uint8Array($length));',
      );
      addTearDown(deriver.dispose);
      await expectLater(
        deriver.start(request()).result,
        throwsA(
          isA<ScramKeyDerivationException>().having(
            (error) => error.message,
            'sanitized message',
            'worker returned invalid length',
          ),
        ),
      );
    });
  }

  for (final length in [16, 32, 64]) {
    test(
      'returns exactly the requested $length bytes without clearing the result',
      () async {
        final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting('''
self.onmessage = ({data}) => {
  self.postMessage(new Uint8Array(data.keyLength).fill(data.salt[0]));
};
''');
        addTearDown(deriver.dispose);
        final input = request(length: length);
        final task = deriver.start(input);
        expect(input.password, everyElement(0));
        expect(input.salt, everyElement(0));
        final value = await task.result;
        expect(value, orderedEquals(List.filled(length, 7)));
        await task.cancel();
        await deriver.dispose();
        await deriver.dispose();
        expect(value, orderedEquals(List.filled(length, 7)));
        value.fillRange(0, value.length, 0);
        expect(() => deriver.start(request()), throwsStateError);
      },
    );
  }

  test('failed worker response cannot poison the next derivation', () async {
    final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting('''
self.onmessage = ({data}) => {
  self.postMessage(new Uint8Array(data.salt[0] === 1 ? 31 : data.keyLength).fill(9));
};
''');
    addTearDown(deriver.dispose);
    await expectLater(
      deriver.start(request(marker: 1)).result,
      throwsA(isA<ScramKeyDerivationException>()),
    );
    final value = await deriver.start(request(marker: 2)).result;
    addTearDown(() => value.fillRange(0, value.length, 0));
    expect(value, orderedEquals(List.filled(32, 9)));
  });

  test(
    'concurrent out-of-order worker replies keep their request identity',
    () async {
      final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting('''
self.onmessage = ({data}) => {
  setTimeout(() => self.postMessage(new Uint8Array(data.keyLength).fill(data.salt[0])),
    data.salt[0] === 1 ? 50 : 0);
};
''');
      addTearDown(deriver.dispose);
      final results = await Future.wait([
        deriver.start(request(marker: 1)).result,
        deriver.start(request(marker: 2)).result,
      ]);
      addTearDown(() {
        for (final value in results) {
          value.fillRange(0, value.length, 0);
        }
      });
      expect(results[0], orderedEquals(List.filled(32, 1)));
      expect(results[1], orderedEquals(List.filled(32, 2)));
    },
  );

  test(
    'disposal cancels every outstanding task and stays idempotent',
    () async {
      final deriver = PlatformScramKeyDeriver.withWorkerSourceForTesting(
        'self.onmessage = () => {};',
      );
      addTearDown(deriver.dispose);
      final tasks = [for (var i = 0; i < 3; i++) deriver.start(request())];
      final failures = [
        for (final task in tasks)
          expectLater(
            task.result,
            throwsA(isA<ScramKeyDerivationCancelledException>()),
          ),
      ];
      await deriver.dispose();
      await Future.wait(failures);
      await deriver.dispose();
      for (final task in tasks) {
        await task.cancel();
      }
      expect(() => deriver.start(request()), throwsStateError);
    },
  );
}
