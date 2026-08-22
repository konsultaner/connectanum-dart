import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _externalRoots = Expando<_NativeExternalByteBuffer>(
  'connectanum.native.external-root',
);
final _externalAnchors = Expando<_NativeExternalByteBuffer>(
  'connectanum.native.external-anchor',
);

final class _NativeExternalByteBuffer {
  const _NativeExternalByteBuffer(
    this.pointer,
    this.baseOffsetInBytes,
    this.lengthInBytes,
  );

  final ffi.Pointer<ffi.Uint8> pointer;
  final int baseOffsetInBytes;
  final int lengthInBytes;
}

final class NativeExternalByteSlice {
  const NativeExternalByteSlice({
    required this.pointer,
    required this.length,
    required this.owner,
  });

  final ffi.Pointer<ffi.Uint8> pointer;
  final int length;

  /// Keeps the external typed-data view and its FFI finalizer alive through
  /// synchronous native reads.
  final Object owner;
}

/// Allocates an uninitialized byte buffer whose storage follows its typed-data
/// views after the frame has been decoded.
Uint8List allocateNativeExternalBytes(int length) {
  if (length < 0) {
    throw RangeError.range(length, 0, null, 'length');
  }
  if (length == 0) {
    return Uint8List(0);
  }
  final pointer = malloc<ffi.Uint8>(length);
  Uint8List bytes;
  try {
    // Attach the allocator finalizer to the external typed-data allocation so
    // subviews keep the storage alive even after the root list is unreachable.
    bytes = pointer.asTypedList(
      length,
      finalizer: malloc.nativeFree,
      token: pointer.cast(),
    );
  } catch (_) {
    malloc.free(pointer);
    rethrow;
  }
  final owner = _NativeExternalByteBuffer(
    pointer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  _externalRoots[bytes] = owner;
  return bytes;
}

/// Retains the allocation behind [rootBytes] for the lifetime of [anchor].
void retainNativeExternalBytes(Object anchor, Uint8List rootBytes) {
  final owner = _externalRoots[rootBytes];
  if (owner != null) {
    _externalAnchors[anchor] = owner;
  }
}

bool hasRetainedNativeExternalBytes(Object anchor) {
  return _externalAnchors[anchor] != null;
}

/// Resolves [bytes] to validated native storage retained by [anchor].
NativeExternalByteSlice? nativeExternalByteSlice(
  Uint8List bytes, {
  Object? anchor,
}) {
  final owner =
      (anchor == null ? null : _externalAnchors[anchor]) ??
      _externalAnchors[bytes] ??
      _externalRoots[bytes];
  if (owner == null) {
    return null;
  }
  final start = bytes.offsetInBytes;
  final end = start + bytes.lengthInBytes;
  final registeredEnd = owner.baseOffsetInBytes + owner.lengthInBytes;
  if (start < owner.baseOffsetInBytes || end > registeredEnd) {
    return null;
  }
  return NativeExternalByteSlice(
    pointer: owner.pointer + (start - owner.baseOffsetInBytes),
    length: bytes.lengthInBytes,
    owner: bytes,
  );
}
