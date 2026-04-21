import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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
  static const sendQueueFull = -17;
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
    required CtFfiBindings bindings,
    this.argumentsBytes,
    this.argumentsKeywordsBytes,
  }) : _bindings = bindings;

  final Object message;
  final Uint8List bytes;
  final int handle;
  final Uint8List? argumentsBytes;
  final Uint8List? argumentsKeywordsBytes;
  final CtFfiBindings _bindings;

  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _bindings.ctMessageRelease(handle);
  }
}

class _MessageFinalizerToken {
  const _MessageFinalizerToken(this.bindings, this.handle);

  final CtFfiBindings bindings;
  final int handle;
}

void _finalizeNativeMessage(_MessageFinalizerToken token) {
  token.bindings.ctMessageRelease(token.handle);
}

class NativeClientRuntime {
  factory NativeClientRuntime.instance({String? libraryPath}) {
    final current = _instance;
    if (current != null) {
      return current;
    }
    final resolvedPath = NativeLibraryLoader.resolvePath(libraryPath);
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

  void closeConnection(int connectionId) {
    ensureStarted();
    final result = _bindings.ctConnectionClose(connectionId);
    if (result < 0 && result != NativeTransportErrorCode.connectionNotFound) {
      _throwForError(result, 'Failed to close native transport connection');
    }
  }

  void sendMessage(int connectionId, Uint8List payload) {
    ensureStarted();
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
        bindings: _bindings,
        argumentsBytes: args,
        argumentsKeywordsBytes: kwargs,
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
    NativeTransportErrorCode.unsupportedSerializer =>
      '$context: serializer is unsupported by the native runtime',
    NativeTransportErrorCode.sendQueueFull =>
      '$context: native send queue is full',
    _ => '$context: native error $code',
  };
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

  static String resolvePath([String? override]) {
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
    if (envOverride != null && envOverride.isNotEmpty) {
      return envOverride;
    }
    final hooks = _probeHooksRunner(Directory.current);
    if (hooks != null) {
      return hooks;
    }
    for (final candidate in _relativeCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    throw StateError(
      'Failed to locate $_libraryFileName. Set CONNECTANUM_NATIVE_LIB or build ct_ffi first.',
    );
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
