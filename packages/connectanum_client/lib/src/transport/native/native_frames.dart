part of '../../../native_buffers.dart';

final class _FrameInfo extends ffi.Struct {
  @ffi.UintPtr()
  external int length;
  @ffi.UintPtr()
  external int segments;
}

typedef _FrameInfoN = ffi.Int32 Function(ffi.Int32, ffi.Pointer<_FrameInfo>);
typedef _FrameInfoD = int Function(int, ffi.Pointer<_FrameInfo>);
typedef _ComposeFrameN =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
    );
typedef _ComposeFrameD =
    int Function(ffi.Pointer<ffi.Void>, int, int, int, int);

/// Optional VM-only support for immutable segmented FlatBuffers frames.
abstract interface class NativeFrameTransport implements NativeBufferTransport {
  void sendNativeFrame(NativeFlatBufferFrame frame, {bool transfer = false});
  NativeWriteReceipt sendNativeFrameTracked(
    NativeFlatBufferFrame frame, {
    bool transfer = false,
  });
}

extension NativeFrameAllocation on NativeBufferAllocator {
  bool get supportsFlatBufferFrames => _frames != null;

  _NativeFrameApi get _frameApi =>
      _frames ??
      (throw UnsupportedError('Native segmented-frame ABI v1 is unavailable'));

  /// Retain a control-only WAMP envelope and independently owned application
  /// buffers. Args/kwargs must be CBOR array/dictionary bytes; opaque payloads
  /// remain uninterpreted. All input buffers stay live on success and failure.
  NativeFlatBufferFrame composeFlatBufferFrame(
    NativeOwnedBuffer control, {
    NativeOwnedBuffer? arguments,
    NativeOwnedBuffer? argumentsKeywords,
    NativeOwnedBuffer? opaquePayload,
  }) => _frameApi.compose(control, arguments, argumentsKeywords, opaquePayload);

  /// Default sends retain the caller's frame. Transfer consumes it upon native
  /// submission, including runtime, serializer, connection and queue rejection.
  void sendFrame(
    int connectionId,
    NativeFlatBufferFrame frame, {
    bool transfer = false,
  }) => _frameApi.send(connectionId, frame, transfer: transfer);

  NativeWriteReceipt sendFrameTracked(
    int connectionId,
    NativeFlatBufferFrame frame, {
    bool transfer = false,
  }) => _frameApi.sendTracked(connectionId, frame, transfer: transfer);
}

/// An immutable frame retaining each original allocation. It has no implicit
/// contiguous bytes getter. Retained frames can be reused for fan-out.
final class NativeFlatBufferFrame implements ffi.Finalizable {
  NativeFlatBufferFrame._(this._handle, this.length, this.segmentCount);
  final _FrameHandle _handle;
  final int length;
  final int segmentCount;
  bool get isDisposed => !_handle.live;

  NativeFlatBufferFrame retain() {
    _handle.check();
    return _handle.api.wrap(_handle.api._retain(_handle.id));
  }

  /// The original immutable control bytes, with an independent view owner.
  /// Application spans remain separate and are not copied or flattened.
  Uint8List get controlBytes {
    _handle.check();
    final api = _handle.api;
    final id = api._control(_handle.id);
    _check(id);
    late final int capacity;
    late final int length;
    try {
      final info = api.owner._getInfoId(id);
      capacity = info.capacity;
      length = info.length;
    } catch (_) {
      api.owner._release(id);
      rethrow;
    }
    final buffer = NativeOwnedBuffer._(
      _OwnedHandle(api.owner, id, externalSize: capacity),
      length,
      0,
      0,
    );
    try {
      return buffer.bytes;
    } finally {
      buffer.dispose();
    }
  }

  void dispose() => _handle.dispose();
}

final class _FrameHandle implements ffi.Finalizable {
  _FrameHandle(this.api, this.id, int length) {
    try {
      api._finalizer.attach(
        this,
        ffi.Pointer<ffi.Void>.fromAddress(id),
        detach: this,
        externalSize: length,
      );
    } catch (_) {
      api._release(id);
      rethrow;
    }
  }
  final _NativeFrameApi api;
  final int id;
  bool live = true;
  void check() {
    if (!live) throw StateError('Native frame was disposed or transferred');
  }

  int consume() {
    check();
    live = false;
    api._finalizer.detach(this);
    return id;
  }

  void dispose() {
    if (!live) return;
    _check(api._release(consume()));
  }
}

final class _NativeFrameApi {
  _NativeFrameApi(this.owner, ffi.DynamicLibrary library) {
    _compose = library.lookupFunction<_ComposeFrameN, _ComposeFrameD>(
      'ct_native_frame_compose',
    );
    _retain = library.lookupFunction<_ReleaseN, _ReleaseD>(
      'ct_native_frame_retain',
    );
    _release = library.lookupFunction<_ReleaseN, _ReleaseD>(
      'ct_native_frame_release',
    );
    _info = library.lookupFunction<_FrameInfoN, _FrameInfoD>(
      'ct_native_frame_info',
    );
    _control = library.lookupFunction<_ReleaseN, _ReleaseD>(
      'ct_native_frame_control',
    );
    _send = library.lookupFunction<_SendN, _SendD>('ct_native_frame_send');
    _sendTracked = library.lookupFunction<_SendN, _SendD>(
      'ct_native_frame_send_tracked',
    );
    _finalizer = _finalizers.putIfAbsent(
      owner._identity,
      () => ffi.NativeFinalizer(
        library.lookup<ffi.NativeFinalizerFunction>(
          'ct_native_frame_finalizer',
        ),
      ),
    );
  }
  static final _finalizers = <int, ffi.NativeFinalizer>{};
  final NativeBufferAllocator owner;
  late final _ComposeFrameD _compose;
  late final _ReleaseD _retain;
  late final _ReleaseD _release;
  late final _FrameInfoD _info;
  late final _ReleaseD _control;
  late final _SendD _send;
  late final _SendD _sendTracked;
  late final ffi.NativeFinalizer _finalizer;

  static _NativeFrameApi? load(
    NativeBufferAllocator owner,
    ffi.DynamicLibrary library,
  ) {
    const symbols = [
      'ct_native_frame_abi_version',
      'ct_native_frame_compose',
      'ct_native_frame_retain',
      'ct_native_frame_release',
      'ct_native_frame_info',
      'ct_native_frame_control',
      'ct_native_frame_send',
      'ct_native_frame_send_tracked',
      'ct_native_frame_finalizer',
    ];
    if (!owner.supportsExternalTokens ||
        !owner.supportsWriteCompletion ||
        !symbols.every(library.providesSymbol) ||
        library.lookupFunction<_VersionN, _VersionD>(symbols[0])() != 1)
      return null;
    return _NativeFrameApi(owner, library);
  }

  NativeFlatBufferFrame wrap(int id) {
    _check(id);
    ffi.Pointer<_FrameInfo> out = ffi.nullptr;
    late final int length;
    late final int segments;
    try {
      out = calloc<_FrameInfo>();
      _check(_info(id, out));
      length = out.ref.length;
      segments = out.ref.segments;
    } catch (_) {
      _release(id);
      rethrow;
    } finally {
      if (out.address != 0) calloc.free(out);
    }
    final handle = _FrameHandle(this, id, length);
    try {
      return NativeFlatBufferFrame._(handle, length, segments);
    } catch (_) {
      handle.dispose();
      rethrow;
    }
  }

  NativeFlatBufferFrame compose(
    NativeOwnedBuffer control,
    NativeOwnedBuffer? args,
    NativeOwnedBuffer? kwargs,
    NativeOwnedBuffer? opaque,
  ) {
    int handle(NativeOwnedBuffer? buffer) {
      if (buffer == null) return 0;
      buffer._handle.check();
      if (buffer._handle.api._identity != owner._identity) {
        throw ArgumentError('Buffer belongs to a different native library');
      }
      return buffer._handle.id;
    }

    return wrap(
      _compose(
        owner._externalIdentity,
        handle(control),
        handle(args),
        handle(kwargs),
        handle(opaque),
      ),
    );
  }

  int submission(int connectionId, NativeFlatBufferFrame frame, bool transfer) {
    RangeError.checkValueInInterval(
      connectionId,
      1,
      0x7fffffff,
      'connectionId',
    );
    frame._handle.check();
    if (frame._handle.api.owner._identity != owner._identity) {
      throw ArgumentError('Frame belongs to a different native library');
    }
    return (transfer ? frame : frame.retain())._handle.consume();
  }

  void send(
    int connectionId,
    NativeFlatBufferFrame frame, {
    required bool transfer,
  }) {
    _check(_send(connectionId, submission(connectionId, frame, transfer)));
  }

  NativeWriteReceipt sendTracked(
    int connectionId,
    NativeFlatBufferFrame frame, {
    required bool transfer,
  }) {
    owner._requireWriteCompletion();
    final id = _sendTracked(
      connectionId,
      submission(connectionId, frame, transfer),
    );
    _check(id);
    if (id == 0) throw StateError('Native writer returned no receipt');
    return NativeWriteReceipt._(owner, id);
  }
}
