import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _MappedBytes extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;
  @ffi.UintPtr()
  external int length;
  external ffi.Pointer<ffi.Void> owner;
}

typedef _AllocateNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<_MappedBytes>);
typedef _AllocateDart = int Function(int, ffi.Pointer<_MappedBytes>);
typedef _ReleaseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _HandleReleaseNative =
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _ImmutableNative =
    ffi.Handle Function(
      ffi.Int,
      ffi.Pointer<ffi.Void>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
      ffi.IntPtr,
      ffi.Pointer<ffi.NativeFunction<_HandleReleaseNative>>,
    );
typedef _ImmutableDart =
    Object Function(
      int,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.NativeFunction<_HandleReleaseNative>>,
    );

/// Internal carrier; its immutable bytes share storage within an isolate group.
final class NativeByteSnapshot {
  NativeByteSnapshot._(this.bytes);
  final Uint8List bytes;
}

/// Snapshots mutable input once before routing it between internal isolates.
final class NativeIsolateBytes {
  static final _known = Expando<bool>();
  static final _api = ffi.DynamicLibrary.process();
  static final _available = _api.providesSymbol(
    'Dart_NewUnmodifiableExternalTypedDataWithFinalizer',
  );
  static final _immutable = _api
      .lookupFunction<_ImmutableNative, _ImmutableDart>(
        'Dart_NewUnmodifiableExternalTypedDataWithFinalizer',
      );

  static NativeByteSnapshot? transfer(Uint8List bytes) {
    if (_known[bytes] == true) return NativeByteSnapshot._(bytes);
    final allocator = NativeMqttFrameBufferAllocator._snapshotAllocator;
    if (!_available || allocator == null) return null;
    final result = allocator._snapshot(bytes);
    _known[result] = true;
    return NativeByteSnapshot._(result);
  }

  static Uint8List materialize(NativeByteSnapshot snapshot) {
    _known[snapshot.bytes] = true;
    return snapshot.bytes;
  }
}

/// Owns large MQTT frame bodies independently of the runtime and its buffers.
/// The SDK accounts their external bytes and retains the backing through views.
final class NativeMqttFrameBufferAllocator {
  factory NativeMqttFrameBufferAllocator.forLibrary(
    ffi.DynamicLibrary library,
  ) {
    final allocator = _libraries.putIfAbsent(
      library.handle.address,
      () => NativeMqttFrameBufferAllocator._(library),
    );
    if (allocator.supportsMappedBytes &&
        library.providesSymbol(
          'ct_mapped_bytes_handle_finalizer',
        )) {
      _snapshotAllocator = allocator;
    }
    return allocator;
  }

  NativeMqttFrameBufferAllocator._(this._library);

  // Keep callback code loaded even after the runtime and allocator are dropped.
  static final _libraries = <int, NativeMqttFrameBufferAllocator>{};
  static NativeMqttFrameBufferAllocator? _snapshotAllocator;
  final ffi.DynamicLibrary _library;
  late final bool supportsMappedBytes =
      _library.providesSymbol('ct_mapped_bytes_allocate') &&
      _library.providesSymbol('ct_mapped_bytes_finalizer');
  late final _allocate = _library
      .lookupFunction<_AllocateNative, _AllocateDart>(
        'ct_mapped_bytes_allocate',
      );
  late final _finalizer = _library.lookup<ffi.NativeFunction<_ReleaseNative>>(
    'ct_mapped_bytes_finalizer',
  );
  late final _release = _finalizer
      .asFunction<void Function(ffi.Pointer<ffi.Void>)>();
  late final _handleFinalizer = _library
      .lookup<ffi.NativeFunction<_HandleReleaseNative>>(
        'ct_mapped_bytes_handle_finalizer',
      );

  Uint8List _snapshot(Uint8List source) {
    RangeError.checkValueInInterval(source.length, 1, 0x7fffffff, 'length');
    final out = calloc<_MappedBytes>();
    var transferred = false;
    try {
      final result = _allocate(source.length, out);
      if (result < 0) {
        throw StateError('Failed to snapshot binary bytes: $result');
      }
      // This temporary view stays private and is never written after publishing.
      out.ref.data.asTypedList(out.ref.length).setAll(0, source);
      final bytes =
          NativeIsolateBytes._immutable(
                2, // Dart_TypedData_kUint8, from the public VM API.
                out.ref.data.cast(),
                out.ref.length,
                out.ref.owner,
                out.ref.length,
                _handleFinalizer,
              )
              as Uint8List;
      transferred = true;
      return bytes;
    } finally {
      if (!transferred && out.ref.owner != ffi.nullptr) _release(out.ref.owner);
      calloc.free(out);
    }
  }

  Uint8List allocate(int length) {
    RangeError.checkValueInInterval(length, 0, 0x7fffffff, 'length');
    if (length < 16 * 1024) return Uint8List(length);
    if (!supportsMappedBytes) {
      // Older native libraries retain the previous external-byte accounting.
      final bytes = calloc<ffi.Uint8>(length);
      try {
        return bytes.asTypedList(length, finalizer: calloc.nativeFree);
      } catch (_) {
        calloc.free(bytes);
        rethrow;
      }
    }
    final out = calloc<_MappedBytes>();
    var transferred = false;
    try {
      final result = _allocate(length, out);
      if (result < 0) {
        throw StateError('Failed to allocate MQTT frame body: $result');
      }
      final bytes = out.ref.data.asTypedList(
        out.ref.length,
        finalizer: _finalizer,
        token: out.ref.owner,
      );
      transferred = true;
      return bytes;
    } finally {
      if (!transferred && out.ref.owner != ffi.nullptr) _release(out.ref.owner);
      calloc.free(out);
    }
  }
}
