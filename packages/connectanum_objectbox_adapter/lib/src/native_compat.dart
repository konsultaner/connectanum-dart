// The SDK compatibility surface is intentionally isolated here. These exact
// published versions are pinned and tested against real libraries; never load a
// second ObjectBox runtime and pass it a Store from the first one.
// ignore_for_file: implementation_imports

import 'dart:ffi';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:ffi/ffi.dart';
import 'package:objectbox/internal.dart';
import 'package:objectbox/objectbox.dart';
import 'package:objectbox/src/native/bindings/bindings.dart';

import 'metrics.dart';
import 'native_receive.dart';

NativeExternalByteSlice? resolveConnectanumBytes(
  Uint8List bytes,
  Object? owner,
) =>
    nativeExternalByteSlice(
      bytes,
      anchor:
          owner is num || owner is String || owner is bool || owner is Record
          ? null
          : owner,
    ) ??
    resolveReceivedNativeBytes(bytes, owner);

/// Non-moving external storage rooted until a synchronous native call returns.
final class NativeInputLifetime implements Finalizable {
  NativeInputLifetime(this.pointer, this.bytes, this.owner);
  final Pointer<Uint8> pointer;
  final Uint8List bytes;
  final Object? owner;

  int put(NativeObjectBoxAccess access, int id, int length, PutMode mode) =>
      access.put(pointer, length, id, mode);

  int putNew(NativeObjectBoxAccess access, int length, PutMode mode) =>
      access.putNew(pointer, length, mode);
}

final class NativeObjectBoxAccess<T> {
  NativeObjectBoxAccess(this.store) {
    model = InternalStoreAccess.entityDef<T>(store).model;
    box = C.box(InternalStoreAccess.ptr(store), model.id.id);
    if (box == nullptr) fail('obx_box');
  }

  final Store store;
  late final ModelEntity model;
  late final Pointer<OBX_box> box;

  void checkOpen() {
    if (store.isClosed()) throw StateError('ObjectBox Store is closed');
  }

  void addCloseListener(Object key, void Function() listener) =>
      InternalStoreAccess.addCloseListener(store, key, listener);

  void removeCloseListener(Object key) =>
      InternalStoreAccess.removeCloseListener(store, key);

  R write<R>(R Function() callback) {
    checkOpen();
    return store.runInTransaction(TxMode.write, callback);
  }

  int reserveId() {
    final id = C.box_id_for_put(box, 0);
    if (id <= 0) fail('obx_box_id_for_put');
    return id;
  }

  int put(Pointer<Uint8> bytes, int length, int id, PutMode mode) {
    final prepared = C.box_id_for_put(box, id);
    if (prepared <= 0) fail('obx_box_id_for_put');
    if (prepared != id) {
      throw StateError('ObjectBox changed a nonzero encoded ID');
    }
    final code = C.box_put5(box, id, bytes, length, mode._nativeValue);
    if (code != OBX_SUCCESS) fail('obx_box_put5', code);
    return id;
  }

  int putNew(Pointer<Uint8> bytes, int length, PutMode mode) {
    final id = C.box_put_object4(
      box,
      bytes.cast<Void>(),
      length,
      mode._nativeValue,
    );
    if (id <= 0) fail('obx_box_put_object4');
    return id;
  }

  R? read<R>(
    int id,
    R Function(Pointer<Uint8>, int) callback,
  ) {
    checkOpen();
    return InternalStoreAccess.runInTransaction(store, TxMode.read, (
      transaction,
    ) {
      final data = calloc<Pointer<Uint8>>();
      final size = calloc<Size>();
      try {
        final code = C.box_get(box, id, data, size);
        if (code == OBX_NOT_FOUND) return null;
        if (code != OBX_SUCCESS) fail('obx_box_get', code);
        if (data.value == nullptr || size.value <= 0) {
          throw StateError('ObjectBox returned an empty successful object');
        }
        return callback(data.value, size.value);
      } finally {
        calloc.free(size);
        calloc.free(data);
      }
    });
  }

  Never fail(String operation, [int? code]) {
    final actual = code ?? C.last_error_code();
    final message = C.last_error_message();
    throw ObjectBoxAdapterException(
      operation,
      actual,
      message == nullptr
          ? 'ObjectBox returned no error message'
          : message.cast<Utf8>().toDartString(),
    );
  }
}

extension on PutMode {
  int get _nativeValue => switch (this) {
    PutMode.put => OBXPutMode.PUT,
    PutMode.insert => OBXPutMode.INSERT,
    PutMode.update => OBXPutMode.UPDATE,
  };
}
