import 'dart:typed_data';

import '../transport/native/message_binding.dart';
import '../transport/native/message_protocol.dart';
import '../transport/native/native_transports_io.dart';
import '../transport/native/runtime.dart';
import 'file_transfer_digest.dart';

FileTransferDigest createFileTransferDigest({
  required Object? anchor,
  required bool allowNative,
}) {
  final incoming = nativeIncomingMessageForAnchor(anchor);
  final message = incoming?.message;
  try {
    final runtime = NativeClientRuntime.instance();
    final canHashRetainedArgument =
        message is NativeSessionMessage &&
        (message.serializer == NativeMessageSerializer.messagePack ||
            message.serializer == NativeMessageSerializer.cbor);
    return allowNative && canHashRetainedArgument
        ? _NativeFileTransferDigest(runtime)
        : _NativeBytesFileTransferDigest(runtime);
  } on NativeTransportException {
    return DartFileTransferDigest();
  } on ArgumentError {
    return DartFileTransferDigest();
  } on UnsupportedError {
    return DartFileTransferDigest();
  }
}

Uint8List? nativeFileChunkBytes(Object? anchor) =>
    nativeSingleBinaryArgumentForAnchor(anchor);

bool releaseNativeFileChunkBytes(Uint8List bytes) =>
    NativeClientRuntime.releaseOwnedExternalBytes(bytes);

bool releaseNativeFileChunkMessage(Object? anchor) {
  final incoming = nativeIncomingMessageForAnchor(anchor);
  if (incoming == null) {
    return false;
  }
  incoming.release();
  return true;
}

class _NativeBytesFileTransferDigest extends _NativeFileTransferDigest {
  _NativeBytesFileTransferDigest(super.runtime);

  @override
  void add(
    Uint8List bytes, {
    Object? anchor,
    bool consumeNativeOwnership = false,
  }) {
    ensureOpen();
    final expectedLength = bytes.length;
    final hashedBytes = consumeNativeOwnership
        ? runtime.updateSha256ByConsumingExternalBytes(handle, bytes) ??
              runtime.updateSha256(handle, bytes, anchor: anchor)
        : runtime.updateSha256(handle, bytes, anchor: anchor);
    if (hashedBytes != expectedLength) {
      throw StateError(
        'Native file digest hashed $hashedBytes of $expectedLength bytes',
      );
    }
  }
}

class _NativeFileTransferDigest implements FileTransferDigest {
  _NativeFileTransferDigest(this.runtime)
    : handle = runtime.createSha256State();

  final NativeClientRuntime runtime;
  final int handle;
  bool _finished = false;

  void ensureOpen() {
    if (_finished) {
      throw StateError('File transfer digest is already finalized');
    }
  }

  @override
  void add(
    Uint8List bytes, {
    Object? anchor,
    bool consumeNativeOwnership = false,
  }) {
    ensureOpen();
    final incoming = nativeIncomingMessageForAnchor(anchor);
    if (incoming == null) {
      throw StateError('Native file chunk lost its retained message handle');
    }
    final hashedBytes = runtime.updateSha256WithMessageBinaryArgument(
      handle,
      incoming.handle,
    );
    if (hashedBytes != bytes.length) {
      throw StateError(
        'Native file digest hashed $hashedBytes of ${bytes.length} bytes',
      );
    }
  }

  @override
  String finish() {
    if (_finished) {
      throw StateError('File transfer digest is already finalized');
    }
    final digest = runtime.finalizeSha256State(handle);
    _finished = true;
    return encodeSha256Digest(digest);
  }

  @override
  void abort() {
    if (_finished) {
      return;
    }
    _finished = true;
    runtime.releaseSha256State(handle);
  }
}
