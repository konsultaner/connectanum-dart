import 'dart:ffi' as ffi;

typedef CtStartRuntimeNative = ffi.Int32 Function();
typedef CtStartRuntimeDart = int Function();

typedef CtShutdownNative = ffi.Int32 Function();
typedef CtShutdownDart = int Function();

typedef CtClientConnectRawsocketNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
    );
typedef CtClientConnectRawsocketDart =
    int Function(ffi.Pointer<ffi.Char>, int, int, int, int, int, int, int);

typedef CtClientConnectWebSocketNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<CtHttpHeader>,
      ffi.Size,
      ffi.Uint32,
      ffi.Uint32,
    );
typedef CtClientConnectWebSocketDart =
    int Function(
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      int,
      int,
      ffi.Pointer<CtHttpHeader>,
      int,
      int,
      int,
    );

typedef CtConnectionCloseNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionCloseDart = int Function(int);

typedef CtConnectionMaxRawsocketExponentNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionMaxRawsocketExponentDart = int Function(int);

typedef CtPollConnectionMessageNative = ffi.Int32 Function(ffi.Int32);
typedef CtPollConnectionMessageDart = int Function(int);

typedef CtWaitConnectionMessageNative =
    ffi.Int32 Function(ffi.Int32, ffi.Uint32);
typedef CtWaitConnectionMessageDart = int Function(int, int);

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

final class CtHttpHeader extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> namePtr;

  @ffi.Size()
  external int nameLen;

  external ffi.Pointer<ffi.Uint8> valuePtr;

  @ffi.Size()
  external int valueLen;
}

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

  @ffi.Uint64()
  external int primaryId;

  @ffi.Uint64()
  external int secondaryId;

  @ffi.Uint64()
  external int detailNumberA;

  @ffi.Uint64()
  external int detailNumberB;

  @ffi.Uint32()
  external int flags;

  external ffi.Pointer<ffi.Uint8> stringAPtr;

  @ffi.Size()
  external int stringALen;

  external ffi.Pointer<ffi.Uint8> stringBPtr;

  @ffi.Size()
  external int stringBLen;

  external ffi.Pointer<ffi.Uint8> stringCPtr;

  @ffi.Size()
  external int stringCLen;

  external ffi.Pointer<ffi.Uint8> stringDPtr;

  @ffi.Size()
  external int stringDLen;

  external ffi.Pointer<ffi.Uint8> stringEPtr;

  @ffi.Size()
  external int stringELen;
}

class CtFfiBindings {
  CtFfiBindings(ffi.DynamicLibrary library)
    : ctStartRuntime = library
          .lookupFunction<CtStartRuntimeNative, CtStartRuntimeDart>(
            'ct_start_runtime',
          ),
      ctShutdown = library.lookupFunction<CtShutdownNative, CtShutdownDart>(
        'ct_shutdown',
      ),
      ctClientConnectRawsocket = library
          .lookupFunction<
            CtClientConnectRawsocketNative,
            CtClientConnectRawsocketDart
          >('ct_client_connect_rawsocket'),
      ctClientConnectWebSocket = library
          .lookupFunction<
            CtClientConnectWebSocketNative,
            CtClientConnectWebSocketDart
          >('ct_client_connect_websocket'),
      ctConnectionClose = library
          .lookupFunction<CtConnectionCloseNative, CtConnectionCloseDart>(
            'ct_connection_close',
          ),
      ctConnectionMaxRawsocketExponent = library
          .lookupFunction<
            CtConnectionMaxRawsocketExponentNative,
            CtConnectionMaxRawsocketExponentDart
          >('ct_connection_max_rawsocket_exponent'),
      ctPollConnectionMessage = library
          .lookupFunction<
            CtPollConnectionMessageNative,
            CtPollConnectionMessageDart
          >('ct_poll_connection_message'),
      ctWaitConnectionMessage = library
          .lookupFunction<
            CtWaitConnectionMessageNative,
            CtWaitConnectionMessageDart
          >('ct_wait_connection_message'),
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
      ctSendMessage = library
          .lookupFunction<CtSendMessageNative, CtSendMessageDart>(
            'ct_send_message',
          );

  final CtStartRuntimeDart ctStartRuntime;
  final CtShutdownDart ctShutdown;
  final CtClientConnectRawsocketDart ctClientConnectRawsocket;
  final CtClientConnectWebSocketDart ctClientConnectWebSocket;
  final CtConnectionCloseDart ctConnectionClose;
  final CtConnectionMaxRawsocketExponentDart ctConnectionMaxRawsocketExponent;
  final CtPollConnectionMessageDart ctPollConnectionMessage;
  final CtWaitConnectionMessageDart ctWaitConnectionMessage;
  final CtMessageGetDart ctMessageGet;
  final CtMessageReleaseDart ctMessageRelease;
  final CtMessageRetainDart ctMessageRetain;
  final CtSendMessageDart ctSendMessage;
}
