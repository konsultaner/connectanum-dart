import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json_serializer;

import 'runtime.dart';

const int nativeCanonicalBase64Threshold = 64 * 1024;

void installNativeCanonicalBase64Codecs(AbstractSerializer serializer) {
  if (serializer is! json_serializer.Serializer) {
    return;
  }
  serializer.installCanonicalBase64ByteEncoder(
    _encodeCanonicalBase64WithNative,
  );
  serializer.installCanonicalBase64ByteDecoder(
    _decodeCanonicalBase64WithNative,
  );
}

Uint8List? _encodeCanonicalBase64WithNative(Uint8List input) {
  if (input.length < nativeCanonicalBase64Threshold) {
    return null;
  }
  try {
    return NativeClientRuntime.instance().encodeCanonicalBase64Bytes(input);
  } on NativeTransportException {
    return null;
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

Uint8List? _decodeCanonicalBase64WithNative(
  Uint8List input,
  int start,
  int end,
) {
  try {
    return NativeClientRuntime.instance().decodeCanonicalBase64Bytes(
      input,
      start,
      end,
    );
  } on NativeTransportException {
    return null;
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}
