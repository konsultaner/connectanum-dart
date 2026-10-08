part of '../../../native_buffers.dart';

typedef _SendOwnedSegmentsN =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Pointer<ffi.Int32>,
      ffi.UintPtr,
    );
typedef _SendOwnedSegmentsD =
    int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Int32>, int);

/// Optional native submission of already encoded CBOR/MessagePack/JSON frames.
/// FlatBuffers transports use NativeFrameTransport to validate their profile.
abstract interface class NativeSegmentedBufferTransport
    implements NativeBufferTransport {
  void sendEncodedNativeBufferSegments(List<NativeOwnedBuffer> segments);
  NativeWriteReceipt sendEncodedNativeBufferSegmentsTracked(
    List<NativeOwnedBuffer> segments,
  );
}

extension NativeOwnedSegmentSubmission on NativeBufferAllocator {
  bool get supportsSegmentedBuffers => _segments != null;

  /// Queues one complete encoded frame, retaining 1–64 frozen native spans.
  /// At least one span must be nonempty. Caller handles remain valid on both
  /// success and rejection; callers may dispose them after acceptance. This
  /// copies no payload bytes and does not parse or transcode the wire encoding.
  void sendSegments(int connectionId, List<NativeOwnedBuffer> segments) {
    _check(_ownedSegments.submit(connectionId, segments, tracked: false));
  }

  /// Reports queue acceptance and complete local write/flush, not peer delivery.
  /// Disposing the receipt does not cancel the queued frame or consume inputs.
  NativeWriteReceipt sendSegmentsTracked(
    int connectionId,
    List<NativeOwnedBuffer> segments,
  ) {
    final id = _ownedSegments.submit(connectionId, segments, tracked: true);
    _check(id);
    if (id == 0) throw StateError('Native writer returned no receipt');
    return NativeWriteReceipt._(this, id);
  }

  _NativeOwnedSegmentsApi get _ownedSegments =>
      _segments ??
      (throw UnsupportedError('Native owned-segment ABI v1 is unavailable'));
}

// A List alone has no Finalizable lifetime guarantee. Keep every input wrapper
// strongly reachable until the native call has retained its frozen allocation.
final class _OwnedSegmentInputs implements ffi.Finalizable {
  _OwnedSegmentInputs(List<NativeOwnedBuffer> parts)
    : parts = List<NativeOwnedBuffer>.of(parts, growable: false);
  final List<NativeOwnedBuffer> parts;
}

final class _NativeOwnedSegmentsApi {
  _NativeOwnedSegmentsApi(this.owner, ffi.DynamicLibrary library)
    : _send = library.lookupFunction<_SendOwnedSegmentsN, _SendOwnedSegmentsD>(
        'ct_owned_buffer_send_segments',
      ),
      _sendTracked = library
          .lookupFunction<_SendOwnedSegmentsN, _SendOwnedSegmentsD>(
            'ct_owned_buffer_send_segments_tracked',
          );

  final NativeBufferAllocator owner;
  final _SendOwnedSegmentsD _send;
  final _SendOwnedSegmentsD _sendTracked;

  static _NativeOwnedSegmentsApi? load(
    NativeBufferAllocator owner,
    ffi.DynamicLibrary library,
  ) {
    const symbols = [
      'ct_owned_buffer_segments_abi_version',
      'ct_owned_buffer_send_segments',
      'ct_owned_buffer_send_segments_tracked',
    ];
    if (!owner.supportsExternalTokens ||
        !owner.supportsWriteCompletion ||
        !symbols.every(library.providesSymbol) ||
        library.lookupFunction<_VersionN, _VersionD>(symbols[0])() != 1) {
      return null;
    }
    return _NativeOwnedSegmentsApi(owner, library);
  }

  int submit(
    int connectionId,
    List<NativeOwnedBuffer> segments, {
    required bool tracked,
  }) {
    final inputs = _OwnedSegmentInputs(segments);
    final parts = inputs.parts;
    RangeError.checkValueInInterval(
      connectionId,
      1,
      0x7fffffff,
      'connectionId',
    );
    RangeError.checkValueInInterval(parts.length, 1, 64, 'segments.length');
    for (final segment in parts) {
      owner.validateFrozenBuffer(segment);
    }
    if (parts.every((segment) => segment.length == 0)) {
      throw ArgumentError('An encoded frame must contain bytes');
    }
    final handles = calloc<ffi.Int32>(parts.length);
    try {
      for (var index = 0; index < parts.length; index++) {
        handles[index] = parts[index]._handle.id;
      }
      return (tracked ? _sendTracked : _send)(
        owner._externalIdentity,
        connectionId,
        handles,
        parts.length,
      );
    } finally {
      calloc.free(handles);
    }
  }
}
