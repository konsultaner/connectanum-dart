import 'dart:convert';
import 'dart:io';

import '../protocol/constants.dart';
import '../protocol/json_rpc.dart';

const _acceptJson = 'application/json';
const _acceptSse = 'text/event-stream';
const _acceptStreamableHttp = 'application/json, text/event-stream';
const _headerLastEventId = 'Last-Event-ID';
const _headerProtocolVersion = 'MCP-Protocol-Version';
const _headerSessionId = 'MCP-Session-Id';

/// Minimal Dart IO client for MCP Streamable HTTP endpoints.
///
/// The client keeps the negotiated MCP session headers and SSE cursor so
/// consumer applications can use router-hosted MCP endpoints without
/// reimplementing the transport/session details.
final class McpStreamableHttpClient {
  McpStreamableHttpClient(
    this.endpoint, {
    HttpClient? httpClient,
    this.headers = const <String, String>{},
    this.defaultProtocolVersion = mcpLatestProtocolVersion,
    bool closeHttpClient = false,
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null || closeHttpClient,
       protocolVersion = defaultProtocolVersion;

  final Uri endpoint;
  final Map<String, String> headers;
  final String defaultProtocolVersion;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;

  int _nextRequestId = 1;

  String protocolVersion;
  String? sessionId;
  String? lastEventId;

  Future<JsonMap> initialize({
    Object? id = 'initialize',
    JsonMap capabilities = const <String, Object?>{},
    JsonMap clientInfo = const <String, Object?>{
      'name': 'connectanum_mcp',
      'version': '0.1.0',
    },
    String? protocolVersion,
  }) async {
    final response = await post(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': protocolVersion ?? this.protocolVersion,
        'capabilities': capabilities,
        'clientInfo': clientInfo,
      },
    });
    if (response == null) {
      throw const FormatException('initialize did not return a JSON-RPC body');
    }
    return response;
  }

  Future<void> notifyInitialized() async {
    await notification('notifications/initialized');
  }

  Future<JsonMap> request(
    String method, {
    Object? id,
    JsonMap? params,
    bool streamable = true,
  }) async {
    final response = await post(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id ?? _nextRequestId++,
      'method': method,
      'params': ?params,
    }, streamable: streamable);
    if (response == null) {
      throw FormatException('$method did not return a JSON-RPC body');
    }
    return response;
  }

  Future<void> notification(String method, {JsonMap? params}) async {
    await post(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    });
  }

  Future<JsonMap?> post(JsonMap message, {bool streamable = true}) async {
    final request = await _httpClient.postUrl(endpoint);
    _applyHeaders(
      request,
      accept: streamable ? _acceptStreamableHttp : _acceptJson,
    );
    request.headers.contentType = ContentType.json;
    final requestBody = utf8.encode(jsonEncode(message));
    request.contentLength = requestBody.length;
    request.add(requestBody);

    final response = await request.close();
    _captureSessionHeaders(response);
    final body = await _readBody(response);
    _throwIfHttpError(response, body);

    if (response.statusCode == HttpStatus.accepted ||
        response.statusCode == HttpStatus.noContent ||
        body.isEmpty) {
      return null;
    }

    if (_isSse(response)) {
      return _firstJsonEvent(parseMcpSseEvents(body));
    }
    return _jsonMapFromBody(body, 'JSON-RPC response');
  }

  Future<List<McpSseEvent>> poll({String? lastEventId}) async {
    final request = await _httpClient.getUrl(endpoint);
    _applyHeaders(
      request,
      accept: _acceptSse,
      lastEventId: lastEventId ?? this.lastEventId,
    );

    final response = await request.close();
    _captureSessionHeaders(response);
    final body = await _readBody(response);
    _throwIfHttpError(response, body);

    if (!_isSse(response)) {
      throw FormatException(
        'Expected $_acceptSse response, got ${response.headers.contentType?.mimeType ?? 'unknown'}',
      );
    }

    final events = parseMcpSseEvents(body);
    _captureLastEventId(events);
    return events;
  }

  Future<void> deleteSession() async {
    final request = await _httpClient.deleteUrl(endpoint);
    _applyHeaders(request, accept: _acceptJson);

    final response = await request.close();
    final body = await _readBody(response);
    _throwIfHttpError(response, body);
    sessionId = null;
    lastEventId = null;
  }

  void close({bool force = false}) {
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  void _applyHeaders(
    HttpClientRequest request, {
    required String accept,
    String? lastEventId,
  }) {
    request.headers.set(HttpHeaders.acceptHeader, accept);
    request.headers.set(_headerProtocolVersion, protocolVersion);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final session = sessionId;
    if (session != null) {
      request.headers.set(_headerSessionId, session);
    }
    if (lastEventId != null) {
      request.headers.set(_headerLastEventId, lastEventId);
    }
  }

  void _captureSessionHeaders(HttpClientResponse response) {
    final negotiatedSessionId = response.headers.value(_headerSessionId);
    if (negotiatedSessionId != null && negotiatedSessionId.isNotEmpty) {
      sessionId = negotiatedSessionId;
    }
    final negotiatedProtocolVersion = response.headers.value(
      _headerProtocolVersion,
    );
    if (negotiatedProtocolVersion != null &&
        negotiatedProtocolVersion.isNotEmpty) {
      protocolVersion = negotiatedProtocolVersion;
    }
  }

  JsonMap? _firstJsonEvent(List<McpSseEvent> events) {
    _captureLastEventId(events);
    for (final event in events) {
      final data = event.jsonData;
      if (data != null) {
        return data;
      }
    }
    return null;
  }

  void _captureLastEventId(List<McpSseEvent> events) {
    for (final event in events) {
      final id = event.id;
      if (id != null && id.isNotEmpty) {
        lastEventId = id;
      }
    }
  }
}

final class McpSseEvent {
  const McpSseEvent({this.id, this.event, required this.data, this.retryMs});

  final String? id;
  final String? event;
  final String data;
  final int? retryMs;

  JsonMap? get jsonData {
    if (data.trim().isEmpty) {
      return null;
    }
    return _jsonMapFromBody(data, 'SSE event data');
  }
}

final class McpStreamableHttpException implements Exception {
  const McpStreamableHttpException({
    required this.statusCode,
    required this.reasonPhrase,
    required this.body,
    this.error,
  });

  final int statusCode;
  final String reasonPhrase;
  final String body;
  final JsonMap? error;

  @override
  String toString() {
    final detail = error ?? (body.isEmpty ? reasonPhrase : body);
    return 'McpStreamableHttpException($statusCode): $detail';
  }
}

List<McpSseEvent> parseMcpSseEvents(String body) {
  final events = <McpSseEvent>[];
  final dataLines = <String>[];
  String? id;
  String? event;
  int? retryMs;

  void commit() {
    if (id != null ||
        event != null ||
        retryMs != null ||
        dataLines.isNotEmpty) {
      events.add(
        McpSseEvent(
          id: id,
          event: event,
          data: dataLines.join('\n'),
          retryMs: retryMs,
        ),
      );
    }
    id = null;
    event = null;
    retryMs = null;
    dataLines.clear();
  }

  for (final rawLine in const LineSplitter().convert(body)) {
    if (rawLine.isEmpty) {
      commit();
      continue;
    }
    if (rawLine.startsWith(':')) {
      continue;
    }

    final colonIndex = rawLine.indexOf(':');
    final field = colonIndex == -1 ? rawLine : rawLine.substring(0, colonIndex);
    var value = colonIndex == -1 ? '' : rawLine.substring(colonIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'data':
        dataLines.add(value);
        break;
      case 'id':
        id = value;
        break;
      case 'event':
        event = value;
        break;
      case 'retry':
        retryMs = int.tryParse(value);
        break;
    }
  }
  commit();
  return events;
}

Future<String> _readBody(HttpClientResponse response) {
  return response.transform(utf8.decoder).join();
}

bool _isSse(HttpClientResponse response) {
  return response.headers.contentType?.mimeType == _acceptSse;
}

JsonMap _jsonMapFromBody(String body, String label) {
  final decoded = jsonDecode(body);
  return jsonMapFrom(decoded, label: label);
}

void _throwIfHttpError(HttpClientResponse response, String body) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }

  JsonMap? error;
  if (body.isNotEmpty) {
    try {
      error = _jsonMapFromBody(body, 'HTTP error response');
    } on Object {
      error = null;
    }
  }
  throw McpStreamableHttpException(
    statusCode: response.statusCode,
    reasonPhrase: response.reasonPhrase,
    body: body,
    error: error,
  );
}
