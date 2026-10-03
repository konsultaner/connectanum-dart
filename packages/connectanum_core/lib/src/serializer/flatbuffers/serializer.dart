import 'dart:typed_data';

import '../../message/abstract_message.dart';
import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';
import 'message_reader.dart';
import 'message_projection.dart';
import 'cbor_encoding.dart';
import 'cbor_validation.dart';
import 'dictionary_retention.dart';
import 'message_writer.dart';
import 'runtime.dart';

/// The pinned Connectanum WAMP FlatBuffers binding.
///
/// Dynamic WAMP arguments use CBOR vectors inside a FlatBuffers envelope.
/// Decoded vectors borrow the input, which must remain unchanged while the
/// message is used. Native read-only buffers can retain their backing owner.
/// Transport capability negotiation is separate from this stateless codec.
class Serializer extends AbstractSerializer {
  @override
  Uint8List serialize(AbstractMessage message) {
    final builder = WampFlatBufferBuilder();
    builder.finish(writeWampFlatBufferMessage(message, builder));
    final bytes = builder.buffer;
    if (bytes.length > 64 * 1024 * 1024) {
      throw ArgumentError('FlatBuffers frame exceeds the byte limit');
    }
    return bytes;
  }

  @override
  AbstractMessage? deserialize(Uint8List? message) =>
      message == null ? null : readWampFlatBufferMessage(message);

  /// Decode a validated native metadata dictionary without reading application
  /// vectors. WAMP integers retain their portable value across Dart platforms.
  Map<String, dynamic> deserializeMetadata(Uint8List encodedDictionary) =>
      decodeFlatBufferMetadata(encodedDictionary);

  /// Decode a bounded application CBOR span when a native consumer accesses it.
  /// This preserves the same integer and binary values as [deserialize].
  Object? deserializeApplication(Uint8List encodedValue) =>
      decodeWampFlatBufferApplication(encodedValue);

  /// Preserve the original dictionary when a native bridge reconstructs a
  /// message from routing fields. Application vectors are never materialized.
  void retainMetadata(AbstractMessage message, Uint8List encodedDictionary) {
    retainWampFlatBufferDictionary(
      message,
      encodedDictionary,
      decodeFlatBufferMetadata(encodedDictionary),
    );
  }

  /// Return a bounded, detached logical dictionary, including retained unknown
  /// keys and current model edits. Application vectors are never accessed.
  Map<String, dynamic> metadataFor(AbstractMessage message) =>
      decodeFlatBufferMetadata(
        encodeWampFlatBufferCbor(
          projectWampFlatBufferMessage(message).dictionary ??
              <String, Object?>{},
          maximumBytes: 1024 * 1024,
          stringDictionaryKeys: true,
        ),
      );

  /// Snapshot logical metadata for a reconstructed or decorated message.
  /// This has the same retention semantics as [retainMetadata], with bounded
  /// encoding and detached binary values before any retained state is changed.
  void retainMetadataValues(
    AbstractMessage message,
    Map<String, dynamic> dictionary,
  ) => retainMetadata(
    message,
    encodeWampFlatBufferCbor(
      dictionary,
      maximumBytes: 1024 * 1024,
      stringDictionaryKeys: true,
    ),
  );

  /// A typed FlatBuffers PPT payload is an application-provided byte buffer.
  /// Its schema belongs to the application; this codec does not interpret it.
  /// Dynamic values require their own payload encoding, such as CBOR.
  @override
  Uint8List serializePPT(PPTPayload pptPayload) => serializePPTFragments(
    arguments: pptPayload.arguments,
    argumentsKeywords: pptPayload.argumentsKeywords,
  );

  @override
  Uint8List serializePPTFragments({
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    if (argumentsBytes != null || argumentsKeywordsBytes != null) {
      throw UnsupportedError(
        'Typed FlatBuffers PPT requires a single application byte buffer',
      );
    }
    if (argumentsKeywords != null ||
        arguments?.length != 1 ||
        arguments!.single is! Uint8List) {
      throw UnsupportedError(
        'Typed FlatBuffers PPT requires a single application byte buffer',
      );
    }
    final bytes = arguments.single as Uint8List;
    if (bytes.length > 64 * 1024 * 1024) {
      throw ArgumentError('FlatBuffers PPT payload exceeds the byte limit');
    }
    return bytes;
  }

  @override
  PPTPayload deserializePPT(Uint8List binPayload) {
    if (binPayload.length > 64 * 1024 * 1024) {
      throw const FormatException(
        'FlatBuffers PPT payload exceeds the byte limit',
      );
    }
    return PPTPayload(arguments: [binPayload]);
  }
}
