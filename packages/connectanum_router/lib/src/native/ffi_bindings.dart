import 'dart:ffi' as ffi;

typedef CtStartRuntimeNative = ffi.Int32 Function();
typedef CtStartRuntimeDart = int Function();

typedef CtShutdownNative = ffi.Int32 Function();
typedef CtShutdownDart = int Function();

typedef CtListenNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Uint32, ffi.Int32);
typedef CtListenDart = int Function(ffi.Pointer<ffi.Char>, int, int);

typedef CtGetLocalPortNative = ffi.Int32 Function(ffi.Int32);
typedef CtGetLocalPortDart = int Function(int);

typedef CtPollConnectionNative = ffi.Int32 Function(ffi.Int32);
typedef CtPollConnectionDart = int Function(int);

typedef CtPollConnectionMessageNative = ffi.Int32 Function(ffi.Int32);
typedef CtPollConnectionMessageDart = int Function(int);

typedef CtMessageGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtMessageInfo>);
typedef CtMessageGetDart = int Function(int, ffi.Pointer<CtMessageInfo>);

typedef CtMessageReleaseNative = ffi.Void Function(ffi.Int32);
typedef CtMessageReleaseDart = void Function(int);

typedef CtApplyRouterConfigNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtApplyRouterConfigDart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef CtConnectionMaxRawsocketExponentNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionMaxRawsocketExponentDart = int Function(int);

typedef ListenerCallbackNative = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef ConnectionCallbackNative = ffi.Void Function(ffi.Int32, ffi.Int32);

typedef CtSetOnListenerStartedNative =
    ffi.Void Function(ffi.Pointer<ffi.NativeFunction<ListenerCallbackNative>>);
typedef CtSetOnListenerStartedDart =
    void Function(ffi.Pointer<ffi.NativeFunction<ListenerCallbackNative>>);

typedef CtSetOnConnectionNative =
    ffi.Void Function(
      ffi.Pointer<ffi.NativeFunction<ConnectionCallbackNative>>,
    );
typedef CtSetOnConnectionDart =
    void Function(ffi.Pointer<ffi.NativeFunction<ConnectionCallbackNative>>);

final class CtMessageInfo extends ffi.Struct {
  @ffi.Uint8()
  external int serializer;

  @ffi.Uint64()
  external int messageCode;

  external ffi.Pointer<ffi.Uint8> framePtr;

  @ffi.Size()
  external int frameLen;

  external ffi.Pointer<ffi.Uint8> argsPtr;

  @ffi.Size()
  external int argsLen;

  external ffi.Pointer<ffi.Uint8> kwargsPtr;

  @ffi.Size()
  external int kwargsLen;
}

/// Thin wrapper around the ct_ffi dynamic library.
class CtFfiBindings {
  CtFfiBindings(ffi.DynamicLibrary library)
    : ctStartRuntime = library
          .lookupFunction<CtStartRuntimeNative, CtStartRuntimeDart>(
            'ct_start_runtime',
          ),
      ctShutdown = library.lookupFunction<CtShutdownNative, CtShutdownDart>(
        'ct_shutdown',
      ),
      ctListen = library.lookupFunction<CtListenNative, CtListenDart>(
        'ct_listen',
      ),
      ctGetLocalPort = library
          .lookupFunction<CtGetLocalPortNative, CtGetLocalPortDart>(
            'ct_get_local_port',
          ),
      ctPollConnection = library
          .lookupFunction<CtPollConnectionNative, CtPollConnectionDart>(
            'ct_poll_connection',
          ),
      ctPollConnectionMessage = library
          .lookupFunction<
            CtPollConnectionMessageNative,
            CtPollConnectionMessageDart
          >('ct_poll_connection_message'),
      ctMessageGet = library
          .lookupFunction<CtMessageGetNative, CtMessageGetDart>(
            'ct_message_get',
          ),
      ctMessageRelease = library
          .lookupFunction<CtMessageReleaseNative, CtMessageReleaseDart>(
            'ct_message_release',
          ),
      ctApplyRouterConfig = library
          .lookupFunction<CtApplyRouterConfigNative, CtApplyRouterConfigDart>(
            'ct_apply_router_config',
          ),
      ctConnectionMaxRawsocketExponent = library
          .lookupFunction<
            CtConnectionMaxRawsocketExponentNative,
            CtConnectionMaxRawsocketExponentDart
          >('ct_connection_max_rawsocket_exponent'),
      ctSetOnListenerStarted = library
          .lookupFunction<
            CtSetOnListenerStartedNative,
            CtSetOnListenerStartedDart
          >('ct_set_on_listener_started'),
      ctSetOnConnection = library
          .lookupFunction<CtSetOnConnectionNative, CtSetOnConnectionDart>(
            'ct_set_on_connection',
          );

  final CtStartRuntimeDart ctStartRuntime;
  final CtShutdownDart ctShutdown;
  final CtListenDart ctListen;
  final CtGetLocalPortDart ctGetLocalPort;
  final CtPollConnectionDart ctPollConnection;
  final CtPollConnectionMessageDart ctPollConnectionMessage;
  final CtMessageGetDart ctMessageGet;
  final CtMessageReleaseDart ctMessageRelease;
  final CtApplyRouterConfigDart ctApplyRouterConfig;
  final CtConnectionMaxRawsocketExponentDart ctConnectionMaxRawsocketExponent;
  final CtSetOnListenerStartedDart ctSetOnListenerStarted;
  final CtSetOnConnectionDart ctSetOnConnection;
}
