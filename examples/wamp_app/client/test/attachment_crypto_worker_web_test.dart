@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/attachment_crypto_worker.dart';
import 'package:wamp_app/src/infrastructure/attachment_crypto_worker_web.dart';

void main() {
  test('Web Worker matches the native AES-256-GCM vector', () async {
    final worker = AttachmentCryptoWorker();
    addTearDown(worker.dispose);
    final request = _request();

    final encrypted = await worker.start(request).result;

    expect(
      _hex(encrypted),
      'e6197e2e41ce04b86a6c8dd80b77ced160bd4b0386a2547b84173c9d63b66b1e'
      'f25765dc8b07751a77b52ee32557add6772a747b56e52c4979673165984dbb8f'
      '14a4381068d1b2d768ed6b3dbc0eca5e',
    );
    expect(request.key, everyElement(0));
    expect(request.input, everyElement(0));

    final opened = await worker
        .start(
          AttachmentCryptoRequest(
            operation: AttachmentCryptoOperation.decrypt,
            key: _key(),
            nonce: _nonce(),
            additionalData: _additionalData(),
            input: encrypted,
          ),
        )
        .result;
    expect(opened, _plaintext());
  });

  test('concurrent Web Worker results cannot cross requests', () async {
    final worker = AttachmentCryptoWorker();
    addTearDown(worker.dispose);

    final encrypted = await Future.wait(
      List.generate(6, (index) {
        return worker
            .start(
              AttachmentCryptoRequest(
                operation: AttachmentCryptoOperation.encrypt,
                key: Uint8List.fromList(
                  List<int>.generate(32, (offset) => index + offset),
                ),
                nonce: Uint8List.fromList(
                  List<int>.generate(12, (offset) => 31 + index + offset),
                ),
                additionalData: Uint8List.fromList([index]),
                input: Uint8List.fromList(
                  List<int>.generate(8192 + index, (offset) => index ^ offset),
                ),
              ),
            )
            .result;
      }),
    );

    final opened = await Future.wait(
      List.generate(6, (index) {
        return worker
            .start(
              AttachmentCryptoRequest(
                operation: AttachmentCryptoOperation.decrypt,
                key: Uint8List.fromList(
                  List<int>.generate(32, (offset) => index + offset),
                ),
                nonce: Uint8List.fromList(
                  List<int>.generate(12, (offset) => 31 + index + offset),
                ),
                additionalData: Uint8List.fromList([index]),
                input: encrypted[index],
              ),
            )
            .result;
      }),
    );
    for (var index = 0; index < opened.length; index += 1) {
      expect(
        opened[index],
        List<int>.generate(8192 + index, (offset) => (index ^ offset) & 0xff),
      );
    }
  });

  test('64 MiB Web Worker crypto keeps the event loop responsive', () async {
    final worker = AttachmentCryptoWorker();
    addTearDown(worker.dispose);
    final input = Uint8List(64 * 1024 * 1024);
    for (var offset = 0; offset < input.length; offset += 4096) {
      input[offset] = offset & 0xff;
    }
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks += 1,
    );

    final encrypted = await worker
        .start(
          AttachmentCryptoRequest(
            operation: AttachmentCryptoOperation.encrypt,
            key: _key(),
            nonce: _nonce(),
            additionalData: _additionalData(),
            input: input,
          ),
          timeout: const Duration(seconds: 20),
        )
        .result;
    timer.cancel();

    expect(encrypted.length, input.length + 16);
    expect(ticks, greaterThan(0));
    encrypted.fillRange(0, encrypted.length, 0);
    input.fillRange(0, input.length, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'Web Worker cancellation, timeout, crash, and disposal fail closed',
    () async {
      const delayedWorker = '''
self.onmessage=function(){
  setTimeout(function(){
    const result=new Uint8Array([1]);
    self.postMessage(result,[result.buffer]);
  },10000);
};
''';
      final cancelWorker =
          PlatformAttachmentCryptoWorker.withWorkerSourceForTesting(
            delayedWorker,
          );
      final cancelled = cancelWorker.start(_request());
      final cancelledExpectation = expectLater(
        cancelled.result,
        throwsA(isA<AttachmentCryptoCancelledException>()),
      );
      await cancelled.cancel();
      await cancelledExpectation;
      await cancelWorker.dispose();

      final timeoutWorker =
          PlatformAttachmentCryptoWorker.withWorkerSourceForTesting(
            delayedWorker,
          );
      addTearDown(timeoutWorker.dispose);
      await expectLater(
        timeoutWorker.start(_request(), timeout: Duration.zero).result,
        throwsA(isA<AttachmentCryptoTimeoutException>()),
      );

      const crashingWorker = '''
self.onmessage=function(){throw new Error('sensitive failure');};
''';
      final crashWorker =
          PlatformAttachmentCryptoWorker.withWorkerSourceForTesting(
            crashingWorker,
          );
      addTearDown(crashWorker.dispose);
      await expectLater(
        crashWorker.start(_request()).result,
        throwsA(
          isA<AttachmentCryptoException>().having(
            (error) => error.message,
            'message',
            'worker failed',
          ),
        ),
      );

      final disposeWorker =
          PlatformAttachmentCryptoWorker.withWorkerSourceForTesting(
            delayedWorker,
          );
      final disposedTask = disposeWorker.start(_request());
      final disposedExpectation = expectLater(
        disposedTask.result,
        throwsA(isA<AttachmentCryptoCancelledException>()),
      );
      await disposeWorker.dispose();
      await disposedExpectation;
      await disposeWorker.dispose();
      expect(() => disposeWorker.start(_request()), throwsStateError);
    },
  );
}

AttachmentCryptoRequest _request() => AttachmentCryptoRequest(
  operation: AttachmentCryptoOperation.encrypt,
  key: _key(),
  nonce: _nonce(),
  additionalData: _additionalData(),
  input: _plaintext(),
);

Uint8List _key() =>
    Uint8List.fromList(List<int>.generate(32, (index) => index));

Uint8List _nonce() =>
    Uint8List.fromList(List<int>.generate(12, (index) => 0xa0 + index));

Uint8List _additionalData() =>
    Uint8List.fromList(utf8.encode('wampapp-worker-vector'));

Uint8List _plaintext() =>
    Uint8List.fromList(List<int>.generate(64, (index) => index));

String _hex(Uint8List value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
