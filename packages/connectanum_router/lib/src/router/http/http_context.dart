// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/invocation.dart' as invocation_msg;
import 'package:connectanum_core/src/message/yield.dart' as yield_msg;
import 'package:connectanum_router/src/native/runtime.dart';

/// Keys used for encoding HTTP metadata into WAMP custom maps.
abstract final class HttpInvocationKeys {
  static const requestId = '_http_request_id';
  static const request = '_http';
  static const response = '_http_response';
  static const responseStreamControlPort = '_http_response_stream_control_port';
  static const responseBodyKind = 'bodyKind';
  static const responseBody = 'body';
  static const responseBodyEncoding = 'bodyEncoding';
  static const responseFilePath = 'filePath';
  static const requestBodyHandle = 'bodyHandle';
  static const requestBodyLength = 'bodyLength';
  static const requestBodyStreaming = 'bodyStreaming';
  static const requestBodyLibraryPath = 'bodyLibraryPath';
}

abstract final class HttpInvocationControlMessages {
  static const openResponseStream = '_http_response_stream_open';
}

/// Snapshot of an HTTP request that is routed through the WAMP invocation
/// pipeline.
class HttpRequestSnapshot {
  HttpRequestSnapshot({
    required this.id,
    required this.method,
    required this.target,
    required this.path,
    required this.protocol,
    required this.version,
    required Map<String, String> headers,
    this.query,
    Uint8List? body,
    this.nativeBody,
    bool copyBody = true,
    this.realm,
    this.procedure,
  }) : headers = Map.unmodifiable(headers),
       _body = body == null
           ? null
           : (copyBody ? Uint8List.fromList(body) : body);

  final int id;
  final String method;
  final String target;
  final String path;
  final String protocol;
  final int version;
  final Map<String, String> headers;
  final String? query;
  Uint8List? _body;
  final NativeHttpRequestBody? nativeBody;
  final String? realm;
  final String? procedure;

  Uint8List? get body {
    final existing = _body;
    if (existing != null) {
      return existing;
    }
    final nativeBody = this.nativeBody;
    if (nativeBody == null) {
      return null;
    }
    final materialized = nativeBody.materializeOwnedBytes();
    _body = materialized;
    return materialized;
  }

  Map<String, Object?> toInvocationPayload({String? nativeLibraryPath}) {
    final payload = <String, Object?>{
      'id': id,
      'method': method,
      'target': target,
      'path': path,
      if (query != null) 'query': query,
      'protocol': protocol,
      'version': version,
      'headers': headers,
      if (realm != null) 'realm': realm,
      if (procedure != null) 'procedure': procedure,
    };
    final transferableBody = _transferableNativeBody(nativeLibraryPath);
    if (transferableBody != null) {
      payload[HttpInvocationKeys.requestBodyHandle] =
          transferableBody.nativeHandle;
      payload[HttpInvocationKeys.requestBodyLength] = transferableBody.length;
      payload[HttpInvocationKeys.requestBodyStreaming] =
          transferableBody.isStreaming;
      payload[HttpInvocationKeys.requestBodyLibraryPath] = nativeLibraryPath;
    } else {
      final body = this.body;
      if (body != null) {
        payload['body'] = body;
      }
    }
    return payload;
  }

  NativeHttpRequestBody? _transferableNativeBody(String? nativeLibraryPath) {
    final candidate = nativeBody;
    if (_body != null ||
        candidate == null ||
        !candidate.hasNativeHandle ||
        nativeLibraryPath == null ||
        nativeLibraryPath.isEmpty) {
      return null;
    }
    return candidate;
  }

  static HttpRequestSnapshot? fromInvocationPayload(
    Map<String, Object?>? payload,
  ) {
    if (payload == null) {
      return null;
    }
    final id = payload['id'];
    final method = payload['method'];
    final target = payload['target'];
    final path = payload['path'];
    final protocol = payload['protocol'];
    final version = payload['version'];
    final headers = payload['headers'];
    if (id is! int ||
        method is! String ||
        target is! String ||
        path is! String ||
        protocol is! String ||
        version is! int ||
        headers is! Map) {
      return null;
    }
    final query = payload['query'] as String?;
    final body = payload['body'];
    Uint8List? binaryBody;
    if (body is Uint8List) {
      binaryBody = body;
    } else if (body is List<int>) {
      binaryBody = Uint8List.fromList(body);
    }
    NativeHttpRequestBody? nativeBody;
    final bodyHandle = payload[HttpInvocationKeys.requestBodyHandle];
    final bodyLength = payload[HttpInvocationKeys.requestBodyLength];
    final bodyStreaming = payload[HttpInvocationKeys.requestBodyStreaming];
    if (bodyHandle is int && bodyLength is int && bodyStreaming is bool) {
      nativeBody = NativeHttpRequestBody.borrowed(
        handle: bodyHandle,
        length: bodyLength,
        streaming: bodyStreaming,
        libraryPath:
            payload[HttpInvocationKeys.requestBodyLibraryPath] as String?,
      );
    }
    return HttpRequestSnapshot(
      id: id,
      method: method,
      target: target,
      path: path,
      query: query,
      protocol: protocol,
      version: version,
      headers: headers.cast<String, String>(),
      body: binaryBody,
      nativeBody: nativeBody,
      realm: payload['realm'] as String?,
      procedure: payload['procedure'] as String?,
    );
  }
}

/// Supported response body encodings.
enum HttpResponseBodyKind { bytes, text, json, file }

/// Represents the payload for an HTTP response routed back to the native layer.
class HttpResponsePayload {
  HttpResponsePayload._({
    required this.requestId,
    required this.status,
    required Map<String, String> headers,
    required this.bodyKind,
    this.bodyBytes,
    this.bodyText,
    this.bodyJson,
    this.bodyEncoding,
    this.filePath,
    this.progress = false,
  }) : headers = Map.unmodifiable(headers);

  final int requestId;
  final int status;
  final Map<String, String> headers;
  final HttpResponseBodyKind bodyKind;
  final Uint8List? bodyBytes;
  final String? bodyText;
  final Object? bodyJson;
  final String? bodyEncoding;
  final String? filePath;
  final bool progress;

  Map<String, Object?> toKeywordArguments() {
    final payload = <String, Object?>{
      HttpInvocationKeys.requestId: requestId,
      'status': status,
      'headers': headers,
      HttpInvocationKeys.responseBodyKind: bodyKind.name,
      'progress': progress,
    };
    switch (bodyKind) {
      case HttpResponseBodyKind.bytes:
        payload[HttpInvocationKeys.responseBody] = bodyBytes;
        break;
      case HttpResponseBodyKind.text:
        payload[HttpInvocationKeys.responseBody] = bodyText;
        payload[HttpInvocationKeys.responseBodyEncoding] =
            bodyEncoding ?? 'utf8';
        break;
      case HttpResponseBodyKind.json:
        payload[HttpInvocationKeys.responseBody] = bodyJson;
        break;
      case HttpResponseBodyKind.file:
        payload[HttpInvocationKeys.responseFilePath] = filePath;
        break;
    }
    return payload;
  }

  Map<String, Object?> toEventPayload() {
    return <String, Object?>{
      'requestId': requestId,
      'status': status,
      'headers': headers,
      'bodyKind': bodyKind.name,
      if (bodyBytes != null) 'bodyBytes': bodyBytes,
      if (bodyText != null) 'bodyText': bodyText,
      if (bodyJson != null) 'bodyJson': bodyJson,
      if (bodyEncoding != null) 'bodyEncoding': bodyEncoding,
      if (filePath != null) 'filePath': filePath,
      'progress': progress,
    };
  }

  Uint8List? encodeBodyBytes() {
    switch (bodyKind) {
      case HttpResponseBodyKind.bytes:
        final bytes = bodyBytes;
        if (bytes == null) {
          return Uint8List(0);
        }
        return Uint8List.fromList(bytes);
      case HttpResponseBodyKind.text:
        final text = bodyText;
        if (text == null) {
          return Uint8List(0);
        }
        final encodingName = bodyEncoding ?? 'utf8';
        final encoding = Encoding.getByName(encodingName) ?? utf8;
        return Uint8List.fromList(encoding.encode(text));
      case HttpResponseBodyKind.json:
        return Uint8List.fromList(utf8.encode(jsonEncode(bodyJson)));
      case HttpResponseBodyKind.file:
        return null;
    }
  }

  static HttpResponsePayload? fromKeywordArguments(
    Map<String, Object?>? kwargs,
  ) {
    if (kwargs == null) {
      return null;
    }
    final requestId = kwargs[HttpInvocationKeys.requestId];
    final status = kwargs['status'];
    final headers = kwargs['headers'];
    final bodyKindRaw = kwargs[HttpInvocationKeys.responseBodyKind];
    if (requestId is! int ||
        status is! int ||
        headers is! Map ||
        bodyKindRaw is! String) {
      return null;
    }
    HttpResponseBodyKind? kind;
    for (final candidate in HttpResponseBodyKind.values) {
      if (candidate.name == bodyKindRaw) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) {
      return null;
    }
    final progress = kwargs['progress'] == true;
    Uint8List? bodyBytes;
    String? bodyText;
    Object? bodyJson;
    String? bodyEncoding;
    String? filePath;
    switch (kind) {
      case HttpResponseBodyKind.bytes:
        final body = kwargs[HttpInvocationKeys.responseBody];
        if (body is Uint8List) {
          bodyBytes = body;
        } else if (body is List<int>) {
          bodyBytes = Uint8List.fromList(body);
        } else if (body != null) {
          return null;
        }
        break;
      case HttpResponseBodyKind.text:
        final body = kwargs[HttpInvocationKeys.responseBody];
        if (body != null && body is! String) {
          return null;
        }
        bodyText = body as String?;
        bodyEncoding =
            kwargs[HttpInvocationKeys.responseBodyEncoding] as String?;
        break;
      case HttpResponseBodyKind.json:
        bodyJson = kwargs[HttpInvocationKeys.responseBody];
        break;
      case HttpResponseBodyKind.file:
        final path = kwargs[HttpInvocationKeys.responseFilePath];
        if (path is! String) {
          return null;
        }
        filePath = path;
        break;
    }
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers.cast<String, String>(),
      bodyKind: kind,
      bodyBytes: bodyBytes,
      bodyText: bodyText,
      bodyJson: bodyJson,
      bodyEncoding: bodyEncoding,
      filePath: filePath,
      progress: progress,
    );
  }
}

/// Helper for constructing HTTP response payloads.
abstract final class HttpResponseUtil {
  static HttpResponsePayload bytes({
    required int requestId,
    required int status,
    Map<String, String>? headers,
    required Uint8List body,
  }) {
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers ?? const {},
      bodyKind: HttpResponseBodyKind.bytes,
      bodyBytes: Uint8List.fromList(body),
    );
  }

  static HttpResponsePayload text({
    required int requestId,
    required int status,
    Map<String, String>? headers,
    required String body,
    String encoding = 'utf8',
  }) {
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers ?? const {},
      bodyKind: HttpResponseBodyKind.text,
      bodyText: body,
      bodyEncoding: encoding,
    );
  }

  static HttpResponsePayload json({
    required int requestId,
    required int status,
    Map<String, String>? headers,
    required Object? body,
  }) {
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
      bodyKind: HttpResponseBodyKind.json,
      bodyJson: body,
    );
  }

  static HttpResponsePayload file({
    required int requestId,
    required int status,
    Map<String, String>? headers,
    required String path,
  }) {
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers ?? const {},
      bodyKind: HttpResponseBodyKind.file,
      filePath: path,
    );
  }

  static void respond(
    invocation_msg.Invocation invocation,
    HttpResponsePayload payload, {
    bool progress = false,
  }) {
    final kwargs = payload.copyWith(progress: progress).toKeywordArguments();
    invocation.respondWith(
      argumentsKeywords: kwargs,
      options: progress ? yield_msg.YieldOptions(progress: true) : null,
    );
  }
}

extension on HttpResponsePayload {
  HttpResponsePayload copyWith({bool? progress}) {
    return HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers,
      bodyKind: bodyKind,
      bodyBytes: bodyBytes,
      bodyText: bodyText,
      bodyJson: bodyJson,
      bodyEncoding: bodyEncoding,
      filePath: filePath,
      progress: progress ?? this.progress,
    );
  }
}

/// Convenience wrapper exposed to invocation handlers so they can inspect the
/// incoming HTTP request and emit responses using [HttpResponseUtil].
class HttpInvocationContext {
  HttpInvocationContext._(this.invocation, this.request)
    : requestId =
          invocation.details.custom[HttpInvocationKeys.requestId] as int;

  final invocation_msg.Invocation invocation;
  final HttpRequestSnapshot request;
  final int requestId;

  static HttpInvocationContext? maybeFromInvocation(
    invocation_msg.Invocation invocation,
  ) {
    final custom = invocation.details.custom;
    if (!custom.containsKey(HttpInvocationKeys.requestId)) {
      return null;
    }
    final requestPayload = custom[HttpInvocationKeys.request];
    final request = HttpRequestSnapshot.fromInvocationPayload(
      (requestPayload as Map?)?.cast<String, Object?>(),
    );
    if (request == null) {
      return null;
    }
    return HttpInvocationContext._(invocation, request);
  }

  void send(HttpResponsePayload payload) {
    HttpResponseUtil.respond(invocation, payload);
  }

  void sendBytes({
    required Uint8List body,
    int status = 200,
    Map<String, String>? headers,
  }) {
    send(
      HttpResponseUtil.bytes(
        requestId: requestId,
        status: status,
        headers: headers,
        body: body,
      ),
    );
  }

  void sendText({
    required String body,
    int status = 200,
    Map<String, String>? headers,
    String encoding = 'utf8',
  }) {
    send(
      HttpResponseUtil.text(
        requestId: requestId,
        status: status,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  void sendJson({
    required Object? body,
    int status = 200,
    Map<String, String>? headers,
  }) {
    send(
      HttpResponseUtil.json(
        requestId: requestId,
        status: status,
        headers: headers,
        body: body,
      ),
    );
  }

  void sendFile({
    required String path,
    int status = 200,
    Map<String, String>? headers,
  }) {
    send(
      HttpResponseUtil.file(
        requestId: requestId,
        status: status,
        headers: headers,
        path: path,
      ),
    );
  }

  HttpResponseStream streamResponse({
    int status = 200,
    Map<String, String>? headers,
    void Function()? onStreamOpened,
    void Function()? onFirstBodyWrite,
    void Function()? onFirstBodyWriteCompleted,
    void Function(Duration duration)? onDirectStreamOpenRoundTrip,
    void Function(Duration duration)? onDirectStreamRequestQueueDelay,
    void Function(Duration duration)? onDirectStreamDescriptorOpenCall,
    void Function(Duration duration)? onDirectStreamReplyDeliveryDelay,
  }) {
    return HttpResponseStream._(
      invocation: invocation,
      requestId: requestId,
      status: status,
      headers: headers ?? const {},
      onStreamOpened: onStreamOpened,
      onFirstBodyWrite: onFirstBodyWrite,
      onFirstBodyWriteCompleted: onFirstBodyWriteCompleted,
      onDirectStreamOpenRoundTrip: onDirectStreamOpenRoundTrip,
      onDirectStreamRequestQueueDelay: onDirectStreamRequestQueueDelay,
      onDirectStreamDescriptorOpenCall: onDirectStreamDescriptorOpenCall,
      onDirectStreamReplyDeliveryDelay: onDirectStreamReplyDeliveryDelay,
      responseStreamControlPort:
          invocation.details.custom[HttpInvocationKeys
                  .responseStreamControlPort]
              as SendPort?,
    );
  }
}

class HttpResponseStream {
  HttpResponseStream._({
    required this.invocation,
    required this.requestId,
    required this.status,
    required Map<String, String> headers,
    void Function()? onStreamOpened,
    void Function()? onFirstBodyWrite,
    void Function()? onFirstBodyWriteCompleted,
    void Function(Duration duration)? onDirectStreamOpenRoundTrip,
    void Function(Duration duration)? onDirectStreamRequestQueueDelay,
    void Function(Duration duration)? onDirectStreamDescriptorOpenCall,
    void Function(Duration duration)? onDirectStreamReplyDeliveryDelay,
    SendPort? responseStreamControlPort,
  }) : headers = Map.unmodifiable(headers),
       _onStreamOpened = onStreamOpened,
       _onFirstBodyWrite = onFirstBodyWrite,
       _onFirstBodyWriteCompleted = onFirstBodyWriteCompleted {
    _directStream = responseStreamControlPort == null
        ? null
        : _DirectHttpResponseStreamController(
            requestId: requestId,
            status: status,
            headers: Map.unmodifiable(headers),
            onStreamOpened: onStreamOpened,
            onFirstBodyWrite: onFirstBodyWrite,
            onFirstBodyWriteCompleted: onFirstBodyWriteCompleted,
            onDirectStreamOpenRoundTrip: onDirectStreamOpenRoundTrip,
            onDirectStreamRequestQueueDelay: onDirectStreamRequestQueueDelay,
            onDirectStreamDescriptorOpenCall: onDirectStreamDescriptorOpenCall,
            onDirectStreamReplyDeliveryDelay: onDirectStreamReplyDeliveryDelay,
            controlPort: responseStreamControlPort,
            onFallbackProgress: (chunk) {
              final payload = HttpResponsePayload._(
                requestId: requestId,
                status: status,
                headers: headers,
                bodyKind: HttpResponseBodyKind.bytes,
                bodyBytes: chunk,
                progress: true,
              );
              HttpResponseUtil.respond(invocation, payload, progress: true);
            },
            onFallbackClose: (finalChunk) {
              final payload = HttpResponsePayload._(
                requestId: requestId,
                status: status,
                headers: headers,
                bodyKind: HttpResponseBodyKind.bytes,
                bodyBytes: finalChunk,
                progress: false,
              );
              HttpResponseUtil.respond(invocation, payload);
            },
            onDirectComplete: () => invocation.respondWith(),
            onCompleted: _completeDone,
          );
  }

  final invocation_msg.Invocation invocation;
  final int requestId;
  final int status;
  final Map<String, String> headers;
  final void Function()? _onStreamOpened;
  final void Function()? _onFirstBodyWrite;
  final void Function()? _onFirstBodyWriteCompleted;
  late final _DirectHttpResponseStreamController? _directStream;
  final Completer<void> _doneCompleter = Completer<void>();
  bool _closed = false;
  bool _streamOpenedNotified = false;
  bool _firstBodyWriteNotified = false;
  bool _firstBodyWriteCompletedNotified = false;

  bool get isClosed => _closed;
  Future<void> get done => _doneCompleter.future;

  void _completeDone() {
    if (_doneCompleter.isCompleted) {
      return;
    }
    _doneCompleter.complete();
  }

  void _notifyStreamOpened() {
    if (_streamOpenedNotified) {
      return;
    }
    _streamOpenedNotified = true;
    _onStreamOpened?.call();
  }

  void _notifyFirstBodyWrite() {
    if (_firstBodyWriteNotified) {
      return;
    }
    _firstBodyWriteNotified = true;
    _onFirstBodyWrite?.call();
  }

  void _notifyFirstBodyWriteCompleted() {
    if (_firstBodyWriteCompletedNotified) {
      return;
    }
    _firstBodyWriteCompletedNotified = true;
    _onFirstBodyWriteCompleted?.call();
  }

  void add(List<int> chunk) {
    if (_closed) {
      throw StateError('HTTP response stream already closed');
    }
    if (chunk.isEmpty) {
      return;
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    final directStream = _directStream;
    if (directStream != null && directStream.add(bytes)) {
      return;
    }
    _notifyStreamOpened();
    _notifyFirstBodyWrite();
    final payload = HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers,
      bodyKind: HttpResponseBodyKind.bytes,
      bodyBytes: bytes,
      progress: true,
    );
    HttpResponseUtil.respond(invocation, payload, progress: true);
    _notifyFirstBodyWriteCompleted();
  }

  void close([List<int>? finalChunk]) {
    if (_closed) {
      return;
    }
    Uint8List? finalBytes;
    if (finalChunk != null && finalChunk.isNotEmpty) {
      finalBytes = finalChunk is Uint8List
          ? finalChunk
          : Uint8List.fromList(finalChunk);
    }
    final directStream = _directStream;
    if (directStream != null && directStream.close(finalBytes)) {
      _closed = true;
      return;
    }
    final payload = HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers,
      bodyKind: HttpResponseBodyKind.bytes,
      bodyBytes: finalBytes,
      progress: false,
    );
    HttpResponseUtil.respond(invocation, payload);
    _closed = true;
    _completeDone();
  }
}

class _DirectHttpResponseStreamController {
  _DirectHttpResponseStreamController({
    required this.requestId,
    required this.status,
    required this.headers,
    this.onStreamOpened,
    this.onFirstBodyWrite,
    this.onFirstBodyWriteCompleted,
    this.onDirectStreamOpenRoundTrip,
    this.onDirectStreamRequestQueueDelay,
    this.onDirectStreamDescriptorOpenCall,
    this.onDirectStreamReplyDeliveryDelay,
    required this.controlPort,
    required this.onFallbackProgress,
    required this.onFallbackClose,
    required this.onDirectComplete,
    required this.onCompleted,
  });

  final int requestId;
  final int status;
  final Map<String, String> headers;
  final void Function()? onStreamOpened;
  final void Function()? onFirstBodyWrite;
  final void Function()? onFirstBodyWriteCompleted;
  final void Function(Duration duration)? onDirectStreamOpenRoundTrip;
  final void Function(Duration duration)? onDirectStreamRequestQueueDelay;
  final void Function(Duration duration)? onDirectStreamDescriptorOpenCall;
  final void Function(Duration duration)? onDirectStreamReplyDeliveryDelay;
  final SendPort controlPort;
  final void Function(Uint8List chunk) onFallbackProgress;
  final void Function(Uint8List? finalChunk) onFallbackClose;
  final void Function() onDirectComplete;
  final void Function() onCompleted;

  final Queue<Uint8List> _pendingChunks = Queue<Uint8List>();
  Future<NativeHttpResponseStream?>? _streamFuture;
  NativeHttpResponseStream? _stream;
  Uint8List? _finalChunk;
  bool _fallback = false;
  bool _closed = false;
  bool _flushing = false;
  bool _completionSent = false;
  bool _directWriteStarted = false;
  bool _streamOpenedReported = false;
  bool _firstBodyWriteReported = false;
  bool _firstBodyWriteCompletedReported = false;

  bool add(Uint8List chunk) {
    if (_fallback) {
      return false;
    }
    _pendingChunks.add(chunk);
    _scheduleFlush();
    return true;
  }

  bool close(Uint8List? finalChunk) {
    if (_fallback) {
      return false;
    }
    _closed = true;
    _finalChunk = finalChunk;
    _scheduleFlush();
    return true;
  }

  void _scheduleFlush() {
    if (_flushing) {
      return;
    }
    _flushing = true;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    try {
      final stream = await _ensureStream();
      if (stream == null) {
        _fallbackPendingChunks();
        return;
      }
      while (_pendingChunks.isNotEmpty) {
        final chunk = _pendingChunks.removeFirst();
        if (chunk.isEmpty) {
          continue;
        }
        _reportFirstBodyWrite();
        stream.add(chunk);
        _reportFirstBodyWriteCompleted();
        _directWriteStarted = true;
      }
      if (_closed) {
        final finalChunk = _finalChunk;
        _finalChunk = null;
        if (finalChunk != null && finalChunk.isNotEmpty) {
          _reportFirstBodyWrite();
          stream.add(finalChunk);
          _reportFirstBodyWriteCompleted();
          _directWriteStarted = true;
        }
        stream.close();
        _sendCompletionOnce();
      }
    } catch (_) {
      if (!_directWriteStarted) {
        _fallbackPendingChunks();
      } else if (_closed) {
        _sendCompletionOnce();
      }
    } finally {
      _flushing = false;
      if (!_fallback &&
          !_completionSent &&
          (_pendingChunks.isNotEmpty || _closed)) {
        _scheduleFlush();
      }
    }
  }

  Future<NativeHttpResponseStream?> _ensureStream() async {
    final existing = _stream;
    if (existing != null) {
      return existing;
    }
    final future = _streamFuture ??= _openStream();
    final resolved = await future;
    _stream = resolved;
    if (resolved != null) {
      _reportStreamOpened();
    }
    return resolved;
  }

  Future<NativeHttpResponseStream?> _openStream() async {
    final replyPort = ReceivePort();
    final roundTripStopwatch = Stopwatch()..start();
    final requestSentAtUs = DateTime.now().microsecondsSinceEpoch;
    try {
      controlPort.send({
        'type': HttpInvocationControlMessages.openResponseStream,
        'requestId': requestId,
        'status': status,
        'headers': headers,
        'sentAtUs': requestSentAtUs,
        'replyPort': replyPort.sendPort,
      });
      final response = await replyPort.first;
      final responseReceivedAtUs = DateTime.now().microsecondsSinceEpoch;
      if (response is! Map) {
        return null;
      }
      final handle = response['handle'];
      if (handle is! int || handle <= 0) {
        return null;
      }
      onDirectStreamOpenRoundTrip?.call(roundTripStopwatch.elapsed);
      final requestQueueDelayUs = response['requestQueueDelayUs'];
      if (requestQueueDelayUs is int && requestQueueDelayUs >= 0) {
        onDirectStreamRequestQueueDelay?.call(
          Duration(microseconds: requestQueueDelayUs),
        );
      }
      final descriptorOpenUs = response['descriptorOpenUs'];
      if (descriptorOpenUs is int && descriptorOpenUs >= 0) {
        onDirectStreamDescriptorOpenCall?.call(
          Duration(microseconds: descriptorOpenUs),
        );
      }
      final replySentAtUs = response['replySentAtUs'];
      if (replySentAtUs is int &&
          replySentAtUs >= 0 &&
          responseReceivedAtUs >= replySentAtUs) {
        onDirectStreamReplyDeliveryDelay?.call(
          Duration(microseconds: responseReceivedAtUs - replySentAtUs),
        );
      }
      return NativeHttpResponseStream.borrowed(
        handle: handle,
        libraryPath: response['libraryPath'] as String?,
      );
    } finally {
      replyPort.close();
    }
  }

  void _fallbackPendingChunks() {
    if (_fallback) {
      return;
    }
    _fallback = true;
    while (_pendingChunks.isNotEmpty) {
      final chunk = _pendingChunks.removeFirst();
      if (chunk.isNotEmpty) {
        _reportStreamOpened();
        _reportFirstBodyWrite();
        onFallbackProgress(chunk);
        _reportFirstBodyWriteCompleted();
      }
    }
    if (_closed) {
      if (_finalChunk != null && _finalChunk!.isNotEmpty) {
        _reportStreamOpened();
        _reportFirstBodyWrite();
      }
      onFallbackClose(_finalChunk);
      if (_finalChunk != null && _finalChunk!.isNotEmpty) {
        _reportFirstBodyWriteCompleted();
      }
      _completionSent = true;
      onCompleted();
    }
  }

  void _sendCompletionOnce() {
    if (_completionSent) {
      return;
    }
    _completionSent = true;
    onDirectComplete();
    onCompleted();
  }

  void _reportStreamOpened() {
    if (_streamOpenedReported) {
      return;
    }
    _streamOpenedReported = true;
    onStreamOpened?.call();
  }

  void _reportFirstBodyWrite() {
    if (_firstBodyWriteReported) {
      return;
    }
    _firstBodyWriteReported = true;
    onFirstBodyWrite?.call();
  }

  void _reportFirstBodyWriteCompleted() {
    if (_firstBodyWriteCompletedReported) {
      return;
    }
    _firstBodyWriteCompletedReported = true;
    onFirstBodyWriteCompleted?.call();
  }
}
