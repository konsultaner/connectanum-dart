import 'dart:typed_data';

import '../../message/abstract_message.dart';
import '../../message/abstract_message_with_payload.dart';
import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';
import 'message_reader.dart';
import 'message_projection.dart';
import 'cbor_encoding.dart';
import 'cbor_validation.dart';
import 'dictionary_retention.dart';
import 'message_writer.dart';
import 'runtime.dart';
import 'wire_writer.dart';

/// The pinned Connectanum WAMP FlatBuffers binding.
///
/// Dynamic WAMP arguments use CBOR vectors inside a FlatBuffers envelope.
/// Decoded vectors borrow the input, which must remain unchanged while the
/// message is used. Native read-only buffers can retain their backing owner.
/// Transport capability negotiation is separate from this stateless codec.
class Serializer extends AbstractSerializer {
  @override
  Uint8List serialize(AbstractMessage message) {
    final fields = prepareWampFlatBufferMessage(message);
    final body = fields['msg'] as Map<String, Object?>;
    var vectorBytes = (fields['metadata'] as Uint8List?)?.length ?? 0;
    for (final value in body.values) {
      if (value is Uint8List) vectorBytes += value.length;
    }
    // Encoding already produced these vectors. Reserve their bytes once instead
    // of growing a small envelope to twice the large application payload size.
    final builder = WampFlatBufferBuilder(
      initialSize: vectorBytes > 1024 ? (vectorBytes + 1024 + 7) & ~7 : 1024,
    );
    builder.finish(writeWampFlatBufferFields(fields, builder));
    final bytes = builder.buffer;
    if (bytes.length > 64 * 1024 * 1024) {
      throw ArgumentError('FlatBuffers frame exceeds the byte limit');
    }
    return bytes;
  }

  /// Encode one WAMP frame while retaining its encoded application byte views.
  /// Concatenate the fragments in order; each fragment is part of that frame.
  /// Keep their backing owners and contents valid until transmission completes.
  /// General Dart arguments still require CBOR encoding before composition.
  /// A single binary WAMP argument, including opaque encrypted ciphertext,
  /// can retain its bytes after a small CBOR prefix.
  @override
  List<Uint8List>? serializeFragments(AbstractMessage message) {
    if (message is! AbstractMessageWithPayload) return null;
    final fields = prepareWampFlatBufferMessage(
      message,
      fragmentBinaryArguments: true,
    );
    final body = fields['msg'] as Map<String, Object?>;
    final payload = body['payload'];
    if (payload is Uint8List) {
      final builder = WampFlatBufferBuilder();
      // The builder grows backwards. An empty vector written first places its
      // length word at the end of the envelope, directly before the body span.
      final vector = builder.writeListUint8(const <int>[]);
      body['payload'] = FlatBufferByteVectorReference(builder, vector);
      builder.finish(writeWampFlatBufferFields(fields, builder));
      final control = builder.buffer;
      if (vector == 4 && control.length % 8 == 0) {
        if (payload.length > 64 * 1024 * 1024 - control.length) {
          throw ArgumentError('FlatBuffers frame exceeds the byte limit');
        }
        // Both fragments form one FlatBuffer. Its vector length covers the
        // following original body; the root offset at the start stays intact.
        ByteData.sublistView(
          control,
        ).setUint32(control.length - 4, payload.length, Endian.little);
        return [control, payload];
      }
      // Keep the existing layout if a builder cannot place the original body
      // at an eight-byte wire boundary.
      body['payload'] = payload;
    }
    final builder = WampFlatBufferBuilder();
    final vectors = <DeferredFlatBufferVector>[];
    final root = writeWampFlatBufferFields(
      fields,
      builder,
      deferredVectors: vectors,
    );
    if (vectors.isEmpty) return null;
    return finishWampFlatBufferFragments(builder, root, vectors);
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

  /// Retain immutable, owner-backed native metadata for a forwarding path.
  /// Validation is immediate. Untagged dictionaries defer decoding/snapshots
  /// until a Dart resend; tagged dictionaries keep eager semantic decoding.
  /// [initialMessage] must reconstruct the original control fields without
  /// payloads or retained metadata, independently of later edits to [message].
  /// The native bytes must remain unchanged while the message is alive. A
  /// successful call replaces prior retained metadata; invalid bytes leave it
  /// unchanged. The factory must not re-enter retention on this message.
  void retainNativeMetadata(
    AbstractMessage message,
    Uint8List encodedDictionary,
    AbstractMessage Function() initialMessage,
  ) {
    if (!validateDeferredFlatBufferMetadata(encodedDictionary)) {
      retainMetadata(message, encodedDictionary);
      return;
    }
    retainNativeWampFlatBufferDictionary(
      message,
      encodedDictionary,
      initialMessage,
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
