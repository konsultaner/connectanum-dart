import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _externalRoots = Expando<_NativeExternalByteBuffer>(
  'connectanum.native.external-root',
);
final _externalAnchors = Expando<_NativeExternalByteBuffer>(
  'connectanum.native.external-anchor',
);
// Retain the source as a finalization token, including in compiled Dart where
// an otherwise unread metadata field does not preserve the source's lifetime.
// The source allocation keeps its sole native-free finalizer.
final _externalAliases = Finalizer<Object>((_) {});

final class _NativeExternalAllocation implements ffi.Finalizable {
  _NativeExternalAllocation(this.pointer, int length) {
    _finalizer.attach(
      this,
      pointer.cast(),
      detach: this,
      externalSize: length,
    );
  }
  static final _finalizer = ffi.NativeFinalizer(malloc.nativeFree);
  final ffi.Pointer<ffi.Uint8> pointer;
  bool released = false;

  void release() {
    if (released) return;
    released = true;
    _finalizer.detach(this);
    malloc.free(pointer);
  }
}

final class _NativeExternalByteBuffer {
  const _NativeExternalByteBuffer(
    this.pointer,
    this.buffer,
    this.baseOffsetInBytes,
    this.lengthInBytes,
    this.allocation,
  );

  final ffi.Pointer<ffi.Uint8> pointer;
  final ByteBuffer buffer;
  final int baseOffsetInBytes;
  final int lengthInBytes;
  final _NativeExternalAllocation allocation;
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
  _NativeExternalAllocation? allocation;
  try {
    allocation = _NativeExternalAllocation(pointer, length);
    final bytes = pointer.asTypedList(length);
    final owner = _NativeExternalByteBuffer(
      pointer,
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
      allocation,
    );
    // The backing external typed data, its ByteBuffer and every derived view
    // retain this owner. An explicit scope end can detach its sole finalizer.
    _externalRoots[bytes] = owner;
    return bytes;
  } catch (_) {
    if (allocation == null) {
      malloc.free(pointer);
    } else {
      allocation.release();
    }
    rethrow;
  }
}

/// Retains the allocation behind [rootBytes] for the lifetime of [anchor].
void retainNativeExternalBytes(Object anchor, Uint8List rootBytes) {
  final owner = _externalRoots[rootBytes];
  if (owner != null && !owner.allocation.released) {
    _externalAnchors[anchor] = owner;
  }
}

bool hasRetainedNativeExternalBytes(Object anchor) {
  final owner = _externalAnchors[anchor];
  return owner != null && !owner.allocation.released;
}

/// Explicitly ends all use of this registered allocation and its aliases.
/// Repeated releases are safe; no view may be accessed after the first release.
bool releaseRetainedNativeExternalBytes(Object anchor) {
  final owner =
      _externalAnchors[anchor] ??
      (anchor is Uint8List ? _externalRoots[anchor] : null);
  if (owner == null) return false;
  owner.allocation.release();
  return true;
}

_NativeExternalByteBuffer? _retainedOwner(Uint8List bytes, Object? anchor) =>
    (anchor == null ? null : _externalAnchors[anchor]) ??
    _externalAnchors[bytes] ??
    _externalRoots[bytes];

/// Resolves [bytes] to validated native storage retained by [anchor].
NativeExternalByteSlice? nativeExternalByteSlice(
  Uint8List bytes, {
  Object? anchor,
}) {
  final owner = _retainedOwner(bytes, anchor);
  // Buffer getters can return distinct wrappers for the same allocation.
  // Their equality checks backing storage, including read-only/nested views.
  if (owner == null ||
      owner.allocation.released ||
      bytes.buffer != owner.buffer) {
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

/// A bounded backing buffer for an already validated native range.
///
/// The original allocation keeps its finalizer. Both the mutable backing root
/// and its read-only facade retain that allocation, including through derived
/// views after the facade is collected. No foreign allocation is adopted.
Uint8List? nativeExternalByteView(Uint8List bytes, {Object? anchor}) {
  final slice = nativeExternalByteSlice(bytes, anchor: anchor);
  if (slice == null) return null;
  if (bytes.offsetInBytes == 0 &&
      bytes.buffer.lengthInBytes == bytes.lengthInBytes) {
    return bytes;
  }
  final backing = slice.pointer.asTypedList(slice.length);
  final view = backing.asUnmodifiableView();
  final owner = _NativeExternalByteBuffer(
    slice.pointer,
    backing.buffer,
    0,
    slice.length,
    _retainedOwner(bytes, anchor)!.allocation,
  );
  _externalRoots[backing] = owner;
  _externalRoots[view] = owner;
  _externalAliases.attach(backing, slice.owner);
  return view;
}
