import 'dart:convert';
import 'dart:io';

typedef McpJsonMap = Map<String, Object?>;

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
  static const latestProtocolVersion = '2025-11-25';

  McpStreamableHttpClient(
    this.endpoint, {
    HttpClient? httpClient,
    this.headers = const <String, String>{},
    this.defaultProtocolVersion = latestProtocolVersion,
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

  Future<McpJsonMap> initialize({
    Object? id = 'initialize',
    McpJsonMap capabilities = const <String, Object?>{},
    McpJsonMap clientInfo = const <String, Object?>{
      'name': 'connectanum_client',
      'version': '2.2.6',
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

  Future<McpJsonMap> request(
    String method, {
    Object? id,
    McpJsonMap? params,
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

  Future<McpJsonMap> ping({Object? id, bool streamable = true}) async {
    final response = await request('ping', id: id, streamable: streamable);
    return _jsonRpcResultFrom(response, method: 'ping');
  }

  Future<McpStreamableToolListPage> listTools({
    Object? id,
    String? cursor,
    bool streamable = true,
  }) async {
    final response = await request(
      'tools/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: streamable,
    );
    final result = _jsonRpcResultFrom(response, method: 'tools/list');
    return McpStreamableToolListPage(
      tools: _jsonMapListFrom(
        result,
        key: 'tools',
        method: 'tools/list',
        label: 'tools/list result tool',
      ),
      nextCursor: _nextCursorFrom(result, method: 'tools/list'),
    );
  }

  Future<McpJsonMap> callTool(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
  }) async {
    final response = await request(
      'tools/call',
      id: id,
      params: <String, Object?>{'name': name, 'arguments': arguments},
      streamable: streamable,
    );
    return _jsonRpcResultFrom(response, method: 'tools/call');
  }

  Future<McpStreamableResourceListPage> listResources({
    Object? id,
    String? cursor,
    bool streamable = true,
  }) async {
    final response = await request(
      'resources/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: streamable,
    );
    final result = _jsonRpcResultFrom(response, method: 'resources/list');
    return McpStreamableResourceListPage(
      resources: _jsonMapListFrom(
        result,
        key: 'resources',
        method: 'resources/list',
        label: 'resources/list result resource',
      ),
      nextCursor: _nextCursorFrom(result, method: 'resources/list'),
    );
  }

  Future<List<McpJsonMap>> readResource(
    String uri, {
    Object? id,
    bool streamable = true,
  }) async {
    final response = await request(
      'resources/read',
      id: id,
      params: <String, Object?>{'uri': uri},
      streamable: streamable,
    );
    final result = _jsonRpcResultFrom(response, method: 'resources/read');
    return _jsonMapListFrom(
      result,
      key: 'contents',
      method: 'resources/read',
      label: 'resources/read result content',
    );
  }

  Future<McpStreamableResourceTemplateListPage> listResourceTemplates({
    Object? id,
    String? cursor,
    bool streamable = true,
  }) async {
    final response = await request(
      'resources/templates/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: streamable,
    );
    final result = _jsonRpcResultFrom(
      response,
      method: 'resources/templates/list',
    );
    return McpStreamableResourceTemplateListPage(
      resourceTemplates: _jsonMapListFrom(
        result,
        key: 'resourceTemplates',
        method: 'resources/templates/list',
        label: 'resources/templates/list result resource template',
      ),
      nextCursor: _nextCursorFrom(result, method: 'resources/templates/list'),
    );
  }

  Future<McpStreamablePromptListPage> listPrompts({
    Object? id,
    String? cursor,
    bool streamable = true,
  }) async {
    final response = await request(
      'prompts/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: streamable,
    );
    final result = _jsonRpcResultFrom(response, method: 'prompts/list');
    return McpStreamablePromptListPage(
      prompts: _jsonMapListFrom(
        result,
        key: 'prompts',
        method: 'prompts/list',
        label: 'prompts/list result prompt',
      ),
      nextCursor: _nextCursorFrom(result, method: 'prompts/list'),
    );
  }

  Future<McpJsonMap> getPrompt(
    String name, {
    Object? id,
    Map<String, String> arguments = const <String, String>{},
    bool streamable = true,
  }) async {
    final response = await request(
      'prompts/get',
      id: id,
      params: <String, Object?>{'name': name, 'arguments': arguments},
      streamable: streamable,
    );
    return _jsonRpcResultFrom(response, method: 'prompts/get');
  }

  Future<void> notification(String method, {McpJsonMap? params}) async {
    await post(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    });
  }

  Future<McpJsonMap?> post(McpJsonMap message, {bool streamable = true}) async {
    final response = await _postPayload(message, streamable: streamable);
    if (response == null) {
      return null;
    }
    return _jsonMapFrom(response, label: 'JSON-RPC response');
  }

  Future<List<McpJsonMap>?> postBatch(
    List<McpJsonMap> messages, {
    bool streamable = true,
  }) async {
    final response = await _postPayload(messages, streamable: streamable);
    if (response == null) {
      return null;
    }
    if (response is! List) {
      throw FormatException('JSON-RPC batch response must be an array');
    }
    return [
      for (final item in response)
        _jsonMapFrom(item, label: 'JSON-RPC batch response item'),
    ];
  }

  Future<Object?> _postPayload(
    Object? message, {
    bool streamable = true,
  }) async {
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
      return _firstJsonValue(parseMcpSseEvents(body));
    }
    return _jsonValueFromBody(body);
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

  Object? _firstJsonValue(List<McpSseEvent> events) {
    _captureLastEventId(events);
    for (final event in events) {
      final value = event.jsonValue;
      if (value != null) {
        return value;
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

final class McpStreamableToolListPage {
  const McpStreamableToolListPage({required this.tools, this.nextCursor});

  final List<McpJsonMap> tools;
  final String? nextCursor;
}

final class McpStreamableResourceListPage {
  const McpStreamableResourceListPage({
    required this.resources,
    this.nextCursor,
  });

  final List<McpJsonMap> resources;
  final String? nextCursor;
}

final class McpStreamableResourceTemplateListPage {
  const McpStreamableResourceTemplateListPage({
    required this.resourceTemplates,
    this.nextCursor,
  });

  final List<McpJsonMap> resourceTemplates;
  final String? nextCursor;
}

final class McpStreamablePromptListPage {
  const McpStreamablePromptListPage({required this.prompts, this.nextCursor});

  final List<McpJsonMap> prompts;
  final String? nextCursor;
}

final class McpJsonRpcException implements Exception {
  const McpJsonRpcException({
    required this.id,
    required this.method,
    required this.error,
  });

  final Object? id;
  final String method;
  final McpJsonMap error;

  @override
  String toString() {
    final message = error['message'];
    return 'McpJsonRpcException($method, id: $id): $message';
  }
}

final class McpSseEvent {
  const McpSseEvent({this.id, this.event, required this.data, this.retryMs});

  final String? id;
  final String? event;
  final String data;
  final int? retryMs;

  Object? get jsonValue {
    if (data.trim().isEmpty) {
      return null;
    }
    return _jsonValueFromBody(data);
  }

  McpJsonMap? get jsonData {
    final value = jsonValue;
    if (value == null) {
      return null;
    }
    return _jsonMapFrom(value, label: 'SSE event data');
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
  final McpJsonMap? error;

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

McpJsonMap _jsonMapFromBody(String body, String label) {
  return _jsonMapFrom(_jsonValueFromBody(body), label: label);
}

Object? _jsonValueFromBody(String body) {
  return jsonDecode(body);
}

void _throwIfHttpError(HttpClientResponse response, String body) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }

  McpJsonMap? error;
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

McpJsonMap _jsonRpcResultFrom(McpJsonMap response, {required String method}) {
  final error = response['error'];
  if (error != null) {
    throw McpJsonRpcException(
      id: response['id'],
      method: method,
      error: _jsonMapFrom(error, label: '$method error'),
    );
  }
  return _jsonMapFrom(response['result'], label: '$method result');
}

List<McpJsonMap> _jsonMapListFrom(
  McpJsonMap result, {
  required String key,
  required String method,
  required String label,
}) {
  final value = result[key];
  if (value is! List) {
    throw FormatException('$method result.$key must be an array');
  }
  return [for (final item in value) _jsonMapFrom(item, label: label)];
}

String? _nextCursorFrom(McpJsonMap result, {required String method}) {
  final nextCursor = result['nextCursor'];
  if (nextCursor != null && nextCursor is! String) {
    throw FormatException('$method result.nextCursor must be a string');
  }
  return nextCursor as String?;
}

McpJsonMap _jsonMapFrom(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label must contain only string keys');
    }
    result[key] = entry.value;
  }
  return result;
}
