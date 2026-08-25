import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/attachment_crypto_worker.dart';
import 'package:wamp_app/src/infrastructure/attachment_crypto_worker_native.dart';

void main() {
  test('native backend matches the AES-256-GCM compatibility vector', () async {
    final worker = AttachmentCryptoWorker();
    addTearDown(worker.dispose);
    final request = _request(AttachmentCryptoOperation.encrypt);

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

  test('concurrent native results cannot cross requests', () async {
    final worker = AttachmentCryptoWorker();
    addTearDown(worker.dispose);

    final encrypted = await Future.wait(
      List.generate(8, (index) {
        final plaintext = Uint8List.fromList(
          List<int>.generate(4096 + index, (offset) => index ^ offset),
        );
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
                input: plaintext,
              ),
            )
            .result;
      }),
    );

    final opened = await Future.wait(
      List.generate(8, (index) {
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
        List<int>.generate(4096 + index, (offset) => (index ^ offset) & 0xff),
      );
    }
  });

  test(
    'native cancellation, timeout, crash, and disposal fail closed',
    () async {
      final cancelWorker = PlatformAttachmentCryptoWorker.withBackendForTesting(
        _blockingBackend,
      );
      final cancelRequest = _request();
      final cancelled = cancelWorker.start(cancelRequest);
      final cancelledExpectation = expectLater(
        cancelled.result,
        throwsA(isA<AttachmentCryptoCancelledException>()),
      );
      await cancelled.cancel();
      await cancelledExpectation;
      await cancelWorker.dispose();
      expect(cancelRequest.key, everyElement(0));
      expect(cancelRequest.input, everyElement(0));

      final timeoutWorker =
          PlatformAttachmentCryptoWorker.withBackendForTesting(
            _blockingBackend,
          );
      addTearDown(timeoutWorker.dispose);
      final timeoutRequest = _request();
      await expectLater(
        timeoutWorker.start(timeoutRequest, timeout: Duration.zero).result,
        throwsA(isA<AttachmentCryptoTimeoutException>()),
      );
      await timeoutWorker.dispose();
      expect(timeoutRequest.key, everyElement(0));
      expect(timeoutRequest.input, everyElement(0));

      final crashWorker = PlatformAttachmentCryptoWorker.withBackendForTesting(
        _crashingBackend,
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
          PlatformAttachmentCryptoWorker.withBackendForTesting(
            _blockingBackend,
          );
      final disposeRequest = _request();
      final disposedTask = disposeWorker.start(disposeRequest);
      final disposedExpectation = expectLater(
        disposedTask.result,
        throwsA(isA<AttachmentCryptoCancelledException>()),
      );
      await disposeWorker.dispose();
      await disposedExpectation;
      await disposeWorker.dispose();
      expect(disposeRequest.key, everyElement(0));
      expect(disposeRequest.input, everyElement(0));
      expect(() => disposeWorker.start(_request()), throwsStateError);
    },
  );
}

AttachmentCryptoRequest _request([
  AttachmentCryptoOperation operation = AttachmentCryptoOperation.encrypt,
]) => AttachmentCryptoRequest(
  operation: operation,
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

Future<Uint8List> _blockingBackend(AttachmentCryptoRequest _) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return Uint8List(0);
}

Future<Uint8List> _crashingBackend(AttachmentCryptoRequest _) async {
  throw StateError('sensitive failure');
}
