import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/cbor_serializer.dart' as serializer_cbor;
import 'package:connectanum_core/json_serializer.dart' as serializer_json;
import 'package:connectanum_core/msgpack_serializer.dart' as serializer_msgpack;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'runtime.dart';

AbstractMessage bindMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  final decoded = _serializerFor(serializer).deserialize(bytes);
  if (decoded == null) {
    throw ArgumentError('Failed to deserialize native WAMP message');
  }
  if (decoded is AbstractMessageWithPayload &&
      (argsBytes != null || kwargsBytes != null)) {
    decoded.setLazyPayload(
      argumentsBytes: argsBytes,
      argumentsDecoder: argsBytes == null
          ? null
          : (fragment) => _decodeArgumentList(serializer, fragment),
      argumentsKeywordsBytes: kwargsBytes,
      argumentsKeywordsDecoder: kwargsBytes == null
          ? null
          : (fragment) => _decodeKeywordMap(serializer, fragment),
    );
  }
  return decoded;
}

AbstractSerializer _serializerFor(NativeMessageSerializer serializer) {
  return switch (serializer) {
    NativeMessageSerializer.json => serializer_json.Serializer(),
    NativeMessageSerializer.messagePack => serializer_msgpack.Serializer(),
    NativeMessageSerializer.cbor => serializer_cbor.Serializer(),
    NativeMessageSerializer.ubjson ||
    NativeMessageSerializer.flatbuffers => throw UnsupportedError(
      'Serializer ${serializer.name} is not supported by connectanum_client',
    ),
  };
}

List<dynamic> _decodeArgumentList(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <dynamic>[];
  }
  if (decoded is List) {
    return List<dynamic>.from(decoded);
  }
  throw ArgumentError('Expected a WAMP argument list but got $decoded');
}

Map<String, dynamic> _decodeKeywordMap(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <String, dynamic>{};
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected a WAMP keyword map but got $decoded');
}

Object? _decodeFragment(NativeMessageSerializer serializer, Uint8List bytes) {
  return switch (serializer) {
    NativeMessageSerializer.json => jsonDecode(utf8.decode(bytes)),
    NativeMessageSerializer.messagePack => msgpack.deserialize(bytes),
    NativeMessageSerializer.cbor => cbor.cborDecode(bytes.toList()).toObject(),
    NativeMessageSerializer.ubjson ||
    NativeMessageSerializer.flatbuffers => throw UnsupportedError(
      'Serializer ${serializer.name} is not supported for payload decoding',
    ),
  };
}
