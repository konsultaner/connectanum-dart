import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

import 'message_projection.dart';
import 'cbor_encoding.dart';
import 'cbor_validation.dart';
import 'wire_writer.dart';

/// Write a model directly into the supplied builder. The caller finishes and
/// freezes the root, so a guarded native-backed builder can use the same path.
/// References reuse vectors from this build without reading the model payload.
/// Ordinary Dart values still need CBOR construction and a vector write.
int writeWampFlatBufferMessage(
  AbstractMessage message,
  fb.Builder builder, {
  FlatBufferByteVectorReference? argumentsVector,
  FlatBufferByteVectorReference? argumentsKeywordsVector,
  FlatBufferByteVectorReference? payloadVector,
}) {
  final projection = projectWampFlatBufferMessage(message);
  final fields = projection.fields;
  final body = fields['msg'] as Map<String, Object?>;
  if (projection.dictionary != null) {
    fields['metadata'] = encodeWampFlatBufferCbor(
      projection.dictionary,
      maximumBytes: 1048576,
      stringDictionaryKeys: true,
    );
  }
  if (message is AbstractMessageWithPayload) {
    final lazy = message.toLazyPayload();
    final payload =
        payloadVector ??
        lazy.transparentBinaryPayload ??
        lazy.packedPayloadBytes;
    if (payload != null) {
      if (argumentsVector != null || argumentsKeywordsVector != null) {
        throw ArgumentError(
          'Transparent payload cannot also carry args/kwargs',
        );
      }
      body['payload'] = payload;
      return writeWampFlatBufferFields(fields, builder);
    }
    if (argumentsVector != null) {
      body['args'] = argumentsVector;
    } else if (lazy.encoding == LazyPayloadEncoding.cbor &&
        lazy.argumentsBytes != null) {
      body['args'] = lazy.argumentsBytes;
    } else if (message.wireArguments != null) {
      body['args'] = encodeWampFlatBufferCbor(message.wireArguments);
    }
    if (argumentsKeywordsVector != null) {
      body['kwargs'] = argumentsKeywordsVector;
    } else if (lazy.encoding == LazyPayloadEncoding.cbor &&
        lazy.argumentsKeywordsBytes != null) {
      body['kwargs'] = lazy.argumentsKeywordsBytes;
    } else if (message.wireArgumentsKeywords != null) {
      body['kwargs'] = encodeWampFlatBufferCbor(message.wireArgumentsKeywords);
    }
  } else if (argumentsVector != null ||
      argumentsKeywordsVector != null ||
      payloadVector != null) {
    throw ArgumentError('This WAMP message has no payload vectors');
  }
  if (body['args'] case final Uint8List args) {
    validateFlatBufferCbor(args, rootMajor: 4);
  }
  if (body['kwargs'] case final Uint8List kwargs) {
    validateFlatBufferCbor(
      kwargs,
      rootMajor: 5,
      rootStringDictionaryKeys: true,
    );
  }
  return writeWampFlatBufferFields(fields, builder);
}
