import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'attachment_crypto_worker.dart';

typedef AttachmentCryptoBackend = Future<Uint8List> Function(
  AttachmentCryptoRequest request,
);

final class PlatformAttachmentCryptoWorker implements AttachmentCryptoWorker {
  PlatformAttachmentCryptoWorker() : _backend = _cryptWithPlatformApis;

  PlatformAttachmentCryptoWorker.withBackendForTesting(this._backend);

  final AttachmentCryptoBackend _backend;
  final Set<_NativeAttachmentCryptoTask> _tasks =
      <_NativeAttachmentCryptoTask>{};
  bool _disposed = false;

  @override
  AttachmentCryptoTask start(
    AttachmentCryptoRequest request, {
    Duration? timeout,
  }) {
    if (_disposed) throw StateError('Attachment crypto worker is disposed');
    late final _NativeAttachmentCryptoTask task;
    task = _NativeAttachmentCryptoTask(
      request,
      backend: _backend,
      timeout: timeout,
      onDone: () => _tasks.remove(task),
    );
    _tasks.add(task);
    task.start();
    return task;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final tasks = _tasks.toList(growable: false);
    await Future.wait(tasks.map((task) => task.cancel()));
    await Future.wait(tasks.map((task) => task.backendDone));
  }
}

final class _NativeAttachmentCryptoTask implements AttachmentCryptoTask {
  _NativeAttachmentCryptoTask(
    this._request, {
    required this.backend,
    required this.timeout,
    required this.onDone,
  });

  final AttachmentCryptoRequest _request;
  final AttachmentCryptoBackend backend;
  final Duration? timeout;
  final void Function() onDone;
  final Completer<Uint8List> _completer = Completer<Uint8List>();
  Timer? _timer;
  late final Future<void> _backendDone;
  bool _finished = false;

  @override
  Future<Uint8List> get result => _completer.future;

  Future<void> get backendDone => _backendDone;

  void start() {
    if (timeout != null) {
      _timer = Timer(
        timeout!,
        () => _fail(const AttachmentCryptoTimeoutException()),
      );
    }
    _backendDone = Future<Uint8List>.sync(() => backend(_request))
        .then<void>(
          _succeed,
          onError: (_) =>
              _fail(const AttachmentCryptoException('worker failed')),
        )
        .whenComplete(() {
          _clearRequest(_request);
          onDone();
        });
  }

  @override
  Future<void> cancel() async {
    _fail(const AttachmentCryptoCancelledException());
  }

  void _succeed(Uint8List value) {
    if (_finished) {
      _clear(value);
      return;
    }
    _finished = true;
    _completer.complete(value);
    _cleanup();
  }

  void _fail(Object error) {
    if (_finished) return;
    _finished = true;
    _completer.completeError(error);
    _cleanup();
  }

  void _cleanup() {
    _timer?.cancel();
  }
}

final AesGcm _aes256Gcm = FlutterAesGcm.with256bits();

Future<Uint8List> _cryptWithPlatformApis(
  AttachmentCryptoRequest request,
) async {
  final secretKey = SecretKeyData(request.key, overwriteWhenDestroyed: true);
  try {
    return switch (request.operation) {
      AttachmentCryptoOperation.encrypt => await _encrypt(request, secretKey),
      AttachmentCryptoOperation.decrypt => await _decrypt(request, secretKey),
    };
  } finally {
    secretKey.destroy();
  }
}

Future<Uint8List> _encrypt(
  AttachmentCryptoRequest request,
  SecretKey secretKey,
) async {
  final box = await _aes256Gcm.encrypt(
    request.input,
    secretKey: secretKey,
    nonce: request.nonce,
    aad: request.additionalData,
  );
  return Uint8List(box.cipherText.length + box.mac.bytes.length)
    ..setAll(0, box.cipherText)
    ..setAll(box.cipherText.length, box.mac.bytes);
}

Future<Uint8List> _decrypt(
  AttachmentCryptoRequest request,
  SecretKey secretKey,
) async {
  if (request.input.length < 16) {
    throw const AttachmentCryptoException('worker failed');
  }
  final tagOffset = request.input.length - 16;
  final box = SecretBox(
    Uint8List.sublistView(request.input, 0, tagOffset),
    nonce: request.nonce,
    mac: Mac(Uint8List.sublistView(request.input, tagOffset)),
  );
  return Uint8List.fromList(
    await _aes256Gcm.decrypt(
      box,
      secretKey: secretKey,
      aad: request.additionalData,
    ),
  );
}

void _clearRequest(AttachmentCryptoRequest request) {
  _clear(request.key);
  _clear(request.nonce);
  _clear(request.additionalData);
  _clear(request.input);
}

void _clear(Uint8List value) => value.fillRange(0, value.length, 0);
