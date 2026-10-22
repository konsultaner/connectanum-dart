import 'dart:ffi';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:ffi/ffi.dart';
import 'package:objectbox/objectbox.dart';

import 'metrics.dart';
import 'native_compat.dart';
import 'schema.dart';

const objectBoxPptScheme = 'x_connectanum_objectbox';
const objectBoxSchemaMetadataKey = 'x_objectbox_schema';

/// Writes already encoded entity FlatBuffers through ObjectBox's synchronous
/// C API. It never reconstructs a Dart entity or owns the caller's Store.
final class ObjectBoxFlatBufferAdapter<T> {
  ObjectBoxFlatBufferAdapter(
    Store store, {
    bool allowRelationIds = false,
    int maximumBytes = 64 * 1024 * 1024,
  }) : _access = NativeObjectBoxAccess<T>(store) {
    schema = ObjectBoxEntitySchema.fromModel(
      _access.model,
      allowRelationIds: allowRelationIds,
      maximumBytes: maximumBytes,
    );
    _access.addCloseListener(this, () {
      _closed = true;
    });
  }

  final NativeObjectBoxAccess<T> _access;
  late final ObjectBoxEntitySchema schema;
  bool _closed = false;
  int _staging = 0;
  int _snapshots = 0;
  int _borrowed = 0;
  int _padding = 0;
  int _successful = 0;
  int _failed = 0;

  ObjectBoxCopyMetrics get copyMetrics => ObjectBoxCopyMetrics(
    stagingCopyBytes: _staging,
    snapshotCopyBytes: _snapshots,
    borrowedInputBytes: _borrowed,
    paddingBytes: _padding,
    successfulWrites: _successful,
    failedWrites: _failed,
  );

  void _checkOpen() {
    if (_closed) throw StateError('ObjectBox adapter is closed');
    _access.checkOpen();
  }

  /// Releases adapter bookkeeping; it does not close the caller's Store.
  void close() {
    if (_closed) return;
    _access.removeCloseListener(this);
    _closed = true;
  }

  /// Reserves an ObjectBox ID for a buffer that will be built subsequently.
  int reserveId() {
    _checkOpen();
    return _access.write(_access.reserveId);
  }

  /// Typed PPT options announcing the registered entity schema, without adding
  /// a wrapper or schema header to the entity's stored FlatBuffer bytes.
  PublishOptions publishOptions({bool acknowledge = true}) => PublishOptions(
    acknowledge: acknowledge,
    pptScheme: objectBoxPptScheme,
    pptSerializer: 'flatbuffers',
  )..custom[objectBoxSchemaMetadataKey] = schema.fingerprint;

  /// Persists a public lazy event without reading its arguments or constructing
  /// an entity. Encrypted payloads must first be authenticated and decrypted by
  /// the application's E2EE path, then supplied explicitly to [putBytes].
  ObjectBoxPutResult putEvent(
    LazyEventPayload event, {
    PutMode mode = PutMode.put,
    bool assignIdIfZero = true,
  }) {
    _checkOpen();
    if (event.pptScheme != objectBoxPptScheme ||
        event.pptSerializer != 'flatbuffers' ||
        event.pptCipher != null ||
        event.pptKeyId != null) {
      throw const FormatException(
        'Expected a plaintext ObjectBox entity PPT event',
      );
    }
    final fingerprint = event.customDetails?[objectBoxSchemaMetadataKey];
    final bytes = event.packedPayloadBytes;
    if (fingerprint is! String || bytes == null) {
      throw const FormatException(
        'ObjectBox event is missing schema or entity bytes',
      );
    }
    return putBytes(
      bytes,
      schemaFingerprint: fingerprint,
      storageOwner: event.payload.storageOwner,
      mode: mode,
      assignIdIfZero: assignIdIfZero,
    );
  }

  /// [bytes] must be an entity payload, not a WAMP envelope. Supply the sender's
  /// schema fingerprint. [storageOwner] can be the received Connectanum message
  /// retaining a derived native payload view; unrelated owners cannot substitute
  /// other bytes. Ordinary Dart arrays take one explicit native staging copy.
  ObjectBoxPutResult putBytes(
    Uint8List bytes, {
    required String schemaFingerprint,
    Object? storageOwner,
    PutMode mode = PutMode.put,
    bool assignIdIfZero = true,
  }) {
    _checkOpen();
    if (bytes.length < 16 || bytes.length > schema.maximumBytes) {
      throw const FormatException(
        'ObjectBox FlatBuffer length is outside limits',
      );
    }
    final native = resolveConnectanumBytes(bytes, storageOwner);
    return _put(
      bytes,
      native?.pointer,
      native?.owner ?? storageOwner,
      schemaFingerprint: schemaFingerprint,
      mode: mode,
      assignIdIfZero: assignIdIfZero,
    );
  }

  /// Advanced FFI integration. The caller must provide a readable native range
  /// that stays valid and immutable throughout this synchronous call, and an
  /// owner retaining that range. The pointer is never adopted or freed.
  ObjectBoxPutResult putNative(
    Pointer<Uint8> pointer,
    int length, {
    required Object lifetimeOwner,
    required String schemaFingerprint,
    PutMode mode = PutMode.put,
    bool assignIdIfZero = true,
  }) {
    _checkOpen();
    if (pointer == nullptr || length < 16 || length > schema.maximumBytes) {
      throw ArgumentError('Invalid native entity range');
    }
    return _put(
      pointer.asTypedList(length),
      pointer,
      lifetimeOwner,
      schemaFingerprint: schemaFingerprint,
      mode: mode,
      assignIdIfZero: assignIdIfZero,
    );
  }

  ObjectBoxPutResult _put(
    Uint8List bytes,
    Pointer<Uint8>? pointer,
    Object? owner, {
    required String schemaFingerprint,
    required PutMode mode,
    required bool assignIdIfZero,
  }) {
    final id = schema.validate(bytes, schemaFingerprint: schemaFingerprint);
    if (id == 0 && (!assignIdIfZero || mode == PutMode.update)) {
      throw ArgumentError('This write requires a nonzero encoded ObjectBox ID');
    }
    final reasons = <ObjectBoxCopyReason>[
      if (pointer == null) ObjectBoxCopyReason.unavailableNativeLease,
      if (bytes.length % 4 != 0) ObjectBoxCopyReason.padding,
      if (id == 0) ObjectBoxCopyReason.idAssignment,
    ];
    Pointer<Uint8>? staged;
    try {
      final size = (bytes.length + 3) & ~3;
      if (reasons.isNotEmpty) {
        staged = malloc<Uint8>(size);
        final destination = staged.asTypedList(size);
        destination.setRange(0, bytes.length, bytes);
        _staging += bytes.length;
        destination.fillRange(bytes.length, size, 0);
        _padding += size - bytes.length;
        pointer = staged;
      } else {
        _borrowed += bytes.length;
      }
      final lifetime = NativeInputLifetime(pointer!, bytes, owner);
      final writtenId = _access.write(
        () => id == 0
            ? lifetime.putNew(_access, size, mode)
            : lifetime.put(_access, id, size, mode),
      );
      _successful++;
      return ObjectBoxPutResult(
        id: writtenId,
        copiedBytes: staged == null ? 0 : bytes.length,
        copyReasons: reasons,
      );
    } catch (_) {
      _failed++;
      rethrow;
    } finally {
      if (staged != null) malloc.free(staged);
    }
  }

  /// An owned Dart snapshot suitable for asynchronous work. Exactly one body
  /// copy is counted, before the read transaction closes. Missing IDs return null.
  Uint8List? getBytes(int id) {
    _checkId(id);
    _checkOpen();
    return _access.read(id, (pointer, length) {
      if (length > schema.maximumBytes) {
        throw StateError('Stored object exceeds read limit');
      }
      final result = Uint8List.fromList(pointer.asTypedList(length));
      _snapshots += length;
      return result;
    });
  }

  static void _checkId(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'Must be positive');
  }
}
