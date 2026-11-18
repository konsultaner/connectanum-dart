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

/// Owns large MQTT frame bodies independently of the runtime and its buffers.
/// The SDK accounts their external bytes and retains the backing through views.
final class NativeMqttFrameBufferAllocator {
  factory NativeMqttFrameBufferAllocator.forLibrary(
    ffi.DynamicLibrary library,
  ) => _libraries.putIfAbsent(
    library.handle.address,
    () => NativeMqttFrameBufferAllocator._(library),
  );

  NativeMqttFrameBufferAllocator._(this._library);

  // Keep callback code loaded even after the runtime and allocator are dropped.
  static final _libraries = <int, NativeMqttFrameBufferAllocator>{};
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
