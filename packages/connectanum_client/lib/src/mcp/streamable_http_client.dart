import 'dart:convert';
import 'dart:io';

import 'http_auth_client.dart';
import 'text_validation.dart';

typedef McpJsonMap = Map<String, Object?>;

const _acceptJson = 'application/json';
const _acceptSse = 'text/event-stream';
const _acceptStreamableHttp = 'application/json, text/event-stream';
const _headerLastEventId = 'Last-Event-ID';
const _headerProtocolVersion = 'MCP-Protocol-Version';
const _headerSessionId = 'MCP-Session-Id';
const _headerMethod = 'Mcp-Method';
const _headerName = 'Mcp-Name';
const _headerParameterPrefix = 'Mcp-Param-';
const _base64HeaderPrefix = '=?base64?';
const _base64HeaderSuffix = '?=';
final _mcpToolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
const _mcpLatestProtocolVersion = '2025-11-25';
const _mcpSupportedProtocolVersions = <String>{
  '2025-03-26',
  '2025-06-18',
  _mcpLatestProtocolVersion,
};

String _validatedMcpToolName(String value, String name) {
  if (_mcpToolNamePattern.hasMatch(value)) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'MCP tool names must be 1-128 ASCII letters, digits, underscores, '
    'hyphens, or dots.',
  );
}

String _validatedMcpResourceUri(String value, String name) {
  final parsed = Uri.tryParse(value);
  if (value.isNotEmpty && parsed != null && parsed.hasScheme) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'MCP resource URI must be an absolute URI with a scheme.',
  );
}

String _validatedMcpPromptName(String value, String name) {
  if (value.isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, name, 'MCP prompt name is required.');
}

bool _mcpProtocolVersionSupported(String value) =>
    _mcpSupportedProtocolVersions.contains(value);

String _validatedMcpProtocolVersion(String value, String name) {
  if (_mcpProtocolVersionSupported(value)) {
    return value;
  }
  throw ArgumentError.value(value, name, 'Unsupported MCP protocol version.');
}

bool _mcpSessionIdHeaderValueValid(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      return false;
    }
  }
  return value.isNotEmpty;
}

bool _mcpLastEventIdHeaderValueValid(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return false;
    }
  }
  return true;
}

void _validateJsonRpcVersion(McpJsonMap message, {required String label}) {
  if (message['jsonrpc'] != '2.0') {
    throw FormatException('JSON-RPC $label jsonrpc must be 2.0');
  }
}

Object? _validateJsonRpcRequestId(McpJsonMap message, {required String label}) {
  _validateJsonRpcVersion(message, label: label);
  final method = message['method'];
  if (method is! String || method.isEmpty) {
    throw FormatException('JSON-RPC $label method must be a non-empty string');
  }
  if (containsMcpWhitespaceOrControl(method)) {
    throw FormatException(
      'JSON-RPC $label method must not contain whitespace or control '
      'characters',
    );
  }
  if (message.containsKey('result') || message.containsKey('error')) {
    throw FormatException('JSON-RPC $label must not contain result or error');
  }
  if (message.containsKey('params')) {
    final params = message['params'];
    if (params is! Map) {
      throw FormatException('JSON-RPC $label params must be an object');
    }
    if (params.keys.any((key) => key is! String)) {
      throw FormatException(
        'JSON-RPC $label params must contain only string keys',
      );
    }
  }
  if (!message.containsKey('id')) {
    return null;
  }
  final id = message['id'];
  if (id is! String && id is! int) {
    throw FormatException(
      'JSON-RPC $label contained invalid request id ${id ?? 'null'}',
    );
  }
  return id;
}

Object? _validateJsonRpcResponseId(
  McpJsonMap response, {
  required String label,
}) {
  if (!response.containsKey('id')) {
    throw FormatException('$label must include an id');
  }
  final id = response['id'];
  if (id is! String && id is! int) {
    throw FormatException('$label id must be a string or integer');
  }
  return id;
}

void _validateJsonRpcBatchRequestIds(List<McpJsonMap> messages) {
  if (messages.isEmpty) {
    throw const FormatException('JSON-RPC batch must not be empty');
  }
  final seenIds = <Object?>[];
  for (final message in messages) {
    final id = _validateJsonRpcRequestId(message, label: 'batch request');
    if (id == null) {
      continue;
    }
    if (seenIds.any((seenId) => seenId == id)) {
      throw FormatException(
        'JSON-RPC batch request contained duplicate request id $id',
      );
    }
    seenIds.add(id);
  }
}

bool _jsonRpcMessageIsResponse(Object? value) {
  return value is Map &&
      (value.containsKey('result') || value.containsKey('error'));
}

void _validateJsonRpcSseMessageValue(Object? value) {
  if (value is List) {
    if (value.isEmpty) {
      throw const FormatException('JSON-RPC SSE event batch must not be empty');
    }
    for (final item in value) {
      _validateJsonRpcSseMessage(item, label: 'JSON-RPC SSE event batch item');
    }
    return;
  }
  if (value is! Map) {
    throw const FormatException(
      'JSON-RPC SSE event data must be an object or array',
    );
  }
  _validateJsonRpcSseMessage(value, label: 'JSON-RPC SSE event data');
}

void _validateJsonRpcSseMessage(Object? value, {required String label}) {
  final message = _jsonMapFrom(value, label: label);
  if (_jsonRpcMessageIsResponse(message)) {
    _validateJsonRpcResponseId(message, label: '$label response');
    _validateJsonRpcResponseObject(message, label: '$label response');
    return;
  }
  _validateJsonRpcRequestId(message, label: '$label request');
}

void _validateJsonRpcResponseObject(
  McpJsonMap response, {
  required String label,
}) {
  _validateJsonRpcVersion(response, label: label);
  final hasResult = response.containsKey('result');
  final hasError = response.containsKey('error');
  if (hasResult == hasError) {
    throw FormatException('$label must contain exactly one of result or error');
  }
  if (hasError) {
    final error = _jsonMapFrom(response['error'], label: '$label error');
    if (error['code'] is! int) {
      throw FormatException('$label error code must be an integer');
    }
    if (error['message'] is! String) {
      throw FormatException('$label error message must be a string');
    }
  }
}

/// Minimal Dart IO client for MCP Streamable HTTP endpoints.
///
/// The client keeps the negotiated MCP session headers and SSE cursor so
/// consumer applications can use router-hosted MCP endpoints without
/// reimplementing the transport/session details.
final class McpStreamableHttpClient {
  static const latestProtocolVersion = _mcpLatestProtocolVersion;

  McpStreamableHttpClient(
    this.endpoint, {
    HttpClient? httpClient,
    this.headers = const <String, String>{},
    String defaultProtocolVersion = latestProtocolVersion,
    bool closeHttpClient = false,
  }) : defaultProtocolVersion = _validatedMcpProtocolVersion(
         defaultProtocolVersion,
         'defaultProtocolVersion',
       ),
       _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null || closeHttpClient,
       _authorizationHeader = _authorizationHeaderFrom(headers),
       _protocolVersion = _validatedMcpProtocolVersion(
         defaultProtocolVersion,
         'defaultProtocolVersion',
       );

  /// Creates a client for bearer-protected MCP HTTP endpoints.
  McpStreamableHttpClient.withBearerToken(
    Uri endpoint,
    String bearerToken, {
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    String defaultProtocolVersion = latestProtocolVersion,
    bool closeHttpClient = false,
  }) : this(
         endpoint,
         httpClient: httpClient,
         headers: _headersWithBearerToken(headers, bearerToken),
         defaultProtocolVersion: defaultProtocolVersion,
         closeHttpClient: closeHttpClient,
       );

  /// Creates a client for MCP HTTP endpoints using an HTTP auth bridge grant.
  McpStreamableHttpClient.withAuthGrant(
    Uri endpoint,
    ConnectanumHttpAuthGrant grant, {
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    String defaultProtocolVersion = latestProtocolVersion,
    bool closeHttpClient = false,
  }) : this(
         endpoint,
         httpClient: httpClient,
         headers: _headersWithAuthGrant(headers, grant),
         defaultProtocolVersion: defaultProtocolVersion,
         closeHttpClient: closeHttpClient,
       );

  final Uri endpoint;
  final Map<String, String> headers;
  final String defaultProtocolVersion;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final String? _authorizationHeader;
  final _toolHeaderParametersByName = <String, List<_McpToolHeaderParameter>>{};

  int _nextRequestId = 1;

  String _protocolVersion;
  String? sessionId;
  String? lastEventId;

  String get protocolVersion => _protocolVersion;

  set protocolVersion(String value) {
    _protocolVersion = _validatedMcpProtocolVersion(value, 'protocolVersion');
  }

  static Map<String, String> _headersWithBearerToken(
    Map<String, String> headers,
    String bearerToken,
  ) {
    final token = bearerToken.trim();
    if (token.isEmpty || containsMcpWhitespaceOrControl(token)) {
      throw ArgumentError.value(
        bearerToken,
        'bearerToken',
        token.isEmpty
            ? 'Bearer token must not be empty.'
            : 'Bearer token must not contain whitespace or control characters.',
      );
    }
    return <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toLowerCase() != HttpHeaders.authorizationHeader)
          entry.key: entry.value,
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };
  }

  static String? _authorizationHeaderFrom(Map<String, String> headers) {
    String? value;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == HttpHeaders.authorizationHeader) {
        value = entry.value;
      }
    }
    return value;
  }

  static Map<String, String> _headersWithAuthGrant(
    Map<String, String> headers,
    ConnectanumHttpAuthGrant grant,
  ) {
    final tokenType = grant.tokenType.trim();
    if (tokenType.toLowerCase() != 'bearer') {
      throw ArgumentError.value(
        grant.tokenType,
        'grant.tokenType',
        'Only Bearer HTTP auth grants can authorize MCP HTTP clients.',
      );
    }
    return _headersWithBearerToken(headers, grant.accessToken);
  }

  Future<McpJsonMap> initialize({
    Object? id = 'initialize',
    McpJsonMap capabilities = const <String, Object?>{},
    McpJsonMap clientInfo = const <String, Object?>{
      'name': 'connectanum_client',
      'version': '2.2.6',
    },
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final requestedProtocolVersion = protocolVersion ?? this.protocolVersion;
    final response = await post(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': requestedProtocolVersion,
          'capabilities': capabilities,
          'clientInfo': clientInfo,
        },
      },
      includeSession: false,
      protocolVersion: requestedProtocolVersion,
      headers: headers,
    );
    if (response == null) {
      throw const FormatException('initialize did not return a JSON-RPC body');
    }
    final result = response['result'];
    if (result is Map) {
      final negotiatedProtocolVersion = result['protocolVersion'];
      if (negotiatedProtocolVersion is String &&
          negotiatedProtocolVersion.isNotEmpty) {
        if (!_mcpProtocolVersionSupported(negotiatedProtocolVersion)) {
          _clearSessionState();
          throw McpStreamableProtocolException(
            'Unsupported initialize protocolVersion: '
            '$negotiatedProtocolVersion',
          );
        }
        this.protocolVersion = negotiatedProtocolVersion;
      }
    }
    return response;
  }

  Future<void> notifyInitialized({
    Map<String, String> headers = const <String, String>{},
  }) async {
    await notification('notifications/initialized', headers: headers);
  }

  Future<McpJsonMap> request(
    String method, {
    Object? id,
    McpJsonMap? params,
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await post(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id ?? _nextRequestId++,
        'method': method,
        'params': ?params,
      },
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    if (response == null) {
      throw FormatException('$method did not return a JSON-RPC body');
    }
    return response;
  }

  Future<McpJsonMap> requestDirect(
    String method, {
    Object? id,
    McpJsonMap? params,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return request(
      method,
      id: id,
      params: params,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpJsonMap> ping({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'ping',
      id: id,
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _jsonRpcResultFrom(response, method: 'ping');
  }

  Future<McpJsonMap> pingDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await requestDirect(
      'ping',
      id: id,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _jsonRpcResultFrom(response, method: 'ping');
  }

  Future<McpStreamableToolListPage> listTools({
    Object? id,
    String? cursor,
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'tools/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: 'tools/list');
    final tools = _rememberToolHeaderParameters(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: 'tools/list',
        label: 'tools/list result tool',
      ),
    );
    return McpStreamableToolListPage(
      tools: tools,
      nextCursor: _nextCursorFrom(result, method: 'tools/list'),
    );
  }

  Future<McpStreamableToolListPage> listToolsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'tools/list';
    final response = await requestDirect(
      method,
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: method);
    final tools = _rememberToolHeaderParameters(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: method,
        label: '$method result tool',
      ),
    );
    return McpStreamableToolListPage(
      tools: tools,
      nextCursor: _nextCursorFrom(result, method: method),
    );
  }

  Future<McpJsonMap> callTool(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await request(
      'tools/call',
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _jsonRpcResultFrom(response, method: 'tools/call');
  }

  Future<void> notifyTool(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notification(
      'tools/call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  Future<McpJsonMap> callToolDirect(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await requestDirect(
      'tools/call',
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _jsonRpcResultFrom(response, method: 'tools/call');
  }

  Future<void> notifyToolDirect(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notificationDirect(
      'tools/call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  Future<McpStreamableToolListPage> listConnectanumToolsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'connectanum.tools.list';
    final response = await request(
      method,
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: method);
    final tools = _rememberToolHeaderParameters(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: method,
        label: '$method result tool',
      ),
    );
    return McpStreamableToolListPage(
      tools: tools,
      nextCursor: _nextCursorFrom(result, method: method),
    );
  }

  Future<McpJsonMap> callConnectanumToolDirect(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'connectanum.tool.call';
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await request(
      method,
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _jsonRpcResultFrom(response, method: method);
  }

  Future<McpJsonMap> callConnectanumMethod(
    String method, {
    Object? id,
    McpJsonMap params = const <String, Object?>{},
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      method,
      id: id,
      params: params,
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
    return _jsonRpcResultFrom(response, method: method);
  }

  Future<McpJsonMap> callConnectanumMethodDirect(
    String method, {
    Object? id,
    McpJsonMap params = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await requestDirect(
      method,
      id: id,
      params: params,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
    return _jsonRpcResultFrom(response, method: method);
  }

  Future<void> notifyConnectanumToolDirect(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notificationDirect(
      'connectanum.tool.call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  Future<void> notifyConnectanumMethod(
    String method, {
    McpJsonMap params = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notification(
      method,
      params: params,
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
  }

  Future<void> notifyConnectanumMethodDirect(
    String method, {
    McpJsonMap params = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notificationDirect(
      method,
      params: params,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
  }

  Future<McpStreamableResourceListPage> listResources({
    Object? id,
    String? cursor,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'resources/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
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
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final resourceUri = _validatedMcpResourceUri(uri, 'uri');
    final response = await request(
      'resources/read',
      id: id,
      params: <String, Object?>{'uri': resourceUri},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
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
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'resources/templates/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
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
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'prompts/list',
      id: id,
      params: cursor == null ? null : <String, Object?>{'cursor': cursor},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
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
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final promptName = _validatedMcpPromptName(name, 'name');
    final response = await request(
      'prompts/get',
      id: id,
      params: <String, Object?>{'name': promptName, 'arguments': arguments},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _jsonRpcResultFrom(response, method: 'prompts/get');
  }

  Future<McpStreamableResourceListPage> listResourcesDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listResources(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<List<McpJsonMap>> readResourceDirect(
    String uri, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return readResource(
      uri,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamableResourceTemplateListPage> listResourceTemplatesDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listResourceTemplates(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpStreamablePromptListPage> listPromptsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listPrompts(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpJsonMap> getPromptDirect(
    String name, {
    Object? id,
    Map<String, String> arguments = const <String, String>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getPrompt(
      name,
      id: id,
      arguments: arguments,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<void> notification(
    String method, {
    McpJsonMap? params,
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    await post(
      <String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': ?params},
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<void> notificationDirect(
    String method, {
    McpJsonMap? params,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notification(
      method,
      params: params,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<McpJsonMap?> post(
    McpJsonMap message, {
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    _validateJsonRpcRequestId(message, label: 'request');
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    final response = await _postPayload(
      message,
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: effectiveProtocolVersion,
      extraHeaders: headers,
    );
    if (response == null) {
      return null;
    }
    return _jsonMapFrom(response, label: 'JSON-RPC response');
  }

  Future<McpJsonMap?> postDirect(
    McpJsonMap message, {
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return post(
      message,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<List<McpJsonMap>?> postBatch(
    List<McpJsonMap> messages, {
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    _validateJsonRpcBatchRequestIds(messages);
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    final response = await _postPayload(
      messages,
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: effectiveProtocolVersion,
      extraHeaders: headers,
    );
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

  Future<List<McpJsonMap>?> postBatchDirect(
    List<McpJsonMap> messages, {
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return postBatch(
      messages,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  Future<Object?> _postPayload(
    Object? message, {
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final request = await _httpClient.postUrl(endpoint);
    _applyHeaders(
      request,
      accept: streamable ? _acceptStreamableHttp : _acceptJson,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
    _applyStandardRequestHeaders(request, message);
    request.headers.contentType = ContentType.json;
    final requestBody = utf8.encode(jsonEncode(message));
    request.contentLength = requestBody.length;
    request.add(requestBody);

    final requestMethod = _requestMethodForStandardHeaders(message);
    final capturesSessionHeaders =
        includeSession || (streamable && requestMethod == 'initialize');
    final capturesProtocolVersion =
        protocolVersion == null || requestMethod == 'initialize';
    final clearsSessionOnMissing = requestMethod == 'initialize';
    final resetsLastEventId = requestMethod == 'initialize';
    final response = await request.close();
    final body = await _readBody(response);
    if (capturesSessionHeaders) {
      _throwIfHttpErrorForSession(response, body);
    } else {
      _throwIfHttpError(response, body);
    }

    if (response.statusCode == HttpStatus.accepted ||
        response.statusCode == HttpStatus.noContent ||
        body.isEmpty) {
      _validatePostResponseShape(message, null);
      if (capturesSessionHeaders) {
        _captureSessionHeaders(
          response,
          captureProtocolVersion: capturesProtocolVersion,
          clearSessionOnMissing: clearsSessionOnMissing,
          resetLastEventId: resetsLastEventId,
        );
      }
      return null;
    }

    if (_isSse(response)) {
      final events = parseMcpSseEvents(body);
      final value = _jsonRpcResponseValueFromSseEvents(message, events);
      _validatePostResponseShape(
        message,
        value,
        responseBodyReturned: body.isNotEmpty,
      );
      _validateMcpSseEventIds(events);
      if (capturesSessionHeaders) {
        _captureSessionHeaders(
          response,
          captureProtocolVersion: capturesProtocolVersion,
          clearSessionOnMissing: clearsSessionOnMissing,
          resetLastEventId: resetsLastEventId,
        );
        _captureLastEventId(events);
      }
      return value;
    }

    final value = _jsonValueFromBody(body);
    _validatePostResponseShape(message, value, responseBodyReturned: true);
    if (capturesSessionHeaders) {
      _captureSessionHeaders(
        response,
        captureProtocolVersion: capturesProtocolVersion,
        clearSessionOnMissing: clearsSessionOnMissing,
        resetLastEventId: resetsLastEventId,
      );
    }
    return value;
  }

  void _validatePostResponseShape(
    Object? requestPayload,
    Object? responseValue, {
    bool responseBodyReturned = false,
  }) {
    if (requestPayload is Map && requestPayload.containsKey('id')) {
      if (responseValue == null) {
        throw const FormatException('JSON-RPC response was not returned');
      }
      final response = _jsonMapFrom(responseValue, label: 'JSON-RPC response');
      final expectedResponseId = requestPayload['id'];
      final responseId = _validateJsonRpcResponseId(
        response,
        label: 'JSON-RPC response',
      );
      if (responseId != expectedResponseId) {
        throw FormatException(
          'JSON-RPC response contained unexpected response id $responseId',
        );
      }
      _validateJsonRpcResponseObject(response, label: 'JSON-RPC response');
      return;
    }

    if (requestPayload is Map) {
      if (responseBodyReturned) {
        throw const FormatException(
          'JSON-RPC notification response must not include a body',
        );
      }
      return;
    }

    if (requestPayload is List) {
      final expectedResponseIds = <Object?>[];
      for (final item in requestPayload) {
        if (item is Map && item.containsKey('id')) {
          expectedResponseIds.add(item['id']);
        }
      }
      if (expectedResponseIds.isEmpty) {
        if (responseBodyReturned) {
          throw const FormatException(
            'JSON-RPC notification-only batch response must not include a body',
          );
        }
        return;
      }
      if (responseValue == null) {
        throw const FormatException('JSON-RPC batch response was not returned');
      }
      if (responseValue is! List) {
        throw const FormatException('JSON-RPC batch response must be an array');
      }
      final responseIds = <Object?>[];
      for (final item in responseValue) {
        final response = _jsonMapFrom(
          item,
          label: 'JSON-RPC batch response item',
        );
        final responseId = _validateJsonRpcResponseId(
          response,
          label: 'JSON-RPC batch response item',
        );
        if (!expectedResponseIds.contains(responseId)) {
          throw FormatException(
            'JSON-RPC batch response contained unexpected response id '
            '$responseId',
          );
        }
        if (responseIds.contains(responseId)) {
          throw FormatException(
            'JSON-RPC batch response contained duplicate response for id '
            '$responseId',
          );
        }
        _validateJsonRpcResponseObject(
          response,
          label: 'JSON-RPC batch response item',
        );
        responseIds.add(responseId);
      }
      for (final id in expectedResponseIds) {
        if (!responseIds.contains(id)) {
          throw FormatException(
            'JSON-RPC batch response missing response for id $id',
          );
        }
      }
    }
  }

  Future<List<McpSseEvent>> poll({
    String? lastEventId,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await _httpClient.getUrl(endpoint);
    _applyHeaders(
      request,
      accept: _acceptSse,
      lastEventId: lastEventId ?? this.lastEventId,
      extraHeaders: headers,
    );

    final response = await request.close();
    final body = await _readBody(response);
    _throwIfHttpErrorForSession(response, body);

    if (!_isSse(response)) {
      throw FormatException(
        'Expected $_acceptSse response, got ${response.headers.contentType?.mimeType ?? 'unknown'}',
      );
    }

    final events = parseMcpSseEvents(body);
    for (final event in events) {
      final value = event.jsonValue;
      if (value != null) {
        _validateJsonRpcSseMessageValue(value);
      }
    }
    _validateMcpSseEventIds(events);
    _captureSessionHeaders(response);
    _captureLastEventId(events);
    return events;
  }

  Future<void> deleteSession({
    Map<String, String> headers = const <String, String>{},
  }) async {
    final activeSessionId = sessionId;
    if (activeSessionId == null) {
      _clearSessionState();
      return;
    }
    final request = await _httpClient.deleteUrl(endpoint);
    _applyHeaders(request, accept: _acceptJson, extraHeaders: headers);

    final response = await request.close();
    final body = await _readBody(response);
    _throwIfHttpErrorForSession(response, body);
    final responseSessionId = response.headers.value(_headerSessionId);
    if (responseSessionId != null) {
      if (!_mcpSessionIdHeaderValueValid(responseSessionId)) {
        throw const McpStreamableProtocolException(
          'Invalid MCP-Session-Id response header',
        );
      }
      if (responseSessionId != activeSessionId) {
        throw const McpStreamableProtocolException(
          'MCP-Session-Id response header did not match the active session',
        );
      }
    }
    _clearSessionState();
  }

  void close({bool force = false}) {
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  void _applyStandardRequestHeaders(
    HttpClientRequest request,
    Object? message,
  ) {
    final method = _requestMethodForStandardHeaders(message);
    if (method == null) {
      return;
    }
    request.headers.set(_headerMethod, method);
    final name = _requestNameForStandardHeaders(message, method);
    if (name != null) {
      request.headers.set(_headerName, name);
    }
  }

  void _applyHeaders(
    HttpClientRequest request, {
    required String accept,
    String? lastEventId,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    request.headers.set(HttpHeaders.acceptHeader, accept);
    request.headers.set(_headerProtocolVersion, effectiveProtocolVersion);
    void applyConsumerHeaders(Map<String, String> source) {
      for (final entry in source.entries) {
        if (_isControlledMcpRequestHeader(entry.key)) {
          continue;
        }
        request.headers.set(entry.key, entry.value);
      }
    }

    applyConsumerHeaders(headers);
    applyConsumerHeaders(extraHeaders);
    final authorizationHeader = _authorizationHeader;
    if (authorizationHeader != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorizationHeader);
    }
    final session = includeSession ? sessionId : null;
    if (session != null) {
      if (!_mcpSessionIdHeaderValueValid(session)) {
        throw const FormatException(
          'MCP-Session-Id header value contains invalid characters',
        );
      }
      request.headers.set(_headerSessionId, session);
    }
    if (lastEventId != null) {
      if (!_mcpLastEventIdHeaderValueValid(lastEventId)) {
        throw const FormatException(
          'Last-Event-ID header value contains invalid characters',
        );
      }
      request.headers.set(_headerLastEventId, lastEventId);
    }
  }

  void _captureSessionHeaders(
    HttpClientResponse response, {
    bool captureProtocolVersion = true,
    bool clearSessionOnMissing = false,
    bool resetLastEventId = false,
  }) {
    final negotiatedSessionId = response.headers.value(_headerSessionId);
    if (negotiatedSessionId != null &&
        !_mcpSessionIdHeaderValueValid(negotiatedSessionId)) {
      throw const McpStreamableProtocolException(
        'Invalid MCP-Session-Id response header',
      );
    }

    final negotiatedProtocolVersion = captureProtocolVersion
        ? response.headers.value(_headerProtocolVersion)
        : null;
    if (negotiatedProtocolVersion != null &&
        negotiatedProtocolVersion.isNotEmpty &&
        !_mcpProtocolVersionSupported(negotiatedProtocolVersion)) {
      throw McpStreamableProtocolException(
        'Unsupported MCP-Protocol-Version response header: '
        '$negotiatedProtocolVersion',
      );
    }

    if (negotiatedSessionId != null) {
      if (resetLastEventId || sessionId != negotiatedSessionId) {
        lastEventId = null;
      }
      sessionId = negotiatedSessionId;
    } else if (clearSessionOnMissing) {
      _clearSessionState();
    }
    if (negotiatedProtocolVersion != null &&
        negotiatedProtocolVersion.isNotEmpty) {
      protocolVersion = negotiatedProtocolVersion;
    }
  }

  void _throwIfHttpErrorForSession(HttpClientResponse response, String body) {
    try {
      _throwIfHttpError(response, body);
    } on McpStreamableHttpException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized ||
          error.statusCode == HttpStatus.forbidden ||
          error.statusCode == HttpStatus.notFound) {
        _clearSessionState();
      }
      rethrow;
    }
  }

  void _clearSessionState() {
    sessionId = null;
    lastEventId = null;
  }

  Object? _jsonRpcResponseValueFromSseEvents(
    Object? requestPayload,
    List<McpSseEvent> events,
  ) {
    final values = <Object?>[];
    for (final event in events) {
      final value = event.jsonValue;
      if (value != null) {
        _validateJsonRpcSseMessageValue(value);
        values.add(value);
      }
    }

    if (requestPayload is Map) {
      if (!requestPayload.containsKey('id')) {
        return null;
      }
      final requestId = requestPayload['id'];
      Object? matchingResponse;
      for (final responseValue in _jsonRpcResponseValues(values)) {
        if (!_jsonRpcMessageIsResponse(responseValue)) {
          continue;
        }
        final response = _jsonMapFrom(
          responseValue,
          label: 'JSON-RPC response',
        );
        if (!response.containsKey('id')) {
          throw const FormatException('JSON-RPC response must include an id');
        }
        if (!_jsonRpcResponseIdMatches(response, requestId)) {
          throw FormatException(
            'JSON-RPC response contained unexpected response id '
            '${response['id']}',
          );
        }
        if (matchingResponse != null) {
          throw FormatException(
            'JSON-RPC response contained duplicate response for id $requestId',
          );
        }
        _validateJsonRpcResponseObject(response, label: 'JSON-RPC response');
        matchingResponse = response;
      }
      return matchingResponse;
    }

    if (requestPayload is List) {
      final requestIds = <Object?>[];
      for (final item in requestPayload) {
        if (item is Map && item.containsKey('id')) {
          requestIds.add(item['id']);
        }
      }
      if (requestIds.isEmpty) {
        return null;
      }
      final responses = <Object?>[];
      for (final response in _jsonRpcResponseValues(values)) {
        if (_jsonRpcMessageIsResponse(response)) {
          responses.add(response);
        }
      }
      return responses.isEmpty ? null : responses;
    }

    for (final value in values) {
      return value;
    }
    return null;
  }

  Iterable<Object?> _jsonRpcResponseValues(List<Object?> values) sync* {
    for (final value in values) {
      if (value is List) {
        yield* value;
      } else {
        yield value;
      }
    }
  }

  bool _jsonRpcResponseIdMatches(McpJsonMap response, Object? requestId) {
    final responseId = _validateJsonRpcResponseId(
      response,
      label: 'JSON-RPC response',
    );
    return responseId == requestId;
  }

  void _validateMcpSseEventIds(List<McpSseEvent> events) {
    for (final event in events) {
      final id = event.id;
      if (id != null && !_mcpLastEventIdHeaderValueValid(id)) {
        throw const FormatException(
          'SSE event id cannot be used as Last-Event-ID',
        );
      }
    }
  }

  void _captureLastEventId(List<McpSseEvent> events) {
    for (final event in events) {
      final id = event.id;
      if (id != null) {
        lastEventId = id.isEmpty ? null : id;
      }
    }
  }

  List<McpJsonMap> _rememberToolHeaderParameters(List<McpJsonMap> tools) {
    final visibleTools = <McpJsonMap>[];
    for (final tool in tools) {
      final name = tool['name'];
      if (name is! String) {
        visibleTools.add(tool);
        continue;
      }
      final headerParameters = _mcpToolHeaderParametersFromTool(tool);
      if (headerParameters == null) {
        _toolHeaderParametersByName.remove(name);
        continue;
      }
      if (headerParameters.isEmpty) {
        _toolHeaderParametersByName.remove(name);
      } else {
        _toolHeaderParametersByName[name] = headerParameters;
      }
      visibleTools.add(tool);
    }
    return List<McpJsonMap>.unmodifiable(visibleTools);
  }

  Map<String, String> _mcpToolParameterHeaders(
    String toolName,
    McpJsonMap arguments,
  ) {
    final parameters = _toolHeaderParametersByName[toolName];
    if (parameters == null || parameters.isEmpty) {
      return const <String, String>{};
    }
    final headers = <String, String>{};
    for (final parameter in parameters) {
      if (!arguments.containsKey(parameter.argumentName)) {
        continue;
      }
      final value = arguments[parameter.argumentName];
      if (value == null) {
        continue;
      }
      headers['$_headerParameterPrefix${parameter.headerName}'] =
          _encodeMcpParameterHeaderValue(
            value,
            argumentName: parameter.argumentName,
          );
    }
    return headers;
  }

  Map<String, String> _headersWithToolParameterHeaders(
    String toolName,
    McpJsonMap arguments,
    Map<String, String> headers,
  ) {
    final parameterHeaders = _mcpToolParameterHeaders(toolName, arguments);
    final filteredHeaders = <String, String>{};
    final parameterPrefix = _headerParameterPrefix.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase().startsWith(parameterPrefix)) {
        continue;
      }
      filteredHeaders[entry.key] = entry.value;
    }
    if (parameterHeaders.isEmpty) {
      return filteredHeaders.length == headers.length
          ? headers
          : filteredHeaders;
    }
    return <String, String>{...filteredHeaders, ...parameterHeaders};
  }

  Map<String, String> _headersWithConnectanumMethodParameterHeaders(
    String method,
    McpJsonMap params,
    Map<String, String> headers,
  ) {
    Object? toolName;
    McpJsonMap? arguments;
    if (method == 'tools/call' ||
        method == 'connectanum.tool.call' ||
        method == 'connectanum.tools.call') {
      toolName = params['name'];
      final rawArguments = params['arguments'];
      arguments = rawArguments == null
          ? const <String, Object?>{}
          : _jsonMapFrom(rawArguments, label: 'direct tool arguments');
    } else if (method.contains('.')) {
      toolName = method;
      arguments = params;
    }
    return toolName is String && arguments != null
        ? _headersWithToolParameterHeaders(toolName, arguments, headers)
        : headers;
  }
}

bool _isControlledMcpRequestHeader(String name) {
  final normalized = name.toLowerCase();
  return normalized == HttpHeaders.acceptHeader ||
      normalized == _headerProtocolVersion.toLowerCase() ||
      normalized == _headerSessionId.toLowerCase() ||
      normalized == _headerLastEventId.toLowerCase() ||
      normalized == _headerMethod.toLowerCase() ||
      normalized == _headerName.toLowerCase();
}

final class _McpToolHeaderParameter {
  const _McpToolHeaderParameter({
    required this.argumentName,
    required this.headerName,
  });

  final String argumentName;
  final String headerName;
}

List<_McpToolHeaderParameter>? _mcpToolHeaderParametersFromTool(
  McpJsonMap tool,
) {
  final inputSchema = tool['inputSchema'];
  if (inputSchema is! Map) {
    return const <_McpToolHeaderParameter>[];
  }
  final properties = inputSchema['properties'];
  if (properties is! Map) {
    return const <_McpToolHeaderParameter>[];
  }
  final headerNames = <String>{};
  final parameters = <_McpToolHeaderParameter>[];
  for (final entry in properties.entries) {
    final argumentName = entry.key;
    final property = entry.value;
    if (argumentName is! String || property is! Map) {
      continue;
    }
    final headerName = property['x-mcp-header'];
    if (headerName == null) {
      continue;
    }
    if (headerName is! String ||
        !_isValidMcpHeaderNameSegment(headerName) ||
        !headerNames.add(headerName.toLowerCase()) ||
        !_mcpHeaderParameterSchemaIsPrimitive(property)) {
      return null;
    }
    parameters.add(
      _McpToolHeaderParameter(
        argumentName: argumentName,
        headerName: headerName,
      ),
    );
  }
  return List<_McpToolHeaderParameter>.unmodifiable(parameters);
}

bool _isValidMcpHeaderNameSegment(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 || codeUnit > 0x7E || codeUnit == 0x3A) {
      return false;
    }
  }
  return true;
}

bool _mcpHeaderParameterSchemaIsPrimitive(Map property) {
  final type = property['type'];
  if (type is String) {
    return _isMcpHeaderPrimitiveType(type);
  }
  if (type is Iterable) {
    var sawType = false;
    for (final value in type) {
      if (value is! String) {
        return false;
      }
      if (value == 'null') {
        continue;
      }
      sawType = true;
      if (!_isMcpHeaderPrimitiveType(value)) {
        return false;
      }
    }
    return sawType;
  }
  return false;
}

bool _isMcpHeaderPrimitiveType(String type) {
  return type == 'string' ||
      type == 'number' ||
      type == 'integer' ||
      type == 'boolean';
}

String _encodeMcpParameterHeaderValue(
  Object? value, {
  required String argumentName,
}) {
  final stringValue = switch (value) {
    final String value => value,
    final num value => value.toString(),
    final bool value => value ? 'true' : 'false',
    _ => throw ArgumentError.value(
      value,
      argumentName,
      'MCP header parameters must be strings, numbers, or booleans.',
    ),
  };
  if (!_mcpParameterHeaderValueNeedsBase64(stringValue)) {
    return stringValue;
  }
  return '$_base64HeaderPrefix${base64Encode(utf8.encode(stringValue))}'
      '$_base64HeaderSuffix';
}

bool _mcpParameterHeaderValueNeedsBase64(String value) {
  if (value.startsWith(_base64HeaderPrefix) &&
      value.endsWith(_base64HeaderSuffix)) {
    return true;
  }
  if (value.startsWith(' ') ||
      value.startsWith('\t') ||
      value.endsWith(' ') ||
      value.endsWith('\t')) {
    return true;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7E || codeUnit == 0x7F) {
      return true;
    }
  }
  return false;
}

String? _requestMethodForStandardHeaders(Object? message) {
  if (message is! Map) {
    return null;
  }
  final method = message['method'];
  return method is String && method.isNotEmpty ? method : null;
}

String? _requestNameForStandardHeaders(Object? message, String method) {
  if (message is! Map) {
    return null;
  }
  final params = message['params'];
  if (params is! Map) {
    return null;
  }
  final field = switch (method) {
    'tools/call' ||
    'connectanum.tool.call' ||
    'connectanum.tools.call' ||
    'prompts/get' => 'name',
    'resources/read' => 'uri',
    _ => null,
  };
  if (field == null) {
    return null;
  }
  final value = params[field];
  return value is String && value.isNotEmpty ? value : null;
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

final class McpStreamableProtocolException implements Exception {
  const McpStreamableProtocolException(this.message);

  final String message;

  @override
  String toString() => 'McpStreamableProtocolException: $message';
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
