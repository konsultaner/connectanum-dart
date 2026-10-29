import 'dart:typed_data';

import '../serializer/owned_copy_metrics.dart';
import 'abstract_message_with_payload.dart';

/// One packed value retained as ordered byte views.
///
/// Concatenating [fragments] must produce [bytes]. Keep the storage valid and
/// unchanged while a consumer uses the payload or returned fragments. A Dart
/// reference does not extend an external database transaction's lifetime.
/// Implementing this interface grants no native ownership or pointer trust.
abstract interface class FragmentedPackedPayloadSource
    implements PackedPayloadSource {
  List<Uint8List> get fragments;
}

/// Borrows byte views and coalesces them only when a contiguous value is needed.
///
/// The part list is snapshotted; its underlying storage remains borrowed.
/// Use the lazy payload's toOwned operation for a detached, writable snapshot.
final class PackedPayloadParts implements FragmentedPackedPayloadSource {
  factory PackedPayloadParts(Iterable<Uint8List> fragments) {
    final retained = List<Uint8List>.unmodifiable(fragments);
    var length = 0;
    for (final fragment in retained) {
      if (fragment.length > _maximumBytes - length) {
        throw ArgumentError('Packed payload exceeds the byte limit');
      }
      length += fragment.length;
    }
    return PackedPayloadParts._(retained, length);
  }

  PackedPayloadParts._(this.fragments, this.length);

  static const _maximumBytes = 64 * 1024 * 1024;

  @override
  final List<Uint8List> fragments;
  final int length;
  Uint8List? _bytes;

  @override
  Uint8List get bytes {
    final cached = _bytes;
    if (cached != null) return cached;
    final builder = CopyAwareBytesBuilder();
    for (final fragment in fragments) {
      builder.add(fragment);
    }
    return _bytes = builder.takeBytes().asUnmodifiableView();
  }
}
