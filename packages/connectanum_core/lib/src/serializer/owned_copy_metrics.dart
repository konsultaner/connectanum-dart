import 'dart:typed_data';

/// Physical buffer operations expressed in logical source bytes. Scalar field
/// encoding, object references and dependency-internal work are not buffer copies.
enum OwnedCopyKind {
  clone,
  coalescing,
  flatBufferVector,
  flatBufferGrowth,
  isolateTransfer,
  framing,
  keyMaterial,
  pptSerializer,
  portableCrypto,
}

/// Opt-in, cumulative, isolate-local observations. Enable before creating router
/// workers; snapshots from distinct isolates must retain distinct identities.
abstract final class OwnedCopyMetrics {
  static bool _enabled = false;
  static int _suspended = 0;
  static int _failedCopies = 0;
  static int _unmeasuredCopies = 0;
  static int _encodedWampBytes = 0;
  static int _rejectedWampSubmissions = 0;
  static final _bytes = List<int>.filled(OwnedCopyKind.values.length, 0);
  static const fields = [
    'clone_copy_bytes',
    'coalescing_copy_bytes',
    'flatbuffer_vector_copy_bytes',
    'flatbuffer_growth_copy_bytes',
    'isolate_transfer_copy_bytes',
    'framing_copy_bytes',
    'key_material_copy_bytes',
    'ppt_serializer_copy_bytes',
    'portable_crypto_copy_bytes',
  ];

  static bool get enabled => _enabled;
  static void enable() => _enabled = true;

  /// Serialized message volume accepted by the Dart send boundary. This is
  /// separate from buffer copies and excludes transport headers and TLS records.
  static void recordEncodedWampSubmission(Object payload) {
    if (!_enabled) return;
    if (payload is List<int>) {
      _encodedWampBytes += payload.length;
    } else if (payload is String) {
      // Browser WebSocket sends a UTF-8 USVString. Count without encoding a
      // second buffer; lone surrogates become three-byte replacement characters.
      var bytes = 0;
      for (var i = 0; i < payload.length; i++) {
        final unit = payload.codeUnitAt(i);
        if (unit < 0x80) {
          bytes++;
        } else if (unit < 0x800) {
          bytes += 2;
        } else if (unit >= 0xd800 &&
            unit <= 0xdbff &&
            i + 1 < payload.length &&
            payload.codeUnitAt(i + 1) >= 0xdc00 &&
            payload.codeUnitAt(i + 1) <= 0xdfff) {
          bytes += 4;
          i++;
        } else {
          bytes += 3;
        }
      }
      _encodedWampBytes += bytes;
    } else {
      throw ArgumentError.value(
        payload,
        'payload',
        'expected encoded bytes or text',
      );
    }
  }

  static void recordEncodedWampSubmissionLength(int length) {
    if (_enabled) {
      if (length < 0) throw ArgumentError.value(length, 'length');
      _encodedWampBytes += length;
    }
  }

  static void recordRejectedWampSubmission() {
    if (_enabled) _rejectedWampSubmissions++;
  }

  /// Adds independent message-volume carriers without changing copy snapshots.
  static Map<String, int>? boundarySnapshot() => !_enabled
      ? null
      : {
          ...snapshot()!,
          'encoded_wamp_volume_version': 1,
          'encoded_wamp_bytes_accepted': _encodedWampBytes,
          'encoded_wamp_send_rejections': _rejectedWampSubmissions,
        };

  static void record(OwnedCopyKind kind, int bytes) {
    if (_enabled && _suspended == 0) {
      if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
      _bytes[kind.index] += bytes;
    }
  }

  /// Dedicated synchronous scopes suppress generic primitives, then report
  /// their actual copies here once. These bytes are a subset of any separate
  /// PPT/provider diagnostic breakdown, never an additional component to add.
  static void recordDedicated(OwnedCopyKind kind, int bytes) {
    if (_enabled) {
      if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
      _bytes[kind.index] += bytes;
    }
  }

  /// Synchronous dedicated counters (such as PPT) own these operations instead.
  static T withoutRecording<T>(T Function() operation) {
    _suspended++;
    try {
      return operation();
    } finally {
      _suspended--;
    }
  }

  static Map<String, int>? snapshot() => !_enabled
      ? null
      : {
          for (var i = 0; i < fields.length; i++) fields[i]: _bytes[i],
          'failed_copy_operations': _failedCopies,
          'unmeasured_copy_operations': _unmeasuredCopies,
        };

  /// A dedicated scope hid generic primitives whose failed partial work is
  /// unknown. Retain that failure even while its ordinary records are suspended.
  static void recordDedicatedFailure() {
    if (_enabled) _failedCopies++;
  }

  /// Failed dependency primitives can have copied an unknown prefix. Such a
  /// window cannot claim a complete total from its successful operations.
  static void recordFailedCopy() {
    if (_enabled && _suspended == 0) _failedCopies++;
  }

  /// An arbitrary backing allocator can relocate or remap storage differently.
  /// Its retained front/back lengths are not proof of its physical copies.
  static void recordUnmeasuredCopy() {
    if (_enabled && _suspended == 0) _unmeasuredCopies++;
  }

  static Uint8List copyBytes(
    List<int> input, {
    OwnedCopyKind kind = OwnedCopyKind.clone,
  }) {
    try {
      final result = Uint8List.fromList(input);
      record(kind, result.length);
      return result;
    } catch (_) {
      recordFailedCopy();
      rethrow;
    }
  }

  static List<int> copyByteValues(Uint8List input) {
    try {
      final result = input.toList();
      record(OwnedCopyKind.clone, result.length);
      return result;
    } catch (_) {
      recordFailedCopy();
      rethrow;
    }
  }
}

/// Retain typed fragments until materialization. Copy operations live here so
/// observation does not infer BytesBuilder implementation details from wire size.
class CopyAwareBytesBuilder implements BytesBuilder {
  static final _empty = Uint8List(0);
  final List<Uint8List> _chunks = [];
  int _length = 0;

  @override
  void add(List<int> bytes) {
    if (bytes.isEmpty) return;
    final typed = bytes is Uint8List
        ? bytes
        : OwnedCopyMetrics.copyBytes(bytes);
    _chunks.add(typed);
    _length += typed.length;
  }

  @override
  void addByte(int byte) => add(Uint8List(1)..[0] = byte);

  @override
  Uint8List takeBytes() {
    final result = _chunks.length == 1 ? _chunks.single : toBytes();
    clear();
    return result;
  }

  @override
  Uint8List toBytes() {
    if (_length == 0) return _empty;
    final result = Uint8List(_length);
    var offset = 0;
    for (final chunk in _chunks) {
      try {
        result.setRange(offset, offset + chunk.length, chunk);
      } catch (_) {
        OwnedCopyMetrics.recordFailedCopy();
        rethrow;
      }
      OwnedCopyMetrics.record(OwnedCopyKind.coalescing, chunk.length);
      offset += chunk.length;
    }
    return result;
  }

  @override
  int get length => _length;
  @override
  bool get isEmpty => _length == 0;
  @override
  bool get isNotEmpty => !isEmpty;
  @override
  void clear() {
    _chunks.clear();
    _length = 0;
  }
}

/// The allocator records its own actual successful moves in OwnedCopyMetrics.
/// Unknown implementations must remain unmeasured instead of assuming that
/// requested preserved ranges imply a physical copy.
abstract interface class CopyObservedAllocator {}

/// Byte-vector methods report their own successful writes and failed operations.
abstract interface class CopyObservedByteVectorBuilder {}
