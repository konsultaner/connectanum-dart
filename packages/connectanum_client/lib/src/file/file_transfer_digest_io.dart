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
  if (!allowNative) {
    return DartFileTransferDigest();
  }
  final incoming = nativeIncomingMessageForAnchor(anchor);
  final message = incoming?.message;
  if (message is! NativeSessionMessage ||
      (message.serializer != NativeMessageSerializer.messagePack &&
          message.serializer != NativeMessageSerializer.cbor)) {
    return DartFileTransferDigest();
  }
  try {
    return _NativeFileTransferDigest(NativeClientRuntime.instance());
  } on NativeTransportException {
    return DartFileTransferDigest();
  }
}

Uint8List? nativeFileChunkBytes(Object? anchor) =>
    nativeSingleBinaryArgumentForAnchor(anchor);

class _NativeFileTransferDigest implements FileTransferDigest {
  _NativeFileTransferDigest(this._runtime)
    : _handle = _runtime.createSha256State();

  final NativeClientRuntime _runtime;
  final int _handle;
  bool _finished = false;

  @override
  void add(Uint8List bytes, {Object? anchor}) {
    if (_finished) {
      throw StateError('File transfer digest is already finalized');
    }
    final incoming = nativeIncomingMessageForAnchor(anchor);
    if (incoming == null) {
      throw StateError('Native file chunk lost its retained message handle');
    }
    final hashedBytes = _runtime.updateSha256WithMessageBinaryArgument(
      _handle,
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
    final digest = _runtime.finalizeSha256State(_handle);
    _finished = true;
    return encodeSha256Digest(digest);
  }

  @override
  void abort() {
    if (_finished) {
      return;
    }
    _finished = true;
    _runtime.releaseSha256State(_handle);
  }
}
