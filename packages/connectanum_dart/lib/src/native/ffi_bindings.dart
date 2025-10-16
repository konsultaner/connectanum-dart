import 'dart:ffi' as ffi;

typedef CtStartRuntimeNative = ffi.Int32 Function();
typedef CtStartRuntimeDart = int Function();

typedef CtShutdownNative = ffi.Int32 Function();
typedef CtShutdownDart = int Function();

typedef CtListenNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Char>,
  ffi.Uint32,
  ffi.Int32,
);
typedef CtListenDart = int Function(
  ffi.Pointer<ffi.Char>,
  int,
  int,
);

typedef CtGetLocalPortNative = ffi.Int32 Function(ffi.Int32);
typedef CtGetLocalPortDart = int Function(int);

typedef CtPollConnectionNative = ffi.Int32 Function(ffi.Int32);
typedef CtPollConnectionDart = int Function(int);

typedef ListenerCallbackNative = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef ConnectionCallbackNative = ffi.Void Function(ffi.Int32, ffi.Int32);

typedef CtSetOnListenerStartedNative = ffi.Void Function(
  ffi.Pointer<ffi.NativeFunction<ListenerCallbackNative>>,
);
typedef CtSetOnListenerStartedDart = void Function(
  ffi.Pointer<ffi.NativeFunction<ListenerCallbackNative>>,
);

typedef CtSetOnConnectionNative = ffi.Void Function(
  ffi.Pointer<ffi.NativeFunction<ConnectionCallbackNative>>,
);
typedef CtSetOnConnectionDart = void Function(
  ffi.Pointer<ffi.NativeFunction<ConnectionCallbackNative>>,
);

/// Thin wrapper around the ct_ffi dynamic library.
class CtFfiBindings {
  CtFfiBindings(ffi.DynamicLibrary library)
      : ctStartRuntime =
            library.lookupFunction<CtStartRuntimeNative, CtStartRuntimeDart>(
          'ct_start_runtime',
        ),
        ctShutdown = library.lookupFunction<CtShutdownNative, CtShutdownDart>(
          'ct_shutdown',
        ),
        ctListen = library.lookupFunction<CtListenNative, CtListenDart>(
          'ct_listen',
        ),
        ctGetLocalPort =
            library.lookupFunction<CtGetLocalPortNative, CtGetLocalPortDart>(
          'ct_get_local_port',
        ),
        ctPollConnection = library
            .lookupFunction<CtPollConnectionNative, CtPollConnectionDart>(
          'ct_poll_connection',
        ),
        ctSetOnListenerStarted = library.lookupFunction<
            CtSetOnListenerStartedNative, CtSetOnListenerStartedDart>(
          'ct_set_on_listener_started',
        ),
        ctSetOnConnection = library
            .lookupFunction<CtSetOnConnectionNative, CtSetOnConnectionDart>(
          'ct_set_on_connection',
        );

  final CtStartRuntimeDart ctStartRuntime;
  final CtShutdownDart ctShutdown;
  final CtListenDart ctListen;
  final CtGetLocalPortDart ctGetLocalPort;
  final CtPollConnectionDart ctPollConnection;
  final CtSetOnListenerStartedDart ctSetOnListenerStarted;
  final CtSetOnConnectionDart ctSetOnConnection;
}
