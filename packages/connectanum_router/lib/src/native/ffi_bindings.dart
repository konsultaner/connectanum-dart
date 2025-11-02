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

typedef CtMessageRetainNative = ffi.Int32 Function(ffi.Int32);
typedef CtMessageRetainDart = int Function(int);

typedef CtSendMessageNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtSendMessageDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef CtForwardPublishEventNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Int32,
      ffi.Uint64,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
    );
typedef CtForwardPublishEventDart =
    int Function(int, int, int, int, int, int, ffi.Pointer<ffi.Char>, int);

typedef CtForwardCallInvocationNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Int32,
      ffi.Uint64,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
    );
typedef CtForwardCallInvocationDart =
    int Function(int, int, int, int, int, int, ffi.Pointer<ffi.Char>, int, int);

typedef CtForwardResultFromYieldNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint64, ffi.Int32);
typedef CtForwardResultFromYieldDart = int Function(int, int, int, int);

typedef CtForwardErrorFromErrorNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Uint64, ffi.Uint64);
typedef CtForwardErrorFromErrorDart = int Function(int, int, int, int);

typedef CtTestMessageEnqueueNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtTestMessageEnqueueDart =
    int Function(int, int, ffi.Pointer<ffi.Uint8>, int);

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

typedef CtTestClearMessagesNative = ffi.Int32 Function();
typedef CtTestClearMessagesDart = int Function();

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
      ctMessageRetain = library
          .lookupFunction<CtMessageRetainNative, CtMessageRetainDart>(
            'ct_message_retain',
          ),
      ctForwardPublishEvent = library
          .lookupFunction<
            CtForwardPublishEventNative,
            CtForwardPublishEventDart
          >('ct_forward_publish_event'),
      ctForwardCallInvocation = library
          .lookupFunction<
            CtForwardCallInvocationNative,
            CtForwardCallInvocationDart
          >('ct_forward_call_invocation'),
      ctForwardResultFromYield = library
          .lookupFunction<
            CtForwardResultFromYieldNative,
            CtForwardResultFromYieldDart
          >('ct_forward_result_from_yield'),
      ctForwardErrorFromError = library
          .lookupFunction<
            CtForwardErrorFromErrorNative,
            CtForwardErrorFromErrorDart
          >('ct_forward_error_from_error'),
      ctSendMessage = _lookupSendMessage(library),
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
          ),
      ctTestMessageEnqueue = _tryLookup(
        () =>
            library.lookupFunction<
              CtTestMessageEnqueueNative,
              CtTestMessageEnqueueDart
            >('ct_test_message_enqueue'),
      ),
      ctTestClearMessages = _tryLookup(
        () => library
            .lookupFunction<CtTestClearMessagesNative, CtTestClearMessagesDart>(
              'ct_test_clear_messages',
            ),
      );

  final CtStartRuntimeDart ctStartRuntime;
  final CtShutdownDart ctShutdown;
  final CtListenDart ctListen;
  final CtGetLocalPortDart ctGetLocalPort;
  final CtPollConnectionDart ctPollConnection;
  final CtPollConnectionMessageDart ctPollConnectionMessage;
  final CtMessageGetDart ctMessageGet;
  final CtMessageReleaseDart ctMessageRelease;
  final CtMessageRetainDart ctMessageRetain;
  final CtForwardPublishEventDart ctForwardPublishEvent;
  final CtForwardCallInvocationDart ctForwardCallInvocation;
  final CtForwardResultFromYieldDart ctForwardResultFromYield;
  final CtForwardErrorFromErrorDart ctForwardErrorFromError;
  final CtSendMessageDart ctSendMessage;
  final CtApplyRouterConfigDart ctApplyRouterConfig;
  final CtConnectionMaxRawsocketExponentDart ctConnectionMaxRawsocketExponent;
  final CtSetOnListenerStartedDart ctSetOnListenerStarted;
  final CtSetOnConnectionDart ctSetOnConnection;
  final CtTestMessageEnqueueDart? ctTestMessageEnqueue;
  final CtTestClearMessagesDart? ctTestClearMessages;
}

CtSendMessageDart _lookupSendMessage(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<CtSendMessageNative, CtSendMessageDart>(
      'ct_send_message',
    );
  } on ArgumentError {
    throw UnsupportedError(
      'ct_send_message symbol not found in native runtime. Please rebuild native/transport.',
    );
  }
}

T? _tryLookup<T>(T Function() lookup) {
  try {
    return lookup();
  } on ArgumentError {
    return null;
  }
}
