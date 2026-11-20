import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json_serializer;

import 'runtime.dart';

const int nativeCanonicalBase64Threshold = 64 * 1024;

void installNativeCanonicalBase64Codecs(
  AbstractSerializer serializer, {
  bool reserveWebSocketEnvelope = false,
}) {
  if (serializer is! json_serializer.Serializer) {
    return;
  }
  serializer.installCanonicalBase64ByteEncoder(
    _encodeCanonicalBase64WithNative,
    envelopeEncoder: reserveWebSocketEnvelope
        ? _encodeCanonicalBase64FrameWithNative
        : null,
  );
  serializer.installCanonicalBase64ByteDecoder(
    _decodeCanonicalBase64WithNative,
    stringDecoder: _decodeCanonicalBase64WithNative,
  );
}

final _transportFrameSlots = Expando<_TransportFrameSlot>();

class _TransportFrameSlot {
  _TransportFrameSlot(this.bytes, this.start, this.end);
  final Uint8List bytes;
  final int start;
  final int end;
  bool used = false;
}

({Uint8List bytes, int copiedBytes})? takeNativeCanonicalBase64Frame(
  List<Uint8List> fragments,
) {
  if (fragments.length != 3) return null;
  final body = fragments[1];
  final slot = _transportFrameSlots[body];
  if (slot == null || slot.used) return null;
  final prefix = fragments[0], suffix = fragments[2];
  if (prefix.length > slot.start ||
      suffix.length > slot.bytes.length - slot.end)
    return null;
  assert(body.offsetInBytes == slot.bytes.offsetInBytes + slot.start);
  assert(body.length == slot.end - slot.start);
  slot.used = true;
  final start = slot.start - prefix.length, end = slot.end + suffix.length;
  slot.bytes.setRange(start, slot.start, prefix);
  slot.bytes.setRange(slot.end, end, suffix);
  return (
    bytes: Uint8List.sublistView(slot.bytes, start, end),
    copiedBytes: prefix.length + suffix.length,
  );
}

Uint8List? _encodeCanonicalBase64FrameWithNative(
  Uint8List input,
  int prefix,
  int suffix,
) => prefix <= 4096 && suffix <= 4096
    ? _encodeTransportBase64(input, prefix, suffix)
    : null;
Uint8List? _encodeCanonicalBase64WithNative(Uint8List input) =>
    _encodeTransportBase64(input, 0, 0);
Uint8List? _encodeTransportBase64(Uint8List input, int prefix, int suffix) {
  final reserve = prefix != 0 || suffix != 0;
  if (input.length < nativeCanonicalBase64Threshold) {
    return null;
  }
  try {
    final runtime = NativeClientRuntime.instance();
    final encoded = runtime.tryEncodeCanonicalBase64TransportBytes(
      input,
      prefix: prefix,
      suffix: suffix,
    );
    if (encoded != null) {
      if (!reserve) return encoded.bytes;
      final body = Uint8List.sublistView(
        encoded.bytes,
        encoded.start,
        encoded.end,
      );
      _transportFrameSlots[body] = _TransportFrameSlot(
        encoded.bytes,
        encoded.start,
        encoded.end,
      );
      return body;
    }
    return runtime.encodeCanonicalBase64Bytes(input);
  } on NativeTransportException {
    return null;
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

Uint8List? _decodeCanonicalBase64WithNative(Object input, int start, int end) {
  try {
    final runtime = NativeClientRuntime.instance();
    if (input is String) {
      return runtime.decodeCanonicalBase64String(input, start, end);
    }
    return runtime.decodeCanonicalBase64Bytes(input as Uint8List, start, end);
  } on NativeTransportException {
    return null;
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}
