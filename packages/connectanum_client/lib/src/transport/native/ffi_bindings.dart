import 'dart:ffi' as ffi;

typedef CtStartRuntimeNative = ffi.Int32 Function();
typedef CtStartRuntimeDart = int Function();

typedef CtShutdownNative = ffi.Int32 Function();
typedef CtShutdownDart = int Function();

typedef CtByteBufferFreeNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef CtByteBufferFreeDart = void Function(ffi.Pointer<ffi.Uint8>, int);

typedef CtExternalByteBufferFreeNative =
    ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef CtExternalByteBufferFreeDart = void Function(ffi.Pointer<ffi.Void>);

typedef CtE2eeKeyringNewNative = ffi.Int32 Function();
typedef CtE2eeKeyringNewDart = int Function();

typedef CtE2eeKeyringAddKeyNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Int32,
    );
typedef CtE2eeKeyringAddKeyDart =
    int Function(
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
    );

typedef CtE2eeKeyringReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtE2eeKeyringReleaseDart = int Function(int);

typedef CtE2eeSessionNewNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef CtE2eeSessionNewDart = int Function(int, ffi.Pointer<ffi.Char>, int);

typedef CtE2eeSessionReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtE2eeSessionReleaseDart = int Function(int);

typedef CtE2eeSessionEncryptNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Pointer<CtByteBuffer>,
    );
typedef CtE2eeSessionEncryptDart =
    int Function(
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<CtByteBuffer>,
    );

typedef CtE2eeSessionDecryptNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Pointer<CtByteBuffer>,
    );
typedef CtE2eeSessionDecryptDart =
    int Function(
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<CtByteBuffer>,
    );

typedef CtE2eeSessionDecryptMessageSingleBinaryArgumentNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<CtExternalByteBuffer>,
    );
typedef CtE2eeSessionDecryptMessageSingleBinaryArgumentDart =
    int Function(
      int,
      ffi.Pointer<ffi.Char>,
      int,
      int,
      int,
      ffi.Pointer<CtExternalByteBuffer>,
    );

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

typedef CtConnectionSupportsFileSegmentsNative = ffi.Int32 Function(ffi.Int32);
typedef CtConnectionSupportsFileSegmentsDart = int Function(int);

typedef CtPollConnectionMessageNative = ffi.Int32 Function(ffi.Int32);
typedef CtPollConnectionMessageDart = int Function(int);

typedef CtWaitConnectionMessageNative =
    ffi.Int32 Function(ffi.Int32, ffi.Uint32);
typedef CtWaitConnectionMessageDart = int Function(int, int);

typedef CtMessageGetNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtMessageInfo>);
typedef CtMessageGetDart = int Function(int, ffi.Pointer<CtMessageInfo>);

typedef CtMessagePeekNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtMessageInfo>);
typedef CtMessagePeekDart = int Function(int, ffi.Pointer<CtMessageInfo>);

typedef CtMessageReleaseNative = ffi.Void Function(ffi.Int32);
typedef CtMessageReleaseDart = void Function(int);

typedef CtMessageRetainNative = ffi.Int32 Function(ffi.Int32);
typedef CtMessageRetainDart = int Function(int);

typedef CtMessageDecodeSingleBinaryArgumentNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<CtExternalByteBuffer>);
typedef CtMessageDecodeSingleBinaryArgumentDart =
    int Function(int, ffi.Pointer<CtExternalByteBuffer>);

typedef CtBase64DecodeCanonicalNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Pointer<CtExternalByteBuffer>,
    );
typedef CtBase64DecodeCanonicalDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<CtExternalByteBuffer>,
    );

typedef CtSha256NewNative = ffi.Int32 Function();
typedef CtSha256NewDart = int Function();

typedef CtSha256UpdateNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtSha256UpdateDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef CtSha256UpdateMessageBinaryArgumentNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef CtSha256UpdateMessageBinaryArgumentDart = int Function(int, int);

typedef CtSha256FinalizeNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef CtSha256FinalizeDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef CtSha256ReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtSha256ReleaseDart = int Function(int);

typedef CtSendMessageNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtSendMessageDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef CtOutboundBufferAllocNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Int32);
typedef CtOutboundBufferAllocDart = ffi.Pointer<ffi.Uint8> Function(int);

typedef CtOutboundBufferFreeNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtOutboundBufferFreeDart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef CtSendMessageOwnedNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef CtSendMessageOwnedDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef CtSendMessageSegmentsOwnedNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Int32>,
      ffi.Int32,
      ffi.Int32,
    );
typedef CtSendMessageSegmentsOwnedDart =
    int Function(
      int,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Int32>,
      int,
      int,
    );

typedef CtSendMessageFragmentedNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32);
typedef CtSendMessageFragmentedDart =
    int Function(int, ffi.Pointer<ffi.Uint8>, int, int);

typedef CtSendMessageFragmentedOwnedNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Int32,
    );
typedef CtSendMessageFragmentedOwnedDart =
    int Function(int, ffi.Pointer<ffi.Uint8>, int, int);

typedef CtFileOpenNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32, ffi.Uint64);
typedef CtFileOpenDart = int Function(ffi.Pointer<ffi.Char>, int, int);

typedef CtFileReleaseNative = ffi.Int32 Function(ffi.Int32);
typedef CtFileReleaseDart = int Function(int);

typedef CtSendMessageFileSegmentNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
    );
typedef CtSendMessageFileSegmentDart =
    int Function(
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
    );

typedef CtSendMessageBase64FileSegmentNative = CtSendMessageFileSegmentNative;
typedef CtSendMessageBase64FileSegmentDart = CtSendMessageFileSegmentDart;

typedef CtSendMessageNativeE2eeFileSegmentNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Int32,
      ffi.Pointer<ffi.Char>,
      ffi.Int32,
      ffi.Int32,
    );
typedef CtSendMessageNativeE2eeFileSegmentDart =
    int Function(
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      int,
    );

final class CtHttpHeader extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> namePtr;

  @ffi.Size()
  external int nameLen;

  external ffi.Pointer<ffi.Uint8> valuePtr;

  @ffi.Size()
  external int valueLen;
}

final class CtByteBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.Size()
  external int len;
}

final class CtExternalByteBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.Size()
  external int len;

  external ffi.Pointer<ffi.Void> owner;
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

  external ffi.Pointer<ffi.Uint8> detailsPtr;

  @ffi.Size()
  external int detailsLen;

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

  external ffi.Pointer<ffi.Uint8> binaryArgPtr;

  @ffi.Size()
  external int binaryArgLen;
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
      ctByteBufferFree = library
          .lookupFunction<CtByteBufferFreeNative, CtByteBufferFreeDart>(
            'ct_byte_buffer_free',
          ),
      ctExternalByteBufferFree = library
          .lookupFunction<
            CtExternalByteBufferFreeNative,
            CtExternalByteBufferFreeDart
          >('ct_external_byte_buffer_free'),
      ctExternalByteBufferFreePointer = library
          .lookup<ffi.NativeFunction<CtExternalByteBufferFreeNative>>(
            'ct_external_byte_buffer_free',
          ),
      ctE2eeKeyringNew = library
          .lookupFunction<CtE2eeKeyringNewNative, CtE2eeKeyringNewDart>(
            'ct_e2ee_keyring_new',
          ),
      ctE2eeKeyringAddKey = library
          .lookupFunction<CtE2eeKeyringAddKeyNative, CtE2eeKeyringAddKeyDart>(
            'ct_e2ee_keyring_add_key',
          ),
      ctE2eeKeyringRelease = library
          .lookupFunction<CtE2eeKeyringReleaseNative, CtE2eeKeyringReleaseDart>(
            'ct_e2ee_keyring_release',
          ),
      ctE2eeSessionNew = library
          .lookupFunction<CtE2eeSessionNewNative, CtE2eeSessionNewDart>(
            'ct_e2ee_session_new',
          ),
      ctE2eeSessionRelease = library
          .lookupFunction<CtE2eeSessionReleaseNative, CtE2eeSessionReleaseDart>(
            'ct_e2ee_session_release',
          ),
      ctE2eeSessionEncrypt = library
          .lookupFunction<CtE2eeSessionEncryptNative, CtE2eeSessionEncryptDart>(
            'ct_e2ee_session_encrypt',
          ),
      ctE2eeSessionDecrypt = library
          .lookupFunction<CtE2eeSessionDecryptNative, CtE2eeSessionDecryptDart>(
            'ct_e2ee_session_decrypt',
          ),
      ctE2eeSessionEncryptAes256Gcm = library
          .lookupFunction<CtE2eeSessionEncryptNative, CtE2eeSessionEncryptDart>(
            'ct_e2ee_session_encrypt_aes256gcm',
          ),
      ctE2eeSessionDecryptAes256Gcm = library
          .lookupFunction<CtE2eeSessionDecryptNative, CtE2eeSessionDecryptDart>(
            'ct_e2ee_session_decrypt_aes256gcm',
          ),
      ctE2eeSessionDecryptMessageSingleBinaryArgument = library
          .lookupFunction<
            CtE2eeSessionDecryptMessageSingleBinaryArgumentNative,
            CtE2eeSessionDecryptMessageSingleBinaryArgumentDart
          >('ct_e2ee_session_decrypt_message_single_binary_argument'),
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
      ctConnectionSupportsFileSegments = library
          .lookupFunction<
            CtConnectionSupportsFileSegmentsNative,
            CtConnectionSupportsFileSegmentsDart
          >('ct_connection_supports_file_segments'),
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
      ctMessagePeek = library
          .lookupFunction<CtMessagePeekNative, CtMessagePeekDart>(
            'ct_message_peek',
          ),
      ctMessageRelease = library
          .lookupFunction<CtMessageReleaseNative, CtMessageReleaseDart>(
            'ct_message_release',
          ),
      ctMessageRetain = library
          .lookupFunction<CtMessageRetainNative, CtMessageRetainDart>(
            'ct_message_retain',
          ),
      ctMessageDecodeSingleBinaryArgument = library
          .lookupFunction<
            CtMessageDecodeSingleBinaryArgumentNative,
            CtMessageDecodeSingleBinaryArgumentDart
          >('ct_message_decode_single_binary_argument'),
      ctBase64DecodeCanonical = _tryLookup(
        () =>
            library.lookupFunction<
              CtBase64DecodeCanonicalNative,
              CtBase64DecodeCanonicalDart
            >('ct_base64_decode_canonical'),
      ),
      ctSha256New = library.lookupFunction<CtSha256NewNative, CtSha256NewDart>(
        'ct_sha256_new',
      ),
      ctSha256Update = library
          .lookupFunction<CtSha256UpdateNative, CtSha256UpdateDart>(
            'ct_sha256_update',
          ),
      ctSha256UpdateMessageBinaryArgument = library
          .lookupFunction<
            CtSha256UpdateMessageBinaryArgumentNative,
            CtSha256UpdateMessageBinaryArgumentDart
          >('ct_sha256_update_message_binary_argument'),
      ctSha256Finalize = library
          .lookupFunction<CtSha256FinalizeNative, CtSha256FinalizeDart>(
            'ct_sha256_finalize',
          ),
      ctSha256Release = library
          .lookupFunction<CtSha256ReleaseNative, CtSha256ReleaseDart>(
            'ct_sha256_release',
          ),
      ctSendMessage = library
          .lookupFunction<CtSendMessageNative, CtSendMessageDart>(
            'ct_send_message',
          ),
      ctOutboundBufferAlloc = _tryLookup(
        () =>
            library.lookupFunction<
              CtOutboundBufferAllocNative,
              CtOutboundBufferAllocDart
            >('ct_outbound_buffer_alloc'),
      ),
      ctOutboundBufferFree = _tryLookup(
        () =>
            library.lookupFunction<
              CtOutboundBufferFreeNative,
              CtOutboundBufferFreeDart
            >('ct_outbound_buffer_free'),
      ),
      ctSendMessageOwned = _tryLookup(
        () => library
            .lookupFunction<CtSendMessageOwnedNative, CtSendMessageOwnedDart>(
              'ct_send_message_owned',
            ),
      ),
      ctSendMessageSegmentsOwned = _tryLookup(
        () =>
            library.lookupFunction<
              CtSendMessageSegmentsOwnedNative,
              CtSendMessageSegmentsOwnedDart
            >('ct_send_message_segments_owned'),
      ),
      ctSendMessageFragmented = library
          .lookupFunction<
            CtSendMessageFragmentedNative,
            CtSendMessageFragmentedDart
          >('ct_send_message_fragmented'),
      ctSendMessageFragmentedOwned = _tryLookup(
        () =>
            library.lookupFunction<
              CtSendMessageFragmentedOwnedNative,
              CtSendMessageFragmentedOwnedDart
            >('ct_send_message_fragmented_owned'),
      ),
      ctFileOpen = library.lookupFunction<CtFileOpenNative, CtFileOpenDart>(
        'ct_file_open',
      ),
      ctFileRelease = library
          .lookupFunction<CtFileReleaseNative, CtFileReleaseDart>(
            'ct_file_release',
          ),
      ctSendMessageFileSegment = library
          .lookupFunction<
            CtSendMessageFileSegmentNative,
            CtSendMessageFileSegmentDart
          >('ct_send_message_file_segment'),
      ctSendMessageBase64FileSegment = library
          .lookupFunction<
            CtSendMessageBase64FileSegmentNative,
            CtSendMessageBase64FileSegmentDart
          >('ct_send_message_base64_file_segment'),
      ctSendMessageNativeE2eeFileSegment = library
          .lookupFunction<
            CtSendMessageNativeE2eeFileSegmentNative,
            CtSendMessageNativeE2eeFileSegmentDart
          >('ct_send_message_native_e2ee_file_segment');

  final CtStartRuntimeDart ctStartRuntime;
  final CtShutdownDart ctShutdown;
  final CtByteBufferFreeDart ctByteBufferFree;
  final CtExternalByteBufferFreeDart ctExternalByteBufferFree;
  final ffi.Pointer<ffi.NativeFunction<CtExternalByteBufferFreeNative>>
  ctExternalByteBufferFreePointer;
  final CtE2eeKeyringNewDart ctE2eeKeyringNew;
  final CtE2eeKeyringAddKeyDart ctE2eeKeyringAddKey;
  final CtE2eeKeyringReleaseDart ctE2eeKeyringRelease;
  final CtE2eeSessionNewDart ctE2eeSessionNew;
  final CtE2eeSessionReleaseDart ctE2eeSessionRelease;
  final CtE2eeSessionEncryptDart ctE2eeSessionEncrypt;
  final CtE2eeSessionDecryptDart ctE2eeSessionDecrypt;
  final CtE2eeSessionEncryptDart ctE2eeSessionEncryptAes256Gcm;
  final CtE2eeSessionDecryptDart ctE2eeSessionDecryptAes256Gcm;
  final CtE2eeSessionDecryptMessageSingleBinaryArgumentDart
  ctE2eeSessionDecryptMessageSingleBinaryArgument;
  final CtClientConnectRawsocketDart ctClientConnectRawsocket;
  final CtClientConnectWebSocketDart ctClientConnectWebSocket;
  final CtConnectionCloseDart ctConnectionClose;
  final CtConnectionMaxRawsocketExponentDart ctConnectionMaxRawsocketExponent;
  final CtConnectionSupportsFileSegmentsDart ctConnectionSupportsFileSegments;
  final CtPollConnectionMessageDart ctPollConnectionMessage;
  final CtWaitConnectionMessageDart ctWaitConnectionMessage;
  final CtMessageGetDart ctMessageGet;
  final CtMessagePeekDart ctMessagePeek;
  final CtMessageReleaseDart ctMessageRelease;
  final CtMessageRetainDart ctMessageRetain;
  final CtMessageDecodeSingleBinaryArgumentDart
  ctMessageDecodeSingleBinaryArgument;
  final CtBase64DecodeCanonicalDart? ctBase64DecodeCanonical;
  final CtSha256NewDart ctSha256New;
  final CtSha256UpdateDart ctSha256Update;
  final CtSha256UpdateMessageBinaryArgumentDart
  ctSha256UpdateMessageBinaryArgument;
  final CtSha256FinalizeDart ctSha256Finalize;
  final CtSha256ReleaseDart ctSha256Release;
  final CtSendMessageDart ctSendMessage;
  final CtOutboundBufferAllocDart? ctOutboundBufferAlloc;
  final CtOutboundBufferFreeDart? ctOutboundBufferFree;
  final CtSendMessageOwnedDart? ctSendMessageOwned;
  final CtSendMessageSegmentsOwnedDart? ctSendMessageSegmentsOwned;
  final CtSendMessageFragmentedDart ctSendMessageFragmented;
  final CtSendMessageFragmentedOwnedDart? ctSendMessageFragmentedOwned;
  final CtFileOpenDart ctFileOpen;
  final CtFileReleaseDart ctFileRelease;
  final CtSendMessageFileSegmentDart ctSendMessageFileSegment;
  final CtSendMessageBase64FileSegmentDart ctSendMessageBase64FileSegment;
  final CtSendMessageNativeE2eeFileSegmentDart
  ctSendMessageNativeE2eeFileSegment;
}

T? _tryLookup<T>(T Function() lookup) {
  try {
    return lookup();
  } on ArgumentError {
    return null;
  }
}
