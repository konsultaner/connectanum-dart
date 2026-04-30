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
  void closeListener(int listenerId);
  int pollConnection(int listenerId);
  int connectionMaxRawSocketExponent(int connectionId);
  NativeConnectionProtocol connectionProtocol(int connectionId);
  void closeConnection(int connectionId);
  String? connectionWebSocketProtocol(int connectionId) => null;
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

  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
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
  int reloadTls() =>
      throw UnsupportedError('TLS reload is not supported by this runtime');
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
  static const sendQueueFull = -17;
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

class NativeHttpTestResponse {
  NativeHttpTestResponse(this.status, this.body);

  final int status;
  final Uint8List body;
}

class NativeHttpResponseStreamDescriptor {
  const NativeHttpResponseStreamDescriptor({
    required this.handle,
    this.libraryPath,
  });

  final int handle;
  final String? libraryPath;
}

abstract class NativeHttpResponseStream {
  factory NativeHttpResponseStream.borrowed({
    required int handle,
    String? libraryPath,
  }) = _BorrowedHttpResponseStream;

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
    this.responseStream,
    this.requestBodyStream,
    this.breakdown = const <NativeRouterMetricsBreakdown>[],
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
  final NativeHttpResponseStreamMetrics? responseStream;
  final NativeHttpRequestBodyStreamMetrics? requestBodyStream;
  final List<NativeRouterMetricsBreakdown> breakdown;

  bool sameValues(NativeRouterMetrics other) {
    if (totalEvents != other.totalEvents ||
        gracefulEvents != other.gracefulEvents ||
        goAwayEvents != other.goAwayEvents ||
        idleTimeoutEvents != other.idleTimeoutEvents ||
        bodyTimeoutEvents != other.bodyTimeoutEvents ||
        protocolErrorEvents != other.protocolErrorEvents ||
        internalErrorEvents != other.internalErrorEvents ||
        backpressureEvents != other.backpressureEvents ||
        maxBackpressureDepth != other.maxBackpressureDepth ||
        ((responseStream == null) != (other.responseStream == null)) ||
        (responseStream != null &&
            !responseStream!.sameValues(other.responseStream)) ||
        ((requestBodyStream == null) != (other.requestBodyStream == null)) ||
        (requestBodyStream != null &&
            !requestBodyStream!.sameValues(other.requestBodyStream))) {
      return false;
    }
    if (breakdown.length != other.breakdown.length) {
      return false;
    }
    for (var index = 0; index < breakdown.length; index++) {
      if (!breakdown[index].sameValues(other.breakdown[index])) {
        return false;
      }
    }
    return true;
  }
}

class NativeHttpResponseStreamMetrics {
  const NativeHttpResponseStreamMetrics({
    required this.streamingResponsesTotal,
    required this.streamOpenToHeadersSendSamplesTotal,
    required this.streamOpenToHeadersSendUsTotal,
    required this.headersSendCallSamplesTotal,
    required this.headersSendCallUsTotal,
    required this.headersToFirstConnectionWriteSamplesTotal,
    required this.headersToFirstConnectionWriteUsTotal,
    required this.headersToFirstConnectionWriteGe1msTotal,
    required this.headersToFirstConnectionWriteGe5msTotal,
    required this.headersToFirstConnectionWriteGe10msTotal,
    required this.firstChunkChannelWaitSamplesTotal,
    required this.firstChunkChannelWaitUsTotal,
    required this.firstChunkChannelWaitGe1msTotal,
    required this.firstChunkChannelWaitGe5msTotal,
    required this.firstChunkChannelWaitGe10msTotal,
    required this.headersToFirstChunkDequeueSamplesTotal,
    required this.headersToFirstChunkDequeueUsTotal,
    required this.headersToFirstChunkDequeueGe1msTotal,
    required this.headersToFirstChunkDequeueGe5msTotal,
    required this.headersToFirstChunkDequeueGe10msTotal,
    required this.firstChunkSendCallSamplesTotal,
    required this.firstChunkSendCallUsTotal,
    required this.firstChunkSendCallGe1msTotal,
    required this.firstChunkSendCallGe5msTotal,
    required this.firstChunkSendCallGe10msTotal,
    required this.headersToFirstChunkSendCallSamplesTotal,
    required this.headersToFirstChunkSendCallUsTotal,
    required this.tailChunkChannelWaitSamplesTotal,
    required this.tailChunkChannelWaitUsTotal,
    required this.tailChunkChannelWaitGe1msTotal,
    required this.tailChunkChannelWaitGe5msTotal,
    required this.tailChunkChannelWaitGe10msTotal,
    required this.tailChunkSendCallSamplesTotal,
    required this.tailChunkSendCallUsTotal,
    required this.tailChunkSendCallGe1msTotal,
    required this.tailChunkSendCallGe5msTotal,
    required this.tailChunkSendCallGe10msTotal,
    required this.firstToLastChunkSendSamplesTotal,
    required this.firstToLastChunkSendUsTotal,
    required this.firstToLastChunkSendGe1msTotal,
    required this.firstToLastChunkSendGe5msTotal,
    required this.firstToLastChunkSendGe10msTotal,
  });

  final int streamingResponsesTotal;
  final int streamOpenToHeadersSendSamplesTotal;
  final int streamOpenToHeadersSendUsTotal;
  final int headersSendCallSamplesTotal;
  final int headersSendCallUsTotal;
  final int headersToFirstConnectionWriteSamplesTotal;
  final int headersToFirstConnectionWriteUsTotal;
  final int headersToFirstConnectionWriteGe1msTotal;
  final int headersToFirstConnectionWriteGe5msTotal;
  final int headersToFirstConnectionWriteGe10msTotal;
  final int firstChunkChannelWaitSamplesTotal;
  final int firstChunkChannelWaitUsTotal;
  final int firstChunkChannelWaitGe1msTotal;
  final int firstChunkChannelWaitGe5msTotal;
  final int firstChunkChannelWaitGe10msTotal;
  final int headersToFirstChunkDequeueSamplesTotal;
  final int headersToFirstChunkDequeueUsTotal;
  final int headersToFirstChunkDequeueGe1msTotal;
  final int headersToFirstChunkDequeueGe5msTotal;
  final int headersToFirstChunkDequeueGe10msTotal;
  final int firstChunkSendCallSamplesTotal;
  final int firstChunkSendCallUsTotal;
  final int firstChunkSendCallGe1msTotal;
  final int firstChunkSendCallGe5msTotal;
  final int firstChunkSendCallGe10msTotal;
  final int headersToFirstChunkSendCallSamplesTotal;
  final int headersToFirstChunkSendCallUsTotal;
  final int tailChunkChannelWaitSamplesTotal;
  final int tailChunkChannelWaitUsTotal;
  final int tailChunkChannelWaitGe1msTotal;
  final int tailChunkChannelWaitGe5msTotal;
  final int tailChunkChannelWaitGe10msTotal;
  final int tailChunkSendCallSamplesTotal;
  final int tailChunkSendCallUsTotal;
  final int tailChunkSendCallGe1msTotal;
  final int tailChunkSendCallGe5msTotal;
  final int tailChunkSendCallGe10msTotal;
  final int firstToLastChunkSendSamplesTotal;
  final int firstToLastChunkSendUsTotal;
  final int firstToLastChunkSendGe1msTotal;
  final int firstToLastChunkSendGe5msTotal;
  final int firstToLastChunkSendGe10msTotal;

  bool sameValues(NativeHttpResponseStreamMetrics? other) {
    return other != null &&
        streamingResponsesTotal == other.streamingResponsesTotal &&
        streamOpenToHeadersSendSamplesTotal ==
            other.streamOpenToHeadersSendSamplesTotal &&
        streamOpenToHeadersSendUsTotal ==
            other.streamOpenToHeadersSendUsTotal &&
        headersSendCallSamplesTotal == other.headersSendCallSamplesTotal &&
        headersSendCallUsTotal == other.headersSendCallUsTotal &&
        headersToFirstConnectionWriteSamplesTotal ==
            other.headersToFirstConnectionWriteSamplesTotal &&
        headersToFirstConnectionWriteUsTotal ==
            other.headersToFirstConnectionWriteUsTotal &&
        headersToFirstConnectionWriteGe1msTotal ==
            other.headersToFirstConnectionWriteGe1msTotal &&
        headersToFirstConnectionWriteGe5msTotal ==
            other.headersToFirstConnectionWriteGe5msTotal &&
        headersToFirstConnectionWriteGe10msTotal ==
            other.headersToFirstConnectionWriteGe10msTotal &&
        firstChunkChannelWaitSamplesTotal ==
            other.firstChunkChannelWaitSamplesTotal &&
        firstChunkChannelWaitUsTotal == other.firstChunkChannelWaitUsTotal &&
        firstChunkChannelWaitGe1msTotal ==
            other.firstChunkChannelWaitGe1msTotal &&
        firstChunkChannelWaitGe5msTotal ==
            other.firstChunkChannelWaitGe5msTotal &&
        firstChunkChannelWaitGe10msTotal ==
            other.firstChunkChannelWaitGe10msTotal &&
        headersToFirstChunkDequeueSamplesTotal ==
            other.headersToFirstChunkDequeueSamplesTotal &&
        headersToFirstChunkDequeueUsTotal ==
            other.headersToFirstChunkDequeueUsTotal &&
        headersToFirstChunkDequeueGe1msTotal ==
            other.headersToFirstChunkDequeueGe1msTotal &&
        headersToFirstChunkDequeueGe5msTotal ==
            other.headersToFirstChunkDequeueGe5msTotal &&
        headersToFirstChunkDequeueGe10msTotal ==
            other.headersToFirstChunkDequeueGe10msTotal &&
        firstChunkSendCallSamplesTotal ==
            other.firstChunkSendCallSamplesTotal &&
        firstChunkSendCallUsTotal == other.firstChunkSendCallUsTotal &&
        firstChunkSendCallGe1msTotal == other.firstChunkSendCallGe1msTotal &&
        firstChunkSendCallGe5msTotal == other.firstChunkSendCallGe5msTotal &&
        firstChunkSendCallGe10msTotal == other.firstChunkSendCallGe10msTotal &&
        headersToFirstChunkSendCallSamplesTotal ==
            other.headersToFirstChunkSendCallSamplesTotal &&
        headersToFirstChunkSendCallUsTotal ==
            other.headersToFirstChunkSendCallUsTotal &&
        tailChunkChannelWaitSamplesTotal ==
            other.tailChunkChannelWaitSamplesTotal &&
        tailChunkChannelWaitUsTotal == other.tailChunkChannelWaitUsTotal &&
        tailChunkChannelWaitGe1msTotal ==
            other.tailChunkChannelWaitGe1msTotal &&
        tailChunkChannelWaitGe5msTotal ==
            other.tailChunkChannelWaitGe5msTotal &&
        tailChunkChannelWaitGe10msTotal ==
            other.tailChunkChannelWaitGe10msTotal &&
        tailChunkSendCallSamplesTotal == other.tailChunkSendCallSamplesTotal &&
        tailChunkSendCallUsTotal == other.tailChunkSendCallUsTotal &&
        tailChunkSendCallGe1msTotal == other.tailChunkSendCallGe1msTotal &&
        tailChunkSendCallGe5msTotal == other.tailChunkSendCallGe5msTotal &&
        tailChunkSendCallGe10msTotal == other.tailChunkSendCallGe10msTotal &&
        firstToLastChunkSendSamplesTotal ==
            other.firstToLastChunkSendSamplesTotal &&
        firstToLastChunkSendUsTotal == other.firstToLastChunkSendUsTotal &&
        firstToLastChunkSendGe1msTotal ==
            other.firstToLastChunkSendGe1msTotal &&
        firstToLastChunkSendGe5msTotal ==
            other.firstToLastChunkSendGe5msTotal &&
        firstToLastChunkSendGe10msTotal ==
            other.firstToLastChunkSendGe10msTotal;
  }
}

class NativeHttpRequestBodyStreamMetrics {
  const NativeHttpRequestBodyStreamMetrics({
    required this.streamingRequestsTotal,
    required this.dataChunkSamplesTotal,
    required this.dataChunkWaitUsTotal,
    required this.firstChunkWaitSamplesTotal,
    required this.firstChunkWaitUsTotal,
    required this.secondChunkWaitSamplesTotal,
    required this.secondChunkWaitUsTotal,
    required this.remainingTailReadSamplesTotal,
    required this.remainingTailReadUsTotal,
    required this.remainingTailDataWaitSamplesTotal,
    required this.remainingTailDataWaitUsTotal,
    required this.remainingTailDataWaitMaxUsTotal,
    required this.totalReadSamplesTotal,
    required this.totalReadUsTotal,
  });

  final int streamingRequestsTotal;
  final int dataChunkSamplesTotal;
  final int dataChunkWaitUsTotal;
  final int firstChunkWaitSamplesTotal;
  final int firstChunkWaitUsTotal;
  final int secondChunkWaitSamplesTotal;
  final int secondChunkWaitUsTotal;
  final int remainingTailReadSamplesTotal;
  final int remainingTailReadUsTotal;
  final int remainingTailDataWaitSamplesTotal;
  final int remainingTailDataWaitUsTotal;
  final int remainingTailDataWaitMaxUsTotal;
  final int totalReadSamplesTotal;
  final int totalReadUsTotal;

  bool sameValues(NativeHttpRequestBodyStreamMetrics? other) {
    return other != null &&
        streamingRequestsTotal == other.streamingRequestsTotal &&
        dataChunkSamplesTotal == other.dataChunkSamplesTotal &&
        dataChunkWaitUsTotal == other.dataChunkWaitUsTotal &&
        firstChunkWaitSamplesTotal == other.firstChunkWaitSamplesTotal &&
        firstChunkWaitUsTotal == other.firstChunkWaitUsTotal &&
        secondChunkWaitSamplesTotal == other.secondChunkWaitSamplesTotal &&
        secondChunkWaitUsTotal == other.secondChunkWaitUsTotal &&
        remainingTailReadSamplesTotal == other.remainingTailReadSamplesTotal &&
        remainingTailReadUsTotal == other.remainingTailReadUsTotal &&
        remainingTailDataWaitSamplesTotal ==
            other.remainingTailDataWaitSamplesTotal &&
        remainingTailDataWaitUsTotal == other.remainingTailDataWaitUsTotal &&
        remainingTailDataWaitMaxUsTotal ==
            other.remainingTailDataWaitMaxUsTotal &&
        totalReadSamplesTotal == other.totalReadSamplesTotal &&
        totalReadUsTotal == other.totalReadUsTotal;
  }
}

class NativeRouterMetricsBreakdown {
  const NativeRouterMetricsBreakdown({
    required this.listenerId,
    required this.protocol,
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

  final int listenerId;
  final NativeConnectionProtocol protocol;
  final int totalEvents;
  final int gracefulEvents;
  final int goAwayEvents;
  final int idleTimeoutEvents;
  final int bodyTimeoutEvents;
  final int protocolErrorEvents;
  final int internalErrorEvents;
  final int backpressureEvents;
  final int maxBackpressureDepth;

  bool sameValues(NativeRouterMetricsBreakdown other) {
    return listenerId == other.listenerId &&
        protocol == other.protocol &&
        totalEvents == other.totalEvents &&
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
    bool ownsHandle = true,
    bool streaming = false,
    Uint8List Function(int length)? streamReadOverride,
    void Function()? streamFinishOverride,
  }) : _view = view,
       _bindings = bindings,
       _handle = handle,
       _length = length,
       _ownsHandle = ownsHandle,
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

  /// Reconstructs a borrowed HTTP body wrapper from a plain descriptor sent
  /// across isolates. The underlying native handle remains owned by the source
  /// isolate and is released there when the request completes.
  factory NativeHttpRequestBody.borrowed({
    required int handle,
    required int length,
    required bool streaming,
    String? libraryPath,
  }) {
    if (handle <= 0) {
      throw ArgumentError.value(handle, 'handle', 'must be positive');
    }
    final resolvedPath = NativeLibraryLoader.resolvePath(libraryPath);
    final borrowedLibrary = _borrowedLibraries.putIfAbsent(resolvedPath, () {
      final library = ffi.DynamicLibrary.open(resolvedPath);
      return _BorrowedNativeLibrary(library, CtFfiBindings(library));
    });
    return NativeHttpRequestBody._internal(
      Uint8List(0),
      bindings: borrowedLibrary.bindings,
      handle: handle,
      length: length,
      ownsHandle: false,
      streaming: streaming,
    );
  }

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
  final bool _ownsHandle;
  bool _released = false;
  final bool _streaming;
  final Uint8List Function(int length)? _streamReadOverride;
  final void Function()? _streamFinishOverride;
  bool _streamFinished = false;
  static final Map<String, _BorrowedNativeLibrary> _borrowedLibraries =
      <String, _BorrowedNativeLibrary>{};

  static const int _defaultChunkSize = 64 * 1024;

  int get length => _length;
  int? get nativeHandle => _handle;
  bool get isStreaming => _streaming;
  bool get hasNativeHandle =>
      _handle != null && _bindings != null && !_released;

  /// View backed by the native buffer (callers must not mutate).
  Uint8List get view {
    if (_view.isEmpty && _handle != null && !_released && _length > 0) {
      _view = _readAll();
    }
    return _view;
  }

  /// Materializes an isolate-safe Dart-owned buffer without routing through
  /// the borrowed [view] path when the native handle is still active.
  Uint8List materializeOwnedBytes() {
    if (_length == 0) {
      if (_streaming) {
        _finishStreaming(ignoreErrors: false);
      }
      return Uint8List(0);
    }
    if (_streaming) {
      if (_view.isEmpty &&
          ((_handle != null && !_released) || _streamReadOverride != null)) {
        _view = _readAll();
      }
      return _view.isEmpty ? Uint8List(0) : Uint8List.fromList(_view);
    }
    if (_view.isNotEmpty) {
      return Uint8List.fromList(_view);
    }
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == null || _released) {
      return Uint8List(0);
    }
    final buffer = Uint8List(_length);
    var offset = 0;
    while (offset < _length) {
      final remaining = _length - offset;
      final toRead = math.min(remaining, _defaultChunkSize);
      final chunk = _readSlice(offset, toRead);
      if (chunk.isEmpty) {
        break;
      }
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return offset == _length ? buffer : buffer.sublist(0, offset);
  }

  /// Copies the body into Dart-managed memory (safe to send across isolates).
  Uint8List copy() => Uint8List.fromList(materializeOwnedBytes());

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
      } else if (_ownsHandle && _length > 0) {
        _view = _readAll();
      } else if (_ownsHandle) {
        _view = Uint8List(0);
      }
      if (_ownsHandle) {
        final result = bindings.ctHttpBodyRelease(handle);
        if (result != NativeTransportErrorCode.success) {
          // Swallow release failures to avoid crashing during shutdown.
        }
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

class _BorrowedNativeLibrary {
  const _BorrowedNativeLibrary(this.library, this.bindings);

  // ignore: unused_field
  final ffi.DynamicLibrary library;
  final CtFfiBindings bindings;
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

class _NativeMessageMetadata {
  const _NativeMessageMetadata({
    required this.messageCode,
    required this.primaryId,
    required this.secondaryId,
    required this.detailNumberA,
    required this.detailNumberB,
    required this.flags,
    this.detailsBytes,
    this.stringA,
    this.stringB,
    this.stringC,
    this.stringD,
    this.stringE,
  });

  static const flagMetadataBind = 1 << 4;

  final int messageCode;
  final int primaryId;
  final int secondaryId;
  final int detailNumberA;
  final int detailNumberB;
  final int flags;
  final Uint8List? detailsBytes;
  final String? stringA;
  final String? stringB;
  final String? stringC;
  final String? stringD;
  final String? stringE;

  bool hasFlag(int flag) => (flags & flag) != 0;
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
    int Function(int handle)? takeOverride,
    int Function(int handle)? retainOverride,
    void Function(int handle)? releaseOverride,
  }) : _bindings = bindings,
       _takeOverride = takeOverride,
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
      takeOverride: null,
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
    int Function(int handle)? onTake,
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
      takeOverride: onTake ?? (handle > 0 ? (_) => handle : null),
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
  int Function(int handle)? _takeOverride;
  final int Function(int handle)? _retainOverride;
  final void Function(int handle)? _releaseOverride;

  bool get hasNativeHandle => handle > 0;

  int takeHandle() {
    if (!_tryMarkReleased()) {
      return 0;
    }
    _releaseHandle = null;
    final takeOverride = _takeOverride;
    if (takeOverride != null) {
      return takeOverride(handle);
    }
    return 0;
  }

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

  void _setTakeOverride(int Function(int handle)? takeHandle) {
    _takeOverride = takeHandle;
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
      var result = _bindings.ctMessagePeek(handle, infoPtr);
      if (result != NativeTransportErrorCode.success) {
        _bindings.ctMessageRelease(handle);
        throw NativeTransportException(
          result,
          _buildNativeErrorMessage(result, 'Failed to peek connection message'),
        );
      }

      var info = infoPtr.ref;
      final serializer = NativeMessageSerializer.fromId(info.serializer);
      final argsAddress = info.argsLen == 0 ? 0 : info.argsPtr.address;
      final kwargsAddress = info.kwargsLen == 0 ? 0 : info.kwargsPtr.address;
      final args = info.argsLen == 0
          ? null
          : info.argsPtr.asTypedList(info.argsLen);
      final kwargs = info.kwargsLen == 0
          ? null
          : info.kwargsPtr.asTypedList(info.kwargsLen);
      final metadata = _metadataFromFfi(info);

      Uint8List frame;
      int frameAddress;
      AbstractMessage message;

      try {
        final metadataBound =
            metadata.hasFlag(_NativeMessageMetadata.flagMetadataBind)
            ? bindMessage(
                serializer,
                Uint8List(0),
                argsBytes: args,
                kwargsBytes: kwargs,
                metadataMessageCode: metadata.messageCode,
                metadataPrimaryId: metadata.primaryId,
                metadataSecondaryId: metadata.secondaryId,
                metadataDetailNumberA: metadata.detailNumberA,
                metadataFlags: metadata.flags,
                metadataDetailsBytes: metadata.detailsBytes,
                metadataStringA: metadata.stringA,
                metadataStringB: metadata.stringB,
                metadataStringC: metadata.stringC,
                metadataStringD: metadata.stringD,
                metadataStringE: metadata.stringE,
              )
            : null;
        if (metadataBound != null) {
          frame = Uint8List(0);
          frameAddress = 0;
          message = metadataBound;
        } else {
          result = _bindings.ctMessageGet(handle, infoPtr);
          if (result != NativeTransportErrorCode.success) {
            _bindings.ctMessageRelease(handle);
            throw NativeTransportException(
              result,
              _buildNativeErrorMessage(
                result,
                'Failed to read connection message',
              ),
            );
          }
          info = infoPtr.ref;
          frameAddress = info.framePtr.address;
          frame = info.frameLen == 0
              ? Uint8List(0)
              : info.framePtr.asTypedList(info.frameLen);
          message = bindMessage(
            serializer,
            frame,
            argsBytes: args,
            kwargsBytes: kwargs,
          );
        }
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
          takeOverride: null,
          retainOverride: null,
          releaseOverride: null,
        );
        final token = _MessageFinalizerToken(_bindings, handle);
        _messageFinalizer.attach(nativeMessage, token, detach: nativeMessage);
        nativeMessage._setTakeOverride((_) {
          _messageFinalizer.detach(nativeMessage);
          return handle;
        });
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

_NativeMessageMetadata _metadataFromFfi(CtMessageInfo info) {
  final flags = info.flags;
  final metadataBind = (flags & _NativeMessageMetadata.flagMetadataBind) != 0;
  return _NativeMessageMetadata(
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

Uint8List? _readOptionalBytes(ffi.Pointer<ffi.Uint8> ptr, int len) {
  if (len <= 0 || ptr.address == 0) {
    return null;
  }
  return ptr.asTypedList(len);
}

String? _readOptionalString(ffi.Pointer<ffi.Uint8> ptr, int len) {
  if (len <= 0 || ptr.address == 0) {
    return null;
  }
  return String.fromCharCodes(ptr.asTypedList(len));
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
    NativeTransportErrorCode.sendQueueFull =>
      '$context: native send queue full (backpressure)',
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
  static String get _libraryFileName => switch (Platform.operatingSystem) {
    'linux' => 'libct_ffi.so',
    'macos' => 'libct_ffi.dylib',
    'windows' => 'ct_ffi.dll',
    _ => 'libct_ffi.so',
  };

  static Iterable<String> get _relativeCandidates sync* {
    final name = _libraryFileName;
    yield '../native/transport/target/debug/$name';
    yield '../native/transport/target/release/$name';
    yield '../../native/transport/target/debug/$name';
    yield '../../native/transport/target/release/$name';
  }

  static String? _probeHooksRunnerSharedFromAnchor(Directory anchor) {
    final name = _libraryFileName;
    var current = anchor;
    for (var depth = 0; depth < 8; depth++) {
      final base = Directory(
        '${current.path}/.dart_tool/hooks_runner/shared/connectanum_router/build',
      );
      if (base.existsSync()) {
        final resolved = _freshestInConfigDirs(base, name);
        if (resolved != null) {
          return resolved;
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

  static String? _freshestInConfigDirs(Directory base, String fileName) {
    File? freshest;
    for (final entity in base.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final candidate = File('${entity.path}/$fileName');
      if (!candidate.existsSync()) {
        continue;
      }
      if (freshest == null ||
          candidate.lastModifiedSync().isAfter(freshest.lastModifiedSync())) {
        freshest = candidate;
      }
    }
    return freshest?.path;
  }

  static String? _probeFromAnchor(Directory anchor) {
    final name = _libraryFileName;
    var current = anchor;
    for (var depth = 0; depth < 6; depth++) {
      final debug = File('${current.path}/native/transport/target/debug/$name');
      if (debug.existsSync()) {
        return debug.path;
      }
      final release = File(
        '${current.path}/native/transport/target/release/$name',
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

  static String resolvePath(
    String? overridePath, {
    Directory? currentDirectory,
    bool ignoreEnvironmentOverride = false,
  }) {
    if (overridePath != null && overridePath.isNotEmpty) {
      return overridePath;
    }
    if (!ignoreEnvironmentOverride) {
      final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
      if (envOverride != null && envOverride.isNotEmpty) {
        return envOverride;
      }
    }
    final cwd = currentDirectory ?? Directory.current;
    final searchRoots = <Directory>{
      cwd,
      cwd.parent,
      File(Platform.script.toFilePath()).parent,
      File(Platform.script.toFilePath()).parent.parent,
      File(Platform.resolvedExecutable).parent,
    };
    for (final root in searchRoots) {
      final probed = _probeHooksRunnerSharedFromAnchor(root);
      if (probed != null) {
        return probed;
      }
    }
    for (final candidate in _relativeCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    for (final root in searchRoots) {
      final probed = _probeFromAnchor(root);
      if (probed != null) {
        return probed;
      }
    }
    return _libraryFileName;
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
  RandomAccessFile? _runtimeLock;

  static NativeTransportRuntime? _instance;
  static final String _runtimeLockPath =
      '${Directory.systemTemp.path}/connectanum_native_runtime.lock';
  static const Set<int> _runtimeLockRetryErrnos = {
    11, // EAGAIN on Linux
    35, // EWOULDBLOCK on macOS
  };

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
    _releaseRuntimeLock();
    if (_instance == this) {
      _instance = null;
    }
    _onListenerStarted = null;
    _onConnection = null;
  }

  void _acquireRuntimeLock() {
    if (_runtimeLock != null) {
      return;
    }
    final file = File(_runtimeLockPath);
    file.parent.createSync(recursive: true);
    final handle = file.openSync(mode: FileMode.write);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var backoff = const Duration(milliseconds: 25);
    while (true) {
      try {
        handle.lockSync(FileLock.exclusive);
        break;
      } on FileSystemException catch (error) {
        final errno = error.osError?.errorCode;
        if (_runtimeLockRetryErrnos.contains(errno) &&
            DateTime.now().isBefore(deadline)) {
          sleep(backoff);
          if (backoff < const Duration(milliseconds: 250)) {
            backoff *= 2;
          }
          continue;
        }
        rethrow;
      }
    }
    _runtimeLock = handle;
  }

  void _releaseRuntimeLock() {
    final handle = _runtimeLock;
    if (handle == null) {
      return;
    }
    try {
      handle.unlockSync();
    } catch (_) {}
    try {
      handle.closeSync();
    } catch (_) {}
    _runtimeLock = null;
  }

  void setListenerCallbacks({
    void Function(int listenerId, int status)? onStarted,
    void Function(int listenerId, int connectionId)? onConnection,
  }) {
    _onListenerStarted = onStarted;
    _onConnection = onConnection;
  }

  @override
  void start() {
    _acquireRuntimeLock();
    try {
      _checkZero(_bindings.ctStartRuntime(), 'Failed to start runtime');
    } catch (_) {
      _releaseRuntimeLock();
      rethrow;
    }
  }

  @override
  void shutdown() {
    try {
      _checkZero(_bindings.ctShutdown(), 'Failed to shutdown runtime');
    } finally {
      _releaseRuntimeLock();
    }
  }

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
  void closeListener(int listenerId) {
    final result = _bindings.ctListenerClose(listenerId);
    if (result < 0) {
      _throwForError(result, 'Failed to close listener');
    }
  }

  bool get supportsHttp3TestClient =>
      _bindings.ctTestHttp3StreamRequestHandle != null &&
      _bindings.ctTestBufferFreeHandle != null;

  NativeHttpTestResponse runHttp3StreamRequest({
    required String host,
    required int port,
    required String path,
    required String method,
    Map<String, String> headers = const {},
    Uint8List? body,
    required String certificatePem,
  }) {
    final requestFn = _bindings.ctTestHttp3StreamRequestHandle;
    final bufferFree = _bindings.ctTestBufferFreeHandle;
    if (requestFn == null || bufferFree == null) {
      throw UnsupportedError('HTTP/3 test client is not available');
    }
    final payload = body ?? Uint8List(0);
    return using((arena) {
      final hostPtr = host.toNativeUtf8(allocator: arena);
      final pathPtr = path.toNativeUtf8(allocator: arena);
      final methodPtr = method.toNativeUtf8(allocator: arena);
      final certPtr = certificatePem.toNativeUtf8(allocator: arena);

      final headerCount = headers.length;
      final headerArray = headerCount == 0
          ? ffi.nullptr
          : arena<CtHttpHeader>(headerCount);
      var index = 0;
      headers.forEach((name, value) {
        final namePtr = name.toNativeUtf8(allocator: arena);
        final valuePtr = value.toNativeUtf8(allocator: arena);
        headerArray[index]
          ..namePtr = namePtr.cast()
          ..nameLen = name.length
          ..valuePtr = valuePtr.cast()
          ..valueLen = value.length;
        index += 1;
      });

      final bodyPtr = payload.isEmpty
          ? ffi.nullptr
          : arena<ffi.Uint8>(payload.length);
      if (payload.isNotEmpty) {
        bodyPtr.asTypedList(payload.length).setAll(0, payload);
      }

      final statusPtr = arena<ffi.Int32>();
      final responsePtrPtr = arena<ffi.Pointer<ffi.Uint8>>();
      final responseLenPtr = arena<ffi.IntPtr>();

      final result = requestFn(
        hostPtr,
        port,
        pathPtr,
        methodPtr,
        headerArray,
        headerCount,
        bodyPtr,
        payload.length,
        certPtr,
        statusPtr,
        responsePtrPtr,
        responseLenPtr,
      );
      if (result != NativeTransportErrorCode.success) {
        _throwForError(result, 'HTTP/3 test request failed');
      }
      final status = statusPtr.value;
      final responsePtr = responsePtrPtr.value;
      final responseLen = responseLenPtr.value;
      Uint8List responseBody;
      if (responsePtr == ffi.nullptr || responseLen == 0) {
        responseBody = Uint8List(0);
      } else {
        responseBody = Uint8List.fromList(responsePtr.asTypedList(responseLen));
        bufferFree(responsePtr, responseLen);
      }
      return NativeHttpTestResponse(status, responseBody);
    });
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
  void closeConnection(int connectionId) {
    final result = _bindings.ctConnectionClose(connectionId);
    if (result < 0) {
      _throwForError(result, 'Failed to close connection');
    }
  }

  @override
  String? connectionWebSocketProtocol(int connectionId) {
    const initialCapacity = 256;
    return using((arena) {
      var capacity = initialCapacity;
      final lenPtr = arena<ffi.Int32>()..value = capacity;
      var buffer = arena<ffi.Uint8>(capacity);
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = _bindings.ctConnectionWebSocketProtocol(
          connectionId,
          buffer,
          lenPtr,
        );
        if (result == NativeTransportErrorCode.success) {
          final length = lenPtr.value;
          if (length <= 0) {
            return null;
          }
          return utf8.decode(buffer.asTypedList(length));
        }
        if (result == NativeTransportErrorCode.invalidArgument &&
            lenPtr.value > capacity) {
          capacity = lenPtr.value;
          buffer = arena<ffi.Uint8>(capacity);
          lenPtr.value = capacity;
          continue;
        }
        _throwForError(result, 'Failed to query WebSocket subprotocol');
      }
      return null;
    });
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
    final handle = _openHttpResponseStreamHandle(
      handshakeHandle: handshakeHandle,
      status: status,
      headers: headers,
    );
    return _FfiHttpResponseStream(
      bindings: _bindings,
      handle: handle,
      onError: _throwForError,
    );
  }

  @override
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    final handle = _openHttpResponseStreamHandle(
      handshakeHandle: handshakeHandle,
      status: status,
      headers: headers,
    );
    return NativeHttpResponseStreamDescriptor(
      handle: handle,
      libraryPath: _libraryPath,
    );
  }

  int _openHttpResponseStreamHandle({
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
      return result;
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
      final breakdown = <NativeRouterMetricsBreakdown>[];
      if (info.breakdownLen > 0 && info.breakdownPtr.address != 0) {
        for (var index = 0; index < info.breakdownLen; index++) {
          final entry = (info.breakdownPtr + index).ref;
          breakdown.add(
            NativeRouterMetricsBreakdown(
              listenerId: entry.listenerId,
              protocol: NativeConnectionProtocol.fromId(entry.protocol),
              totalEvents: entry.totalEvents,
              gracefulEvents: entry.gracefulEvents,
              goAwayEvents: entry.goAwayEvents,
              idleTimeoutEvents: entry.idleTimeoutEvents,
              bodyTimeoutEvents: entry.bodyTimeoutEvents,
              protocolErrorEvents: entry.protocolErrorEvents,
              internalErrorEvents: entry.internalErrorEvents,
              backpressureEvents: entry.backpressureEvents,
              maxBackpressureDepth: entry.maxBackpressureDepth,
            ),
          );
        }
      }
      final responseStream =
          info.responseStreamingResponsesTotal > 0 ||
              info.responseStreamOpenToHeadersSendSamplesTotal > 0 ||
              info.responseStreamHeadersSendCallSamplesTotal > 0 ||
              info.responseStreamHeadersToFirstConnectionWriteSamplesTotal >
                  0 ||
              info.responseStreamFirstChunkChannelWaitSamplesTotal > 0 ||
              info.responseStreamHeadersToFirstChunkDequeueSamplesTotal > 0 ||
              info.responseStreamFirstChunkSendCallSamplesTotal > 0 ||
              info.responseStreamHeadersToFirstChunkSendCallSamplesTotal > 0 ||
              info.responseStreamTailChunkChannelWaitSamplesTotal > 0 ||
              info.responseStreamTailChunkSendCallSamplesTotal > 0 ||
              info.responseStreamFirstToLastChunkSendSamplesTotal > 0
          ? NativeHttpResponseStreamMetrics(
              streamingResponsesTotal: info.responseStreamingResponsesTotal,
              streamOpenToHeadersSendSamplesTotal:
                  info.responseStreamOpenToHeadersSendSamplesTotal,
              streamOpenToHeadersSendUsTotal:
                  info.responseStreamOpenToHeadersSendUsTotal,
              headersSendCallSamplesTotal:
                  info.responseStreamHeadersSendCallSamplesTotal,
              headersSendCallUsTotal: info.responseStreamHeadersSendCallUsTotal,
              headersToFirstConnectionWriteSamplesTotal:
                  info.responseStreamHeadersToFirstConnectionWriteSamplesTotal,
              headersToFirstConnectionWriteUsTotal:
                  info.responseStreamHeadersToFirstConnectionWriteUsTotal,
              headersToFirstConnectionWriteGe1msTotal:
                  info.responseStreamHeadersToFirstConnectionWriteGe1msTotal,
              headersToFirstConnectionWriteGe5msTotal:
                  info.responseStreamHeadersToFirstConnectionWriteGe5msTotal,
              headersToFirstConnectionWriteGe10msTotal:
                  info.responseStreamHeadersToFirstConnectionWriteGe10msTotal,
              firstChunkChannelWaitSamplesTotal:
                  info.responseStreamFirstChunkChannelWaitSamplesTotal,
              firstChunkChannelWaitUsTotal:
                  info.responseStreamFirstChunkChannelWaitUsTotal,
              firstChunkChannelWaitGe1msTotal:
                  info.responseStreamFirstChunkChannelWaitGe1msTotal,
              firstChunkChannelWaitGe5msTotal:
                  info.responseStreamFirstChunkChannelWaitGe5msTotal,
              firstChunkChannelWaitGe10msTotal:
                  info.responseStreamFirstChunkChannelWaitGe10msTotal,
              headersToFirstChunkDequeueSamplesTotal:
                  info.responseStreamHeadersToFirstChunkDequeueSamplesTotal,
              headersToFirstChunkDequeueUsTotal:
                  info.responseStreamHeadersToFirstChunkDequeueUsTotal,
              headersToFirstChunkDequeueGe1msTotal:
                  info.responseStreamHeadersToFirstChunkDequeueGe1msTotal,
              headersToFirstChunkDequeueGe5msTotal:
                  info.responseStreamHeadersToFirstChunkDequeueGe5msTotal,
              headersToFirstChunkDequeueGe10msTotal:
                  info.responseStreamHeadersToFirstChunkDequeueGe10msTotal,
              firstChunkSendCallSamplesTotal:
                  info.responseStreamFirstChunkSendCallSamplesTotal,
              firstChunkSendCallUsTotal:
                  info.responseStreamFirstChunkSendCallUsTotal,
              firstChunkSendCallGe1msTotal:
                  info.responseStreamFirstChunkSendCallGe1msTotal,
              firstChunkSendCallGe5msTotal:
                  info.responseStreamFirstChunkSendCallGe5msTotal,
              firstChunkSendCallGe10msTotal:
                  info.responseStreamFirstChunkSendCallGe10msTotal,
              headersToFirstChunkSendCallSamplesTotal:
                  info.responseStreamHeadersToFirstChunkSendCallSamplesTotal,
              headersToFirstChunkSendCallUsTotal:
                  info.responseStreamHeadersToFirstChunkSendCallUsTotal,
              tailChunkChannelWaitSamplesTotal:
                  info.responseStreamTailChunkChannelWaitSamplesTotal,
              tailChunkChannelWaitUsTotal:
                  info.responseStreamTailChunkChannelWaitUsTotal,
              tailChunkChannelWaitGe1msTotal:
                  info.responseStreamTailChunkChannelWaitGe1msTotal,
              tailChunkChannelWaitGe5msTotal:
                  info.responseStreamTailChunkChannelWaitGe5msTotal,
              tailChunkChannelWaitGe10msTotal:
                  info.responseStreamTailChunkChannelWaitGe10msTotal,
              tailChunkSendCallSamplesTotal:
                  info.responseStreamTailChunkSendCallSamplesTotal,
              tailChunkSendCallUsTotal:
                  info.responseStreamTailChunkSendCallUsTotal,
              tailChunkSendCallGe1msTotal:
                  info.responseStreamTailChunkSendCallGe1msTotal,
              tailChunkSendCallGe5msTotal:
                  info.responseStreamTailChunkSendCallGe5msTotal,
              tailChunkSendCallGe10msTotal:
                  info.responseStreamTailChunkSendCallGe10msTotal,
              firstToLastChunkSendSamplesTotal:
                  info.responseStreamFirstToLastChunkSendSamplesTotal,
              firstToLastChunkSendUsTotal:
                  info.responseStreamFirstToLastChunkSendUsTotal,
              firstToLastChunkSendGe1msTotal:
                  info.responseStreamFirstToLastChunkSendGe1msTotal,
              firstToLastChunkSendGe5msTotal:
                  info.responseStreamFirstToLastChunkSendGe5msTotal,
              firstToLastChunkSendGe10msTotal:
                  info.responseStreamFirstToLastChunkSendGe10msTotal,
            )
          : null;
      final requestBodyStream =
          info.requestBodyStreamingRequestsTotal > 0 ||
              info.requestBodyStreamDataChunkSamplesTotal > 0 ||
              info.requestBodyStreamFirstChunkWaitSamplesTotal > 0 ||
              info.requestBodyStreamSecondChunkWaitSamplesTotal > 0 ||
              info.requestBodyStreamRemainingTailReadSamplesTotal > 0 ||
              info.requestBodyStreamRemainingTailDataWaitSamplesTotal > 0 ||
              info.requestBodyStreamTotalReadSamplesTotal > 0
          ? NativeHttpRequestBodyStreamMetrics(
              streamingRequestsTotal: info.requestBodyStreamingRequestsTotal,
              dataChunkSamplesTotal:
                  info.requestBodyStreamDataChunkSamplesTotal,
              dataChunkWaitUsTotal: info.requestBodyStreamDataChunkWaitUsTotal,
              firstChunkWaitSamplesTotal:
                  info.requestBodyStreamFirstChunkWaitSamplesTotal,
              firstChunkWaitUsTotal:
                  info.requestBodyStreamFirstChunkWaitUsTotal,
              secondChunkWaitSamplesTotal:
                  info.requestBodyStreamSecondChunkWaitSamplesTotal,
              secondChunkWaitUsTotal:
                  info.requestBodyStreamSecondChunkWaitUsTotal,
              remainingTailReadSamplesTotal:
                  info.requestBodyStreamRemainingTailReadSamplesTotal,
              remainingTailReadUsTotal:
                  info.requestBodyStreamRemainingTailReadUsTotal,
              remainingTailDataWaitSamplesTotal:
                  info.requestBodyStreamRemainingTailDataWaitSamplesTotal,
              remainingTailDataWaitUsTotal:
                  info.requestBodyStreamRemainingTailDataWaitUsTotal,
              remainingTailDataWaitMaxUsTotal:
                  info.requestBodyStreamRemainingTailDataWaitMaxUsTotal,
              totalReadSamplesTotal:
                  info.requestBodyStreamTotalReadSamplesTotal,
              totalReadUsTotal: info.requestBodyStreamTotalReadUsTotal,
            )
          : null;
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
        responseStream: responseStream,
        requestBodyStream: requestBodyStream,
        breakdown: breakdown,
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

  @override
  int reloadTls() {
    final result = _bindings.ctReloadTls();
    if (result < 0) {
      _throwForError(result, 'Failed to reload TLS configuration');
    }
    return result;
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

abstract class _BindingsHttpResponseStream implements NativeHttpResponseStream {
  _BindingsHttpResponseStream({
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

class _FfiHttpResponseStream extends _BindingsHttpResponseStream {
  _FfiHttpResponseStream({
    required super.bindings,
    required super.handle,
    required super.onError,
  });
}

class _BorrowedHttpResponseStream extends _BindingsHttpResponseStream {
  _BorrowedHttpResponseStream({required super.handle, String? libraryPath})
    : super(
        bindings: _borrowedNativeLibrary(libraryPath).bindings,
        onError: (code, context) => throw NativeTransportException(
          code,
          _buildNativeErrorMessage(code, context),
        ),
      );

  static _BorrowedNativeLibrary _borrowedNativeLibrary(String? libraryPath) {
    final resolvedPath = NativeLibraryLoader.resolvePath(libraryPath);
    return _borrowedLibraries.putIfAbsent(resolvedPath, () {
      final library = ffi.DynamicLibrary.open(resolvedPath);
      return _BorrowedNativeLibrary(library, CtFfiBindings(library));
    });
  }

  static final Map<String, _BorrowedNativeLibrary> _borrowedLibraries =
      <String, _BorrowedNativeLibrary>{};
}

class _BorrowedBodyHandleView {
  const _BorrowedBodyHandleView(this.bytes, {required this.streaming});

  final Uint8List bytes;
  final bool streaming;
}
