import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' show AbstractMessage;
import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';
import 'message_binding.dart';

abstract class NativeRuntime {
  void start();
  void shutdown();
  int listen(String host, int port, {int backlog = 128});
  int getLocalPort(int listenerId);
  int pollConnection(int listenerId);
  int connectionMaxRawSocketExponent(int connectionId);
  void sendMessage(int connectionId, Uint8List payload);
  void applyRouterConfig(Uint8List config);
  NativeIncomingMessage? pollMessage(int connectionId);
}

/// Runtime extension that exposes raw message handles so other isolates can
/// materialise messages without crossing isolate boundaries.
abstract class NativeRuntimeWithHandles implements NativeRuntime {
  int pollMessageHandle(int connectionId);
  String? get libraryPathHint;
}

/// Error codes exposed by the native layer.
abstract final class NativeTransportErrorCode {
  static const success = 0;
  static const unsupported = -1;
  static const alreadyStarted = -2;
  static const runtimeNotStarted = -3;
  static const invalidArgument = -4;
  static const listenerNotFound = -5;
  static const channelAlreadyTaken = -6;
  static const io = -7;
  static const routerConfigInvalid = -8;
  static const endpointNotConfigured = -9;
  static const connectionNotFound = -10;
  static const unsupportedSerializer = -11;
}

/// Exception thrown when the native runtime reports an error.
class NativeTransportException implements Exception {
  NativeTransportException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() =>
      'NativeTransportException(code: $code, message: $message)';
}

enum NativeMessageSerializer {
  json(1),
  messagePack(2),
  cbor(3),
  ubjson(4),
  flatbuffers(5);

  const NativeMessageSerializer(this.id);

  final int id;

  static NativeMessageSerializer fromId(int id) {
    for (final serializer in NativeMessageSerializer.values) {
      if (serializer.id == id) {
        return serializer;
      }
    }
    throw StateError('Unsupported serializer id $id');
  }
}

class NativeIncomingMessage {
  NativeIncomingMessage._({
    required this.serializer,
    required this.message,
    required this.bytes,
    required this.frameAddress,
    required this.argumentsAddress,
    required this.argumentsKeywordsAddress,
    this.argumentsBytes,
    this.argumentsKeywordsBytes,
  });

  factory NativeIncomingMessage.synthetic({
    required NativeMessageSerializer serializer,
    required AbstractMessage message,
    Uint8List? bytes,
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
  }) {
    final frameBytes = bytes ?? Uint8List(0);
    final instance = NativeIncomingMessage._(
      serializer: serializer,
      message: message,
      bytes: frameBytes,
      frameAddress: frameBytes.isEmpty ? 0 : 1,
      argumentsAddress: argumentsBytes == null ? 0 : 1,
      argumentsKeywordsAddress: argumentsKeywordsBytes == null ? 0 : 1,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
    );
    instance._setReleaser(() {});
    return instance;
  }

  final NativeMessageSerializer serializer;
  final AbstractMessage message;
  final Uint8List bytes;
  final int frameAddress;
  final int argumentsAddress;
  final int argumentsKeywordsAddress;
  final Uint8List? argumentsBytes;
  final Uint8List? argumentsKeywordsBytes;

  bool _released = false;
  void Function()? _releaseHandle;

  void _setReleaser(void Function() releaseHandle) {
    _releaseHandle = releaseHandle;
  }

  bool _tryMarkReleased() {
    if (_released) {
      return false;
    }
    _released = true;
    return true;
  }

  void dispose() {
    final release = _releaseHandle;
    if (release != null) {
      _releaseHandle = null;
      release();
    }
  }
}

class _MessageFinalizerToken {
  const _MessageFinalizerToken(this._bindings, this.handle);

  final CtFfiBindings _bindings;
  final int handle;
}

void _finalizeNativeMessage(_MessageFinalizerToken token) {
  token._bindings.ctMessageRelease(token.handle);
}

class _MessageBindings {
  _MessageBindings(this._bindings)
    : _messageFinalizer = Finalizer<_MessageFinalizerToken>(
        _finalizeNativeMessage,
      );

  final CtFfiBindings _bindings;
  final Finalizer<_MessageFinalizerToken> _messageFinalizer;

  NativeIncomingMessage materialize(int handle) {
    final infoPtr = calloc<CtMessageInfo>();
    try {
      final result = _bindings.ctMessageGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctMessageRelease(handle);
        throw NativeTransportException(
          result,
          _buildNativeErrorMessage(result, 'Failed to read connection message'),
        );
      }

      final info = infoPtr.ref;
      final serializer = NativeMessageSerializer.fromId(info.serializer);
      final frameAddress = info.framePtr.address;
      final argsAddress = info.argsLen == 0 ? 0 : info.argsPtr.address;
      final kwargsAddress = info.kwargsLen == 0 ? 0 : info.kwargsPtr.address;
      final frame = info.frameLen == 0
          ? Uint8List(0)
          : info.framePtr.asTypedList(info.frameLen);
      final args = info.argsLen == 0
          ? null
          : info.argsPtr.asTypedList(info.argsLen);
      final kwargs = info.kwargsLen == 0
          ? null
          : info.kwargsPtr.asTypedList(info.kwargsLen);

      try {
        final message = bindMessage(
          serializer,
          frame,
          argsBytes: args,
          kwargsBytes: kwargs,
        );
        final nativeMessage = NativeIncomingMessage._(
          serializer: serializer,
          message: message,
          bytes: frame,
          frameAddress: frameAddress,
          argumentsAddress: argsAddress,
          argumentsKeywordsAddress: kwargsAddress,
          argumentsBytes: args,
          argumentsKeywordsBytes: kwargs,
        );
        final token = _MessageFinalizerToken(_bindings, handle);
        _messageFinalizer.attach(nativeMessage, token, detach: nativeMessage);
        nativeMessage._setReleaser(() {
          if (nativeMessage._tryMarkReleased()) {
            _messageFinalizer.detach(nativeMessage);
            _bindings.ctMessageRelease(handle);
          }
        });
        return nativeMessage;
      } on UnsupportedError catch (err) {
        _bindings.ctMessageRelease(handle);
        throw NativeTransportException(
          NativeTransportErrorCode.unsupportedSerializer,
          err.message ??
              'Deserializer for serializer ${serializer.name} is unsupported',
        );
      } on ArgumentError catch (err) {
        _bindings.ctMessageRelease(handle);
        throw NativeTransportException(
          NativeTransportErrorCode.invalidArgument,
          err.message ?? 'Invalid message payload',
        );
      }
    } catch (error) {
      _bindings.ctMessageRelease(handle);
      rethrow;
    } finally {
      calloc.free(infoPtr);
    }
  }
}

String _buildNativeErrorMessage(int code, String context) {
  return switch (code) {
    NativeTransportErrorCode.unsupported =>
      '$context: native runtime unsupported on this platform',
    NativeTransportErrorCode.alreadyStarted =>
      '$context: runtime already started',
    NativeTransportErrorCode.runtimeNotStarted =>
      '$context: runtime not started',
    NativeTransportErrorCode.invalidArgument =>
      '$context: invalid argument to native runtime',
    NativeTransportErrorCode.listenerNotFound => '$context: listener not found',
    NativeTransportErrorCode.connectionNotFound =>
      '$context: connection not found',
    NativeTransportErrorCode.unsupportedSerializer =>
      '$context: serializer not supported by native runtime',
    NativeTransportErrorCode.routerConfigInvalid =>
      '$context: router configuration invalid',
    NativeTransportErrorCode.endpointNotConfigured =>
      '$context: endpoint not configured in native runtime',
    NativeTransportErrorCode.channelAlreadyTaken =>
      '$context: accept channel already taken',
    NativeTransportErrorCode.io => '$context: native I/O failure',
    _ => '$context: error code $code',
  };
}

class NativeMessageHandleDecoder {
  factory NativeMessageHandleDecoder({String? libraryPath}) {
    final resolvedPath = NativeLibraryLoader.resolvePath(libraryPath);
    final library = ffi.DynamicLibrary.open(resolvedPath);
    final bindings = CtFfiBindings(library);
    return NativeMessageHandleDecoder._(resolvedPath, library, bindings);
  }

  NativeMessageHandleDecoder._(this.libraryPath, this._library, this._bindings)
    : _messageBindings = _MessageBindings(_bindings);

  final String libraryPath;
  // ignore: unused_field
  final ffi.DynamicLibrary _library;
  final CtFfiBindings _bindings;
  final _MessageBindings _messageBindings;

  NativeIncomingMessage materialize(int handle) =>
      _messageBindings.materialize(handle);

  void release(int handle) => _bindings.ctMessageRelease(handle);
}

abstract final class NativeLibraryLoader {
  static String resolvePath(String? overridePath) {
    if (overridePath != null && overridePath.isNotEmpty) {
      return overridePath;
    }
    final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
    if (envOverride != null && envOverride.isNotEmpty) {
      return envOverride;
    }
    const candidates = [
      '../native/transport/target/debug/libct_ffi.so',
      '../native/transport/target/release/libct_ffi.so',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return candidates.first;
  }
}

/// Thin wrapper around the native runtime exposed through ct_ffi.
class NativeTransportRuntime implements NativeRuntimeWithHandles {
  factory NativeTransportRuntime({String? libraryPath}) {
    if (_instance != null) {
      throw StateError('NativeTransportRuntime already initialised');
    }
    final resolvedPath = NativeLibraryLoader.resolvePath(libraryPath);
    final library = ffi.DynamicLibrary.open(resolvedPath);
    final runtime = NativeTransportRuntime._(
      resolvedPath,
      library,
      CtFfiBindings(library),
    );
    _instance = runtime;
    runtime._bindings.ctSetOnListenerStarted(_listenerTrampolinePointer);
    runtime._bindings.ctSetOnConnection(_connectionTrampolinePointer);
    return runtime;
  }

  NativeTransportRuntime._(this._libraryPath, this._library, this._bindings)
    : _messageBindings = _MessageBindings(_bindings);

  final String _libraryPath;
  // ignore: unused_field
  final ffi.DynamicLibrary _library; // Keep library alive for the runtime life cycle.
  final CtFfiBindings _bindings;
  final _MessageBindings _messageBindings;

  static NativeTransportRuntime? _instance;

  void Function(int listenerId, int status)? _onListenerStarted;
  void Function(int listenerId, int connectionId)? _onConnection;

  static final ffi.Pointer<ffi.NativeFunction<ListenerCallbackNative>>
  _listenerTrampolinePointer = ffi.Pointer.fromFunction<ListenerCallbackNative>(
    _listenerTrampoline,
  );
  static final ffi.Pointer<ffi.NativeFunction<ConnectionCallbackNative>>
  _connectionTrampolinePointer =
      ffi.Pointer.fromFunction<ConnectionCallbackNative>(_connectionTrampoline);

  void dispose() {
    if (_instance == this) {
      _instance = null;
    }
    _onListenerStarted = null;
    _onConnection = null;
  }

  void setListenerCallbacks({
    void Function(int listenerId, int status)? onStarted,
    void Function(int listenerId, int connectionId)? onConnection,
  }) {
    _onListenerStarted = onStarted;
    _onConnection = onConnection;
  }

  @override
  void start() =>
      _checkZero(_bindings.ctStartRuntime(), 'Failed to start runtime');

  @override
  void shutdown() =>
      _checkZero(_bindings.ctShutdown(), 'Failed to shutdown runtime');

  @override
  int listen(String host, int port, {int backlog = 128}) {
    if (backlog <= 0) {
      throw ArgumentError.value(backlog, 'backlog', 'Must be positive');
    }
    return using((arena) {
      final hostPtr = host.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      final result = _bindings.ctListen(hostPtr, port, backlog);
      if (result < 0) {
        _throwForError(result, 'Failed to create listener');
      }
      return result;
    });
  }

  @override
  int getLocalPort(int listenerId) {
    final result = _bindings.ctGetLocalPort(listenerId);
    if (result < 0) {
      _throwForError(result, 'Failed to query local port');
    }
    return result;
  }

  @override
  int pollConnection(int listenerId) {
    final result = _bindings.ctPollConnection(listenerId);
    if (result == NativeTransportErrorCode.listenerNotFound) {
      throw NativeTransportException(result, 'Listener $listenerId not found');
    }
    if (result < 0) {
      _throwForError(result, 'Polling connections failed');
    }
    return result;
  }

  @override
  int connectionMaxRawSocketExponent(int connectionId) {
    final result = _bindings.ctConnectionMaxRawsocketExponent(connectionId);
    if (result < 0) {
      _throwForError(result, 'Failed to query raw socket exponent');
    }
    return result;
  }

  @override
  void sendMessage(int connectionId, Uint8List payload) {
    if (payload.isEmpty) {
      final result = _bindings.ctSendMessage(
        connectionId,
        ffi.nullptr.cast(),
        0,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send message');
      }
      return;
    }
    final ptr = calloc<ffi.Uint8>(payload.length);
    try {
      ptr.asTypedList(payload.length).setAll(0, payload);
      final result = _bindings.ctSendMessage(
        connectionId,
        ptr,
        payload.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send message');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  void _checkZero(int code, String context) {
    if (code != NativeTransportErrorCode.success) {
      _throwForError(code, context);
    }
  }

  void _throwForError(int code, String context) {
    final message = _buildNativeErrorMessage(code, context);
    throw NativeTransportException(code, message);
  }

  @override
  void applyRouterConfig(Uint8List config) {
    if (config.isEmpty) {
      return;
    }
    final ptr = calloc<ffi.Uint8>(config.length);
    try {
      ptr.asTypedList(config.length).setAll(0, config);
      final result = _bindings.ctApplyRouterConfig(ptr, config.length);
      _checkZero(result, 'Failed to apply router configuration');
    } finally {
      calloc.free(ptr);
    }
  }

  static void _listenerTrampoline(int listenerId, int status) {
    _instance?._onListenerStarted?.call(listenerId, status);
  }

  static void _connectionTrampoline(int listenerId, int connectionId) {
    _instance?._onConnection?.call(listenerId, connectionId);
  }

  @override
  NativeIncomingMessage? pollMessage(int connectionId) {
    final handle = pollMessageHandle(connectionId);
    if (handle == 0) {
      return null;
    }
    return _messageBindings.materialize(handle);
  }

  @override
  int pollMessageHandle(int connectionId) {
    final handle = _bindings.ctPollConnectionMessage(connectionId);
    if (handle == 0) {
      return 0;
    }
    if (handle < 0) {
      _throwForError(handle, 'Polling connection message failed');
    }
    return handle;
  }

  String get libraryPath => _libraryPath;

  @override
  String? get libraryPathHint => _libraryPath;
}
