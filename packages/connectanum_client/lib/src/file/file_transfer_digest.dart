import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class FileTransferDigest {
  void add(
    Uint8List bytes, {
    Object? anchor,
    bool consumeNativeOwnership = false,
  });

  String finish();

  void abort();
}

class DartFileTransferDigest implements FileTransferDigest {
  DartFileTransferDigest() {
    _input = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {
        _digest = digests.single;
      }),
    );
  }

  late final ByteConversionSink _input;
  late Digest _digest;
  bool _finished = false;

  @override
  void add(
    Uint8List bytes, {
    Object? anchor,
    bool consumeNativeOwnership = false,
  }) {
    if (_finished) {
      throw StateError('File transfer digest is already finalized');
    }
    _input.add(bytes);
  }

  @override
  String finish() {
    if (!_finished) {
      _finished = true;
      _input.close();
    }
    return _digest.toString();
  }

  @override
  void abort() {
    if (_finished) {
      return;
    }
    _finished = true;
    _input.close();
  }
}

String encodeSha256Digest(Uint8List digest) =>
    digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
