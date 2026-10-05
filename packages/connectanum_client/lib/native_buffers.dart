/// VM-only initialized native-owned storage and guarded FlatBuffers builders.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

import 'src/transport/native/runtime.dart' show NativeClientRuntime;

part 'src/transport/native/native_frames.dart';

/// Native integration output from `ct_external_buffer_register`.
/// Publish this initialized structure to exactly one Dart consumer. Its handle
/// is a resource reference; copying/forging the fields does not retain it.
final class NativeBufferToken extends ffi.Struct {
  @ffi.Int32()
  external int handle;
  external ffi.Pointer<ffi.Void> identity;
}

typedef _IdentityN = ffi.Pointer<ffi.Void> Function();
typedef _IdentityD = ffi.Pointer<ffi.Void> Function();

final class _BufferInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> base;
  @ffi.UintPtr()
  external int capacity;
  @ffi.UintPtr()
  external int initializedLength;
  @ffi.UintPtr()
  external int offset;
  @ffi.UintPtr()
  external int length;
  @ffi.Int32()
  external int writable;
}

final class _ByteView extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;
  @ffi.UintPtr()
  external int length;
  external ffi.Pointer<ffi.Void> owner;
}

typedef _VersionN = ffi.Uint32 Function();
typedef _VersionD = int Function();
typedef _AllocateN = ffi.Int32 Function(ffi.Int32);
typedef _AllocateD = int Function(int);
typedef _InfoN = ffi.Int32 Function(ffi.Int32, ffi.Pointer<_BufferInfo>);
typedef _InfoD = int Function(int, ffi.Pointer<_BufferInfo>);
typedef _RangeN = ffi.Int32 Function(ffi.Int32, ffi.UintPtr, ffi.UintPtr);
typedef _RangeD = int Function(int, int, int);
typedef _ReleaseN = ffi.Int32 Function(ffi.Int32);
typedef _ReleaseD = int Function(int);
typedef _ExportN = ffi.Int32 Function(ffi.Int32, ffi.Pointer<_ByteView>);
typedef _ExportD = int Function(int, ffi.Pointer<_ByteView>);
typedef _SendN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _SendD = int Function(int, int);
typedef _OwnedE2eeEncryptN =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<ffi.Int32>,
    );
typedef _OwnedE2eeEncryptD =
    int Function(
      int,
      ffi.Pointer<ffi.Char>,
      int,
      int,
      int,
      ffi.Pointer<ffi.Int32>,
    );

/// A native ownership operation failed. Negative codes match the native ABI.
/// Optional VM-only capability of the native RawSocket/WebSocket transports.
abstract interface class NativeBufferTransport {
  NativeBufferAllocator get nativeBuffers;

  /// Submit a complete frame for the selected serializer. Reports acceptance
  /// into the local queue; retained sends preserve the caller's buffer.
  void sendEncodedNativeBuffer(
    NativeOwnedBuffer buffer, {
    bool transfer = false,
  });

  NativeWriteReceipt sendEncodedNativeBufferTracked(
    NativeOwnedBuffer buffer, {
    bool transfer = false,
  });

  /// Flush everything accepted before this call in the native writer queue.
  /// Requires the write-receipt ABI; an abandoned barrier fails explicitly.
  Future<void> drainWrites();
}

enum NativeWriteOutcome { pending, written, abandoned }

/// Observes local native writing, independently of payload release or peer ACK.
/// Explicit disposal returns bounded receipt capacity and does not cancel a send.
final class NativeWriteReceipt implements ffi.Finalizable {
  NativeWriteReceipt._(this._api, this._id) {
    try {
      _api._receiptFinalizer.attach(
        this,
        ffi.Pointer.fromAddress(_id),
        detach: this,
      );
    } catch (_) {
      _api._receiptRelease(_id);
      rethrow;
    }
  }

  final NativeBufferAllocator _api;
  final int _id;
  bool _disposed = false;

  NativeWriteOutcome get outcome {
    if (_disposed) throw StateError('Native write receipt is disposed');
    final state = _api._receiptState(_id);
    _check(state);
    if (state >= NativeWriteOutcome.values.length) {
      throw StateError('Invalid native write outcome $state');
    }
    return NativeWriteOutcome.values[state];
  }

  /// A timeout stops observation; it does not cancel queued/active writing.
  Future<NativeWriteOutcome> wait({Duration? timeout}) async {
    if (timeout != null && timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'Must not be negative');
    }
    final elapsed = Stopwatch()..start();
    while (true) {
      final state = outcome;
      if (state != NativeWriteOutcome.pending) return state;
      if (timeout != null && elapsed.elapsed >= timeout) {
        throw TimeoutException('Native write is still pending', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _api._receiptFinalizer.detach(this);
    _check(_api._receiptRelease(_id));
  }
}

final class NativeBufferException implements Exception {
  NativeBufferException(this.code);
  final int code;
  @override
  String toString() => 'Native buffer operation failed ($code)';
}

void _check(int status) {
  if (status < 0) throw NativeBufferException(status);
}

/// Resolves the complete owned-buffer ABI; older libraries fail explicitly.
final class NativeBufferAllocator {
  _NativeFrameApi? _frames;
  // The finalizer itself must outlive every attachment, including an allocator
  // and all its handles becoming unreachable together. Borrowed custom
  // libraries must stay loaded; retain one finalizer per library, not wrapper.
  static final Map<int, ffi.NativeFinalizer> _libraryFinalizers = {};

  factory NativeBufferAllocator.instance({String? libraryPath}) =>
      NativeClientRuntime.instance(libraryPath: libraryPath).nativeBuffers;

  /// Borrows a library that the caller must keep loaded for process lifetime.
  /// Closing/reloading it invalidates callback addresses and is unsupported.
  /// Prefer [NativeBufferAllocator.instance] for the managed runtime library.
  NativeBufferAllocator(ffi.DynamicLibrary library) {
    const symbols = [
      'ct_owned_buffer_abi_version',
      'ct_owned_buffer_allocate',
      'ct_owned_buffer_info',
      'ct_owned_buffer_freeze',
      'ct_owned_buffer_slice',
      'ct_owned_buffer_release',
      'ct_owned_buffer_handle_finalizer',
      'ct_owned_buffer_export',
      'ct_owned_buffer_view_finalizer',
      'ct_owned_buffer_send',
    ];
    if (!symbols.every(library.providesSymbol)) return;
    final version = library.lookupFunction<_VersionN, _VersionD>(symbols[0]);
    if (version() != 1) return;
    _identity = library
        .lookup<ffi.NativeFunction<_VersionN>>(symbols[0])
        .address;
    _allocate = library.lookupFunction<_AllocateN, _AllocateD>(symbols[1]);
    _info = library.lookupFunction<_InfoN, _InfoD>(symbols[2]);
    _freeze = library.lookupFunction<_RangeN, _RangeD>(symbols[3]);
    _slice = library.lookupFunction<_RangeN, _RangeD>(symbols[4]);
    _release = library.lookupFunction<_ReleaseN, _ReleaseD>(symbols[5]);
    _handleFinalizer = _libraryFinalizers.putIfAbsent(
      _identity,
      () => ffi.NativeFinalizer(
        library.lookup<ffi.NativeFinalizerFunction>(symbols[6]),
      ),
    );
    _export = library.lookupFunction<_ExportN, _ExportD>(symbols[7]);
    _viewFinalizer = library.lookup<ffi.NativeFinalizerFunction>(symbols[8]);
    _freeView = _viewFinalizer
        .asFunction<void Function(ffi.Pointer<ffi.Void>)>();
    _send = library.lookupFunction<_SendN, _SendD>(symbols[9]);
    _supported = true;
    _loadExternalTokens(library);
    _loadWriteCompletion(library);
    _loadOwnedE2eeEncryption(library);
    _frames = _NativeFrameApi.load(this, library);
  }

  void _loadExternalTokens(ffi.DynamicLibrary library) {
    const externalSymbols = [
      'ct_external_lease_abi_version',
      'ct_external_buffer_store_identity',
      'ct_external_owner_create',
      'ct_external_owner_close',
      'ct_external_owner_destroy',
      'ct_external_owner_dispatch',
      'ct_external_owner_wait',
      'ct_external_owner_metrics',
      'ct_external_buffer_register',
    ];
    if (!externalSymbols.every(library.providesSymbol)) return;
    final externalVersion = library.lookupFunction<_VersionN, _VersionD>(
      externalSymbols[0],
    );
    if (externalVersion() != 1) return;
    final identity = library.lookupFunction<_IdentityN, _IdentityD>(
      externalSymbols[1],
    )();
    if (identity.address == 0) return;
    _externalIdentity = identity;
    _externalSupported = true;
  }

  static final _receiptLibraryFinalizers = <int, ffi.NativeFinalizer>{};

  void _loadWriteCompletion(ffi.DynamicLibrary library) {
    const symbols = [
      'ct_write_receipt_abi_version',
      'ct_owned_buffer_send_tracked',
      'ct_connection_drain_writes',
      'ct_write_receipt_state',
      'ct_write_receipt_release',
      'ct_write_receipt_finalizer',
    ];
    if (!symbols.every(library.providesSymbol)) return;
    if (library.lookupFunction<_VersionN, _VersionD>(symbols[0])() != 1) return;
    _sendTracked = library.lookupFunction<_SendN, _SendD>(symbols[1]);
    _drainWrites = library.lookupFunction<_ReleaseN, _ReleaseD>(symbols[2]);
    _receiptState = library.lookupFunction<_ReleaseN, _ReleaseD>(symbols[3]);
    _receiptRelease = library.lookupFunction<_ReleaseN, _ReleaseD>(symbols[4]);
    _receiptFinalizer = _receiptLibraryFinalizers.putIfAbsent(
      _identity,
      () => ffi.NativeFinalizer(
        library.lookup<ffi.NativeFinalizerFunction>(symbols[5]),
      ),
    );
    _writeCompletionSupported = true;
  }

  bool _supported = false;
  bool _externalSupported = false;
  bool _writeCompletionSupported = false;
  bool _ownedE2eeEncryptionSupported = false;
  late final _OwnedE2eeEncryptD _encryptOwnedE2ee;
  late final _SendD _sendTracked;
  late final _ReleaseD _drainWrites;
  late final _ReleaseD _receiptState;
  late final _ReleaseD _receiptRelease;
  late final ffi.NativeFinalizer _receiptFinalizer;
  late final ffi.Pointer<ffi.Void> _externalIdentity;
  late final int _identity;
  late final _AllocateD _allocate;
  late final _InfoD _info;
  late final _RangeD _freeze;
  late final _RangeD _slice;
  late final _ReleaseD _release;
  late final _ExportD _export;
  late final _SendD _send;
  late final ffi.NativeFinalizer _handleFinalizer;
  late final ffi.Pointer<ffi.NativeFinalizerFunction> _viewFinalizer;
  late final void Function(ffi.Pointer<ffi.Void>) _freeView;

  bool get isSupported => _supported;

  /// Complete producer-lease ABI v1 and native token adoption are available.
  bool get supportsExternalTokens => _externalSupported;

  bool get supportsWriteCompletion => _writeCompletionSupported;

  /// Optional ABI for retaining an immutable native input and returning owned
  /// ciphertext without copying the payload through Dart typed data.
  bool get supportsOwnedE2eeEncryption => _ownedE2eeEncryptionSupported;

  void _loadOwnedE2eeEncryption(ffi.DynamicLibrary library) {
    const symbols = [
      'ct_e2ee_owned_buffer_abi_version',
      'ct_e2ee_session_encrypt_owned_buffer',
    ];
    if (!symbols.every(library.providesSymbol)) return;
    final version = library.lookupFunction<_VersionN, _VersionD>(symbols[0]);
    if (version() != 1) return;
    _encryptOwnedE2ee = library
        .lookupFunction<_OwnedE2eeEncryptN, _OwnedE2eeEncryptD>(
          symbols[1],
        );
    _ownedE2eeEncryptionSupported = true;
  }

  void _requireWriteCompletion() {
    _require();
    if (!_writeCompletionSupported) {
      throw UnsupportedError('Native write-receipt ABI v1 is unavailable');
    }
  }

  /// Claims one frozen handle published by a trusted native integration.
  /// `token` must point to initialized, writable [NativeBufferToken] storage.
  /// The native producer owns its release loop and resource lifetime; this
  /// method neither registers callbacks nor dispatches them on a Dart thread.
  ///
  /// ABI, identity and mutable-handle rejection leave the token unconsumed.
  /// Successful validation clears the token before constructing the owner;
  /// later construction failure releases that claimed handle exactly once.
  NativeOwnedBuffer adoptTrustedNativeToken(
    ffi.Pointer<NativeBufferToken> token,
  ) {
    _require();
    if (!_externalSupported) {
      throw UnsupportedError('Native producer-lease ABI v1 is unavailable');
    }
    if (token.address == 0) {
      throw ArgumentError.value(token, 'token', 'Null native token');
    }
    final value = token.ref;
    final id = value.handle;
    if (id <= 0 || value.identity != _externalIdentity) {
      throw ArgumentError('Invalid native token or different buffer library');
    }
    final info = _getInfoId(id);
    if (info.writable != 0) {
      throw StateError('Native token must reference an immutable buffer');
    }
    value.handle = 0;
    value.identity = ffi.nullptr;
    final handle = _OwnedHandle(this, id, externalSize: info.capacity);
    try {
      return NativeOwnedBuffer._(handle, info.length, 0, 0);
    } catch (_) {
      handle.dispose();
      rethrow;
    }
  }

  void _require() {
    if (!_supported) {
      throw UnsupportedError('Native library lacks owned-buffer ABI version 1');
    }
  }

  _OwnedHandle _newHandle(int length) {
    _require();
    RangeError.checkValueInInterval(length, 0, 0x7fffffff, 'length');
    final handle = _allocate(length);
    _check(handle);
    return _OwnedHandle(this, handle, externalSize: length);
  }

  ({
    ffi.Pointer<ffi.Uint8> base,
    int capacity,
    int initializedLength,
    int offset,
    int length,
    int writable,
  })
  _getInfo(_OwnedHandle handle) {
    handle.check();
    return _getInfoId(handle.id);
  }

  ({
    ffi.Pointer<ffi.Uint8> base,
    int capacity,
    int initializedLength,
    int offset,
    int length,
    int writable,
  })
  _getInfoId(int id) {
    final output = calloc<_BufferInfo>();
    try {
      _check(_info(id, output));
      // Snapshot fields; returning output.ref would escape freed struct memory.
      final info = output.ref;
      return (
        base: info.base,
        capacity: info.capacity,
        initializedLength: info.initializedLength,
        offset: info.offset,
        length: info.length,
        writable: info.writable,
      );
    } finally {
      calloc.free(output);
    }
  }

  NativeBufferBuilder allocate(int length) {
    final owner = _newHandle(length);
    try {
      return NativeBufferBuilder._(owner, length);
    } catch (_) {
      owner.dispose();
      rethrow;
    }
  }

  NativeFlatBufferBuilder flatBuffers({
    int initialSize = 1024,
    bool internStrings = false,
    bool deduplicateTables = true,
  }) {
    _require();
    return NativeFlatBufferBuilder._(
      this,
      initialSize,
      internStrings,
      deduplicateTables,
    );
  }

  /// Use fresh model object builders for each buffer, as required by the
  /// FlatBuffers runtime's offset caching. This does not copy the finished frame.
  NativeOwnedBuffer buildFlatBuffer(
    fb.ObjectBuilder model, {
    int initialSize = 1024,
    bool internStrings = false,
    bool deduplicateTables = true,
  }) {
    final builder = flatBuffers(
      initialSize: initialSize,
      internStrings: internStrings,
      deduplicateTables: deduplicateTables,
    );
    try {
      builder.finish(model.finish(builder));
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  /// Check that [buffer] is live, immutable and belongs to this native library.
  /// An optional limit is checked against native storage metadata.
  void validateFrozenBuffer(
    NativeOwnedBuffer buffer, {
    int? maximumLength,
  }) {
    _require();
    buffer._handle.check();
    if (buffer._handle.api._identity != _identity) {
      throw ArgumentError('Buffer belongs to a different native library');
    }
    final info = _getInfo(buffer._handle);
    if (info.writable != 0 || info.length != buffer.length) {
      throw StateError('Buffer is not a matching immutable native view');
    }
    if (maximumLength != null && info.length > maximumLength) {
      throw RangeError.range(info.length, 0, maximumLength, 'buffer.length');
    }
  }

  /// Encrypt a retained frozen input handle and return ciphertext in a new
  /// native-owned buffer. No payload bytes cross the Dart/native boundary.
  /// The input is never consumed, including when validation or encryption fails.
  NativeOwnedBuffer encryptE2eeBuffer(
    int sessionHandle,
    NativeOwnedBuffer plaintext, {
    String? keyId,
    required String cipher,
  }) {
    _require();
    if (!_ownedE2eeEncryptionSupported) {
      throw UnsupportedError('Native owned-buffer E2EE ABI v1 is unavailable');
    }
    RangeError.checkValueInInterval(
      sessionHandle,
      1,
      0x7fffffff,
      'sessionHandle',
    );
    validateFrozenBuffer(plaintext);
    final cipherCode = switch (cipher) {
      'xsalsa20poly1305' => 1,
      'aes256gcm' => 2,
      _ => throw ArgumentError.value(
        cipher,
        'cipher',
        'Unsupported E2EE cipher',
      ),
    };
    final keyIdBytes = keyId == null ? null : utf8.encode(keyId);
    if ((keyIdBytes?.length ?? 0) > 0x7fffffff) {
      throw ArgumentError.value(keyId, 'keyId', 'Key ID is too long');
    }
    final keyIdPointer = keyId?.toNativeUtf8().cast<ffi.Char>() ?? ffi.nullptr;
    final outHandle = calloc<ffi.Int32>();
    try {
      final status = _encryptOwnedE2ee(
        sessionHandle,
        keyIdPointer,
        keyIdBytes?.length ?? 0,
        plaintext._handle.id,
        cipherCode,
        outHandle,
      );
      if (status != 0) {
        if (outHandle.value > 0) _release(outHandle.value);
        _check(status);
      }
      final id = outHandle.value;
      if (id <= 0) throw StateError('Native E2EE returned no output handle');
      late final ({
        ffi.Pointer<ffi.Uint8> base,
        int capacity,
        int initializedLength,
        int offset,
        int length,
        int writable,
      })
      info;
      try {
        info = _getInfoId(id);
        if (info.writable != 0 || info.length == 0) {
          throw StateError('Native E2EE returned an invalid frozen output');
        }
      } catch (_) {
        _release(id);
        rethrow;
      }
      final handle = _OwnedHandle(this, id, externalSize: info.capacity);
      return NativeOwnedBuffer._(handle, info.length, 0, 0);
    } finally {
      calloc.free(outHandle);
      if (keyIdPointer != ffi.nullptr) malloc.free(keyIdPointer);
    }
  }

  /// Queue acceptance only. A transferred buffer is consumed on success or
  /// native rejection; retained sends preserve the caller's immutable handle.
  void send(
    int connectionId,
    NativeOwnedBuffer buffer, {
    bool transfer = false,
  }) {
    _require();
    RangeError.checkValueInInterval(
      connectionId,
      1,
      0x7fffffff,
      'connectionId',
    );
    buffer._handle.check();
    if (buffer._handle.api._identity != _identity) {
      throw ArgumentError('Buffer belongs to a different native library');
    }
    final submitted = transfer ? buffer : buffer.retain();
    final handle = submitted._handle.consume();
    _check(_send(connectionId, handle));
  }

  /// A positive receipt reports queue acceptance. Its Written outcome requires
  /// a complete write and flush. Transfers are consumed on native rejection,
  /// including receipt quota exhaustion; retained sends preserve the original.
  NativeWriteReceipt sendTracked(
    int connectionId,
    NativeOwnedBuffer buffer, {
    bool transfer = false,
  }) {
    _requireWriteCompletion();
    RangeError.checkValueInInterval(
      connectionId,
      1,
      0x7fffffff,
      'connectionId',
    );
    buffer._handle.check();
    if (buffer._handle.api._identity != _identity) {
      throw ArgumentError('Buffer belongs to a different native library');
    }
    final submitted = transfer ? buffer : buffer.retain();
    final receipt = _sendTracked(connectionId, submitted._handle.consume());
    _check(receipt);
    if (receipt == 0) throw StateError('Native writer returned no receipt');
    return NativeWriteReceipt._(this, receipt);
  }

  Future<void> drainWrites(int connectionId, {Duration? timeout}) async {
    _requireWriteCompletion();
    RangeError.checkValueInInterval(
      connectionId,
      1,
      0x7fffffff,
      'connectionId',
    );
    if (timeout != null && timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'Must not be negative');
    }
    final id = _drainWrites(connectionId);
    _check(id);
    if (id == 0) throw StateError('Native writer returned no barrier receipt');
    final receipt = NativeWriteReceipt._(this, id);
    try {
      if (await receipt.wait(timeout: timeout) != NativeWriteOutcome.written) {
        throw StateError('Native writer abandoned the queued flush barrier');
      }
    } finally {
      receipt.dispose();
    }
  }

  Uint8List _bytes(_OwnedHandle handle) {
    handle.check();
    final output = calloc<_ByteView>();
    try {
      _check(_export(handle.id, output));
      final owner = output.ref.owner;
      if (output.ref.length == 0) {
        _freeView(owner);
        return Uint8List(0).asUnmodifiableView();
      }
      late Uint8List view;
      try {
        view = output.ref.data.asTypedList(
          output.ref.length,
          finalizer: _viewFinalizer,
          token: owner,
        );
      } catch (_) {
        _freeView(owner);
        rethrow;
      }
      // Ownership has moved to the SDK backing store. If allocating the
      // read-only facade fails, its finalizer must remain the sole releaser.
      return view.asUnmodifiableView();
    } finally {
      calloc.free(output);
    }
  }
}

final class _OwnedHandle implements ffi.Finalizable {
  _OwnedHandle(this.api, this.id, {int externalSize = 0}) {
    try {
      api._handleFinalizer.attach(
        this,
        ffi.Pointer<ffi.Void>.fromAddress(id),
        detach: this,
        externalSize: externalSize,
      );
    } catch (_) {
      api._release(id);
      rethrow;
    }
  }
  final NativeBufferAllocator api;
  final int id;
  bool live = true;

  void check() {
    if (!live) throw StateError('Native buffer was disposed or transferred');
  }

  int consume() {
    check();
    live = false;
    api._handleFinalizer.detach(this);
    return id;
  }

  void dispose() {
    if (!live) return;
    final handle = consume();
    _check(api._release(handle));
  }
}

/// Frozen bytes with an independently retainable native allocation owner.
final class NativeOwnedBuffer implements ffi.Finalizable {
  NativeOwnedBuffer._(
    this._handle,
    this.length,
    this.growthCopiedBytes,
    this.inputCopiedBytes,
  );
  final _OwnedHandle _handle;
  final int length;
  final int growthCopiedBytes;

  /// Raw byte-vector input copied during construction, separately from growth.
  /// Scalar/string serialization writes are newly encoded data, not frame copies.
  final int inputCopiedBytes;
  bool get isDisposed => !_handle.live;

  /// Each exported view owns a native reference independently of this wrapper.
  /// The list, its ByteBuffer and derived views are read-only.
  Uint8List get bytes => _handle.api._bytes(_handle);

  NativeOwnedBuffer retain() => slice(0, length);

  NativeOwnedBuffer slice(int offset, [int? end]) {
    _handle.check();
    final stop = RangeError.checkValidRange(offset, end, length);
    final capacity = _handle.api._getInfo(_handle).capacity;
    final id = _handle.api._slice(_handle.id, offset, stop - offset);
    _check(id);
    return NativeOwnedBuffer._(
      _OwnedHandle(_handle.api, id, externalSize: capacity),
      stop - offset,
      growthCopiedBytes,
      inputCopiedBytes,
    );
  }

  void dispose() => _handle.dispose();
}

/// Writes initialized native memory without exposing mutable typed-data views.
final class NativeBufferBuilder implements ffi.Finalizable {
  NativeBufferBuilder._(this._handle, this.length) {
    final info = _handle.api._getInfo(_handle);
    _data = length == 0
        ? ByteData(0)
        : ByteData.sublistView(info.base.asTypedList(length));
  }
  final _OwnedHandle _handle;
  final int length;
  late final ByteData _data;
  bool _frozen = false;
  int _writing = 0;
  int _inputCopiedBytes = 0;

  T _write<T>(T Function() action) {
    _handle.check();
    if (_frozen) throw StateError('Native buffer is frozen');
    _writing++;
    try {
      return action();
    } finally {
      _writing--;
    }
  }

  void setUint8(int offset, int value) =>
      _write(() => _data.setUint8(offset, value));
  void setUint32(int offset, int value, [Endian endian = Endian.little]) =>
      _write(() => _data.setUint32(offset, value, endian));
  void setUint64(int offset, int value, [Endian endian = Endian.little]) =>
      _write(() => _data.setUint64(offset, value, endian));
  void writeBytes(int offset, List<int> bytes) => _write(() {
    RangeError.checkValidRange(offset, offset + bytes.length, length);
    _data.buffer.asUint8List().setRange(offset, offset + bytes.length, bytes);
    _inputCopiedBytes += bytes.length;
  });

  NativeOwnedBuffer freeze({int offset = 0, int? length}) {
    if (_writing != 0) throw StateError('Cannot freeze during a write');
    _handle.check();
    if (_frozen) throw StateError('Native buffer is already frozen');
    final used = length ?? this.length - offset;
    RangeError.checkValidRange(offset, offset + used, this.length);
    _check(_handle.api._freeze(_handle.id, offset, used));
    _frozen = true;
    return NativeOwnedBuffer._(_handle, used, 0, _inputCopiedBytes);
  }

  void dispose() {
    if (_writing != 0) throw StateError('Cannot dispose during a write');
    if (!_frozen) _handle.dispose();
  }
}

final class _NativeAllocator extends fb.Allocator implements ffi.Finalizable {
  _NativeAllocator(this.api);
  final NativeBufferAllocator api;
  final Map<ByteData, _OwnedHandle> _owners = Map.identity();
  ByteData? current;
  int growthCopiedBytes = 0;
  int allocations = 0;

  @override
  ByteData allocate(int size) {
    RangeError.checkValueInInterval(size, 0, 0x7ffffff8, 'size');
    // The builder aligns offsets from the allocation's end. Round its physical
    // capacity too, so backward-built uint64/float64 fields have aligned native
    // addresses even when the caller requests an odd initial size.
    final alignedSize = (size + 7) & ~7;
    final owner = api._newHandle(alignedSize);
    try {
      final info = api._getInfo(owner);
      final data = alignedSize == 0
          ? ByteData(0)
          : ByteData.sublistView(info.base.asTypedList(alignedSize));
      _owners[data] = owner;
      current = data;
      allocations++;
      return data;
    } catch (_) {
      owner.dispose();
      rethrow;
    }
  }

  @override
  void deallocate(ByteData data) {
    _owners.remove(data)?.dispose();
    if (identical(current, data)) current = null;
  }

  @override
  ByteData resize(ByteData oldData, int size, int back, int front) {
    final data = super.resize(oldData, size, back, front);
    growthCopiedBytes += back + front;
    return data;
  }

  NativeOwnedBuffer freeze(int used, int inputCopiedBytes) {
    final data = current!;
    final owner = _owners[data]!;
    _check(api._freeze(owner.id, data.lengthInBytes - used, used));
    _owners.remove(data);
    current = null;
    return NativeOwnedBuffer._(
      owner,
      used,
      growthCopiedBytes,
      inputCopiedBytes,
    );
  }

  void dispose() {
    for (final owner in _owners.values) {
      owner.dispose();
    }
    _owners.clear();
    current = null;
  }
}

/// Implements the pinned Builder API through guarded composition, including
/// model callbacks. No raw allocator or writable buffer escapes this facade.
final class NativeFlatBufferBuilder implements fb.Builder, ffi.Finalizable {
  NativeFlatBufferBuilder._(
    NativeBufferAllocator api,
    this.initialSize,
    bool internStrings,
    this.deduplicateTables,
  ) : _allocator = _NativeAllocator(api) {
    try {
      _builder = fb.Builder(
        initialSize: initialSize,
        internStrings: internStrings,
        deduplicateTables: deduplicateTables,
        allocator: _allocator,
      );
    } catch (_) {
      _allocator.dispose();
      rethrow;
    }
  }
  final _NativeAllocator _allocator;
  late final fb.Builder _builder;
  NativeOwnedBuffer? _frozen;
  bool _finished = false;
  bool _disposed = false;
  int _writing = 0;
  int _inputCopiedBytes = 0;
  @override
  final int initialSize;
  @override
  final bool deduplicateTables;
  int get growthCopiedBytes => _allocator.growthCopiedBytes;
  int get allocationCount => _allocator.allocations;

  T _write<T>(T Function() action, {bool allowFinished = false}) {
    if (_disposed || _frozen != null || (_finished && !allowFinished)) {
      throw StateError('Native builder no longer accepts writes');
    }
    _writing++;
    try {
      return action();
    } finally {
      _writing--;
    }
  }

  NativeOwnedBuffer freeze() {
    if (_disposed || !_finished || _writing != 0) {
      throw StateError('Finish the native builder before freezing');
    }
    return _frozen ??= _allocator.freeze(_builder.size(), _inputCopiedBytes);
  }

  void dispose() {
    if (_writing != 0) throw StateError('Cannot dispose during a write');
    if (_disposed) return;
    _disposed = true;
    _allocator.dispose();
    _frozen = null;
  }

  @override
  Uint8List get buffer => freeze().bytes;
  @override
  int get offset => _builder.offset;
  @override
  int size() => _builder.size();
  @override
  void finish(int offset, [String? fileIdentifier]) {
    _write(() => _builder.finish(offset, fileIdentifier));
    _finished = true;
  }

  @override
  void reset() {
    _write(_builder.reset, allowFinished: true);
    _finished = false;
  }

  @override
  int writeListOfStructs(List<fb.ObjectBuilder> structBuilders) => _write(() {
    for (var i = structBuilders.length - 1; i >= 0; i--) {
      structBuilders[i].finish(this);
    }
    return _builder.endStructVector(structBuilders.length);
  });
  @override
  void addBool(int field, bool? value, [bool? def]) =>
      _write(() => _builder.addBool(field, value, def));

  @override
  void putBool(bool value) => _write(() => _builder.putBool(value));

  @override
  void addInt32(int field, int? value, [int? def]) =>
      _write(() => _builder.addInt32(field, value, def));

  @override
  void putInt32(int value) => _write(() => _builder.putInt32(value));

  @override
  void addInt16(int field, int? value, [int? def]) =>
      _write(() => _builder.addInt16(field, value, def));

  @override
  void putInt16(int value) => _write(() => _builder.putInt16(value));

  @override
  void addInt8(int field, int? value, [int? def]) =>
      _write(() => _builder.addInt8(field, value, def));

  @override
  void putInt8(int value) => _write(() => _builder.putInt8(value));

  @override
  void addUint32(int field, int? value, [int? def]) =>
      _write(() => _builder.addUint32(field, value, def));

  @override
  void putUint32(int value) => _write(() => _builder.putUint32(value));

  @override
  void addUint16(int field, int? value, [int? def]) =>
      _write(() => _builder.addUint16(field, value, def));

  @override
  void putUint16(int value) => _write(() => _builder.putUint16(value));

  @override
  void addUint8(int field, int? value, [int? def]) =>
      _write(() => _builder.addUint8(field, value, def));

  @override
  void putUint8(int value) => _write(() => _builder.putUint8(value));

  @override
  void addFloat32(int field, double? value, [double? def]) =>
      _write(() => _builder.addFloat32(field, value, def));

  @override
  void putFloat32(double value) => _write(() => _builder.putFloat32(value));

  @override
  void addFloat64(int field, double? value, [double? def]) =>
      _write(() => _builder.addFloat64(field, value, def));

  @override
  void putFloat64(double value) => _write(() => _builder.putFloat64(value));

  @override
  void addUint64(int field, int? value, [double? def]) =>
      _write(() => _builder.addUint64(field, value, def));

  @override
  void putUint64(int value) => _write(() => _builder.putUint64(value));

  @override
  void addInt64(int field, int? value, [double? def]) =>
      _write(() => _builder.addInt64(field, value, def));

  @override
  void putInt64(int value) => _write(() => _builder.putInt64(value));

  @override
  int writeList(List<int> values) => _write(() => _builder.writeList(values));

  @override
  int writeListFloat64(List<double> values) =>
      _write(() => _builder.writeListFloat64(values));

  @override
  int writeListFloat32(List<double> values) =>
      _write(() => _builder.writeListFloat32(values));

  @override
  int writeListInt64(List<int> values) =>
      _write(() => _builder.writeListInt64(values));

  @override
  int writeListUint64(List<int> values) =>
      _write(() => _builder.writeListUint64(values));

  @override
  int writeListInt32(List<int> values) =>
      _write(() => _builder.writeListInt32(values));

  @override
  int writeListUint32(List<int> values) =>
      _write(() => _builder.writeListUint32(values));

  @override
  int writeListInt16(List<int> values) =>
      _write(() => _builder.writeListInt16(values));

  @override
  int writeListUint16(List<int> values) =>
      _write(() => _builder.writeListUint16(values));

  @override
  int writeListBool(List<bool> values) =>
      _write(() => _builder.writeListBool(values));

  @override
  int writeListInt8(List<int> values) => _write(() {
    final result = _builder.writeListInt8(values);
    _inputCopiedBytes += values.length;
    return result;
  });

  @override
  int writeListUint8(List<int> values) => _write(() {
    final result = _builder.writeListUint8(values);
    _inputCopiedBytes += values.length;
    return result;
  });

  @override
  void addStruct(int field, int offset) =>
      _write(() => _builder.addStruct(field, offset));
  @override
  void addOffset(int field, int? offset) =>
      _write(() => _builder.addOffset(field, offset));
  @override
  void startTable(int numFields) =>
      _write(() => _builder.startTable(numFields));
  @override
  int endTable() => _write(_builder.endTable);
  @override
  int endStructVector(int count) =>
      _write(() => _builder.endStructVector(count));
  @override
  void pad(int howManyBytes) => _write(() => _builder.pad(howManyBytes));
  @override
  int writeString(String value, {bool asciiOptimization = false}) => _write(
    () => _builder.writeString(value, asciiOptimization: asciiOptimization),
  );
}
