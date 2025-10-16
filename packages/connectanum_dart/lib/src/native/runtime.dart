import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';

abstract class NativeRuntime {
  void start();
  void shutdown();
  int listen(String host, int port, {int backlog = 128});
  int getLocalPort(int listenerId);
  int pollConnection(int listenerId);
  void applyRouterConfig(Uint8List config);
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

/// Thin wrapper around the native runtime exposed through ct_ffi.
class NativeTransportRuntime implements NativeRuntime {
  factory NativeTransportRuntime({String? libraryPath}) {
    if (_instance != null) {
      throw StateError('NativeTransportRuntime already initialised');
    }
    final library = _openLibrary(libraryPath);
    final runtime = NativeTransportRuntime._(library, CtFfiBindings(library));
    _instance = runtime;
    runtime._bindings.ctSetOnListenerStarted(_listenerTrampolinePointer);
    runtime._bindings.ctSetOnConnection(_connectionTrampolinePointer);
    return runtime;
  }

  NativeTransportRuntime._(this._library, this._bindings);

  final ffi.DynamicLibrary
  _library; // Keep library alive for the runtime life cycle.
  final CtFfiBindings _bindings;

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

  static ffi.DynamicLibrary _openLibrary(String? overridePath) {
    final path = overridePath ?? _defaultLibraryPath();
    if (!File(path).existsSync()) {
      throw ArgumentError('ct_ffi dynamic library not found at $path');
    }
    return ffi.DynamicLibrary.open(path);
  }

  static String _defaultLibraryPath() {
    final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
    if (envOverride != null && envOverride.isNotEmpty) {
      return envOverride;
    }
    // Default to debug or release builds relative to the repo root.
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

  void _checkZero(int code, String context) {
    if (code != NativeTransportErrorCode.success) {
      _throwForError(code, context);
    }
  }

  void _throwForError(int code, String context) {
    final message = switch (code) {
      NativeTransportErrorCode.unsupported =>
        '$context: native runtime unsupported on this platform',
      NativeTransportErrorCode.alreadyStarted =>
        '$context: runtime already started',
      NativeTransportErrorCode.runtimeNotStarted =>
        '$context: runtime not started',
      NativeTransportErrorCode.invalidArgument =>
        '$context: invalid argument to native runtime',
      NativeTransportErrorCode.listenerNotFound =>
        '$context: listener not found',
      NativeTransportErrorCode.channelAlreadyTaken =>
        '$context: accept channel already taken',
      NativeTransportErrorCode.io => '$context: native I/O failure',
      _ => '$context: error code $code',
    };
    throw NativeTransportException(code, message);
  }

  @override
  void applyRouterConfig(Uint8List config) {
    throw UnsupportedError(
      'Native runtime configuration wiring not implemented yet',
    );
  }

  static void _listenerTrampoline(int listenerId, int status) {
    _instance?._onListenerStarted?.call(listenerId, status);
  }

  static void _connectionTrampoline(int listenerId, int connectionId) {
    _instance?._onConnection?.call(listenerId, connectionId);
  }
}
