import 'dart:typed_data';

import '../../message/fragmented_payload_source.dart';
import '../owned_copy_metrics.dart';
import 'runtime.dart';
import 'wire_writer.dart' show FlatBufferByteVectorReference;

/// Builds an application FlatBuffer with one borrowed byte vector at its tail.
///
/// Use the supplied builder and vector offset in the application's generated
/// table builder; return its root offset without finishing or resetting it.
/// The application owns its schema. The vector uses normal byte alignment.
///
/// The small prefix is snapshotted so escaped builder views cannot change it.
/// The original bytes stay borrowed and must remain valid and unchanged until
/// every consumer finishes. This does not acquire an external/native lease.
PackedPayloadParts buildFlatBufferPayloadParts({
  required Uint8List bytes,
  required int Function(
    WampFlatBufferBuilder builder,
    FlatBufferByteVectorReference vector,
  )
  buildRoot,
  String? fileIdentifier,
}) {
  const maximumBytes = 64 * 1024 * 1024;
  if (fileIdentifier != null &&
      (fileIdentifier.length != 4 ||
          fileIdentifier.codeUnits.any((unit) => unit > 127))) {
    throw ArgumentError.value(
      fileIdentifier,
      'fileIdentifier',
      'Expected exactly four ASCII characters',
    );
  }
  if (bytes.length > maximumBytes) {
    throw ArgumentError('FlatBuffers payload exceeds the byte limit');
  }
  final builder = WampFlatBufferBuilder(
    initialSize: 128,
    deduplicateTables: false,
  );
  // Keep the alignment effect of the full vector without allocating its body.
  // FlatBuffers scalar alignment and a four-byte identifier need at most eight.
  final virtualTail = ((bytes.length + 3) & ~3) & 7;
  final vector = FlatBufferByteVectorReference(
    builder,
    builder.writeListUint8(Uint8List(virtualTail)),
  );
  final root = buildRoot(builder, vector);
  if (root < 4 || root > builder.offset) {
    throw ArgumentError('Application root is outside the supplied builder');
  }
  builder.finish(root, fileIdentifier);
  final storage = builder.buffer;
  if (storage.length < virtualTail + 4) {
    throw StateError('Application builder lost its borrowed vector');
  }
  final prefix = Uint8List.sublistView(
    storage,
    0,
    storage.length - virtualTail,
  );
  final data = ByteData.sublistView(prefix);
  if (data.getUint32(prefix.length - 4, Endian.little) != virtualTail) {
    throw StateError('Application builder changed its borrowed vector');
  }
  final padding = (-bytes.length) & 3;
  if (prefix.length + bytes.length + padding > maximumBytes) {
    throw ArgumentError('FlatBuffers payload exceeds the byte limit');
  }
  data.setUint32(prefix.length - 4, bytes.length, Endian.little);
  return PackedPayloadParts([
    OwnedCopyMetrics.copyBytes(prefix).asUnmodifiableView(),
    bytes,
    if (padding != 0) Uint8List(padding).asUnmodifiableView(),
  ]);
}
