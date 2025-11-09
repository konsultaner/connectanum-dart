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
typedef CtListenerHttp3PortNative = ffi.Int32 Function(ffi.Int32);
typedef CtListenerHttp3PortDart = int Function(int);
typedef CtConnectionGetHttp3ConnectionNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionGetHttp3ConnectionDart = int Function(int);
typedef CtHttp3ConnectionReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp3ConnectionReleaseDart = int Function(int);

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

typedef CtConnectionProtocolNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionProtocolDart = int Function(int);

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

typedef CtConnectionTakeHttpHandshakeNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionTakeHttpHandshakeDart = int Function(int);
typedef CtConnectionTakeHttp2HandshakeNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionTakeHttp2HandshakeDart = int Function(int);
typedef CtConnectionTakeHttp3HandshakeNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionTakeHttp3HandshakeDart = int Function(int);

typedef CtHttpHandshakeGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtHttpHandshakeInfo>);
typedef CtHttpHandshakeGetDart =
    int Function(int, ffi.Pointer<CtHttpHandshakeInfo>);

typedef CtHttpHandshakeHeaderNative =
    ffi.Int32 Function(ffi.Int32, ffi.Size, ffi.Pointer<CtHttpHeader>);
typedef CtHttpHandshakeHeaderDart =
    int Function(int, int, ffi.Pointer<CtHttpHeader>);
typedef CtHttpHandshakeBodyRetainNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttpHandshakeBodyRetainDart = int Function(int);
typedef CtHttpBodyGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtHttpBodyView>);
typedef CtHttpBodyGetDart = int Function(int, ffi.Pointer<CtHttpBodyView>);
typedef CtHttpBodyReadNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Size,
      ffi.Size,
      ffi.Pointer<CtHttpBodyView>,
    );
typedef CtHttpBodyReadDart =
    int Function(int, int, int, ffi.Pointer<CtHttpBodyView>);
typedef CtHttpBodyReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttpBodyReleaseDart = int Function(int);

typedef CtHttpHandshakeReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttpHandshakeReleaseDart = int Function(int);
typedef CtHttp2HandshakeGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtHttp2HandshakeInfo>);
typedef CtHttp2HandshakeGetDart =
    int Function(int, ffi.Pointer<CtHttp2HandshakeInfo>);
typedef CtHttp2HandshakeListenerProtocolNative =
    ffi.Int32 Function(ffi.Int32, ffi.Size, ffi.Pointer<CtStringView>);
typedef CtHttp2HandshakeListenerProtocolDart =
    int Function(int, int, ffi.Pointer<CtStringView>);
typedef CtHttp2HandshakeReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp2HandshakeReleaseDart = int Function(int);
typedef CtHttp3HandshakeGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtHttp3HandshakeInfo>);
typedef CtHttp3HandshakeGetDart =
    int Function(int, ffi.Pointer<CtHttp3HandshakeInfo>);
typedef CtHttp3HandshakeListenerProtocolNative =
    ffi.Int32 Function(ffi.Int32, ffi.Size, ffi.Pointer<CtStringView>);
typedef CtHttp3HandshakeListenerProtocolDart =
    int Function(int, int, ffi.Pointer<CtStringView>);
typedef CtHttp3HandshakeReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp3HandshakeReleaseDart = int Function(int);
typedef CtHttp3ConnectionPollStreamNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp3ConnectionPollStreamDart = int Function(int);
typedef CtHttp3ConnectionPollRequestNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp3ConnectionPollRequestDart = int Function(int);
typedef CtHttp3StreamGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtHttp3StreamInfo>);
typedef CtHttp3StreamGetDart =
    int Function(int, ffi.Pointer<CtHttp3StreamInfo>);
typedef CtHttp3StreamReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtHttp3StreamReleaseDart = int Function(int);
typedef CtHttpResponseSendNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<CtHttpHeader>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
    );
typedef CtHttpResponseSendDart =
    int Function(
      int,
      int,
      ffi.Pointer<CtHttpHeader>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
    );

typedef CtConnectionTakeWebsocketHandshakeNative =
    ffi.Int32 Function(ffi.Int32);
typedef CtConnectionTakeWebsocketHandshakeDart = int Function(int);

typedef CtWebSocketHandshakeGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtWebSocketHandshakeInfo>);
typedef CtWebSocketHandshakeGetDart =
    int Function(int, ffi.Pointer<CtWebSocketHandshakeInfo>);

typedef CtWebSocketHandshakeValueNative =
    ffi.Int32 Function(ffi.Int32, ffi.Size, ffi.Pointer<CtStringView>);
typedef CtWebSocketHandshakeValueDart =
    int Function(int, int, ffi.Pointer<CtStringView>);

typedef CtWebSocketHandshakeReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtWebSocketHandshakeReleaseDart = int Function(int);

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

final class CtHttpHandshakeInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> methodPtr;

  @ffi.Size()
  external int methodLen;

  external ffi.Pointer<ffi.Uint8> targetPtr;

  @ffi.Size()
  external int targetLen;

  external ffi.Pointer<ffi.Uint8> pathPtr;

  @ffi.Size()
  external int pathLen;

  external ffi.Pointer<ffi.Uint8> queryPtr;

  @ffi.Size()
  external int queryLen;

  external ffi.Pointer<ffi.Uint8> protocolPtr;

  @ffi.Size()
  external int protocolLen;

  @ffi.Uint8()
  external int version;

  @ffi.Size()
  external int headersLen;

  external ffi.Pointer<ffi.Uint8> bodyPtr;

  @ffi.Size()
  external int bodyLen;

  external ffi.Pointer<ffi.Uint8> realmPtr;

  @ffi.Size()
  external int realmLen;

  external ffi.Pointer<ffi.Uint8> procedurePtr;

  @ffi.Size()
  external int procedureLen;
}

final class CtHttpBodyView extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> dataPtr;

  @ffi.Size()
  external int dataLen;
}

final class CtHttp2HandshakeInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> protocolPtr;

  @ffi.Size()
  external int protocolLen;

  external ffi.Pointer<ffi.Uint8> alpnPtr;

  @ffi.Size()
  external int alpnLen;

  @ffi.Size()
  external int listenerProtocolsLen;
}

final class CtHttp3HandshakeInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> protocolPtr;

  @ffi.Size()
  external int protocolLen;

  external ffi.Pointer<ffi.Uint8> alpnPtr;

  @ffi.Size()
  external int alpnLen;

  @ffi.Size()
  external int listenerProtocolsLen;
}

final class CtHttp3StreamInfo extends ffi.Struct {
  @ffi.Uint64()
  external int streamId;
}

final class CtHttpHeader extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> namePtr;

  @ffi.Size()
  external int nameLen;

  external ffi.Pointer<ffi.Uint8> valuePtr;

  @ffi.Size()
  external int valueLen;
}

final class CtStringView extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.Size()
  external int len;
}

final class CtWebSocketHandshakeInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> keyPtr;

  @ffi.Size()
  external int keyLen;

  @ffi.Size()
  external int protocolsLen;

  @ffi.Size()
  external int extensionsLen;

  external ffi.Pointer<ffi.Uint8> versionPtr;

  @ffi.Size()
  external int versionLen;

  external CtHttpHandshakeInfo httpInfo;
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
      ctListenerHttp3Port = library
          .lookupFunction<CtListenerHttp3PortNative, CtListenerHttp3PortDart>(
            'ct_listener_http3_port',
          ),
      ctConnectionGetHttp3Connection = library
          .lookupFunction<
            CtConnectionGetHttp3ConnectionNative,
            CtConnectionGetHttp3ConnectionDart
          >('ct_connection_get_http3_connection'),
      ctHttp3ConnectionRelease = library
          .lookupFunction<
            CtHttp3ConnectionReleaseNative,
            CtHttp3ConnectionReleaseDart
          >('ct_http3_connection_release'),
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
      ctConnectionProtocol = library
          .lookupFunction<CtConnectionProtocolNative, CtConnectionProtocolDart>(
            'ct_connection_protocol',
          ),
      ctConnectionTakeHttpHandshake = library
          .lookupFunction<
            CtConnectionTakeHttpHandshakeNative,
            CtConnectionTakeHttpHandshakeDart
          >('ct_connection_take_http_handshake'),
      ctConnectionTakeHttp2Handshake = library
          .lookupFunction<
            CtConnectionTakeHttp2HandshakeNative,
            CtConnectionTakeHttp2HandshakeDart
          >('ct_connection_take_http2_handshake'),
      ctConnectionTakeHttp3Handshake = library
          .lookupFunction<
            CtConnectionTakeHttp3HandshakeNative,
            CtConnectionTakeHttp3HandshakeDart
          >('ct_connection_take_http3_handshake'),
      ctHttpHandshakeGet = library
          .lookupFunction<CtHttpHandshakeGetNative, CtHttpHandshakeGetDart>(
            'ct_http_handshake_get',
          ),
      ctHttpHandshakeHeader = library
          .lookupFunction<
            CtHttpHandshakeHeaderNative,
            CtHttpHandshakeHeaderDart
          >('ct_http_handshake_header'),
      ctHttpHandshakeBodyRetain = library
          .lookupFunction<
            CtHttpHandshakeBodyRetainNative,
            CtHttpHandshakeBodyRetainDart
          >('ct_http_handshake_body_retain'),
      ctHttpBodyGet = library
          .lookupFunction<CtHttpBodyGetNative, CtHttpBodyGetDart>(
            'ct_http_body_get',
          ),
      ctHttpBodyRead = library
          .lookupFunction<CtHttpBodyReadNative, CtHttpBodyReadDart>(
            'ct_http_body_read',
          ),
      ctHttpBodyRelease = library
          .lookupFunction<CtHttpBodyReleaseNative, CtHttpBodyReleaseDart>(
            'ct_http_body_release',
          ),
      ctHttpHandshakeRelease = library
          .lookupFunction<
            CtHttpHandshakeReleaseNative,
            CtHttpHandshakeReleaseDart
          >('ct_http_handshake_release'),
      ctHttp2HandshakeGet = library
          .lookupFunction<CtHttp2HandshakeGetNative, CtHttp2HandshakeGetDart>(
            'ct_http2_handshake_get',
          ),
      ctHttp2HandshakeListenerProtocol = library
          .lookupFunction<
            CtHttp2HandshakeListenerProtocolNative,
            CtHttp2HandshakeListenerProtocolDart
          >('ct_http2_handshake_listener_protocol'),
      ctHttp2HandshakeRelease = library
          .lookupFunction<
            CtHttp2HandshakeReleaseNative,
            CtHttp2HandshakeReleaseDart
          >('ct_http2_handshake_release'),
      ctHttp3HandshakeGet = library
          .lookupFunction<CtHttp3HandshakeGetNative, CtHttp3HandshakeGetDart>(
            'ct_http3_handshake_get',
          ),
      ctHttp3HandshakeListenerProtocol = library
          .lookupFunction<
            CtHttp3HandshakeListenerProtocolNative,
            CtHttp3HandshakeListenerProtocolDart
          >('ct_http3_handshake_listener_protocol'),
      ctHttp3HandshakeRelease = library
          .lookupFunction<
            CtHttp3HandshakeReleaseNative,
            CtHttp3HandshakeReleaseDart
          >('ct_http3_handshake_release'),
      ctHttp3ConnectionPollStream = library
          .lookupFunction<
            CtHttp3ConnectionPollStreamNative,
            CtHttp3ConnectionPollStreamDart
          >('ct_http3_connection_poll_stream'),
      ctHttp3ConnectionPollRequest = library
          .lookupFunction<
            CtHttp3ConnectionPollRequestNative,
            CtHttp3ConnectionPollRequestDart
          >('ct_http3_connection_poll_request'),
      ctHttp3StreamGet = library
          .lookupFunction<CtHttp3StreamGetNative, CtHttp3StreamGetDart>(
            'ct_http3_stream_get',
          ),
      ctHttp3StreamRelease = library
          .lookupFunction<CtHttp3StreamReleaseNative, CtHttp3StreamReleaseDart>(
            'ct_http3_stream_release',
          ),
      ctHttpResponseSend = library
          .lookupFunction<CtHttpResponseSendNative, CtHttpResponseSendDart>(
            'ct_http_response_send',
          ),
      ctConnectionTakeWebsocketHandshake = library
          .lookupFunction<
            CtConnectionTakeWebsocketHandshakeNative,
            CtConnectionTakeWebsocketHandshakeDart
          >('ct_connection_take_websocket_handshake'),
      ctWebSocketHandshakeGet = library
          .lookupFunction<
            CtWebSocketHandshakeGetNative,
            CtWebSocketHandshakeGetDart
          >('ct_websocket_handshake_get'),
      ctWebSocketHandshakeProtocol = library
          .lookupFunction<
            CtWebSocketHandshakeValueNative,
            CtWebSocketHandshakeValueDart
          >('ct_websocket_handshake_protocol'),
      ctWebSocketHandshakeExtension = library
          .lookupFunction<
            CtWebSocketHandshakeValueNative,
            CtWebSocketHandshakeValueDart
          >('ct_websocket_handshake_extension'),
      ctWebSocketHandshakeRelease = library
          .lookupFunction<
            CtWebSocketHandshakeReleaseNative,
            CtWebSocketHandshakeReleaseDart
          >('ct_websocket_handshake_release'),
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
  final CtListenerHttp3PortDart ctListenerHttp3Port;
  final CtConnectionGetHttp3ConnectionDart ctConnectionGetHttp3Connection;
  final CtHttp3ConnectionReleaseDart ctHttp3ConnectionRelease;
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
  final CtConnectionProtocolDart ctConnectionProtocol;
  final CtConnectionTakeHttpHandshakeDart ctConnectionTakeHttpHandshake;
  final CtConnectionTakeHttp2HandshakeDart ctConnectionTakeHttp2Handshake;
  final CtConnectionTakeHttp3HandshakeDart ctConnectionTakeHttp3Handshake;
  final CtHttpHandshakeGetDart ctHttpHandshakeGet;
  final CtHttpHandshakeHeaderDart ctHttpHandshakeHeader;
  final CtHttpHandshakeBodyRetainDart ctHttpHandshakeBodyRetain;
  final CtHttpBodyGetDart ctHttpBodyGet;
  final CtHttpBodyReadDart ctHttpBodyRead;
  final CtHttpBodyReleaseDart ctHttpBodyRelease;
  final CtHttpHandshakeReleaseDart ctHttpHandshakeRelease;
  final CtHttp2HandshakeGetDart ctHttp2HandshakeGet;
  final CtHttp2HandshakeListenerProtocolDart ctHttp2HandshakeListenerProtocol;
  final CtHttp2HandshakeReleaseDart ctHttp2HandshakeRelease;
  final CtHttp3HandshakeGetDart ctHttp3HandshakeGet;
  final CtHttp3HandshakeListenerProtocolDart ctHttp3HandshakeListenerProtocol;
  final CtHttp3HandshakeReleaseDart ctHttp3HandshakeRelease;
  final CtHttp3ConnectionPollStreamDart ctHttp3ConnectionPollStream;
  final CtHttp3ConnectionPollRequestDart ctHttp3ConnectionPollRequest;
  final CtHttp3StreamGetDart ctHttp3StreamGet;
  final CtHttp3StreamReleaseDart ctHttp3StreamRelease;
  final CtHttpResponseSendDart ctHttpResponseSend;
  final CtConnectionTakeWebsocketHandshakeDart
  ctConnectionTakeWebsocketHandshake;
  final CtWebSocketHandshakeGetDart ctWebSocketHandshakeGet;
  final CtWebSocketHandshakeValueDart ctWebSocketHandshakeProtocol;
  final CtWebSocketHandshakeValueDart ctWebSocketHandshakeExtension;
  final CtWebSocketHandshakeReleaseDart ctWebSocketHandshakeRelease;
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
