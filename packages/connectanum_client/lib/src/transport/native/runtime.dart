import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'external_byte_buffer.dart';
import 'ffi_bindings.dart';
import 'message_binding.dart';
import 'message_protocol.dart';

String? _readOptionalString(ffi.Pointer<ffi.Uint8> ptr, int len) {
  if (ptr == ffi.nullptr) {
    return null;
  }
  return utf8.decode(ptr.asTypedList(len));
}

Uint8List? _readOptionalBytes(ffi.Pointer<ffi.Uint8> ptr, int len) {
  if (ptr == ffi.nullptr || len == 0) {
    return null;
  }
  return ptr.asTypedList(len);
}

abstract final class NativeTransportErrorCode {
  static const success = 0;
  static const unsupported = -1;
  static const alreadyStarted = -2;
  static const runtimeNotStarted = -3;
  static const invalidArgument = -4;
  static const io = -7;
  static const connectionNotFound = -10;
  static const unsupportedSerializer = -11;
  static const handleUnavailable = -14;
  static const sendQueueFull = -17;
  static const keyNotFound = -18;
  static const decryptionFailed = -19;
}

class NativeTransportException implements Exception {
  NativeTransportException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() =>
      'NativeTransportException(code: $code, message: $message)';
}

class NativeIncomingMessage {
  NativeIncomingMessage._({
    required this.message,
    required this.bytes,
    required this.handle,
    required this.runtimeIdentity,
    required CtFfiBindings bindings,
    required Finalizer<_MessageFinalizerToken> messageFinalizer,
    this.argumentsBytes,
    this.argumentsKeywordsBytes,
    this.singleBinaryArgumentBytes,
  }) : _bindings = bindings,
       _messageFinalizer = messageFinalizer;

  final Object message;
  final Uint8List bytes;
  final int handle;
  final Object runtimeIdentity;
  final Uint8List? argumentsBytes;
  final Uint8List? argumentsKeywordsBytes;
  final Uint8List? singleBinaryArgumentBytes;
  final CtFfiBindings _bindings;
  final Finalizer<_MessageFinalizerToken> _messageFinalizer;

  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _messageFinalizer.detach(this);
    _bindings.ctMessageRelease(handle);
  }
}

final Expando<_NativeExternalBytesReference> _nativeExternalBytes =
    Expando<_NativeExternalBytesReference>('connectanum.native.external-bytes');
const int _asyncSha256MinimumBytes = 256 * 1024;

class _NativeExternalBytesReference {
  const _NativeExternalBytesReference({
    required this.runtimeIdentity,
    required this.pointer,
    required this.length,
  });

  final Object runtimeIdentity;
  final ffi.Pointer<ffi.Uint8> pointer;
  final int length;
}

class _MessageFinalizerToken {
  const _MessageFinalizerToken(this.bindings, this.handle);

  final CtFfiBindings bindings;
  final int handle;
}

void _finalizeNativeMessage(_MessageFinalizerToken token) {
  token.bindings.ctMessageRelease(token.handle);
}

class NativeFileSegmentMetrics {
  const NativeFileSegmentMetrics({
    required this.rawSocketZeroCopyCallsTotal,
    required this.rawSocketZeroCopyBytesTotal,
    required this.bufferedFileSegmentCallsTotal,
    required this.bufferedFileSegmentBytesTotal,
  });

  final int rawSocketZeroCopyCallsTotal;
  final int rawSocketZeroCopyBytesTotal;
  final int bufferedFileSegmentCallsTotal;
  final int bufferedFileSegmentBytesTotal;

  NativeFileSegmentMetrics deltaFrom(NativeFileSegmentMetrics before) =>
      NativeFileSegmentMetrics(
        rawSocketZeroCopyCallsTotal: _counterDelta(
          rawSocketZeroCopyCallsTotal,
          before.rawSocketZeroCopyCallsTotal,
        ),
        rawSocketZeroCopyBytesTotal: _counterDelta(
          rawSocketZeroCopyBytesTotal,
          before.rawSocketZeroCopyBytesTotal,
        ),
        bufferedFileSegmentCallsTotal: _counterDelta(
          bufferedFileSegmentCallsTotal,
          before.bufferedFileSegmentCallsTotal,
        ),
        bufferedFileSegmentBytesTotal: _counterDelta(
          bufferedFileSegmentBytesTotal,
          before.bufferedFileSegmentBytesTotal,
        ),
      );

  static int _counterDelta(int current, int before) =>
      current >= before ? current - before : current;
}

class NativeClientRuntime {
  factory NativeClientRuntime.instance({String? libraryPath}) {
    final current = _instance;
    if (current != null) {
      return current;
    }
    final resolvedPath = NativeLibraryLoader.resolvePath(override: libraryPath);
    final library = ffi.DynamicLibrary.open(resolvedPath);
    final runtime = NativeClientRuntime._(
      resolvedPath,
      library,
      CtFfiBindings(library),
    );
    _instance = runtime;
    return runtime;
  }

  NativeClientRuntime._(this.libraryPath, this._library, this._bindings)
    : _messageFinalizer = Finalizer<_MessageFinalizerToken>(
        _finalizeNativeMessage,
      );

  static NativeClientRuntime? _instance;

  final String libraryPath;
  // ignore: unused_field
  final ffi.DynamicLibrary _library;
  final CtFfiBindings _bindings;
  final Finalizer<_MessageFinalizerToken> _messageFinalizer;
  bool _started = false;

  void ensureStarted() {
    if (_started) {
      return;
    }
    final result = _bindings.ctStartRuntime();
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.alreadyStarted) {
      _throwForError(result, 'Failed to start native client runtime');
    }
    _started = true;
  }

  void shutdown() {
    if (!_started) {
      return;
    }
    final result = _bindings.ctShutdown();
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.runtimeNotStarted) {
      _throwForError(result, 'Failed to shut down native client runtime');
    }
    _started = false;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  static void shutdownShared() {
    _instance?.shutdown();
  }

  int connectRawSocket({
    required String host,
    required int port,
    required bool useTls,
    required bool allowInsecure,
    required NativeMessageSerializer serializer,
    required int maxMessageLengthExponent,
    Duration? heartbeatInterval,
    Duration? heartbeatTimeout,
  }) {
    ensureStarted();
    final hostPtr = host.toNativeUtf8().cast<ffi.Char>();
    try {
      final result = _bindings.ctClientConnectRawsocket(
        hostPtr,
        port,
        useTls ? 1 : 0,
        allowInsecure ? 1 : 0,
        serializer.id,
        maxMessageLengthExponent,
        heartbeatInterval?.inMilliseconds ?? 0,
        heartbeatTimeout?.inMilliseconds ?? 0,
      );
      if (result <= 0) {
        _throwForError(result, 'Failed to open native rawsocket transport');
      }
      return result;
    } finally {
      malloc.free(hostPtr);
    }
  }

  int createE2eeKeyring() {
    ensureStarted();
    final result = _bindings.ctE2eeKeyringNew();
    if (result <= 0) {
      _throwForError(result, 'Failed to create native E2EE keyring');
    }
    return result;
  }

  void addE2eeKey(
    int keyringHandle,
    String keyId,
    Uint8List key, {
    bool makeDefault = false,
  }) {
    ensureStarted();
    final keyIdPtr = keyId.toNativeUtf8().cast<ffi.Char>();
    final keyPtr = malloc<ffi.Uint8>(key.length);
    try {
      keyPtr.asTypedList(key.length).setAll(0, key);
      final result = _bindings.ctE2eeKeyringAddKey(
        keyringHandle,
        keyIdPtr,
        keyId.length,
        keyPtr,
        key.length,
        makeDefault ? 1 : 0,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to add key to native E2EE keyring');
      }
    } finally {
      malloc.free(keyIdPtr);
      malloc.free(keyPtr);
    }
  }

  void releaseE2eeKeyring(int handle) {
    ensureStarted();
    final result = _bindings.ctE2eeKeyringRelease(handle);
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.handleUnavailable) {
      _throwForError(result, 'Failed to release native E2EE keyring');
    }
  }

  int createE2eeSession(int keyringHandle, {String? defaultKeyId}) {
    ensureStarted();
    final defaultKeyIdPtr =
        defaultKeyId?.toNativeUtf8().cast<ffi.Char>() ?? ffi.nullptr;
    try {
      final result = _bindings.ctE2eeSessionNew(
        keyringHandle,
        defaultKeyIdPtr,
        defaultKeyId?.length ?? 0,
      );
      if (result <= 0) {
        _throwForError(result, 'Failed to create native E2EE session');
      }
      return result;
    } finally {
      if (defaultKeyIdPtr != ffi.nullptr) {
        malloc.free(defaultKeyIdPtr);
      }
    }
  }

  void releaseE2eeSession(int handle) {
    ensureStarted();
    final result = _bindings.ctE2eeSessionRelease(handle);
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.handleUnavailable) {
      _throwForError(result, 'Failed to release native E2EE session');
    }
  }

  Uint8List encryptE2ee(
    int sessionHandle,
    Uint8List plaintext, {
    String? keyId,
    String cipher = 'xsalsa20poly1305',
  }) {
    ensureStarted();
    final encrypt = switch (cipher) {
      'xsalsa20poly1305' => _bindings.ctE2eeSessionEncrypt,
      'aes256gcm' => _bindings.ctE2eeSessionEncryptAes256Gcm,
      _ => throw ArgumentError.value(
        cipher,
        'cipher',
        'Unsupported E2EE cipher',
      ),
    };
    final keyIdPtr = keyId?.toNativeUtf8().cast<ffi.Char>() ?? ffi.nullptr;
    final plaintextPtr = malloc<ffi.Uint8>(plaintext.length);
    final bufferPtr = calloc<CtByteBuffer>();
    try {
      plaintextPtr.asTypedList(plaintext.length).setAll(0, plaintext);
      final result = encrypt(
        sessionHandle,
        keyIdPtr,
        keyId?.length ?? 0,
        plaintextPtr,
        plaintext.length,
        bufferPtr,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to encrypt native E2EE payload');
      }
      return _copyAndFreeByteBuffer(bufferPtr.ref);
    } finally {
      if (keyIdPtr != ffi.nullptr) {
        malloc.free(keyIdPtr);
      }
      malloc.free(plaintextPtr);
      calloc.free(bufferPtr);
    }
  }

  Uint8List decryptE2ee(
    int sessionHandle,
    Uint8List ciphertext, {
    String? keyId,
    String cipher = 'xsalsa20poly1305',
  }) {
    ensureStarted();
    final decrypt = switch (cipher) {
      'xsalsa20poly1305' => _bindings.ctE2eeSessionDecrypt,
      'aes256gcm' => _bindings.ctE2eeSessionDecryptAes256Gcm,
      _ => throw ArgumentError.value(
        cipher,
        'cipher',
        'Unsupported E2EE cipher',
      ),
    };
    final keyIdPtr = keyId?.toNativeUtf8().cast<ffi.Char>() ?? ffi.nullptr;
    final ciphertextPtr = malloc<ffi.Uint8>(ciphertext.length);
    final bufferPtr = calloc<CtByteBuffer>();
    try {
      ciphertextPtr.asTypedList(ciphertext.length).setAll(0, ciphertext);
      final result = decrypt(
        sessionHandle,
        keyIdPtr,
        keyId?.length ?? 0,
        ciphertextPtr,
        ciphertext.length,
        bufferPtr,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to decrypt native E2EE payload');
      }
      return _copyAndFreeByteBuffer(bufferPtr.ref);
    } finally {
      if (keyIdPtr != ffi.nullptr) {
        malloc.free(keyIdPtr);
      }
      malloc.free(ciphertextPtr);
      calloc.free(bufferPtr);
    }
  }

  Uint8List? decryptE2eeMessageSingleBinaryArgument(
    int sessionHandle,
    NativeIncomingMessage incoming, {
    String? keyId,
    String cipher = 'xsalsa20poly1305',
  }) {
    ensureStarted();
    if (!identical(incoming.runtimeIdentity, this)) {
      return null;
    }
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
    final keyIdPtr = keyId?.toNativeUtf8().cast<ffi.Char>() ?? ffi.nullptr;
    final outputPtr = calloc<CtExternalByteBuffer>();
    try {
      final result = _bindings.ctE2eeSessionDecryptMessageSingleBinaryArgument(
        sessionHandle,
        keyIdPtr,
        keyIdBytes?.length ?? 0,
        incoming.handle,
        cipherCode,
        outputPtr,
      );
      if (result == NativeTransportErrorCode.unsupported) {
        return null;
      }
      if (result != NativeTransportErrorCode.success) {
        _throwForError(
          result,
          'Failed to decrypt native message binary argument',
        );
      }
      final output = outputPtr.ref;
      if (output.owner == ffi.nullptr) {
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native E2EE decrypt returned no external buffer owner',
        );
      }
      if (output.len == 0) {
        _bindings.ctExternalByteBufferFree(output.owner);
        return Uint8List(0);
      }
      if (output.ptr == ffi.nullptr) {
        _bindings.ctExternalByteBufferFree(output.owner);
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native E2EE decrypt returned no external buffer bytes',
        );
      }
      Uint8List? bytes;
      try {
        bytes = output.ptr.asTypedList(
          output.len,
          finalizer: _bindings.ctExternalByteBufferFreePointer,
          token: output.owner,
        );
        _nativeExternalBytes[bytes] = _NativeExternalBytesReference(
          runtimeIdentity: this,
          pointer: output.ptr,
          length: output.len,
        );
        return bytes;
      } catch (_) {
        // Once asTypedList succeeds, its finalizer exclusively owns the token.
        if (bytes == null) {
          _bindings.ctExternalByteBufferFree(output.owner);
        }
        rethrow;
      }
    } finally {
      if (keyIdPtr != ffi.nullptr) {
        malloc.free(keyIdPtr);
      }
      calloc.free(outputPtr);
    }
  }

  int connectWebSocket({
    required String host,
    required int port,
    required String target,
    required bool useTls,
    required bool allowInsecure,
    required NativeMessageSerializer serializer,
    required Map<String, String> headers,
    Duration? heartbeatInterval,
    Duration? heartbeatTimeout,
  }) {
    ensureStarted();
    final hostPtr = host.toNativeUtf8().cast<ffi.Char>();
    final targetPtr = target.toNativeUtf8().cast<ffi.Char>();
    final headerPointers = <ffi.Pointer<ffi.Uint8>>[];
    final headerArray = headers.isEmpty
        ? ffi.nullptr
        : calloc<CtHttpHeader>(headers.length);
    try {
      if (headerArray != ffi.nullptr) {
        var index = 0;
        for (final entry in headers.entries) {
          final nameBytes = Uint8List.fromList(utf8.encode(entry.key));
          final valueBytes = Uint8List.fromList(utf8.encode(entry.value));
          final namePtr = malloc<ffi.Uint8>(nameBytes.length);
          final valuePtr = malloc<ffi.Uint8>(valueBytes.length);
          headerPointers
            ..add(namePtr)
            ..add(valuePtr);
          namePtr.asTypedList(nameBytes.length).setAll(0, nameBytes);
          valuePtr.asTypedList(valueBytes.length).setAll(0, valueBytes);
          final header = (headerArray + index).ref;
          header.namePtr = namePtr;
          header.nameLen = nameBytes.length;
          header.valuePtr = valuePtr;
          header.valueLen = valueBytes.length;
          index += 1;
        }
      }
      final result = _bindings.ctClientConnectWebSocket(
        hostPtr,
        port,
        targetPtr,
        useTls ? 1 : 0,
        allowInsecure ? 1 : 0,
        serializer.id,
        headerArray,
        headers.length,
        heartbeatInterval?.inMilliseconds ?? 0,
        heartbeatTimeout?.inMilliseconds ?? 0,
      );
      if (result <= 0) {
        _throwForError(result, 'Failed to open native websocket transport');
      }
      return result;
    } finally {
      malloc.free(hostPtr);
      malloc.free(targetPtr);
      for (final pointer in headerPointers) {
        malloc.free(pointer);
      }
      if (headerArray != ffi.nullptr) {
        calloc.free(headerArray);
      }
    }
  }

  int connectionMaxRawSocketExponent(int connectionId) {
    ensureStarted();
    final result = _bindings.ctConnectionMaxRawsocketExponent(connectionId);
    if (result < 0) {
      _throwForError(result, 'Failed to read native rawsocket settings');
    }
    return result;
  }

  bool connectionSupportsFileSegments(int connectionId) {
    ensureStarted();
    final result = _bindings.ctConnectionSupportsFileSegments(connectionId);
    if (result < 0) {
      _throwForError(result, 'Failed to read native file segment capability');
    }
    return result == 1;
  }

  NativeFileSegmentMetrics fileSegmentMetricsSnapshot() {
    final info = calloc<CtFileSegmentMetricsInfo>();
    try {
      final result = _bindings.ctFileSegmentMetricsSnapshot(info);
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'snapshot file-segment metrics');
      }
      final value = info.ref;
      return NativeFileSegmentMetrics(
        rawSocketZeroCopyCallsTotal: value.rawSocketZeroCopyCallsTotal,
        rawSocketZeroCopyBytesTotal: value.rawSocketZeroCopyBytesTotal,
        bufferedFileSegmentCallsTotal: value.bufferedFileSegmentCallsTotal,
        bufferedFileSegmentBytesTotal: value.bufferedFileSegmentBytesTotal,
      );
    } finally {
      calloc.free(info);
    }
  }

  void closeConnection(int connectionId) {
    ensureStarted();
    final result = _bindings.ctConnectionClose(connectionId);
    if (result < 0 && result != NativeTransportErrorCode.connectionNotFound) {
      _throwForError(result, 'Failed to close native transport connection');
    }
  }

  void sendMessage(int connectionId, Uint8List payload) {
    ensureStarted();
    final ownedResult = _sendOwnedMessage(connectionId, payload);
    if (ownedResult != null) {
      if (ownedResult != NativeTransportErrorCode.success) {
        _throwForError(ownedResult, 'Failed to send native transport message');
      }
      return;
    }

    final dataPtr = malloc<ffi.Uint8>(payload.length);
    try {
      dataPtr.asTypedList(payload.length).setAll(0, payload);
      final result = _bindings.ctSendMessage(
        connectionId,
        dataPtr,
        payload.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send native transport message');
      }
    } finally {
      malloc.free(dataPtr);
    }
  }

  void sendMessageFragmented(
    int connectionId,
    Uint8List payload, {
    required int fragmentSize,
  }) {
    ensureStarted();
    if (fragmentSize <= 0) {
      throw ArgumentError.value(
        fragmentSize,
        'fragmentSize',
        'fragmentSize must be > 0',
      );
    }
    final ownedResult = _sendOwnedMessage(
      connectionId,
      payload,
      fragmentSize: fragmentSize,
    );
    if (ownedResult != null) {
      if (ownedResult != NativeTransportErrorCode.success) {
        _throwForError(
          ownedResult,
          'Failed to send fragmented native transport message',
        );
      }
      return;
    }

    final dataPtr = malloc<ffi.Uint8>(payload.length);
    try {
      dataPtr.asTypedList(payload.length).setAll(0, payload);
      final result = _bindings.ctSendMessageFragmented(
        connectionId,
        dataPtr,
        payload.length,
        fragmentSize,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(
          result,
          'Failed to send fragmented native transport message',
        );
      }
    } finally {
      malloc.free(dataPtr);
    }
  }

  bool trySendMessageSegments(
    int connectionId,
    List<Uint8List> segments, {
    int fragmentSize = 0,
  }) {
    ensureStarted();
    if (segments.isEmpty) {
      return false;
    }
    if (fragmentSize < 0) {
      throw ArgumentError.value(
        fragmentSize,
        'fragmentSize',
        'fragmentSize must be >= 0',
      );
    }
    final allocate = _bindings.ctOutboundBufferAlloc;
    final release = _bindings.ctOutboundBufferFree;
    final sendSegments = _bindings.ctSendMessageSegmentsOwned;
    if (allocate == null || release == null || sendSegments == null) {
      return false;
    }

    final pointers = malloc<ffi.Pointer<ffi.Uint8>>(segments.length);
    final lengths = malloc<ffi.Int32>(segments.length);
    var allocated = 0;
    var consumed = false;
    try {
      for (var index = 0; index < segments.length; index += 1) {
        final segment = segments[index];
        final segmentPtr = allocate(segment.length);
        if (segment.isNotEmpty && segmentPtr == ffi.nullptr) {
          throw NativeTransportException(
            NativeTransportErrorCode.io,
            'Failed to allocate native outbound message segment',
          );
        }
        pointers[index] = segmentPtr;
        lengths[index] = segment.length;
        allocated += 1;
        if (segment.isNotEmpty) {
          segmentPtr.asTypedList(segment.length).setAll(0, segment);
        }
      }

      consumed = true;
      final result = sendSegments(
        connectionId,
        pointers,
        lengths,
        segments.length,
        fragmentSize,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send native transport segments');
      }
      return true;
    } finally {
      if (!consumed) {
        for (var index = 0; index < allocated; index += 1) {
          release(pointers[index], lengths[index]);
        }
      }
      malloc.free(lengths);
      malloc.free(pointers);
    }
  }

  int? _sendOwnedMessage(
    int connectionId,
    Uint8List payload, {
    int? fragmentSize,
  }) {
    final allocate = _bindings.ctOutboundBufferAlloc;
    final release = _bindings.ctOutboundBufferFree;
    final send = _bindings.ctSendMessageOwned;
    final sendFragmented = _bindings.ctSendMessageFragmentedOwned;
    if (allocate == null ||
        release == null ||
        send == null ||
        (fragmentSize != null && sendFragmented == null)) {
      return null;
    }

    final payloadPtr = allocate(payload.length);
    if (payload.isNotEmpty && payloadPtr == ffi.nullptr) {
      throw NativeTransportException(
        NativeTransportErrorCode.io,
        'Failed to allocate native outbound message buffer',
      );
    }

    var consumed = false;
    try {
      if (payload.isNotEmpty) {
        payloadPtr.asTypedList(payload.length).setAll(0, payload);
      }
      consumed = true;
      return fragmentSize == null
          ? send(connectionId, payloadPtr, payload.length)
          : sendFragmented!(
              connectionId,
              payloadPtr,
              payload.length,
              fragmentSize,
            );
    } finally {
      if (!consumed) {
        release(payloadPtr, payload.length);
      }
    }
  }

  int openFile(String path, {required int expectedLength}) {
    ensureStarted();
    if (expectedLength < 0) {
      throw ArgumentError.value(
        expectedLength,
        'expectedLength',
        'must be non-negative',
      );
    }
    final pathBytes = utf8.encode(path);
    if (pathBytes.isEmpty) {
      throw ArgumentError.value(path, 'path', 'path must not be empty');
    }
    final pathPtr = malloc<ffi.Char>(pathBytes.length);
    try {
      pathPtr
          .cast<ffi.Uint8>()
          .asTypedList(pathBytes.length)
          .setAll(
            0,
            pathBytes,
          );
      final result = _bindings.ctFileOpen(
        pathPtr,
        pathBytes.length,
        expectedLength,
      );
      if (result < 0) {
        _throwForError(result, 'Failed to open native file segment source');
      }
      return result;
    } finally {
      malloc.free(pathPtr);
    }
  }

  void releaseFile(int fileHandle) {
    ensureStarted();
    final result = _bindings.ctFileRelease(fileHandle);
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.handleUnavailable) {
      _throwForError(result, 'Failed to release native file segment source');
    }
  }

  void sendMessageFileSegment(
    int connectionId, {
    required Uint8List prefix,
    required int fileHandle,
    required int fileOffset,
    required int fileLength,
    Uint8List? suffix,
    bool encodeBase64 = false,
  }) {
    ensureStarted();
    if (fileOffset < 0 || fileLength < 0) {
      throw ArgumentError('fileOffset and fileLength must be non-negative');
    }
    final suffixBytes = suffix ?? Uint8List(0);
    var prefixPtr = ffi.nullptr.cast<ffi.Uint8>();
    var suffixPtr = ffi.nullptr.cast<ffi.Uint8>();
    try {
      if (prefix.isNotEmpty) {
        prefixPtr = malloc<ffi.Uint8>(prefix.length);
        prefixPtr.asTypedList(prefix.length).setAll(0, prefix);
      }
      if (suffixBytes.isNotEmpty) {
        suffixPtr = malloc<ffi.Uint8>(suffixBytes.length);
        suffixPtr.asTypedList(suffixBytes.length).setAll(0, suffixBytes);
      }
      final send = encodeBase64
          ? _bindings.ctSendMessageBase64FileSegment
          : _bindings.ctSendMessageFileSegment;
      final result = send(
        connectionId,
        prefixPtr,
        prefix.length,
        fileHandle,
        fileOffset,
        fileLength,
        suffixPtr,
        suffixBytes.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send native file segment');
      }
    } finally {
      if (prefixPtr != ffi.nullptr) {
        malloc.free(prefixPtr);
      }
      if (suffixPtr != ffi.nullptr) {
        malloc.free(suffixPtr);
      }
    }
  }

  void sendMessageNativeE2eeFileSegment(
    int connectionId, {
    required Uint8List prefix,
    required int fileHandle,
    required int fileOffset,
    required int fileLength,
    required int sessionHandle,
    required String keyId,
    required String cipher,
  }) {
    ensureStarted();
    if (fileOffset < 0 || fileLength < 0) {
      throw ArgumentError('fileOffset and fileLength must be non-negative');
    }
    final cipherCode = switch (cipher) {
      'xsalsa20poly1305' => 1,
      'aes256gcm' => 2,
      _ => throw ArgumentError.value(cipher, 'cipher', 'is unsupported'),
    };
    var prefixPtr = ffi.nullptr.cast<ffi.Uint8>();
    final keyIdPtr = keyId.toNativeUtf8().cast<ffi.Char>();
    try {
      if (prefix.isNotEmpty) {
        prefixPtr = malloc<ffi.Uint8>(prefix.length);
        prefixPtr.asTypedList(prefix.length).setAll(0, prefix);
      }
      final result = _bindings.ctSendMessageNativeE2eeFileSegment(
        connectionId,
        prefixPtr,
        prefix.length,
        fileHandle,
        fileOffset,
        fileLength,
        sessionHandle,
        keyIdPtr,
        utf8.encode(keyId).length,
        cipherCode,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send native E2EE file segment');
      }
    } finally {
      if (prefixPtr != ffi.nullptr) {
        malloc.free(prefixPtr);
      }
      malloc.free(keyIdPtr);
    }
  }

  int pollMessageHandle(int connectionId) {
    ensureStarted();
    final result = _bindings.ctPollConnectionMessage(connectionId);
    if (result < 0) {
      _throwForError(result, 'Polling native transport message failed');
    }
    return result;
  }

  int waitMessageHandle(int connectionId, {Duration? timeout}) {
    ensureStarted();
    final result = _bindings.ctWaitConnectionMessage(
      connectionId,
      timeout?.inMilliseconds ?? 0,
    );
    if (result < 0) {
      _throwForError(result, 'Waiting for native transport message failed');
    }
    return result;
  }

  Uint8List? _decodeJsonSingleBinaryArgument(int messageHandle) {
    final outputPtr = calloc<CtExternalByteBuffer>();
    try {
      final result = _bindings.ctMessageDecodeSingleBinaryArgument(
        messageHandle,
        outputPtr,
      );
      if (result == NativeTransportErrorCode.unsupported) {
        return null;
      }
      if (result != NativeTransportErrorCode.success) {
        _throwForError(
          result,
          'Failed to decode native JSON binary argument',
        );
      }
      final output = outputPtr.ref;
      if (output.owner == ffi.nullptr) {
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native JSON decode returned no external buffer owner',
        );
      }
      if (output.len == 0) {
        _bindings.ctExternalByteBufferFree(output.owner);
        return Uint8List(0);
      }
      if (output.ptr == ffi.nullptr) {
        _bindings.ctExternalByteBufferFree(output.owner);
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native JSON decode returned no external buffer bytes',
        );
      }
      Uint8List? bytes;
      try {
        bytes = output.ptr.asTypedList(
          output.len,
          finalizer: _bindings.ctExternalByteBufferFreePointer,
          token: output.owner,
        );
        _nativeExternalBytes[bytes] = _NativeExternalBytesReference(
          runtimeIdentity: this,
          pointer: output.ptr,
          length: output.len,
        );
        return bytes;
      } catch (_) {
        // Once asTypedList succeeds, its finalizer exclusively owns the token.
        if (bytes == null) {
          _bindings.ctExternalByteBufferFree(output.owner);
        }
        rethrow;
      }
    } finally {
      calloc.free(outputPtr);
    }
  }

  Uint8List? decodeCanonicalBase64Bytes(
    Uint8List input,
    int start,
    int end,
  ) {
    RangeError.checkValidRange(start, end, input.length);
    final decode = _bindings.ctBase64DecodeCanonical;
    if (decode == null) {
      return null;
    }

    final length = end - start;
    final externalInput = nativeExternalByteSlice(input, anchor: input);
    ffi.Pointer<ffi.Uint8> ownedInput = ffi.nullptr;
    final inputPtr = externalInput != null
        ? externalInput.pointer + start
        : (() {
            if (length == 0) {
              return ffi.nullptr;
            }
            ownedInput = malloc<ffi.Uint8>(length);
            ownedInput.asTypedList(length).setRange(0, length, input, start);
            return ownedInput;
          })();
    final outputPtr = calloc<CtExternalByteBuffer>();
    try {
      final result = decode(inputPtr, length, outputPtr);
      if (result == NativeTransportErrorCode.unsupported) {
        return null;
      }
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to decode canonical base64 bytes');
      }
      final output = outputPtr.ref;
      if (output.owner == ffi.nullptr) {
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native base64 decode returned no external buffer owner',
        );
      }
      if (output.len == 0) {
        _bindings.ctExternalByteBufferFree(output.owner);
        return Uint8List(0);
      }
      if (output.ptr == ffi.nullptr) {
        _bindings.ctExternalByteBufferFree(output.owner);
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native base64 decode returned no external buffer bytes',
        );
      }
      Uint8List? bytes;
      try {
        bytes = output.ptr.asTypedList(
          output.len,
          finalizer: _bindings.ctExternalByteBufferFreePointer,
          token: output.owner,
        );
        _nativeExternalBytes[bytes] = _NativeExternalBytesReference(
          runtimeIdentity: this,
          pointer: output.ptr,
          length: output.len,
        );
        return bytes;
      } catch (_) {
        // Once asTypedList succeeds, its finalizer exclusively owns the token.
        if (bytes == null) {
          _bindings.ctExternalByteBufferFree(output.owner);
        }
        rethrow;
      }
    } finally {
      if (ownedInput != ffi.nullptr) {
        malloc.free(ownedInput);
      }
      if (externalInput != null) {
        identityHashCode(externalInput.owner);
      }
      calloc.free(outputPtr);
    }
  }

  Uint8List? encodeCanonicalBase64Bytes(Uint8List input) {
    final encode = _bindings.ctBase64EncodeCanonical;
    if (encode == null) {
      return null;
    }

    final externalInput = nativeExternalByteSlice(input, anchor: input);
    ffi.Pointer<ffi.Uint8> ownedInput = ffi.nullptr;
    final inputPtr =
        externalInput?.pointer ??
        (() {
          if (input.isEmpty) {
            return ffi.nullptr;
          }
          ownedInput = malloc<ffi.Uint8>(input.length);
          ownedInput.asTypedList(input.length).setAll(0, input);
          return ownedInput;
        })();
    final outputPtr = calloc<CtExternalByteBuffer>();
    try {
      final result = encode(inputPtr, input.length, outputPtr);
      if (result == NativeTransportErrorCode.unsupported) {
        return null;
      }
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to encode canonical base64 bytes');
      }
      final output = outputPtr.ref;
      if (output.owner == ffi.nullptr) {
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native base64 encode returned no external buffer owner',
        );
      }
      if (output.len == 0) {
        _bindings.ctExternalByteBufferFree(output.owner);
        return Uint8List(0);
      }
      if (output.ptr == ffi.nullptr) {
        _bindings.ctExternalByteBufferFree(output.owner);
        throw NativeTransportException(
          NativeTransportErrorCode.handleUnavailable,
          'Native base64 encode returned no external buffer bytes',
        );
      }
      Uint8List? bytes;
      try {
        bytes = output.ptr.asTypedList(
          output.len,
          finalizer: _bindings.ctExternalByteBufferFreePointer,
          token: output.owner,
        );
        _nativeExternalBytes[bytes] = _NativeExternalBytesReference(
          runtimeIdentity: this,
          pointer: output.ptr,
          length: output.len,
        );
        return bytes;
      } catch (_) {
        // Once asTypedList succeeds, its finalizer exclusively owns the token.
        if (bytes == null) {
          _bindings.ctExternalByteBufferFree(output.owner);
        }
        rethrow;
      }
    } finally {
      if (ownedInput != ffi.nullptr) {
        malloc.free(ownedInput);
      }
      if (externalInput != null) {
        identityHashCode(externalInput.owner);
      }
      calloc.free(outputPtr);
    }
  }

  NativeIncomingMessage materialize(int handle) {
    ensureStarted();
    final infoPtr = calloc<CtMessageInfo>();
    try {
      var result = _bindings.ctMessagePeek(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to peek native message');
      }
      var info = infoPtr.ref;
      final serializer = NativeMessageSerializer.fromId(info.serializer);
      final args = info.argsLen == 0
          ? null
          : info.argsPtr.asTypedList(info.argsLen);
      final kwargs = info.kwargsLen == 0
          ? null
          : info.kwargsPtr.asTypedList(info.kwargsLen);
      final metadata = _metadataFromFfi(info);
      var singleBinaryArgument = info.binaryArgPtr == ffi.nullptr
          ? null
          : info.binaryArgPtr.asTypedList(info.binaryArgLen);
      if (singleBinaryArgument == null &&
          serializer == NativeMessageSerializer.json &&
          info.messageCode == 68 &&
          kwargs == null) {
        singleBinaryArgument = _decodeJsonSingleBinaryArgument(handle);
      }

      Uint8List frame;
      Object message;
      if (metadata.hasFlag(NativeMessageMetadata.flagMetadataBind)) {
        frame = Uint8List(0);
        message = bindSessionMessage(
          serializer,
          frame,
          argsBytes: args,
          kwargsBytes: kwargs,
          metadata: metadata,
        );
      } else {
        result = _bindings.ctMessageGet(handle, infoPtr);
        if (result != NativeTransportErrorCode.success) {
          _throwForError(result, 'Failed to materialize native message');
        }
        info = infoPtr.ref;
        frame = info.frameLen == 0
            ? Uint8List(0)
            : info.framePtr.asTypedList(info.frameLen);
        message = bindSessionMessage(
          serializer,
          frame,
          argsBytes: args,
          kwargsBytes: kwargs,
          metadata: metadata,
        );
      }
      final incoming = NativeIncomingMessage._(
        message: message,
        bytes: frame,
        handle: handle,
        runtimeIdentity: this,
        bindings: _bindings,
        messageFinalizer: _messageFinalizer,
        argumentsBytes: args,
        argumentsKeywordsBytes: kwargs,
        singleBinaryArgumentBytes: singleBinaryArgument,
      );
      final token = _MessageFinalizerToken(_bindings, handle);
      _messageFinalizer.attach(incoming, token, detach: incoming);
      return incoming;
    } catch (_) {
      _bindings.ctMessageRelease(handle);
      rethrow;
    } finally {
      calloc.free(infoPtr);
    }
  }

  Never _throwForError(int code, String context) {
    throw NativeTransportException(
      code,
      _buildNativeErrorMessage(code, context),
    );
  }

  int createSha256State() {
    ensureStarted();
    final handle = _bindings.ctSha256New();
    if (handle < 0) {
      _throwForError(handle, 'Failed to create native SHA-256 state');
    }
    return handle;
  }

  int updateSha256WithMessageBinaryArgument(
    int sha256Handle,
    int messageHandle,
  ) {
    ensureStarted();
    final result = _bindings.ctSha256UpdateMessageBinaryArgument(
      sha256Handle,
      messageHandle,
    );
    if (result < 0) {
      _throwForError(
        result,
        'Failed to hash native message binary argument',
      );
    }
    return result;
  }

  int updateSha256(
    int sha256Handle,
    Uint8List bytes, {
    Object? anchor,
  }) {
    ensureStarted();
    final nativeBytes = _nativeExternalBytes[bytes];
    if (nativeBytes != null &&
        identical(nativeBytes.runtimeIdentity, this) &&
        nativeBytes.length == bytes.length) {
      final result = nativeBytes.length >= _asyncSha256MinimumBytes
          ? _bindings.ctSha256UpdateAsync(
              sha256Handle,
              nativeBytes.pointer,
              nativeBytes.length,
            )
          : _bindings.ctSha256Update(
              sha256Handle,
              nativeBytes.pointer,
              nativeBytes.length,
            );
      if (result < 0) {
        _throwForError(result, 'Failed to hash native external byte payload');
      }
      return result;
    }
    final externalBytes = nativeExternalByteSlice(bytes, anchor: anchor);
    if (externalBytes != null) {
      try {
        final result = _bindings.ctSha256Update(
          sha256Handle,
          externalBytes.pointer,
          externalBytes.length,
        );
        if (result < 0) {
          _throwForError(
            result,
            'Failed to hash external byte payload',
          );
        }
        return result;
      } finally {
        identityHashCode(externalBytes.owner);
      }
    }
    final allocate = _bindings.ctOutboundBufferAlloc;
    final release = _bindings.ctOutboundBufferFree;
    final updateOwnedAsync = _bindings.ctSha256UpdateOwnedAsync;
    if (bytes.length >= _asyncSha256MinimumBytes &&
        allocate != null &&
        release != null &&
        updateOwnedAsync != null) {
      final bytesPtr = allocate(bytes.length);
      if (bytesPtr == ffi.nullptr) {
        throw NativeTransportException(
          NativeTransportErrorCode.io,
          'Failed to allocate native SHA-256 input buffer',
        );
      }
      var consumed = false;
      try {
        bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
        consumed = true;
        final result = updateOwnedAsync(
          sha256Handle,
          bytesPtr,
          bytes.length,
        );
        if (result < 0) {
          _throwForError(result, 'Failed to hash owned native byte payload');
        }
        return result;
      } finally {
        if (!consumed) {
          release(bytesPtr, bytes.length);
        }
      }
    }

    final bytesPtr = malloc<ffi.Uint8>(bytes.length);
    try {
      bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      // Older native libraries retain the borrowed-input compatibility path.
      final result = bytes.length >= _asyncSha256MinimumBytes
          ? _bindings.ctSha256UpdateAsync(
              sha256Handle,
              bytesPtr,
              bytes.length,
            )
          : _bindings.ctSha256Update(
              sha256Handle,
              bytesPtr,
              bytes.length,
            );
      if (result < 0) {
        _throwForError(result, 'Failed to hash native byte payload');
      }
      return result;
    } finally {
      malloc.free(bytesPtr);
    }
  }

  Uint8List finalizeSha256State(int sha256Handle) {
    ensureStarted();
    const digestLength = 32;
    final digestPtr = calloc<ffi.Uint8>(digestLength);
    try {
      final result = _bindings.ctSha256Finalize(
        sha256Handle,
        digestPtr,
        digestLength,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to finalize native SHA-256 state');
      }
      return Uint8List.fromList(digestPtr.asTypedList(digestLength));
    } finally {
      calloc.free(digestPtr);
    }
  }

  void releaseSha256State(int sha256Handle) {
    ensureStarted();
    final result = _bindings.ctSha256Release(sha256Handle);
    if (result != NativeTransportErrorCode.success &&
        result != NativeTransportErrorCode.handleUnavailable) {
      _throwForError(result, 'Failed to release native SHA-256 state');
    }
  }

  void releaseMessageHandle(int handle) {
    ensureStarted();
    _bindings.ctMessageRelease(handle);
  }
}

NativeMessageMetadata _metadataFromFfi(CtMessageInfo info) {
  final flags = info.flags;
  final metadataBind = (flags & NativeMessageMetadata.flagMetadataBind) != 0;
  return NativeMessageMetadata(
    messageCode: info.messageCode,
    primaryId: info.primaryId,
    secondaryId: info.secondaryId,
    detailNumberA: info.detailNumberA,
    detailNumberB: info.detailNumberB,
    flags: flags,
    detailsBytes: metadataBind
        ? _readOptionalBytes(info.detailsPtr, info.detailsLen)
        : null,
    stringA: metadataBind
        ? _readOptionalString(info.stringAPtr, info.stringALen)
        : null,
    stringB: metadataBind
        ? _readOptionalString(info.stringBPtr, info.stringBLen)
        : null,
    stringC: metadataBind
        ? _readOptionalString(info.stringCPtr, info.stringCLen)
        : null,
    stringD: metadataBind
        ? _readOptionalString(info.stringDPtr, info.stringDLen)
        : null,
    stringE: metadataBind
        ? _readOptionalString(info.stringEPtr, info.stringELen)
        : null,
  );
}

String _buildNativeErrorMessage(int code, String context) {
  return switch (code) {
    NativeTransportErrorCode.unsupported =>
      '$context: native runtime unsupported on this platform',
    NativeTransportErrorCode.alreadyStarted =>
      '$context: native runtime already started',
    NativeTransportErrorCode.runtimeNotStarted =>
      '$context: native runtime not started',
    NativeTransportErrorCode.invalidArgument =>
      '$context: invalid argument passed to native runtime',
    NativeTransportErrorCode.io => '$context: native I/O failure',
    NativeTransportErrorCode.connectionNotFound =>
      '$context: native connection not found',
    NativeTransportErrorCode.handleUnavailable =>
      '$context: native handle is unavailable',
    NativeTransportErrorCode.unsupportedSerializer =>
      '$context: serializer is unsupported by the native runtime',
    NativeTransportErrorCode.sendQueueFull =>
      '$context: native send queue is full',
    NativeTransportErrorCode.keyNotFound =>
      '$context: native E2EE key was not found',
    NativeTransportErrorCode.decryptionFailed =>
      '$context: native E2EE payload could not be decrypted',
    _ => '$context: native error $code',
  };
}

Uint8List _copyAndFreeByteBuffer(CtByteBuffer buffer) {
  if (buffer.ptr == ffi.nullptr || buffer.len == 0) {
    return Uint8List(0);
  }
  final bytes = Uint8List.fromList(buffer.ptr.asTypedList(buffer.len));
  NativeClientRuntime.instance()._bindings.ctByteBufferFree(
    buffer.ptr,
    buffer.len,
  );
  return bytes;
}

abstract final class NativeLibraryLoader {
  static String get _libraryFileName => switch (Platform.operatingSystem) {
    'linux' => 'libct_ffi.so',
    'macos' => 'libct_ffi.dylib',
    'windows' => 'ct_ffi.dll',
    _ => 'libct_ffi.so',
  };

  static String get _hookLibraryFileName => switch (Platform.operatingSystem) {
    'linux' => 'libconnectanum_client_ct_ffi.so',
    'macos' => 'libconnectanum_client_ct_ffi.dylib',
    'windows' => 'connectanum_client_ct_ffi.dll',
    _ => 'libconnectanum_client_ct_ffi.so',
  };

  static String resolvePath({
    String? override,
    bool ignoreEnvironmentOverride = false,
  }) {
    if (override != null && override.isNotEmpty) {
      return override;
    }
    if (!ignoreEnvironmentOverride) {
      final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
      if (envOverride != null && envOverride.isNotEmpty) {
        return envOverride;
      }
    }
    for (final candidate in _relativeCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    final hooks = _probeHooksRunner(Directory.current);
    if (hooks != null) {
      return hooks;
    }
    return _libraryFileName;
  }

  static Iterable<String> get _relativeCandidates sync* {
    final name = _libraryFileName;
    yield 'native/transport/target/debug/$name';
    yield 'native/transport/target/release/$name';
    yield '../native/transport/target/debug/$name';
    yield '../native/transport/target/release/$name';
    yield '../../native/transport/target/debug/$name';
    yield '../../native/transport/target/release/$name';
    yield '../../../native/transport/target/debug/$name';
    yield '../../../native/transport/target/release/$name';
  }

  static String? _probeHooksRunner(Directory anchor) {
    final names = <String>[_hookLibraryFileName, _libraryFileName];
    var current = anchor.absolute;
    for (var depth = 0; depth < 8; depth++) {
      final base = Directory(
        '${current.path}/.dart_tool/hooks_runner/shared/connectanum_client/build',
      );
      if (base.existsSync()) {
        for (final name in names) {
          final resolved = _freshestHookArtifact(base, name);
          if (resolved != null) {
            return resolved;
          }
        }
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    return null;
  }

  static String? _freshestHookArtifact(Directory base, String fileName) {
    File? freshest;
    for (final entity in base.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final file = File('${entity.path}/$fileName');
      if (!file.existsSync()) {
        continue;
      }
      if (freshest == null ||
          file.lastModifiedSync().isAfter(freshest.lastModifiedSync())) {
        freshest = file;
      }
    }
    return freshest?.path;
  }
}
