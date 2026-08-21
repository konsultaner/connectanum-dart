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
  if (message is! NativeSessionMessage ||
      (message.serializer != NativeMessageSerializer.messagePack &&
          message.serializer != NativeMessageSerializer.cbor)) {
    return DartFileTransferDigest();
  }
  try {
    final runtime = NativeClientRuntime.instance();
    return allowNative
        ? _NativeFileTransferDigest(runtime)
        : _NativeBytesFileTransferDigest(runtime);
  } on NativeTransportException {
    return DartFileTransferDigest();
  }
}

Uint8List? nativeFileChunkBytes(Object? anchor) =>
    nativeSingleBinaryArgumentForAnchor(anchor);

class _NativeBytesFileTransferDigest extends _NativeFileTransferDigest {
  _NativeBytesFileTransferDigest(super.runtime);

  @override
  void add(Uint8List bytes, {Object? anchor}) {
    ensureOpen();
    final hashedBytes = runtime.updateSha256(handle, bytes);
    if (hashedBytes != bytes.length) {
      throw StateError(
        'Native file digest hashed $hashedBytes of ${bytes.length} bytes',
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
  void add(Uint8List bytes, {Object? anchor}) {
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
