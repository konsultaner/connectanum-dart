import 'dart:typed_data';

import 'attachment_crypto_worker_stub.dart'
    if (dart.library.io) 'attachment_crypto_worker_native.dart'
    if (dart.library.js_interop) 'attachment_crypto_worker_web.dart'
    as platform;

enum AttachmentCryptoOperation { encrypt, decrypt }

/// One independently cancellable AES-256-GCM chunk operation.
final class AttachmentCryptoRequest {
  AttachmentCryptoRequest({
    required this.operation,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List additionalData,
    required Uint8List input,
  }) : key = Uint8List.fromList(key),
       nonce = Uint8List.fromList(nonce),
       additionalData = Uint8List.fromList(additionalData),
       input = Uint8List.fromList(input) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must contain 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError.value(nonce.length, 'nonce', 'must contain 12 bytes');
    }
  }

  final AttachmentCryptoOperation operation;
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List additionalData;
  final Uint8List input;
}

abstract interface class AttachmentCryptoTask {
  Future<Uint8List> get result;

  Future<void> cancel();
}

/// Runs chunk encryption away from the Flutter event loop on every platform.
abstract interface class AttachmentCryptoWorker {
  factory AttachmentCryptoWorker() = platform.PlatformAttachmentCryptoWorker;

  AttachmentCryptoTask start(
    AttachmentCryptoRequest request, {
    Duration? timeout,
  });

  Future<void> dispose();
}

class AttachmentCryptoException implements Exception {
  const AttachmentCryptoException(this.message);

  final String message;

  @override
  String toString() => 'AttachmentCryptoException: $message';
}

final class AttachmentCryptoCancelledException
    extends AttachmentCryptoException {
  const AttachmentCryptoCancelledException()
    : super('attachment crypto was cancelled');
}

final class AttachmentCryptoTimeoutException extends AttachmentCryptoException {
  const AttachmentCryptoTimeoutException()
    : super('attachment crypto timed out');
}
