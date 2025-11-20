import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' show AbstractMessage;
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'ffi_bindings.dart';
import 'message_binding.dart';

abstract class NativeRuntime {
  void start();
  void shutdown();
  int listen(String host, int port, {int backlog = 128});
  int getLocalPort(int listenerId);
  int getHttp3Port(int listenerId);
  int pollConnection(int listenerId);
  int connectionMaxRawSocketExponent(int connectionId);
  NativeConnectionProtocol connectionProtocol(int connectionId);
  NativeHttpHandshake? takeHttpHandshake(int connectionId);
  void releaseHttpHandshake(int handle);
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId);
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  });
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status,
    String reason,
  });
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId);
  void releaseHttp2Handshake(int handle);
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId);
  void releaseHttp3Handshake(int handle);
  NativeHttp3Connection? takeHttp3Connection(int connectionId);
  NativeHttp3Stream? pollHttp3Stream(int connectionId);
  NativeHttpHandshake? pollHttp3Request(int connectionId);
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    throw UnsupportedError('HTTP responses not supported by runtime');
  }

  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    throw UnsupportedError('HTTP response streaming not supported by runtime');
  }

  NativeHttpConnectionEvent? pollHttpConnectionEvent();

  NativeRouterMetrics? pollRouterMetrics() => null;

  void sendMessage(int connectionId, Uint8List payload);
  void applyRouterConfig(Uint8List config);
  NativeIncomingMessage? pollMessage(int connectionId);
}

/// Runtime extension that exposes raw message handles so other isolates can
/// materialise messages without crossing isolate boundaries.
abstract class NativeRuntimeWithHandles implements NativeRuntime {
  int pollMessageHandle(int connectionId);
  int pollWebSocketMessageHandle(int connectionId);
  String? get libraryPathHint;
  int retainMessageHandle(int handle);
  void releaseMessageHandle(int handle);

  /// TODO(protocol-negotiation): replace RawSocket-only forwarding with
  /// protocol-aware APIs once the native runtime negotiates between RawSocket,
  /// WebSocket, and HTTP. The current bridge assumes RawSocket frames only.
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  });
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? procedure,
    bool? receiveProgress,
  });
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  });
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  });

  /// TODO(protocol-negotiation): expose negotiated protocol metadata and HTTP/
  /// WebSocket frame streaming APIs (e.g., header handles, continuation events)
  /// once the native transport supports them.
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
  static const unsupportedProtocol = -12;
  static const handshakeConsumed = -13;
  static const handleUnavailable = -14;
  static const streamClosed = -15;
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

enum NativeConnectionProtocol {
  rawsocket(1),
  websocket(2),
  http(3),
  http2(4),
  http3(5);

  const NativeConnectionProtocol(this.id);

  final int id;

  static NativeConnectionProtocol fromId(int id) {
    for (final value in NativeConnectionProtocol.values) {
      if (value.id == id) {
        return value;
      }
    }
    throw StateError('Unsupported connection protocol id $id');
  }
}

class NativeHttpHandshake {
  NativeHttpHandshake._({
    required this.handle,
    required this.method,
    required this.target,
    required this.path,
    required this.protocol,
    required this.version,
    required this.headers,
    required this.body,
    required void Function() release,
    this.query,
    this.realm,
    this.procedure,
  }) : _release = release;

  factory NativeHttpHandshake.synthetic({
    int handle = -1,
    required String method,
    required String target,
    required String path,
    String? query,
    String protocol = 'http/1.1',
    int version = 1,
    Map<String, String>? headers,
    Uint8List? body,
    NativeHttpRequestBody? bodyHandle,
    String? realm,
    String? procedure,
  }) {
    final resolvedHeaders = headers == null
        ? const <String, String>{}
        : Map<String, String>.unmodifiable(Map<String, String>.from(headers));
    final resolvedBody =
        bodyHandle ??
        NativeHttpRequestBody.synthetic(
          body == null ? Uint8List(0) : Uint8List.fromList(body),
        );
    return NativeHttpHandshake._(
      handle: handle,
      method: method,
      target: target,
      path: path,
      query: query,
      protocol: protocol,
      version: version,
      headers: resolvedHeaders,
      body: resolvedBody,
      realm: realm,
      procedure: procedure,
      release: () {},
    );
  }

  final int handle;
  final String method;
  final String target;
  final String path;
  final String protocol;
  final int version;
  final Map<String, String> headers;
  final NativeHttpRequestBody body;
  final String? query;
  final String? realm;
  final String? procedure;

  bool _released = false;
  final void Function() _release;

  void release() {
    if (_released) {
      return;
    }
    body._releaseHandle();
    _release();
    _released = true;
  }
}

class NativeHttp2Handshake {
  NativeHttp2Handshake._({
    required this.handle,
    required this.protocol,
    required this.alpn,
    required List<String> listenerProtocols,
    required void Function() release,
  }) : listenerProtocols = List.unmodifiable(listenerProtocols),
       _release = release;

  factory NativeHttp2Handshake.synthetic({
    int handle = -1,
    String protocol = 'http/2',
    String? alpn,
    List<String> listenerProtocols = const <String>[],
    void Function()? onRelease,
  }) {
    return NativeHttp2Handshake._(
      handle: handle,
      protocol: protocol,
      alpn: alpn,
      listenerProtocols: listenerProtocols,
      release: onRelease ?? () {},
    );
  }

  final int handle;
  final String protocol;
  final String? alpn;
  final List<String> listenerProtocols;
  final void Function() _release;

  void release() => _release();
}

class NativeHttp3Handshake {
  NativeHttp3Handshake._({
    required this.handle,
    required this.protocol,
    required this.alpn,
    required List<String> listenerProtocols,
    required void Function() release,
  }) : listenerProtocols = List.unmodifiable(listenerProtocols),
       _release = release;

  factory NativeHttp3Handshake.synthetic({
    int handle = -1,
    String protocol = 'http/3',
    String? alpn,
    List<String> listenerProtocols = const <String>[],
    void Function()? onRelease,
  }) {
    return NativeHttp3Handshake._(
      handle: handle,
      protocol: protocol,
      alpn: alpn,
      listenerProtocols: listenerProtocols,
      release: onRelease ?? () {},
    );
  }

  final int handle;
  final String protocol;
  final String? alpn;
  final List<String> listenerProtocols;
  final void Function() _release;

  void release() => _release();
}

class NativeHttp3Connection {
  const NativeHttp3Connection({
    required this.handle,
    required void Function() release,
  }) : _release = release;

  final int handle;
  final void Function() _release;

  void release() => _release();
}

class NativeHttp3Stream {
  NativeHttp3Stream._({
    required this.handle,
    required this.streamId,
    required void Function() release,
  }) : _release = release;

  factory NativeHttp3Stream.synthetic({
    int handle = -1,
    int streamId = 0,
    void Function()? onRelease,
  }) {
    return NativeHttp3Stream._(
      handle: handle,
      streamId: streamId,
      release: onRelease ?? () {},
    );
  }

  final int handle;
  final int streamId;
  final void Function() _release;

  void release() => _release();
}

enum NativeHttpResponseBodyKind { bytes, text, json, file }

abstract class NativeHttpResponseBody {
  const NativeHttpResponseBody(this.kind);

  final NativeHttpResponseBodyKind kind;
}

class NativeHttpResponseBytes extends NativeHttpResponseBody {
  NativeHttpResponseBytes(this.bytes) : super(NativeHttpResponseBodyKind.bytes);

  final Uint8List bytes;
}

class NativeHttpResponseText extends NativeHttpResponseBody {
  NativeHttpResponseText(this.text, {this.encoding = 'utf8'})
    : super(NativeHttpResponseBodyKind.text);

  final String text;
  final String encoding;
}

class NativeHttpResponseJson extends NativeHttpResponseBody {
  NativeHttpResponseJson(this.value) : super(NativeHttpResponseBodyKind.json);

  final Object? value;
}

class NativeHttpResponseFile extends NativeHttpResponseBody {
  NativeHttpResponseFile(this.path) : super(NativeHttpResponseBodyKind.file);

  final String path;
}

class NativeHttpResponse {
  NativeHttpResponse({
    required this.status,
    Map<String, String>? headers,
    required this.body,
  }) : headers = Map.unmodifiable(headers ?? const {});

  final int status;
  final Map<String, String> headers;
  final NativeHttpResponseBody body;
}

abstract class NativeHttpResponseStream {
  bool get isClosed;
  void add(Uint8List chunk);
  void close([Uint8List? finalChunk]);
}

abstract final class NativeHttpConnectionEventReason {
  static const graceful = 1;
  static const goAway = 2;
  static const idleTimeout = 3;
  static const bodyTimeout = 4;
  static const protocolError = 5;
  static const internal = 6;
}

enum NativeHttpConnectionCloseReason {
  graceful,
  goAway,
  idleTimeout,
  bodyTimeout,
  protocolError,
  internal,
}

class NativeHttpConnectionEvent {
  NativeHttpConnectionEvent({
    required this.connectionId,
    required this.protocol,
    required this.reason,
    required this.requestCount,
    required this.idleTimeouts,
    required this.bodyTimeouts,
    required this.backpressureEvents,
    required this.maxBackpressureDepth,
    required this.goAwayEvents,
    this.detail,
  });

  final int connectionId;
  final NativeConnectionProtocol protocol;
  final NativeHttpConnectionCloseReason reason;
  final int requestCount;
  final int idleTimeouts;
  final int bodyTimeouts;
  final int backpressureEvents;
  final int maxBackpressureDepth;
  final int goAwayEvents;
  final String? detail;

  bool get isClosed => true;
}

class NativeRouterMetrics {
  const NativeRouterMetrics({
    required this.totalEvents,
    required this.gracefulEvents,
    required this.goAwayEvents,
    required this.idleTimeoutEvents,
    required this.bodyTimeoutEvents,
    required this.protocolErrorEvents,
    required this.internalErrorEvents,
    required this.backpressureEvents,
    required this.maxBackpressureDepth,
  });

  final int totalEvents;
  final int gracefulEvents;
  final int goAwayEvents;
  final int idleTimeoutEvents;
  final int bodyTimeoutEvents;
  final int protocolErrorEvents;
  final int internalErrorEvents;
  final int backpressureEvents;
  final int maxBackpressureDepth;

  bool sameValues(NativeRouterMetrics other) {
    return totalEvents == other.totalEvents &&
        gracefulEvents == other.gracefulEvents &&
        goAwayEvents == other.goAwayEvents &&
        idleTimeoutEvents == other.idleTimeoutEvents &&
        bodyTimeoutEvents == other.bodyTimeoutEvents &&
        protocolErrorEvents == other.protocolErrorEvents &&
        internalErrorEvents == other.internalErrorEvents &&
        backpressureEvents == other.backpressureEvents &&
        maxBackpressureDepth == other.maxBackpressureDepth;
  }
}

class NativeWebSocketHandshake {
  factory NativeWebSocketHandshake.synthetic({
    int handle = -1,
    required String key,
    List<String> protocols = const <String>[],
    List<String> extensions = const <String>[],
    void Function()? onRelease,
  }) {
    return NativeWebSocketHandshake._(
      handle: handle,
      key: key,
      protocols: List<String>.unmodifiable(protocols),
      extensions: List<String>.unmodifiable(extensions),
      release: onRelease ?? () {},
    );
  }

  NativeWebSocketHandshake._({
    required this.handle,
    required this.key,
    required this.protocols,
    required this.extensions,
    required void Function() release,
  }) : _release = release;

  final int handle;
  final String key;
  final List<String> protocols;
  final List<String> extensions;

  bool _released = false;
  final void Function() _release;

  void release() {
    if (_released) {
      return;
    }
    _release();
    _released = true;
  }

  void consume() => _released = true;
}

class NativeHttpRequestBody {
  NativeHttpRequestBody._internal(
    Uint8List view, {
    CtFfiBindings? bindings,
    int? handle,
    required int length,
    bool streaming = false,
    Uint8List Function(int length)? streamReadOverride,
    void Function()? streamFinishOverride,
  }) : _view = view,
       _bindings = bindings,
       _handle = handle,
       _length = length,
       _streaming = streaming,
       _streamReadOverride = streamReadOverride,
       _streamFinishOverride = streamFinishOverride;

  factory NativeHttpRequestBody.synthetic(Uint8List bytes) =>
      NativeHttpRequestBody._internal(
        bytes.isEmpty ? Uint8List(0) : bytes,
        length: bytes.length,
      );

  factory NativeHttpRequestBody._fromNative({
    required Uint8List view,
    required CtFfiBindings bindings,
    required int handle,
    required int length,
    required bool streaming,
  }) => NativeHttpRequestBody._internal(
    view.isEmpty ? Uint8List(0) : view,
    bindings: bindings,
    handle: handle,
    length: length,
    streaming: streaming,
  );

  @visibleForTesting
  factory NativeHttpRequestBody.testStreaming({
    required int length,
    required Uint8List Function(int length) onRead,
    void Function()? onFinish,
  }) => NativeHttpRequestBody._internal(
    Uint8List(0),
    length: length,
    streaming: true,
    streamReadOverride: onRead,
    streamFinishOverride: onFinish,
  );

  Uint8List _view;
  final CtFfiBindings? _bindings;
  final int? _handle;
  final int _length;
  bool _released = false;
  final bool _streaming;
  final Uint8List Function(int length)? _streamReadOverride;
  final void Function()? _streamFinishOverride;
  bool _streamFinished = false;

  static const int _defaultChunkSize = 64 * 1024;

  int get length => _length;

  /// View backed by the native buffer (callers must not mutate).
  Uint8List get view {
    if (_view.isEmpty && _handle != null && !_released && _length > 0) {
      _view = _readAll();
    }
    return _view;
  }

  /// Copies the body into Dart-managed memory (safe to send across isolates).
  Uint8List copy() => Uint8List.fromList(view);

  /// Signals that no more streaming data is required and the native reader can reclaim the socket.
  void finish() {
    _finishStreaming(ignoreErrors: false);
  }

  /// Convenience helper to expose the body as a single-chunk stream.
  Stream<List<int>> openRead({int chunkSize = _defaultChunkSize}) async* {
    if (_view.isNotEmpty && (!_streaming || _streamFinished)) {
      yield _view;
      return;
    }
    final hasNativeHandle = _handle != null && _bindings != null && !_released;
    final hasStreamOverride = _streamReadOverride != null;
    if (!_streaming && !hasNativeHandle) {
      if (_view.isNotEmpty) {
        yield _view;
      }
      return;
    }
    if (_streaming && !hasNativeHandle && !hasStreamOverride) {
      if (_view.isNotEmpty) {
        yield _view;
      }
      return;
    }
    if (_length == 0 && !_streaming) {
      return;
    }
    var offset = 0;
    final effectiveChunk = math.max(1, chunkSize);
    while (offset < _length) {
      final remaining = _length - offset;
      final toRead = math.min(remaining, effectiveChunk);
      final chunk = _streaming
          ? _readStreamingChunk(toRead)
          : _readSlice(offset, toRead);
      if (chunk.isEmpty) {
        break;
      }
      yield chunk;
      offset += chunk.length;
    }
    if (_streaming) {
      _finishStreaming(ignoreErrors: false);
    }
  }

  void _releaseHandle() {
    if (_released) {
      return;
    }
    final handle = _handle;
    if (handle == null) {
      _released = true;
      return;
    }
    final bindings = _bindings;
    if (bindings != null) {
      if (_streaming) {
        _finishStreaming(ignoreErrors: true);
        _view = _view.isNotEmpty ? Uint8List.fromList(_view) : Uint8List(0);
      } else if (_view.isNotEmpty) {
        _view = Uint8List.fromList(_view);
      } else if (_length > 0) {
        _view = _readAll();
      } else {
        _view = Uint8List(0);
      }
      final result = bindings.ctHttpBodyRelease(handle);
      if (result != NativeTransportErrorCode.success) {
        // Swallow release failures to avoid crashing during shutdown.
      }
    }
    _released = true;
  }

  Uint8List _readSlice(int offset, int count) {
    if (_streaming) {
      return _readStreamingChunk(count);
    }
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == null || count == 0) {
      return Uint8List(0);
    }
    final viewPtr = calloc<CtHttpBodyView>();
    try {
      final result = bindings.ctHttpBodyRead(handle, offset, count, viewPtr);
      if (result != NativeTransportErrorCode.success) {
        throw NativeTransportException(
          result,
          'Failed to read HTTP body slice',
        );
      }
      final view = viewPtr.ref;
      if (view.dataPtr == ffi.nullptr || view.dataLen == 0) {
        return Uint8List(0);
      }
      return view.dataPtr.asTypedList(view.dataLen);
    } finally {
      calloc.free(viewPtr);
    }
  }

  Uint8List _readStreamingChunk(int count) {
    if (count == 0) {
      return Uint8List(0);
    }
    final override = _streamReadOverride;
    if (override != null) {
      return override(count);
    }
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == null) {
      return Uint8List(0);
    }
    final viewPtr = calloc<CtHttpBodyView>();
    try {
      final result = bindings.ctHttpBodyStreamRead(handle, count, viewPtr);
      if (result != NativeTransportErrorCode.success) {
        throw NativeTransportException(
          result,
          'Failed to read streaming HTTP body chunk',
        );
      }
      final view = viewPtr.ref;
      if (view.dataPtr == ffi.nullptr || view.dataLen == 0) {
        return Uint8List(0);
      }
      final borrowed = view.dataPtr.asTypedList(view.dataLen);
      return Uint8List.fromList(borrowed);
    } finally {
      calloc.free(viewPtr);
    }
  }

  Uint8List _readAll() {
    if (_length == 0) {
      if (_streaming) {
        _finishStreaming(ignoreErrors: false);
      }
      return Uint8List(0);
    }
    final buffer = Uint8List(_length);
    var offset = 0;
    while (offset < _length) {
      final remaining = _length - offset;
      final toRead = math.min(remaining, _defaultChunkSize);
      final chunk = _streaming
          ? _readStreamingChunk(toRead)
          : _readSlice(offset, toRead);
      if (chunk.isEmpty) {
        break;
      }
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    if (_streaming) {
      _finishStreaming(ignoreErrors: false);
    }
    if (offset == _length) {
      return buffer;
    }
    return buffer.sublist(0, offset);
  }

  void _finishStreaming({required bool ignoreErrors}) {
    if (!_streaming || _streamFinished) {
      return;
    }
    final override = _streamFinishOverride;
    if (override != null) {
      override();
      _streamFinished = true;
      return;
    }
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == null) {
      _streamFinished = true;
      return;
    }
    final result = bindings.ctHttpBodyFinish(handle);
    if (result != NativeTransportErrorCode.success && !ignoreErrors) {
      throw NativeTransportException(
        result,
        'Failed to finish HTTP body stream',
      );
    }
    _streamFinished = true;
  }
}

class _HttpHandshakeFields {
  _HttpHandshakeFields({
    required this.method,
    required this.target,
    required this.path,
    required this.query,
    required this.protocol,
    required this.version,
    required this.headers,
    required this.body,
    required this.realm,
    required this.procedure,
    required this.bodyLength,
  });

  final String method;
  final String target;
  final String path;
  final String? query;
  final String protocol;
  final int version;
  final Map<String, String> headers;
  final Uint8List body;
  final String? realm;
  final String? procedure;
  final int bodyLength;
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
    required this.handle,
    required CtFfiBindings? bindings,
    this.argumentsBytes,
    this.argumentsKeywordsBytes,
    int Function(int handle)? retainOverride,
    void Function(int handle)? releaseOverride,
  }) : _bindings = bindings,
       _retainOverride = retainOverride,
       _releaseOverride = releaseOverride;

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
      handle: -1,
      bindings: null,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      retainOverride: null,
      releaseOverride: null,
    );
    instance._setReleaser(() {});
    return instance;
  }

  factory NativeIncomingMessage.test({
    required NativeMessageSerializer serializer,
    required AbstractMessage message,
    required int handle,
    Uint8List? bytes,
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    int Function(int handle)? onRetain,
    void Function(int handle)? onRelease,
  }) {
    final frameBytes = bytes ?? Uint8List(0);
    final instance = NativeIncomingMessage._(
      serializer: serializer,
      message: message,
      bytes: frameBytes,
      frameAddress: frameBytes.isEmpty ? 0 : 1,
      argumentsAddress: argumentsBytes == null ? 0 : 1,
      argumentsKeywordsAddress: argumentsKeywordsBytes == null ? 0 : 1,
      handle: handle,
      bindings: null,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: argumentsKeywordsBytes,
      retainOverride: onRetain,
      releaseOverride: onRelease,
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
  final int handle;
  final Uint8List? argumentsBytes;
  final Uint8List? argumentsKeywordsBytes;
  final CtFfiBindings? _bindings;
  final int Function(int handle)? _retainOverride;
  final void Function(int handle)? _releaseOverride;

  bool get hasNativeHandle => handle > 0;

  int retainHandle() {
    if (_retainOverride != null) {
      return _retainOverride(handle);
    }
    final bindings = _bindings;
    if (bindings == null || handle <= 0) {
      return 0;
    }
    return bindings.ctMessageRetain(handle);
  }

  void releaseRetainedHandle(int retainedHandle) {
    if (_releaseOverride != null) {
      _releaseOverride(retainedHandle);
      return;
    }
    final bindings = _bindings;
    if (bindings == null || retainedHandle <= 0) {
      return;
    }
    bindings.ctMessageRelease(retainedHandle);
  }

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
          handle: handle,
          bindings: _bindings,
          argumentsBytes: args,
          argumentsKeywordsBytes: kwargs,
          retainOverride: null,
          releaseOverride: null,
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
    NativeTransportErrorCode.unsupportedProtocol =>
      '$context: connection protocol not supported for this operation',
    NativeTransportErrorCode.handshakeConsumed =>
      '$context: connection handshake already consumed',
    NativeTransportErrorCode.handleUnavailable =>
      '$context: native handle unavailable',
    NativeTransportErrorCode.streamClosed =>
      '$context: native HTTP response stream closed',
    _ => '$context: error code $code',
  };
}

NativeHttpConnectionCloseReason _connectionReasonFromCode(int code) {
  switch (code) {
    case NativeHttpConnectionEventReason.graceful:
      return NativeHttpConnectionCloseReason.graceful;
    case NativeHttpConnectionEventReason.goAway:
      return NativeHttpConnectionCloseReason.goAway;
    case NativeHttpConnectionEventReason.idleTimeout:
      return NativeHttpConnectionCloseReason.idleTimeout;
    case NativeHttpConnectionEventReason.bodyTimeout:
      return NativeHttpConnectionCloseReason.bodyTimeout;
    case NativeHttpConnectionEventReason.protocolError:
      return NativeHttpConnectionCloseReason.protocolError;
    default:
      return NativeHttpConnectionCloseReason.internal;
  }
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
  static const _relativeCandidates = <String>{
    '../native/transport/target/debug/libct_ffi.so',
    '../native/transport/target/release/libct_ffi.so',
    '../../native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
  };

  static String? _probeFromAnchor(Directory anchor) {
    var current = anchor;
    for (var depth = 0; depth < 6; depth++) {
      final debug = File(
        '${current.path}/native/transport/target/debug/libct_ffi.so',
      );
      if (debug.existsSync()) {
        return debug.path;
      }
      final release = File(
        '${current.path}/native/transport/target/release/libct_ffi.so',
      );
      if (release.existsSync()) {
        return release.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    return null;
  }

  static String resolvePath(String? overridePath) {
    if (overridePath != null && overridePath.isNotEmpty) {
      return overridePath;
    }
    final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
    if (envOverride != null && envOverride.isNotEmpty) {
      return envOverride;
    }
    for (final candidate in _relativeCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    final searchRoots = <Directory>{
      Directory.current,
      Directory.current.parent,
      File(Platform.script.toFilePath()).parent,
      File(Platform.script.toFilePath()).parent.parent,
      File(Platform.resolvedExecutable).parent,
    };
    for (final root in searchRoots) {
      final probed = _probeFromAnchor(root);
      if (probed != null) {
        return probed;
      }
    }
    return _relativeCandidates.first;
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
  final ffi.DynamicLibrary _library; // Retain library for runtime lifetime.
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
  int getHttp3Port(int listenerId) {
    final result = _bindings.ctListenerHttp3Port(listenerId);
    if (result < 0) {
      _throwForError(result, 'Failed to query HTTP/3 port');
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
  NativeConnectionProtocol connectionProtocol(int connectionId) {
    final result = _bindings.ctConnectionProtocol(connectionId);
    if (result < 0) {
      _throwForError(result, 'Failed to query connection protocol');
    }
    return NativeConnectionProtocol.fromId(result);
  }

  @override
  NativeHttpHandshake? takeHttpHandshake(int connectionId) {
    final handle = _bindings.ctConnectionTakeHttpHandshake(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to take HTTP handshake');
    }
    final infoPtr = calloc<CtHttpHandshakeInfo>();
    try {
      final result = _bindings.ctHttpHandshakeGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttpHandshakeRelease(handle);
        _throwForError(result, 'Failed to read HTTP handshake');
      }
      final info = infoPtr.ref;
      final data = _readHttpHandshakeData(handle, info);
      int? retainedBodyHandle;
      try {
        final bodyHandle = _bindings.ctHttpHandshakeBodyRetain(handle);
        if (bodyHandle < 0) {
          _bindings.ctHttpHandshakeRelease(handle);
          _throwForError(bodyHandle, 'Failed to retain HTTP body handle');
        }
        NativeHttpRequestBody body;
        if (bodyHandle > 0) {
          retainedBodyHandle = bodyHandle;
          final borrowed = _borrowBodyHandle(bodyHandle);
          body = NativeHttpRequestBody._fromNative(
            view: borrowed.bytes,
            bindings: _bindings,
            handle: bodyHandle,
            length: data.bodyLength,
            streaming: borrowed.streaming,
          );
          retainedBodyHandle = null;
        } else {
          body = NativeHttpRequestBody.synthetic(data.body);
        }
        return NativeHttpHandshake._(
          handle: handle,
          method: data.method,
          target: data.target,
          path: data.path,
          query: data.query,
          protocol: data.protocol,
          version: data.version,
          headers: data.headers,
          body: body,
          realm: data.realm,
          procedure: data.procedure,
          release: () {
            _bindings.ctHttpHandshakeRelease(handle);
          },
        );
      } catch (error) {
        if (retainedBodyHandle != null) {
          _bindings.ctHttpBodyRelease(retainedBodyHandle);
        }
        _bindings.ctHttpHandshakeRelease(handle);
        rethrow;
      }
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  void releaseHttpHandshake(int handle) {
    if (handle <= 0) {
      return;
    }
    _bindings.ctHttpHandshakeRelease(handle);
  }

  @override
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId) {
    final handle = _bindings.ctConnectionTakeWebsocketHandshake(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to take WebSocket handshake');
    }
    final infoPtr = calloc<CtWebSocketHandshakeInfo>();
    try {
      final result = _bindings.ctWebSocketHandshakeGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctWebSocketHandshakeRelease(handle);
        _throwForError(result, 'Failed to read WebSocket handshake');
      }
      final info = infoPtr.ref;
      final key = _decodeUtf8(info.keyPtr, info.keyLen);
      final protocols = <String>[];
      for (var i = 0; i < info.protocolsLen; i++) {
        final viewPtr = calloc<CtStringView>();
        try {
          final protocolResult = _bindings.ctWebSocketHandshakeProtocol(
            handle,
            i,
            viewPtr,
          );
          if (protocolResult != NativeTransportErrorCode.success) {
            _bindings.ctWebSocketHandshakeRelease(handle);
            _throwForError(protocolResult, 'Failed to read WebSocket protocol');
          }
          protocols.add(_decodeUtf8(viewPtr.ref.ptr, viewPtr.ref.len));
        } finally {
          calloc.free(viewPtr);
        }
      }
      final extensions = <String>[];
      for (var i = 0; i < info.extensionsLen; i++) {
        final viewPtr = calloc<CtStringView>();
        try {
          final extResult = _bindings.ctWebSocketHandshakeExtension(
            handle,
            i,
            viewPtr,
          );
          if (extResult != NativeTransportErrorCode.success) {
            _bindings.ctWebSocketHandshakeRelease(handle);
            _throwForError(extResult, 'Failed to read WebSocket extension');
          }
          extensions.add(_decodeUtf8(viewPtr.ref.ptr, viewPtr.ref.len));
        } finally {
          calloc.free(viewPtr);
        }
      }
      return NativeWebSocketHandshake._(
        handle: handle,
        key: key,
        protocols: protocols,
        extensions: extensions,
        release: () {
          _bindings.ctWebSocketHandshakeRelease(handle);
        },
      );
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  }) {
    final protocolBytes = utf8.encode(protocol);
    final protocolPtr = calloc<ffi.Uint8>(protocolBytes.length);
    final buffer = protocolPtr.asTypedList(protocolBytes.length);
    buffer.setAll(0, protocolBytes);
    try {
      final result = _bindings.ctConnectionAcceptWebsocket(
        connectionId,
        handshakeHandle,
        serializer.id,
        protocolPtr,
        protocolBytes.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to accept WebSocket handshake');
      }
    } finally {
      calloc.free(protocolPtr);
    }
  }

  @override
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status = 400,
    String reason = '',
  }) {
    final reasonBytes = utf8.encode(reason);
    final reasonPtr = calloc<ffi.Uint8>(reasonBytes.length);
    final buffer = reasonPtr.asTypedList(reasonBytes.length);
    buffer.setAll(0, reasonBytes);
    try {
      final result = _bindings.ctConnectionRejectWebsocket(
        connectionId,
        handshakeHandle,
        status,
        reasonPtr,
        reasonBytes.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to reject WebSocket handshake');
      }
    } finally {
      calloc.free(reasonPtr);
    }
  }

  @override
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId) {
    final handle = _bindings.ctConnectionTakeHttp2Handshake(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to take HTTP/2 handshake');
    }
    final infoPtr = calloc<CtHttp2HandshakeInfo>();
    try {
      final result = _bindings.ctHttp2HandshakeGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttp2HandshakeRelease(handle);
        _throwForError(result, 'Failed to read HTTP/2 handshake');
      }
      final info = infoPtr.ref;
      final protocol = _decodeUtf8(info.protocolPtr, info.protocolLen);
      final alpn = _decodeUtf8Nullable(info.alpnPtr, info.alpnLen);
      final listenerProtocols = <String>[];
      if (info.listenerProtocolsLen > 0) {
        final viewPtr = calloc<CtStringView>();
        try {
          for (var index = 0; index < info.listenerProtocolsLen; index++) {
            final listenerResult = _bindings.ctHttp2HandshakeListenerProtocol(
              handle,
              index,
              viewPtr,
            );
            if (listenerResult != NativeTransportErrorCode.success) {
              _bindings.ctHttp2HandshakeRelease(handle);
              _throwForError(
                listenerResult,
                'Failed to read HTTP/2 listener protocol',
              );
            }
            final view = viewPtr.ref;
            listenerProtocols.add(_decodeUtf8(view.ptr, view.len));
          }
        } finally {
          calloc.free(viewPtr);
        }
      }
      return NativeHttp2Handshake._(
        handle: handle,
        protocol: protocol,
        alpn: alpn,
        listenerProtocols: listenerProtocols,
        release: () {
          _bindings.ctHttp2HandshakeRelease(handle);
        },
      );
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  void releaseHttp2Handshake(int handle) {
    if (handle <= 0) {
      return;
    }
    _bindings.ctHttp2HandshakeRelease(handle);
  }

  @override
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId) {
    final handle = _bindings.ctConnectionTakeHttp3Handshake(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to take HTTP/3 handshake');
    }
    final infoPtr = calloc<CtHttp3HandshakeInfo>();
    try {
      final result = _bindings.ctHttp3HandshakeGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttp3HandshakeRelease(handle);
        _throwForError(result, 'Failed to read HTTP/3 handshake');
      }
      final info = infoPtr.ref;
      final protocol = _decodeUtf8(info.protocolPtr, info.protocolLen);
      final alpn = _decodeUtf8Nullable(info.alpnPtr, info.alpnLen);
      final listenerProtocols = <String>[];
      if (info.listenerProtocolsLen > 0) {
        final viewPtr = calloc<CtStringView>();
        try {
          for (var index = 0; index < info.listenerProtocolsLen; index++) {
            final listenerResult = _bindings.ctHttp3HandshakeListenerProtocol(
              handle,
              index,
              viewPtr,
            );
            if (listenerResult != NativeTransportErrorCode.success) {
              _bindings.ctHttp3HandshakeRelease(handle);
              _throwForError(
                listenerResult,
                'Failed to read HTTP/3 listener protocol',
              );
            }
            final view = viewPtr.ref;
            listenerProtocols.add(_decodeUtf8(view.ptr, view.len));
          }
        } finally {
          calloc.free(viewPtr);
        }
      }
      return NativeHttp3Handshake._(
        handle: handle,
        protocol: protocol,
        alpn: alpn,
        listenerProtocols: listenerProtocols,
        release: () {
          _bindings.ctHttp3HandshakeRelease(handle);
        },
      );
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  void releaseHttp3Handshake(int handle) {
    if (handle <= 0) {
      return;
    }
    _bindings.ctHttp3HandshakeRelease(handle);
  }

  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) {
    final handle = _bindings.ctConnectionGetHttp3Connection(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to take HTTP/3 connection');
    }
    return NativeHttp3Connection(
      handle: handle,
      release: () {
        final result = _bindings.ctHttp3ConnectionRelease(handle);
        if (result != NativeTransportErrorCode.success) {
          _throwForError(result, 'Failed to release HTTP/3 connection');
        }
      },
    );
  }

  @override
  NativeHttp3Stream? pollHttp3Stream(int connectionId) {
    final handle = _bindings.ctHttp3ConnectionPollStream(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to poll HTTP/3 stream');
    }
    final infoPtr = calloc<CtHttp3StreamInfo>();
    try {
      final result = _bindings.ctHttp3StreamGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttp3StreamRelease(handle);
        _throwForError(result, 'Failed to query HTTP/3 stream');
      }
      final info = infoPtr.ref;
      return NativeHttp3Stream._(
        handle: handle,
        streamId: info.streamId,
        release: () {
          final releaseResult = _bindings.ctHttp3StreamRelease(handle);
          if (releaseResult != NativeTransportErrorCode.success) {
            _throwForError(releaseResult, 'Failed to release HTTP/3 stream');
          }
        },
      );
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  NativeHttpHandshake? pollHttp3Request(int connectionId) {
    final handle = _bindings.ctHttp3ConnectionPollRequest(connectionId);
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to poll HTTP/3 request');
    }
    final infoPtr = calloc<CtHttpHandshakeInfo>();
    var claimedHandle = false;
    try {
      final result = _bindings.ctHttpHandshakeGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttpHandshakeRelease(handle);
        _throwForError(result, 'Failed to read HTTP/3 request');
      }
      final info = infoPtr.ref;
      final data = _readHttpHandshakeData(handle, info);
      final bodyHandle = _bindings.ctHttpHandshakeBodyRetain(handle);
      if (bodyHandle < 0) {
        _bindings.ctHttpHandshakeRelease(handle);
        _throwForError(bodyHandle, 'Failed to retain HTTP/3 body handle');
      }
      late final NativeHttpRequestBody body;
      try {
        if (bodyHandle > 0) {
          final borrowed = _borrowBodyHandle(bodyHandle);
          body = NativeHttpRequestBody._fromNative(
            view: borrowed.bytes,
            bindings: _bindings,
            handle: bodyHandle,
            length: data.bodyLength,
            streaming: borrowed.streaming,
          );
        } else {
          body = NativeHttpRequestBody.synthetic(data.body);
        }
      } catch (error) {
        if (bodyHandle > 0) {
          _bindings.ctHttpBodyRelease(bodyHandle);
        }
        rethrow;
      }
      claimedHandle = true;
      return NativeHttpHandshake._(
        handle: handle,
        method: data.method,
        target: data.target,
        path: data.path,
        query: data.query,
        protocol: data.protocol,
        version: data.version,
        headers: data.headers,
        body: body,
        realm: data.realm,
        procedure: data.procedure,
        release: () {
          final releaseResult = _bindings.ctHttpHandshakeRelease(handle);
          if (releaseResult != NativeTransportErrorCode.success) {
            _throwForError(releaseResult, 'Failed to release HTTP/3 request');
          }
        },
      );
    } finally {
      calloc.free(infoPtr);
      if (!claimedHandle) {
        _bindings.ctHttpHandshakeRelease(handle);
      }
    }
  }

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    if (handshakeHandle <= 0) {
      throw UnsupportedError(
        'HTTP responses require a native handshake handle.',
      );
    }
    final headersList = response.headers.entries.toList(growable: false);
    final headerCount = headersList.length;
    final headerPtr = headerCount == 0
        ? ffi.Pointer<CtHttpHeader>.fromAddress(0)
        : calloc<CtHttpHeader>(headerCount);
    final headerNameStrings = <_NativeString>[];
    final headerValueStrings = <_NativeString>[];
    ffi.Pointer<ffi.Uint8>? bodyPtr;
    try {
      for (var i = 0; i < headerCount; i++) {
        final entry = headersList[i];
        final nameNative = _toNativeString(entry.key);
        final valueNative = _toNativeString(entry.value);
        headerNameStrings.add(nameNative);
        headerValueStrings.add(valueNative);
        final headerStruct = (headerPtr + i).ref;
        headerStruct.namePtr = nameNative.charPtr.cast<ffi.Uint8>();
        headerStruct.nameLen = nameNative.length;
        headerStruct.valuePtr = valueNative.charPtr.cast<ffi.Uint8>();
        headerStruct.valueLen = valueNative.length;
      }

      final bodyBytes = _encodeHttpResponseBody(response.body);
      if (bodyBytes.isEmpty) {
        bodyPtr = ffi.Pointer.fromAddress(0);
      } else {
        bodyPtr = calloc<ffi.Uint8>(bodyBytes.length);
        bodyPtr.asTypedList(bodyBytes.length).setAll(0, bodyBytes);
      }

      final result = _bindings.ctHttpResponseSend(
        handshakeHandle,
        response.status,
        headerPtr,
        headerCount,
        bodyPtr,
        bodyBytes.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send HTTP response');
      }
    } finally {
      for (final name in headerNameStrings) {
        name.dispose();
      }
      for (final value in headerValueStrings) {
        value.dispose();
      }
      if (headerCount > 0) {
        calloc.free(headerPtr);
      }
      final ptr = bodyPtr;
      if (ptr != null && ptr.address != 0) {
        calloc.free(ptr);
      }
    }
  }

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    if (handshakeHandle <= 0) {
      throw UnsupportedError(
        'HTTP response streaming requires a native handshake handle.',
      );
    }
    final entries = headers.entries.toList(growable: false);
    final headerCount = entries.length;
    final headerPtr = headerCount == 0
        ? ffi.Pointer<CtHttpHeader>.fromAddress(0)
        : calloc<CtHttpHeader>(headerCount);
    final headerNameStrings = <_NativeString>[];
    final headerValueStrings = <_NativeString>[];
    try {
      for (var i = 0; i < headerCount; i++) {
        final entry = entries[i];
        final nameNative = _toNativeString(entry.key);
        final valueNative = _toNativeString(entry.value);
        headerNameStrings.add(nameNative);
        headerValueStrings.add(valueNative);
        final headerStruct = (headerPtr + i).ref;
        headerStruct.namePtr = nameNative.charPtr.cast<ffi.Uint8>();
        headerStruct.nameLen = nameNative.length;
        headerStruct.valuePtr = valueNative.charPtr.cast<ffi.Uint8>();
        headerStruct.valueLen = valueNative.length;
      }
      final result = _bindings.ctHttpResponseStreamOpen(
        handshakeHandle,
        status,
        headerPtr,
        headerCount,
      );
      if (result <= 0) {
        _throwForError(result, 'Failed to open HTTP response stream');
      }
      return _FfiHttpResponseStream(
        bindings: _bindings,
        handle: result,
        onError: _throwForError,
      );
    } finally {
      for (final name in headerNameStrings) {
        name.dispose();
      }
      for (final value in headerValueStrings) {
        value.dispose();
      }
      if (headerCount > 0) {
        calloc.free(headerPtr);
      }
    }
  }

  @override
  NativeHttpConnectionEvent? pollHttpConnectionEvent() {
    final handle = _bindings.ctConnectionPollHttpEvent();
    if (handle == 0) {
      return null;
    }
    if (handle < 0) {
      _throwForError(handle, 'Failed to poll HTTP connection event');
    }
    final infoPtr = calloc<CtHttpConnectionEventInfo>();
    try {
      final result = _bindings.ctHttpConnectionEventGet(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttpConnectionEventRelease(handle);
        _throwForError(result, 'Failed to read HTTP connection event');
      }
      final info = infoPtr.ref;
      final detail = _decodeUtf8Nullable(info.detailPtr, info.detailLen);
      final event = NativeHttpConnectionEvent(
        connectionId: info.connectionId,
        protocol: NativeConnectionProtocol.fromId(info.protocol),
        reason: _connectionReasonFromCode(info.reason),
        requestCount: info.requestCount,
        idleTimeouts: info.idleTimeouts,
        bodyTimeouts: info.bodyTimeouts,
        backpressureEvents: info.backpressureEvents,
        maxBackpressureDepth: info.maxBackpressureDepth,
        goAwayEvents: info.goAwayEvents,
        detail: detail,
      );
      _bindings.ctHttpConnectionEventRelease(handle);
      return event;
    } finally {
      calloc.free(infoPtr);
    }
  }

  @override
  NativeRouterMetrics? pollRouterMetrics() {
    final infoPtr = calloc<CtRouterMetricsInfo>();
    try {
      final result = _bindings.ctRouterMetricsSnapshot(infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to read router metrics');
      }
      final info = infoPtr.ref;
      return NativeRouterMetrics(
        totalEvents: info.totalEvents,
        gracefulEvents: info.gracefulEvents,
        goAwayEvents: info.goAwayEvents,
        idleTimeoutEvents: info.idleTimeoutEvents,
        bodyTimeoutEvents: info.bodyTimeoutEvents,
        protocolErrorEvents: info.protocolErrorEvents,
        internalErrorEvents: info.internalErrorEvents,
        backpressureEvents: info.backpressureEvents,
        maxBackpressureDepth: info.maxBackpressureDepth,
      );
    } finally {
      calloc.free(infoPtr);
    }
  }

  Uint8List _encodeHttpResponseBody(NativeHttpResponseBody body) {
    switch (body.kind) {
      case NativeHttpResponseBodyKind.bytes:
        final source = (body as NativeHttpResponseBytes).bytes;
        return Uint8List.fromList(source);
      case NativeHttpResponseBodyKind.text:
        final textBody = body as NativeHttpResponseText;
        final encoding = Encoding.getByName(textBody.encoding) ?? utf8;
        return Uint8List.fromList(encoding.encode(textBody.text));
      case NativeHttpResponseBodyKind.json:
        final jsonBody = body as NativeHttpResponseJson;
        return Uint8List.fromList(utf8.encode(jsonEncode(jsonBody.value)));
      case NativeHttpResponseBodyKind.file:
        throw UnsupportedError('File responses not supported yet');
    }
  }

  _HttpHandshakeFields _readHttpHandshakeData(
    int handle,
    CtHttpHandshakeInfo info,
  ) {
    final method = _decodeUtf8(info.methodPtr, info.methodLen);
    final target = _decodeUtf8(info.targetPtr, info.targetLen);
    final path = _decodeUtf8(info.pathPtr, info.pathLen);
    final query = _decodeUtf8Nullable(info.queryPtr, info.queryLen);
    final protocol = _decodeUtf8(info.protocolPtr, info.protocolLen);
    final headers = <String, String>{};
    for (var i = 0; i < info.headersLen; i++) {
      final headerPtr = calloc<CtHttpHeader>();
      try {
        final headerResult = _bindings.ctHttpHandshakeHeader(
          handle,
          i,
          headerPtr,
        );
        if (headerResult != NativeTransportErrorCode.success) {
          _bindings.ctHttpHandshakeRelease(handle);
          _throwForError(headerResult, 'Failed to read HTTP header');
        }
        final header = headerPtr.ref;
        final name = _decodeUtf8(header.namePtr, header.nameLen);
        final value = _decodeUtf8(header.valuePtr, header.valueLen);
        headers[name] = value;
      } finally {
        calloc.free(headerPtr);
      }
    }
    final body = _borrowBytes(info.bodyPtr, info.bodyLen);
    final realm = _decodeUtf8Nullable(info.realmPtr, info.realmLen);
    final procedure = _decodeUtf8Nullable(info.procedurePtr, info.procedureLen);
    return _HttpHandshakeFields(
      method: method,
      target: target,
      path: path,
      query: query,
      protocol: protocol,
      version: info.version,
      headers: headers,
      body: body,
      realm: realm,
      procedure: procedure,
      bodyLength: info.bodyLen,
    );
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
      final result = _bindings.ctSendMessage(connectionId, ptr, payload.length);
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to send message');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  bool get supportsTestHooks => _bindings.ctTestMessageEnqueue != null;

  int enqueueTestMessage({
    required int connectionId,
    required NativeMessageSerializer serializer,
    required Uint8List frame,
  }) {
    final hook = _bindings.ctTestMessageEnqueue;
    if (hook == null) {
      throw StateError(
        'Native runtime was built without ffi-test support; rebuild with --features ffi-test.',
      );
    }
    if (frame.isEmpty) {
      throw ArgumentError.value(frame.length, 'frame', 'must not be empty');
    }
    final ptr = calloc<ffi.Uint8>(frame.length);
    try {
      ptr.asTypedList(frame.length).setAll(0, frame);
      final result = hook(connectionId, serializer.id, ptr, frame.length);
      if (result < 0) {
        _throwForError(result, 'Failed to enqueue test message');
      }
      return result;
    } finally {
      calloc.free(ptr);
    }
  }

  void clearTestMessages() {
    final hook = _bindings.ctTestClearMessages;
    if (hook == null) {
      return;
    }
    final result = hook();
    if (result != NativeTransportErrorCode.success) {
      _throwForError(result, 'Failed to clear test messages');
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

  @override
  int pollWebSocketMessageHandle(int connectionId) {
    final pollWebSocket = _bindings.ctPollWebSocketMessageHandle;
    if (pollWebSocket == null) {
      return pollMessageHandle(connectionId);
    }
    final handle = pollWebSocket(connectionId);
    if (handle == 0 || handle == NativeTransportErrorCode.unsupported) {
      return 0;
    }
    if (handle < 0) {
      _throwForError(handle, 'Polling websocket message failed');
    }
    return handle;
  }

  @override
  int retainMessageHandle(int handle) {
    final result = _bindings.ctMessageRetain(handle);
    if (result < 0) {
      _throwForError(result, 'Failed to retain message handle');
    }
    return result;
  }

  @override
  void releaseMessageHandle(int handle) {
    if (handle <= 0) {
      return;
    }
    _bindings.ctMessageRelease(handle);
  }

  @override
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  }) {
    final topicBuffer = _toNativeString(topic);
    try {
      final result = _bindings.ctForwardPublishEvent(
        handle,
        connectionId,
        subscriptionId,
        publicationId,
        publisherSessionId != null ? 1 : 0,
        publisherSessionId ?? 0,
        topicBuffer.charPtr,
        topicBuffer.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to forward publish event');
      }
    } finally {
      topicBuffer.dispose();
    }
  }

  @override
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? procedure,
    bool? receiveProgress,
  }) {
    final procedureBuffer = _toNativeString(procedure);
    try {
      final result = _bindings.ctForwardCallInvocation(
        handle,
        connectionId,
        invocationId,
        registrationId,
        callerSessionId != null ? 1 : 0,
        callerSessionId ?? 0,
        procedureBuffer.charPtr,
        procedureBuffer.length,
        receiveProgress == null ? -1 : (receiveProgress ? 1 : 0),
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'Failed to forward call invocation');
      }
    } finally {
      procedureBuffer.dispose();
    }
  }

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {
    final result = _bindings.ctForwardResultFromYield(
      handle,
      connectionId,
      requestId,
      progress ? 1 : 0,
    );
    if (result != NativeTransportErrorCode.success) {
      _throwForError(result, 'Failed to forward result message');
    }
  }

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {
    final result = _bindings.ctForwardErrorFromError(
      handle,
      connectionId,
      requestType,
      requestId,
    );
    if (result != NativeTransportErrorCode.success) {
      _throwForError(result, 'Failed to forward invocation error');
    }
  }

  String _decodeUtf8(ffi.Pointer<ffi.Uint8> ptr, int length) {
    if (ptr == ffi.nullptr || length == 0) {
      return '';
    }
    return utf8.decode(ptr.asTypedList(length));
  }

  String? _decodeUtf8Nullable(ffi.Pointer<ffi.Uint8> ptr, int length) {
    if (ptr == ffi.nullptr || length == 0) {
      return null;
    }
    return utf8.decode(ptr.asTypedList(length));
  }

  static final Uint8List _emptyBytes = Uint8List(0);

  Uint8List _borrowBytes(ffi.Pointer<ffi.Uint8> ptr, int length) {
    if (ptr == ffi.nullptr || length == 0) {
      return _emptyBytes;
    }
    return ptr.asTypedList(length);
  }

  _BorrowedBodyHandleView _borrowBodyHandle(int handle) {
    final viewPtr = calloc<CtHttpBodyView>();
    try {
      final result = _bindings.ctHttpBodyGet(handle, viewPtr);
      if (result == NativeTransportErrorCode.unsupported) {
        return _BorrowedBodyHandleView(_emptyBytes, streaming: true);
      }
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctHttpBodyRelease(handle);
        _throwForError(result, 'Failed to read HTTP body view');
      }
      final view = viewPtr.ref;
      if (view.dataPtr == ffi.nullptr || view.dataLen == 0) {
        return _BorrowedBodyHandleView(_emptyBytes, streaming: false);
      }
      return _BorrowedBodyHandleView(
        view.dataPtr.asTypedList(view.dataLen),
        streaming: false,
      );
    } finally {
      calloc.free(viewPtr);
    }
  }

  _NativeString _toNativeString(String? value) {
    if (value == null || value.isEmpty) {
      return _NativeString(ffi.Pointer<ffi.Char>.fromAddress(0), null, 0);
    }
    final bytes = utf8.encode(value);
    final ptr = calloc<ffi.Uint8>(bytes.length);
    final buffer = ptr.asTypedList(bytes.length);
    buffer.setAll(0, bytes);
    return _NativeString(ptr.cast<ffi.Char>(), ptr, bytes.length);
  }

  String get libraryPath => _libraryPath;

  @override
  String? get libraryPathHint => _libraryPath;
}

class _NativeString {
  _NativeString(this.charPtr, this.bytePtr, this.length);

  final ffi.Pointer<ffi.Char> charPtr;
  final ffi.Pointer<ffi.Uint8>? bytePtr;
  final int length;

  void dispose() {
    final ptr = bytePtr;
    if (ptr != null) {
      calloc.free(ptr);
    }
  }
}

class _FfiHttpResponseStream implements NativeHttpResponseStream {
  _FfiHttpResponseStream({
    required CtFfiBindings bindings,
    required int handle,
    required void Function(int code, String context) onError,
  }) : _bindings = bindings,
       _handle = handle,
       _onError = onError;

  final CtFfiBindings _bindings;
  final int _handle;
  final void Function(int code, String context) _onError;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  void add(Uint8List chunk) {
    if (_closed) {
      throw StateError('HTTP response stream already closed');
    }
    if (chunk.isEmpty) {
      return;
    }
    final ptr = calloc<ffi.Uint8>(chunk.length);
    try {
      ptr.asTypedList(chunk.length).setAll(0, chunk);
      final result = _bindings.ctHttpResponseStreamWrite(
        _handle,
        ptr,
        chunk.length,
      );
      if (result != NativeTransportErrorCode.success) {
        _closed = true;
        _onError(result, 'Failed to write HTTP response chunk');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  void close([Uint8List? finalChunk]) {
    if (_closed) {
      return;
    }
    if (finalChunk != null && finalChunk.isNotEmpty) {
      add(finalChunk);
      if (_closed) {
        return;
      }
    }
    final result = _bindings.ctHttpResponseStreamFinish(_handle);
    _closed = true;
    if (result != NativeTransportErrorCode.success) {
      _onError(result, 'Failed to finish HTTP response stream');
    }
  }
}

class _BorrowedBodyHandleView {
  const _BorrowedBodyHandleView(this.bytes, {required this.streaming});

  final Uint8List bytes;
  final bool streaming;
}
