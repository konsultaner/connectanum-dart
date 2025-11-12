// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/invocation.dart' as invocation_msg;
import 'package:connectanum_core/src/message/yield.dart' as yield_msg;

/// Keys used for encoding HTTP metadata into WAMP custom maps.
abstract final class HttpInvocationKeys {
  static const requestId = '_http_request_id';
  static const request = '_http';
  static const response = '_http_response';
  static const responseBodyKind = 'bodyKind';
  static const responseBody = 'body';
  static const responseBodyEncoding = 'bodyEncoding';
  static const responseFilePath = 'filePath';
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
    this.realm,
    this.procedure,
  }) : headers = Map.unmodifiable(headers),
       body = body == null ? null : Uint8List.fromList(body);

  final int id;
  final String method;
  final String target;
  final String path;
  final String protocol;
  final int version;
  final Map<String, String> headers;
  final String? query;
  final Uint8List? body;
  final String? realm;
  final String? procedure;

  Map<String, Object?> toInvocationPayload() {
    return <String, Object?>{
      'id': id,
      'method': method,
      'target': target,
      'path': path,
      if (query != null) 'query': query,
      'protocol': protocol,
      'version': version,
      'headers': headers,
      if (body != null) 'body': body,
      if (realm != null) 'realm': realm,
      if (procedure != null) 'procedure': procedure,
    };
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
  }) {
    return HttpResponseStream._(
      invocation: invocation,
      requestId: requestId,
      status: status,
      headers: headers ?? const {},
    );
  }
}

class HttpResponseStream {
  HttpResponseStream._({
    required this.invocation,
    required this.requestId,
    required this.status,
    required Map<String, String> headers,
  }) : headers = Map.unmodifiable(headers);

  final invocation_msg.Invocation invocation;
  final int requestId;
  final int status;
  final Map<String, String> headers;
  bool _closed = false;

  bool get isClosed => _closed;

  void add(List<int> chunk) {
    if (_closed) {
      throw StateError('HTTP response stream already closed');
    }
    if (chunk.isEmpty) {
      return;
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    final payload = HttpResponsePayload._(
      requestId: requestId,
      status: status,
      headers: headers,
      bodyKind: HttpResponseBodyKind.bytes,
      bodyBytes: bytes,
      progress: true,
    );
    HttpResponseUtil.respond(invocation, payload, progress: true);
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
  }
}
