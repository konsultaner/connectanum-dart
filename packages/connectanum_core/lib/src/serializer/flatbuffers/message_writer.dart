import 'dart:typed_data';
import 'dart:collection';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

import 'message_projection.dart';
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
    fields['metadata'] = _encode(projection.dictionary, maximumBytes: 1048576);
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
      body['args'] = _encode(message.wireArguments);
    }
    if (argumentsKeywordsVector != null) {
      body['kwargs'] = argumentsKeywordsVector;
    } else if (lazy.encoding == LazyPayloadEncoding.cbor &&
        lazy.argumentsKeywordsBytes != null) {
      body['kwargs'] = lazy.argumentsKeywordsBytes;
    } else if (message.wireArgumentsKeywords != null) {
      body['kwargs'] = _encode(message.wireArgumentsKeywords);
    }
  } else if (argumentsVector != null ||
      argumentsKeywordsVector != null ||
      payloadVector != null) {
    throw ArgumentError('This WAMP message has no payload vectors');
  }
  return writeWampFlatBufferFields(fields, builder);
}

Uint8List _encode(Object? value, {int maximumBytes = 67108864}) {
  _CborInputBudget(maximumBytes).visit(value, 0);
  final bytes = cbor.encode(CborValue(value));
  if (bytes.length > maximumBytes) {
    throw ArgumentError(
      'Encoded FlatBuffers CBOR value exceeds the byte limit',
    );
  }
  return Uint8List.fromList(bytes);
}

/// Bound construction work before entering the recursive CBOR encoder. The
/// byte count is a lower bound; the exact encoded length is checked afterward.
class _CborInputBudget {
  _CborInputBudget(this.maximumBytes);
  final int maximumBytes;
  final active = HashSet<Object>.identity();
  int items = 0;
  int minimumBytes = 0;

  void charge(int bytes) {
    minimumBytes += bytes;
    if (minimumBytes > maximumBytes || ++items > 1000000) {
      throw ArgumentError(
        'FlatBuffers CBOR input exceeds the construction budget',
      );
    }
  }

  void visit(Object? value, int depth) {
    if (value is Uint8List) {
      charge(value.length + 1);
    } else if (value is String) {
      charge(value.length + 1);
    } else if (value is List || value is Map) {
      charge(1);
      if (depth >= 64 || !active.add(value!)) {
        throw ArgumentError(
          'FlatBuffers CBOR input is cyclic or too deeply nested',
        );
      }
      try {
        if (value is List) {
          for (final item in value) {
            visit(item, depth + 1);
          }
        } else {
          for (final entry in (value as Map).entries) {
            visit(entry.key, depth + 1);
            visit(entry.value, depth + 1);
          }
        }
      } finally {
        active.remove(value);
      }
    } else if (value is DateTime) {
      // The shared CBOR codec represents dates as tagged ISO-8601 strings.
      charge(value.toIso8601String().length + 2);
    } else if (value is BigInt) {
      charge((value.bitLength + 7) ~/ 8 + 1);
    } else if (value == null || value is bool || value is num) {
      charge(1);
    } else {
      throw UnsupportedError('Unsupported WAMP value ${value.runtimeType}');
    }
  }
}
