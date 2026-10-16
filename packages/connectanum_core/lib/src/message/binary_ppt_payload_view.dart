import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show LazyPayloadEncoding;

/// Retain an exact, definite singleton binary argument without decoding its body.
/// Unsupported containers and malformed ranges leave validation to the caller's
/// existing decoder. The view retains the input storage and is immutable.
Uint8List? binaryPptArgumentView(
  LazyPayloadEncoding encoding,
  Uint8List bytes,
) {
  if (bytes.length < 2) return null;
  final marker = bytes[1];
  var width = 0;
  var length = 0;
  switch (encoding) {
    case LazyPayloadEncoding.cbor:
      if (bytes[0] != 0x81 || marker >> 5 != 2) return null;
      final info = marker & 31;
      if (info < 24) {
        length = info;
      } else {
        width = switch (info) {
          24 => 1,
          25 => 2,
          26 => 4,
          27 => 8,
          _ => 0,
        };
        if (width == 0) return null;
      }
    case LazyPayloadEncoding.messagePack:
      if (bytes[0] != 0x91) return null;
      width = switch (marker) {
        0xc4 => 1,
        0xc5 => 2,
        0xc6 => 4,
        _ => 0,
      };
      if (width == 0) return null;
    case LazyPayloadEncoding.json:
    case LazyPayloadEncoding.flatbuffers:
      return null;
  }
  var cursor = 2;
  if (width > bytes.length - cursor) return null;
  final maximumPrefix = bytes.length ~/ 256;
  final maximumLastByte = bytes.length % 256;
  for (var index = 0; index < width; index++) {
    final byte = bytes[cursor++];
    if (length > maximumPrefix ||
        (length == maximumPrefix && byte > maximumLastByte)) {
      return null;
    }
    length = length * 256 + byte;
  }
  if (length != bytes.length - cursor) return null;
  return Uint8List.sublistView(bytes, cursor).asUnmodifiableView();
}
