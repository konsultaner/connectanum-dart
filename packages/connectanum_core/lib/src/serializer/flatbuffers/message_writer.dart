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
/// General Dart values still need CBOR construction and a vector write; a
/// fragmented single binary argument can reuse its bytes after a CBOR prefix.
int writeWampFlatBufferMessage(
  AbstractMessage message,
  fb.Builder builder, {
  FlatBufferByteVectorReference? argumentsVector,
  FlatBufferByteVectorReference? argumentsKeywordsVector,
  FlatBufferByteVectorReference? payloadVector,
  LazyMessagePayload? lazyPayload,
  bool includeApplicationPayload = true,
  List<DeferredFlatBufferVector>? deferredVectors,
}) {
  return writeWampFlatBufferFields(
    prepareWampFlatBufferMessage(
      message,
      argumentsVector: argumentsVector,
      argumentsKeywordsVector: argumentsKeywordsVector,
      payloadVector: payloadVector,
      lazyPayload: lazyPayload,
      includeApplicationPayload: includeApplicationPayload,
      fragmentBinaryArguments: deferredVectors != null,
    ),
    builder,
    deferredVectors: deferredVectors,
  );
}

/// Prepare encoded vectors before selecting the initial envelope capacity.
Map<String, Object?> prepareWampFlatBufferMessage(
  AbstractMessage message, {
  FlatBufferByteVectorReference? argumentsVector,
  FlatBufferByteVectorReference? argumentsKeywordsVector,
  FlatBufferByteVectorReference? payloadVector,
  LazyMessagePayload? lazyPayload,
  bool includeApplicationPayload = true,
  bool fragmentBinaryArguments = false,
  bool fragmentPackedPayload = false,
}) {
  final projection = projectWampFlatBufferMessage(message);
  final fields = projection.fields;
  final body = fields['msg'] as Map<String, Object?>;
  var validateArguments = true;
  var validateKeywords = true;
  if (projection.dictionary != null) {
    fields['metadata'] = encodeWampFlatBufferCbor(
      projection.dictionary,
      maximumBytes: 1048576,
      stringDictionaryKeys: true,
    );
  }
  if (message is AbstractMessageWithPayload) {
    if (!includeApplicationPayload) {
      if (argumentsVector != null ||
          argumentsKeywordsVector != null ||
          payloadVector != null) {
        throw ArgumentError(
          'A control-only message cannot include application vectors',
        );
      }
      return fields;
    }
    final lazy = lazyPayload ?? message.toLazyPayload();
    final source = packedPayloadSourceOf(lazy);
    final payload =
        payloadVector ??
        lazy.transparentBinaryPayload ??
        (fragmentPackedPayload && source is FragmentedPackedPayloadSource
            ? FlatBufferByteVectorParts(source.fragments)
            : lazy.packedPayloadBytes);
    if (payload != null) {
      if (argumentsVector != null || argumentsKeywordsVector != null) {
        throw ArgumentError(
          'Transparent payload cannot also carry args/kwargs',
        );
      }
      body['payload'] = payload;
      return fields;
    }
    final scheme = projection.dictionary?['ppt_scheme'];
    if (argumentsVector == null &&
        argumentsKeywordsVector == null &&
        !lazy.hasEncodedArguments &&
        !lazy.hasEncodedArgumentsKeywords &&
        scheme is String &&
        scheme.isNotEmpty &&
        scheme != 'wamp' &&
        projection.dictionary?['ppt_serializer'] == 'flatbuffers' &&
        projection.dictionary?['ppt_cipher'] == null &&
        projection.dictionary?['ppt_keyid'] == null) {
      final arguments = message.wireArguments;
      if (arguments != null &&
          arguments.length == 1 &&
          arguments.single is Uint8List &&
          message.wireArgumentsKeywords == null) {
        // Session's ordinary PPT path supplies [encodedBytes]. The typed
        // payload is already complete: retain it directly, without a CBOR
        // array/byte-string prefix that would misalign its application data.
        // Read the live wrapper so in-place edits cannot reuse stale bytes.
        body['payload'] = arguments.single;
        return fields;
      }
    }
    Map<String, dynamic>? wireKeywords;
    var readKeywords = false;
    if (argumentsVector != null) {
      body['args'] = argumentsVector;
    } else if (lazy.encoding == LazyPayloadEncoding.cbor &&
        lazy.argumentsBytes != null) {
      body['args'] = lazy.argumentsBytes;
    } else {
      final arguments = message.wireArguments;
      if (arguments != null) {
        if (fragmentBinaryArguments &&
            argumentsKeywordsVector == null &&
            lazy.argumentsKeywordsBytes == null &&
            arguments.length == 1 &&
            arguments.single is Uint8List) {
          wireKeywords = message.wireArgumentsKeywords;
          readKeywords = true;
          if (wireKeywords == null) {
            // WAMP's args vector contains CBOR. A single binary argument can
            // be represented by a short CBOR prefix plus its original bytes,
            // including when those bytes are encrypted PPT ciphertext.
            final bytes = arguments.single as Uint8List;
            body['args'] = FlatBufferByteVectorParts([
              _cborBinaryArgumentPrefix(bytes.length),
              bytes,
            ]);
          }
        }
        if (body['args'] == null) {
          body['args'] = encodeWampFlatBufferCbor(arguments);
          // This CBOR array was built from bounded Dart values by the encoder.
          // Raw lazy CBOR below still crosses the structural validator.
          validateArguments = false;
        }
      }
    }
    if (argumentsKeywordsVector != null) {
      body['kwargs'] = argumentsKeywordsVector;
    } else if (lazy.encoding == LazyPayloadEncoding.cbor &&
        lazy.argumentsKeywordsBytes != null) {
      body['kwargs'] = lazy.argumentsKeywordsBytes;
    } else {
      final keywords = readKeywords
          ? wireKeywords
          : message.wireArgumentsKeywords;
      if (keywords != null) {
        final scalar = tryEncodeWampFlatBufferScalarKeywordMap(keywords);
        if (scalar != null) {
          body['kwargs'] = scalar;
          // This narrow encoder validates its complete scalar map. Raw lazy
          // bytes and complex maps still use the structural validator below.
          validateKeywords = false;
        } else {
          body['kwargs'] = encodeWampFlatBufferCbor(keywords);
        }
      }
    }
  } else if (argumentsVector != null ||
      argumentsKeywordsVector != null ||
      payloadVector != null) {
    throw ArgumentError('This WAMP message has no payload vectors');
  }
  if (validateArguments) {
    if (body['args'] case final Uint8List args) {
      if (!isValidatedFlatBufferCborSpan(args, rootMajor: 4)) {
        validateFlatBufferCbor(args, rootMajor: 4);
      }
    }
  }
  if (validateKeywords) {
    if (body['kwargs'] case final Uint8List kwargs) {
      if (!isValidatedFlatBufferCborSpan(
        kwargs,
        rootMajor: 5,
        rootStringDictionaryKeys: true,
      )) {
        validateFlatBufferCbor(
          kwargs,
          rootMajor: 5,
          rootStringDictionaryKeys: true,
        );
      }
    }
  }
  return fields;
}

Uint8List _cborBinaryArgumentPrefix(int length) {
  if (length > 67108864) {
    throw ArgumentError('FlatBuffers binary argument exceeds the byte limit');
  }
  if (length < 24) return Uint8List.fromList([0x81, 0x40 | length]);
  if (length <= 255) return Uint8List.fromList([0x81, 0x58, length]);
  if (length <= 65535) {
    return Uint8List.fromList([0x81, 0x59, length >> 8, length & 255]);
  }
  final prefix = Uint8List(6)
    ..[0] = 0x81
    ..[1] = 0x5a;
  ByteData.sublistView(prefix).setUint32(2, length, Endian.big);
  return prefix;
}
