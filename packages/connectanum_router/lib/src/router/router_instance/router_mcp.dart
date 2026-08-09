part of '../router_instance.dart';

const String _mcpSessionIdHeader = 'MCP-Session-Id';
const String _mcpProtocolVersionHeader = 'MCP-Protocol-Version';
const String _mcpLastEventIdHeader = 'Last-Event-ID';
const String _mcpMethodHeader = 'Mcp-Method';
const String _mcpNameHeader = 'Mcp-Name';
const String _mcpParameterHeaderPrefix = 'Mcp-Param-';
const String _mcpBase64HeaderPrefix = '=?base64?';
const String _mcpBase64HeaderSuffix = '?=';
const String _mcpSseContentType = 'text/event-stream';
const String _mcpJsonContentType = 'application/json';
const String _mcpCorsAllowOriginHeader = 'Access-Control-Allow-Origin';
const String _mcpCorsAllowMethodsHeader = 'Access-Control-Allow-Methods';
const String _mcpCorsAllowHeadersHeader = 'Access-Control-Allow-Headers';
const String _mcpCorsExposeHeadersHeader = 'Access-Control-Expose-Headers';
const String _mcpCorsMaxAgeHeader = 'Access-Control-Max-Age';
const String _mcpCorsRequestHeadersHeader = 'Access-Control-Request-Headers';
const String _mcpCorsAllowMethods = 'GET, POST, DELETE, OPTIONS';
const String _mcpCorsExposeHeaders =
    'MCP-Protocol-Version, MCP-Session-Id, Last-Event-ID';
const String _mcpCorsDefaultAllowHeaders =
    'Accept, Authorization, Content-Type, Last-Event-ID, MCP-Method, '
    'MCP-Name, MCP-Protocol-Version, MCP-Session-Id';
const int _mcpSseEventHistoryLimit = 128;
const int _mcpConfiguredSubscriptionIdBase = 0x1FFE0000000000;
const int _mcpConfiguredRegistrationIdBase = 0x1FFF0000000000;
const Set<String> _mcpSupportedHttpProtocolVersions =
    mcp.mcpSupportedProtocolVersions;
const Set<String> _mcpPostResponseTransportModes = <String>{
  'json',
  'off',
  'false',
  'disabled',
  'sse',
  'stream',
  'streamable',
  'auto',
};
final RegExp _mcpToolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
const Object _mcpNoProtectedResourceMetadata = Object();
final Expando<Object> _mcpProtectedResourceMetadataCache = Expando<Object>(
  'MCP protected resource metadata',
);

const int _mcpDefaultSessionIdleTimeoutMs = 600000;

const int _mcpDefaultMaxRequestBytes = 16 * 1024 * 1024;

const int _mcpDefaultMaxResponseBytes = 16 * 1024 * 1024;

const int _mcpDefaultMaxSessionCount = 1024;

const int _mcpDefaultMaxRequestScopedListenerCount = 1024;

const int _mcpDefaultMaxWampSubscriptionCount = 1024;

const int _mcpDefaultMaxWampSubscriptionQueueLimit = 100;

const int _mcpDefaultMaxWampSubscriptionQueueBytes = 256 * 1024;

const int _mcpDefaultWampCallTimeoutMs = 30000;

int _mcpMaxRequestBytesForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_request_bytes',
        'maxRequestBytes',
      ]) ??
      _mcpDefaultMaxRequestBytes;
}

int _mcpMaxResponseBytesForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_response_bytes',
        'maxResponseBytes',
      ]) ??
      _mcpDefaultMaxResponseBytes;
}

int _mcpMaxSseHistoryBytesForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_sse_history_bytes',
        'maxSseHistoryBytes',
      ]) ??
      _mcpMaxResponseBytesForRoute(route);
}

int _mcpMaxSessionCountForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_session_count',
        'maxSessionCount',
      ]) ??
      _mcpDefaultMaxSessionCount;
}

int _mcpMaxRequestScopedListenerCountForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_request_scoped_listener_count',
        'maxRequestScopedListenerCount',
      ]) ??
      _mcpDefaultMaxRequestScopedListenerCount;
}

int _mcpMaxWampSubscriptionCountForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_wamp_subscription_count',
        'maxWampSubscriptionCount',
      ]) ??
      _mcpDefaultMaxWampSubscriptionCount;
}

int _mcpMaxWampSubscriptionQueueLimitForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_wamp_subscription_queue_limit',
        'maxWampSubscriptionQueueLimit',
      ]) ??
      _mcpDefaultMaxWampSubscriptionQueueLimit;
}

int _mcpMaxWampSubscriptionQueueBytesForRoute(HttpRouteSettings route) {
  return _intOptionAny(route.action.options, const <String>[
        'max_wamp_subscription_queue_bytes',
        'maxWampSubscriptionQueueBytes',
      ]) ??
      _mcpDefaultMaxWampSubscriptionQueueBytes;
}

Duration? _mcpSessionIdleTimeoutForRoute(HttpRouteSettings route) {
  final timeoutMs =
      _intOptionAny(route.action.options, const <String>[
        'session_idle_timeout_ms',
        'sessionIdleTimeoutMs',
      ]) ??
      _mcpDefaultSessionIdleTimeoutMs;
  return timeoutMs == 0 ? null : Duration(milliseconds: timeoutMs);
}

class _McpProtectedResourceMetadata {
  const _McpProtectedResourceMetadata({
    required this.metadataUrl,
    required this.body,
    this.scopes,
  });

  final String metadataUrl;
  final Map<String, Object?> body;
  final List<String>? scopes;
}

_McpProtectedResourceMetadata? _mcpProtectedResourceMetadata(
  HttpRouteSettings route,
) {
  final cached = _mcpProtectedResourceMetadataCache[route];
  if (identical(cached, _mcpNoProtectedResourceMetadata)) {
    return null;
  }
  if (cached is _McpProtectedResourceMetadata) {
    return cached;
  }
  final metadata = _mcpProtectedResourceMetadataFromOptions(
    route.action.options,
  );
  _mcpProtectedResourceMetadataCache[route] =
      metadata ?? _mcpNoProtectedResourceMetadata;
  return metadata;
}

_McpProtectedResourceMetadata? _mcpProtectedResourceMetadataFromOptions(
  Map<String, Object?> options,
) {
  final snakeCase = options['protected_resource_metadata'];
  final camelCase = options['protectedResourceMetadata'];
  if (snakeCase != null && camelCase != null) {
    throw const FormatException(
      'Configure only one of MCP protected_resource_metadata or '
      'protectedResourceMetadata',
    );
  }
  final raw = snakeCase ?? camelCase;
  if (raw == null) {
    return null;
  }
  final optionName = snakeCase != null
      ? 'protected_resource_metadata'
      : 'protectedResourceMetadata';
  if (raw is! Map) {
    throw FormatException('MCP $optionName must be an object');
  }
  final config = <String, Object?>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  if (config.length != raw.length) {
    throw FormatException('MCP $optionName keys must be strings');
  }

  final metadataUrl = _mcpProtectedResourceUrl(
    config,
    optionName,
    'metadata_url',
  );
  final resource = _mcpProtectedResourceUrl(config, optionName, 'resource');
  final authorizationServers = _mcpProtectedResourceStringList(
    config,
    optionName,
    'authorization_servers',
    required: true,
    validate: (value, index) {
      final uri = _mcpAbsoluteHttpUri(value);
      if (uri == null || uri.scheme != 'https') {
        throw FormatException(
          'MCP $optionName.authorization_servers[$index] must use HTTPS',
        );
      }
    },
  )!;
  final scopes = _mcpProtectedResourceStringList(
    config,
    optionName,
    'scopes_supported',
    validate: (value, index) {
      if (!_mcpOAuthScopeTokenValid(value)) {
        throw FormatException(
          'MCP $optionName.scopes_supported[$index] is not a valid OAuth '
          'scope token',
        );
      }
    },
  );
  final resourceName = _mcpProtectedResourceOptionalString(
    config,
    optionName,
    'resource_name',
  );

  return _McpProtectedResourceMetadata(
    metadataUrl: metadataUrl,
    scopes: scopes,
    body: <String, Object?>{
      'resource': resource,
      'authorization_servers': authorizationServers,
      'scopes_supported': ?scopes,
      'resource_name': ?resourceName,
      'bearer_methods_supported': const <String>['header'],
    },
  );
}

String _mcpProtectedResourceUrl(
  Map<String, Object?> config,
  String optionName,
  String key,
) {
  final value = config[key];
  if (value == null) {
    throw FormatException('MCP $optionName.$key is required');
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('MCP $optionName.$key must be a non-empty string');
  }
  final normalized = value.trim();
  final uri = _mcpAbsoluteHttpUri(normalized);
  if (uri == null) {
    throw FormatException(
      'MCP $optionName.$key must be an absolute URL without user info or a '
      'fragment',
    );
  }
  return uri.toString();
}

Uri? _mcpAbsoluteHttpUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

List<String>? _mcpProtectedResourceStringList(
  Map<String, Object?> config,
  String optionName,
  String key, {
  bool required = false,
  void Function(String value, int index)? validate,
}) {
  final raw = config[key];
  if (raw == null) {
    if (required) {
      throw FormatException('MCP $optionName.$key is required');
    }
    return null;
  }
  if (raw is! List) {
    throw FormatException('MCP $optionName.$key must be a list of strings');
  }
  if (raw.isEmpty) {
    throw FormatException('MCP $optionName.$key must not be empty');
  }
  final values = <String>[];
  for (var index = 0; index < raw.length; index += 1) {
    final value = raw[index];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'MCP $optionName.$key[$index] must be a non-empty string',
      );
    }
    final normalized = value.trim();
    validate?.call(normalized, index);
    if (values.contains(normalized)) {
      throw FormatException(
        'MCP $optionName.$key contains duplicate value "$normalized"',
      );
    }
    values.add(normalized);
  }
  return values;
}

String? _mcpProtectedResourceOptionalString(
  Map<String, Object?> config,
  String optionName,
  String key,
) {
  final value = config[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('MCP $optionName.$key must be a non-empty string');
  }
  return value.trim();
}

bool _mcpOAuthScopeTokenValid(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit == 0x21 ||
        (codeUnit >= 0x23 && codeUnit <= 0x5b) ||
        (codeUnit >= 0x5d && codeUnit <= 0x7e)) {
      continue;
    }
    return false;
  }
  return value.isNotEmpty;
}

bool _mcpProtectedResourceMetadataRequest(
  RouterBinding binding,
  RouterHttpRequest request,
  HttpRouteSettings route,
) {
  if (request.method.trim().toUpperCase() != 'GET' ||
      _mcpProtectedResourceMetadata(route) == null) {
    return false;
  }
  final accepted = _mcpAcceptTypes(binding, request);
  final explicitlyRequestsSse = _mcpAcceptIncludesExactMediaType(
    accepted,
    _mcpSseContentType,
  );
  if (explicitlyRequestsSse) {
    return false;
  }
  final sessionId = _mcpHeaderValue(binding, request, _mcpSessionIdHeader);
  return sessionId == null &&
      (accepted.isEmpty ||
          _mcpAcceptAllowsMediaType(accepted, _mcpJsonContentType));
}

Map<String, String> _mcpUnauthorizedHeaders(
  RouterBinding binding, {
  required HttpRouteSettings route,
  required String realm,
  required String authPath,
}) {
  final headers = binding._httpUnauthorizedHeaders(
    realm: realm,
    authPath: authPath,
  );
  final metadata = _mcpProtectedResourceMetadata(route);
  if (metadata == null) {
    return headers;
  }
  final challenge = headers[HttpHeaders.wwwAuthenticateHeader] ?? 'Bearer';
  final scopeParameter = metadata.scopes?.isNotEmpty ?? false
      ? ', scope="${metadata.scopes!.join(' ')}"'
      : '';
  headers[HttpHeaders.wwwAuthenticateHeader] =
      '$challenge$scopeParameter, '
      'resource_metadata="${metadata.metadataUrl}"';
  return headers;
}

Map<String, String> _mcpCorsResponseHeaders(
  RouterBinding binding,
  RouterHttpRequest request,
  HttpRouteSettings route, {
  bool preflight = false,
}) {
  final origin = _mcpHeaderValue(binding, request, 'origin');
  if (origin == null || !_mcpOriginAllowed(binding, request, route)) {
    return const <String, String>{};
  }

  final allowedOrigins = _mcpAllowedOrigins(route.action.options);
  final allowOrigin = allowedOrigins.contains('*') ? '*' : origin;
  final requestHeaders = _mcpHeaderValueRaw(
    binding,
    request,
    _mcpCorsRequestHeadersHeader,
  )?.trim();
  final reflectsRequestHeaders =
      preflight && requestHeaders != null && requestHeaders.isNotEmpty;
  final varyHeaders = <String>[
    if (allowOrigin != '*') 'Origin',
    if (reflectsRequestHeaders) _mcpCorsRequestHeadersHeader,
  ];
  return <String, String>{
    _mcpCorsAllowOriginHeader: allowOrigin,
    _mcpCorsExposeHeadersHeader: _mcpCorsExposeHeaders,
    if (varyHeaders.isNotEmpty) HttpHeaders.varyHeader: varyHeaders.join(', '),
    if (preflight) ...<String, String>{
      _mcpCorsAllowMethodsHeader: _mcpCorsAllowMethods,
      _mcpCorsAllowHeadersHeader:
          requestHeaders == null || requestHeaders.isEmpty
          ? _mcpCorsDefaultAllowHeaders
          : requestHeaders,
      _mcpCorsMaxAgeHeader: '600',
    },
  };
}

Map<String, String> _mcpHttpResponseHeaders({
  bool json = true,
  String? sessionId,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extra = const <String, String>{},
}) {
  return <String, String>{
    if (json) HttpHeaders.contentTypeHeader: _mcpJsonContentType,
    _mcpProtocolVersionHeader: protocolVersion,
    if (sessionId != null && sessionId.isNotEmpty)
      _mcpSessionIdHeader: sessionId,
    ...extra,
  };
}

Map<String, Object?> _mcpJsonRpcErrorPayload({
  required int code,
  required String message,
  Object? id,
  Object? data,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message, 'data': ?data},
  };
}

NativeHttpResponse _mcpJsonRpcHttpError({
  required int status,
  required int code,
  required String message,
  Object? id,
  Object? data,
  String? sessionId,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extraHeaders = const <String, String>{},
}) {
  return NativeHttpResponse(
    status: status,
    headers: _mcpHttpResponseHeaders(
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extra: extraHeaders,
    ),
    body: NativeHttpResponseJson(
      _mcpJsonRpcErrorPayload(code: code, message: message, id: id, data: data),
    ),
  );
}

Future<void> _sendMcpCatalogRefreshHttpError(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  required Object error,
  Object? id,
  String? sessionId,
  required String protocolVersion,
  required Map<String, String> extraHeaders,
}) async {
  binding.onEvent?.call({
    'source': 'binding',
    'type': 'mcp_catalog_refresh_error',
    'listenerId': request.listenerId,
    'connectionId': request.connectionId,
    'endpoint': request.endpoint,
    'errorType': error is _McpAuthorizationCheckFailed
        ? error.errorType
        : error.runtimeType.toString(),
  });
  await binding._sendImmediateHttpResponse(
    request: request,
    handshake: handshake,
    response: _mcpJsonRpcHttpError(
      status: HttpStatus.internalServerError,
      code: mcp.McpErrorCodes.internalError,
      message: 'MCP catalog could not be refreshed',
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    ),
  );
}

String? _mcpHeaderValue(
  RouterBinding binding,
  RouterHttpRequest request,
  String name,
) {
  final value = binding._headerValue(request.headers, name)?.trim();
  return value == null || value.isEmpty ? null : value;
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
  return mcpLastEventIdHeaderValueValidForTest(value);
}

@visibleForTesting
bool mcpLastEventIdHeaderValueValidForTest(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return false;
    }
  }
  return true;
}

void _restoreMcpSseSequenceReservations({
  required Map<String, int> streamSequences,
  required Map<String, int?> previousSequences,
  required Map<String, int> reservedSequences,
}) {
  for (final reservation in reservedSequences.entries) {
    if (streamSequences[reservation.key] != reservation.value) {
      continue;
    }
    final previousSequence = previousSequences[reservation.key];
    if (previousSequence == null) {
      streamSequences.remove(reservation.key);
    } else {
      streamSequences[reservation.key] = previousSequence;
    }
  }
}

@visibleForTesting
void restoreMcpSseSequenceReservationsForTest({
  required Map<String, int> streamSequences,
  required Map<String, int?> previousSequences,
  required Map<String, int> reservedSequences,
}) {
  _restoreMcpSseSequenceReservations(
    streamSequences: streamSequences,
    previousSequences: previousSequences,
    reservedSequences: reservedSequences,
  );
}

String? _mcpHeaderValueRaw(
  RouterBinding binding,
  RouterHttpRequest request,
  String name,
) {
  final value = binding._headerValue(request.headers, name);
  return value == null || value.isEmpty ? null : value;
}

bool _mcpProtocolVersionHeaderSupported(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final value = _mcpHeaderValue(binding, request, _mcpProtocolVersionHeader);
  return value == null || _mcpSupportedHttpProtocolVersions.contains(value);
}

String? _mcpNegotiatedInitializeProtocolVersion(Object? rawMessage) {
  if (rawMessage is! Map || _mcpRequestMethod(rawMessage) != 'initialize') {
    return null;
  }
  final params = rawMessage['params'];
  if (params is! Map) {
    return null;
  }
  final protocolVersion = params['protocolVersion'];
  if (protocolVersion is! String) {
    return null;
  }
  return mcp.mcpNegotiateProtocolVersion(protocolVersion);
}

String? _mcpResponseSessionIdForRequest({
  required String httpMethod,
  required bool streamableHttpRequest,
  required String? sessionId,
}) {
  if (sessionId == null || !_mcpSessionIdHeaderValueValid(sessionId)) {
    return null;
  }
  return switch (httpMethod) {
    'GET' || 'DELETE' => sessionId,
    'POST' when streamableHttpRequest => sessionId,
    _ => null,
  };
}

class _McpAcceptMediaRange {
  const _McpAcceptMediaRange(this.type, this.subtype, this.quality);

  final String type;
  final String subtype;
  final double quality;

  int specificityFor(String type, String subtype) {
    if (this.type == '*' && this.subtype == '*') {
      return 0;
    }
    if (this.type != type) {
      return -1;
    }
    if (this.subtype == '*') {
      return 1;
    }
    if (this.subtype == subtype) {
      return 2;
    }
    return -1;
  }
}

List<_McpAcceptMediaRange> _mcpAcceptTypes(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accept = _mcpHeaderValue(binding, request, HttpHeaders.acceptHeader);
  if (accept == null) {
    return const <_McpAcceptMediaRange>[];
  }

  final accepted = <_McpAcceptMediaRange>[];
  for (final part in accept.split(',')) {
    final segments = part.split(';');
    final mediaType = segments.first.trim().toLowerCase();
    if (mediaType.isEmpty) {
      continue;
    }

    final slash = mediaType.indexOf('/');
    final type = slash < 0 ? mediaType : mediaType.substring(0, slash).trim();
    final subtype = slash < 0 ? '' : mediaType.substring(slash + 1).trim();
    if (type.isEmpty || (slash >= 0 && subtype.isEmpty)) {
      continue;
    }

    var quality = 1.0;
    for (final parameter in segments.skip(1)) {
      final separator = parameter.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final name = parameter.substring(0, separator).trim().toLowerCase();
      if (name != 'q') {
        continue;
      }
      final parsedQuality = double.tryParse(
        parameter.substring(separator + 1).trim(),
      );
      if (parsedQuality != null) {
        quality = parsedQuality;
      }
      break;
    }

    accepted.add(_McpAcceptMediaRange(type, subtype, quality));
  }
  return accepted;
}

bool _mcpAcceptAllowsMediaType(
  Iterable<_McpAcceptMediaRange> accepted,
  String mediaType,
) {
  final slash = mediaType.indexOf('/');
  if (slash <= 0 || slash == mediaType.length - 1) {
    return false;
  }
  final type = mediaType.substring(0, slash).toLowerCase();
  final subtype = mediaType.substring(slash + 1).toLowerCase();

  var bestSpecificity = -1;
  var bestQuality = 0.0;
  for (final range in accepted) {
    final specificity = range.specificityFor(type, subtype);
    if (specificity < 0) {
      continue;
    }
    if (specificity > bestSpecificity) {
      bestSpecificity = specificity;
      bestQuality = range.quality;
    } else if (specificity == bestSpecificity && range.quality > bestQuality) {
      bestQuality = range.quality;
    }
  }
  return bestSpecificity >= 0 && bestQuality > 0;
}

bool _mcpAcceptIncludesExactMediaType(
  Iterable<_McpAcceptMediaRange> accepted,
  String mediaType,
) {
  final slash = mediaType.indexOf('/');
  if (slash <= 0 || slash == mediaType.length - 1) {
    return false;
  }
  final type = mediaType.substring(0, slash).toLowerCase();
  final subtype = mediaType.substring(slash + 1).toLowerCase();

  var found = false;
  var bestQuality = 0.0;
  for (final range in accepted) {
    if (range.type == type && range.subtype == subtype) {
      found = true;
      if (range.quality > bestQuality) {
        bestQuality = range.quality;
      }
    }
  }
  return found && bestQuality > 0;
}

bool _mcpAcceptAllowsJsonResponse(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  if (accepted.isEmpty) {
    return true;
  }
  return _mcpAcceptAllowsMediaType(accepted, _mcpJsonContentType);
}

bool _mcpAcceptAllowsSseResponse(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  return _mcpAcceptAllowsMediaType(accepted, _mcpSseContentType);
}

bool _mcpAcceptRequestsStreamableHttpSession(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  return _mcpAcceptIncludesExactMediaType(accepted, _mcpJsonContentType) &&
      _mcpAcceptIncludesExactMediaType(accepted, _mcpSseContentType);
}

bool _mcpPostResponsesUseSse(
  RouterBinding binding,
  RouterHttpRequest request,
  HttpRouteSettings route, {
  required bool isInitialize,
  required String? sessionId,
}) {
  if (isInitialize || sessionId == null || sessionId.isEmpty) {
    return false;
  }
  if (!_mcpAcceptRequestsStreamableHttpSession(binding, request)) {
    return false;
  }

  final mode = _stringOptionAny(route.action.options, const [
    'post_response_transport',
    'postResponseTransport',
  ])?.trim().toLowerCase();
  switch (mode) {
    case 'json':
    case 'off':
    case 'false':
    case 'disabled':
      return false;
    case 'sse':
    case 'stream':
    case 'streamable':
    case 'auto':
      return true;
  }
  return _boolOptionAny(route.action.options, const [
    'stream_post_responses',
    'streamPostResponses',
  ], defaultValue: true);
}

bool _mcpContentTypeAllowsJsonBody(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final contentType = _mcpHeaderValue(
    binding,
    request,
    HttpHeaders.contentTypeHeader,
  );
  if (contentType == null) {
    return true;
  }
  final mimeType = contentType.split(';').first.trim().toLowerCase();
  return mimeType == _mcpJsonContentType || mimeType.endsWith('+json');
}

bool _mcpOriginAllowed(
  RouterBinding binding,
  RouterHttpRequest request,
  HttpRouteSettings route,
) {
  final origin = _mcpHeaderValue(binding, request, 'origin');
  if (origin == null) {
    return true;
  }
  final allowedOrigins = _mcpAllowedOrigins(route.action.options);
  if (allowedOrigins.contains('*') || allowedOrigins.contains(origin)) {
    return true;
  }
  if (allowedOrigins.isNotEmpty) {
    return false;
  }

  final host = _mcpHeaderValue(binding, request, HttpHeaders.hostHeader);
  final originUri = Uri.tryParse(origin);
  if (host == null || originUri == null || originUri.host.isEmpty) {
    return false;
  }
  final originHost = originUri.hasPort
      ? '${originUri.host}:${originUri.port}'
      : originUri.host;
  return host.toLowerCase() == originHost.toLowerCase();
}

Set<String> _mcpAllowedOrigins(Map<String, Object?> options) {
  final raw =
      options['allowedOrigins'] ??
      options['allowed_origins'] ??
      options['allowedOrigin'] ??
      options['allowed_origin'] ??
      options['origins'];
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? const <String>{} : <String>{trimmed};
  }
  if (raw is Iterable) {
    return {
      for (final value in raw)
        if (value is String && value.trim().isNotEmpty) value.trim(),
    };
  }
  return const <String>{};
}

bool _isStandardMetaProcedure(String procedure) {
  return mcp.McpWampStandardMetaApi.procedures.any(
    (metaProcedure) => metaProcedure.procedure == procedure,
  );
}

String? _mcpValidatedOptionalCursor(Object? value, String label) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a string',
    );
  }
  if (value.isEmpty || containsMcpWhitespaceOrControl(value)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a non-empty string without whitespace or control '
      'characters',
    );
  }
  return value;
}

String _mcpValidatedToolName(Object? value, String label) {
  if (value is! String) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a string',
    );
  }
  if (_mcpToolNamePattern.hasMatch(value)) {
    return value;
  }
  throw mcp.McpException(
    mcp.McpErrorCodes.invalidParams,
    '$label must be 1-128 ASCII letters, digits, underscores, hyphens, or '
    'dots',
  );
}

String _mcpValidatedPromptName(Object? value, String label) {
  if (value is! String) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a string',
    );
  }
  if (value.isEmpty || containsMcpWhitespaceOrControl(value)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a non-empty string without whitespace or control '
      'characters',
    );
  }
  return value;
}

String _mcpValidatedResourceUri(Object? value, String label) {
  if (value is! String) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must be a string',
    );
  }
  if (containsMcpWhitespaceOrControl(value)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      '$label must not contain whitespace or control characters',
    );
  }
  final parsed = Uri.tryParse(value);
  if (value.isNotEmpty && parsed != null && parsed.hasScheme) {
    return value;
  }
  throw mcp.McpException(
    mcp.McpErrorCodes.invalidParams,
    '$label must be an absolute URI with a scheme',
  );
}

String? _mcpRequestMethod(Object? rawMessage) {
  if (rawMessage is Map) {
    final method = rawMessage['method'];
    if (method is String) {
      return method;
    }
  }
  return null;
}

String? _mcpRequestName(Object? rawMessage, String method) {
  if (rawMessage is! Map) {
    return null;
  }
  final params = rawMessage['params'];
  if (params is! Map) {
    return null;
  }
  final field = switch (method) {
    'tools/call' ||
    'connectanum.tool.call' ||
    'connectanum.tools.call' ||
    'prompts/get' => 'name',
    'resources/read' ||
    'resources/subscribe' ||
    'resources/unsubscribe' => 'uri',
    _ => null,
  };
  if (field == null) {
    return null;
  }
  final value = params[field];
  return value is String && value.isNotEmpty ? value : null;
}

NativeHttpResponse? _mcpStatelessMetadataValidationError(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required Object? rawMessage,
  required Map<String, String> extraHeaders,
}) {
  final headerProtocolVersion = _mcpHeaderValue(
    binding,
    request,
    _mcpProtocolVersionHeader,
  );
  final id = _recoverDirectJsonRequestId(rawMessage);
  if (rawMessage is! Map) {
    if (headerProtocolVersion != mcp.mcpLatestStatelessProtocolVersion) {
      return null;
    }
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.invalidRequest,
      message: 'MCP 2026 HTTP POST requires one JSON-RPC message object',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }

  final params = rawMessage['params'];
  final metadata = params is Map ? params['_meta'] : null;
  final bodyProtocolVersion = metadata is Map
      ? metadata['io.modelcontextprotocol/protocolVersion']
      : null;
  final isStatelessRequest =
      headerProtocolVersion == mcp.mcpLatestStatelessProtocolVersion ||
      bodyProtocolVersion == mcp.mcpLatestStatelessProtocolVersion;
  if (!isStatelessRequest) {
    return null;
  }
  if (headerProtocolVersion != mcp.mcpLatestStatelessProtocolVersion) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.headerMismatch,
      message:
          'Header mismatch: missing or mismatched MCP-Protocol-Version header',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  if (metadata is! Map || bodyProtocolVersion == null) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.invalidParams,
      message:
          'MCP 2026 params._meta protocolVersion and clientCapabilities are required',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  if (bodyProtocolVersion != headerProtocolVersion) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.headerMismatch,
      message:
          'Header mismatch: MCP-Protocol-Version header does not match '
          'params._meta protocolVersion',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  final clientCapabilities =
      metadata['io.modelcontextprotocol/clientCapabilities'];
  if (clientCapabilities is! Map) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.invalidParams,
      message: 'MCP 2026 params._meta clientCapabilities must be an object',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  final clientInfo = metadata['io.modelcontextprotocol/clientInfo'];
  if (clientInfo != null &&
      (clientInfo is! Map ||
          clientInfo['name'] is! String ||
          (clientInfo['name'] as String).isEmpty ||
          clientInfo['version'] is! String ||
          (clientInfo['version'] as String).isEmpty)) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: mcp.McpErrorCodes.invalidParams,
      message: 'MCP 2026 params._meta clientInfo must name a versioned client',
      id: id,
      protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  return null;
}

NativeHttpResponse? _mcpStandardHeaderValidationError(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required Object? rawMessage,
  bool requireHeaders = false,
  String? sessionId,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extraHeaders = const <String, String>{},
}) {
  final bodyMethod = _mcpRequestMethod(rawMessage);
  if (bodyMethod == null) {
    return null;
  }
  final id = _recoverDirectJsonRequestId(rawMessage);
  final headerMethod = _mcpHeaderValueRaw(binding, request, _mcpMethodHeader);
  final headerName = _mcpHeaderValueRaw(binding, request, _mcpNameHeader);
  final metadataHeadersPresent = headerMethod != null || headerName != null;
  if (!metadataHeadersPresent && !requireHeaders) {
    return null;
  }
  if (headerMethod == null) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: _mcpHeaderMismatchErrorCode(protocolVersion),
      message: 'Header mismatch: missing Mcp-Method header',
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  if (headerMethod != bodyMethod) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: _mcpHeaderMismatchErrorCode(protocolVersion),
      message:
          "Header mismatch: Mcp-Method header value '$headerMethod' does not "
          "match body method '$bodyMethod'",
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
  }

  final bodyName = _mcpRequestName(rawMessage, bodyMethod);
  if (bodyName == null) {
    if (headerName == null) {
      return null;
    }
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: _mcpHeaderMismatchErrorCode(protocolVersion),
      message:
          'Header mismatch: Mcp-Name header is present but body value is missing',
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  if (headerName == null) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: _mcpHeaderMismatchErrorCode(protocolVersion),
      message: 'Header mismatch: missing Mcp-Name header',
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  if (headerName != bodyName) {
    return _mcpJsonRpcHttpError(
      status: HttpStatus.badRequest,
      code: _mcpHeaderMismatchErrorCode(protocolVersion),
      message:
          "Header mismatch: Mcp-Name header value '$headerName' does not "
          "match body value '$bodyName'",
      id: id,
      sessionId: sessionId,
      protocolVersion: protocolVersion,
      extraHeaders: extraHeaders,
    );
  }
  return null;
}

int _mcpHeaderMismatchErrorCode(String protocolVersion) {
  return protocolVersion == mcp.mcpLatestStatelessProtocolVersion
      ? mcp.McpErrorCodes.headerMismatch
      : mcp.McpErrorCodes.legacyHeaderMismatch;
}

NativeHttpResponse? _mcpToolParameterHeaderValidationError(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required Object? rawMessage,
  required _RouterMcpEndpoint endpoint,
  required bool requireHeaders,
  String? sessionId,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extraHeaders = const <String, String>{},
}) {
  var parameterHeadersPresent = false;
  for (final header in request.headers.entries) {
    if (!_mcpIsParameterHeaderName(header.key)) {
      continue;
    }
    parameterHeadersPresent = true;
    if (!_mcpParameterHeaderValueCharactersValid(header.value)) {
      return _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: _mcpHeaderMismatchErrorCode(protocolVersion),
        message:
            'Header mismatch: ${header.key} header contains invalid characters',
        id: _recoverDirectJsonRequestId(rawMessage),
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extraHeaders: extraHeaders,
      );
    }
  }

  final method = _mcpRequestMethod(rawMessage);
  if (method == null || rawMessage is! Map) {
    return null;
  }
  final params = rawMessage['params'];
  if (params is! Map) {
    return null;
  }

  String? toolName;
  Map<String, Object?> arguments = const <String, Object?>{};
  if (method == 'tools/call' ||
      method == 'connectanum.tool.call' ||
      method == 'connectanum.tools.call') {
    final rawToolName = params['name'];
    if (rawToolName is! String) {
      return null;
    }
    toolName = rawToolName;
    arguments = _jsonMapFrom(params['arguments']) ?? const <String, Object?>{};
  } else if (method.contains('.') && endpoint.server.tools[method] != null) {
    toolName = method;
    arguments = _jsonMapFrom(params) ?? const <String, Object?>{};
  } else {
    return null;
  }

  final tool = endpoint.server.tools[toolName];
  if (tool == null) {
    return null;
  }
  final headerParameters = _mcpToolHeaderParametersFromSchema(tool.inputSchema);
  if (headerParameters.isEmpty) {
    return null;
  }
  final namedMetadataHeadersPresent =
      _mcpHeaderValueRaw(binding, request, _mcpNameHeader) != null;
  final parameterHeadersRequired =
      requireHeaders &&
      (namedMetadataHeadersPresent || parameterHeadersPresent);
  final id = _recoverDirectJsonRequestId(rawMessage);
  for (final parameter in headerParameters) {
    final headerName = '$_mcpParameterHeaderPrefix${parameter.headerName}';
    final headerValue = _mcpHeaderValueRaw(binding, request, headerName);
    final hasArgument = arguments.containsKey(parameter.argumentName);
    final argumentValue = hasArgument
        ? arguments[parameter.argumentName]
        : null;
    if (argumentValue == null) {
      if (headerValue != null) {
        return _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: _mcpHeaderMismatchErrorCode(protocolVersion),
          message:
              'Header mismatch: $headerName header is present but body value '
              "for '${parameter.argumentName}' is missing",
          id: id,
          sessionId: sessionId,
          protocolVersion: protocolVersion,
          extraHeaders: extraHeaders,
        );
      }
      continue;
    }
    final expectedValue = _mcpStringFromHeaderParameterValue(argumentValue);
    if (expectedValue == null) {
      return _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: _mcpHeaderMismatchErrorCode(protocolVersion),
        message:
            "Header mismatch: body value for '${parameter.argumentName}' must "
            'be a string, number, or boolean',
        id: id,
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extraHeaders: extraHeaders,
      );
    }
    if (headerValue == null) {
      if (!parameterHeadersRequired) {
        continue;
      }
      return _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: _mcpHeaderMismatchErrorCode(protocolVersion),
        message: 'Header mismatch: missing $headerName header',
        id: id,
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extraHeaders: extraHeaders,
      );
    }
    final decodedValue = _mcpDecodeParameterHeaderValue(headerValue);
    if (decodedValue == null) {
      return _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: _mcpHeaderMismatchErrorCode(protocolVersion),
        message: 'Header mismatch: malformed $headerName header',
        id: id,
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extraHeaders: extraHeaders,
      );
    }
    if (decodedValue != expectedValue) {
      return _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: _mcpHeaderMismatchErrorCode(protocolVersion),
        message:
            "Header mismatch: $headerName header value '$decodedValue' does "
            "not match body value '$expectedValue'",
        id: id,
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extraHeaders: extraHeaders,
      );
    }
  }
  return null;
}

bool _mcpIsParameterHeaderName(String name) {
  return name.toLowerCase().startsWith(_mcpParameterHeaderPrefix.toLowerCase());
}

bool _mcpParameterHeaderValueCharactersValid(String value) {
  for (final codeUnit in value.codeUnits) {
    final visibleAscii = codeUnit >= 0x20 && codeUnit <= 0x7E;
    if (!visibleAscii && codeUnit != 0x09) {
      return false;
    }
  }
  return true;
}

String? _mcpDecodeParameterHeaderValue(String value) {
  if (!_mcpParameterHeaderValueCharactersValid(value)) {
    return null;
  }
  if (!value.startsWith(_mcpBase64HeaderPrefix) ||
      !value.endsWith(_mcpBase64HeaderSuffix)) {
    return value;
  }
  final encoded = value.substring(
    _mcpBase64HeaderPrefix.length,
    value.length - _mcpBase64HeaderSuffix.length,
  );
  try {
    return utf8.decode(base64Decode(encoded));
  } on FormatException {
    return null;
  }
}

String? _mcpStringFromHeaderParameterValue(Object? value) {
  return switch (value) {
    final String value => value,
    final num value => value.toString(),
    final bool value => value ? 'true' : 'false',
    _ => null,
  };
}

List<_McpToolHeaderParameter> _mcpToolHeaderParametersFromSchema(
  Map<String, Object?> inputSchema,
) {
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
        !_mcpHeaderNameSegmentValid(headerName) ||
        !headerNames.add(headerName.toLowerCase()) ||
        !_mcpHeaderParameterSchemaIsPrimitive(property)) {
      return const <_McpToolHeaderParameter>[];
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

bool _mcpHeaderNameSegmentValid(String value) {
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
    return _mcpHeaderPrimitiveType(type);
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
      if (!_mcpHeaderPrimitiveType(value)) {
        return false;
      }
    }
    return sawType;
  }
  return false;
}

bool _mcpHeaderPrimitiveType(String type) {
  return type == 'string' ||
      type == 'number' ||
      type == 'integer' ||
      type == 'boolean';
}

final class _McpToolHeaderParameter {
  const _McpToolHeaderParameter({
    required this.argumentName,
    required this.headerName,
  });

  final String argumentName;
  final String headerName;
}

String _mcpGenerateHttpSessionId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _mcpSseEventBytes({
  required String id,
  String data = '',
  int? retryMs,
}) {
  final buffer = StringBuffer()..writeln('id: $id');
  if (retryMs != null) {
    buffer.writeln('retry: $retryMs');
  }
  for (final line in data.split('\n')) {
    buffer.writeln('data: $line');
  }
  buffer.writeln();
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

Uint8List _mcpSseEventsBytes(Iterable<_RouterMcpSseEvent> events) {
  final buffer = BytesBuilder(copy: false);
  for (final event in events) {
    buffer.add(
      _mcpSseEventBytes(id: event.id, data: event.data, retryMs: event.retryMs),
    );
  }
  return buffer.takeBytes();
}

Uint8List _mcpRequestScopedSseMessageBytes(Object? message) {
  final encoded = jsonEncode(message);
  final buffer = StringBuffer();
  for (final line in const LineSplitter().convert(encoded)) {
    buffer.writeln('data: $line');
  }
  buffer.writeln();
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

Uint8List _mcpRequestScopedSseHeartbeatBytes() =>
    Uint8List.fromList(utf8.encode(': keep-alive\n\n'));

NativeHttpResponseStream? _mcpOpenSseResponse(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  String? sessionId,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extraHeaders = const <String, String>{},
}) {
  final handle = handshake?.handle ?? request.handshakeHandle;
  if (handle <= 0) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_missing_handshake',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
    });
    return null;
  }
  try {
    return binding.runtime.openHttpResponseStream(
      handshakeHandle: handle,
      status: HttpStatus.ok,
      headers: _mcpHttpResponseHeaders(
        json: false,
        sessionId: sessionId,
        protocolVersion: protocolVersion,
        extra: <String, String>{
          HttpHeaders.contentTypeHeader: 'text/event-stream; charset=utf-8',
          HttpHeaders.cacheControlHeader: 'no-cache',
          'X-Accel-Buffering': 'no',
          ...extraHeaders,
        },
      ),
    );
  } on UnsupportedError catch (error, stackTrace) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_open_unsupported',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  } on NativeTransportException catch (error, stackTrace) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_open_error',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }
  return null;
}

Future<bool> _mcpSendSseResponse(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  required String sessionId,
  required Uint8List body,
  String protocolVersion = mcp.mcpLatestSessionProtocolVersion,
  Map<String, String> extraHeaders = const <String, String>{},
}) async {
  final stream = _mcpOpenSseResponse(
    binding,
    request: request,
    handshake: handshake,
    sessionId: sessionId,
    protocolVersion: protocolVersion,
    extraHeaders: extraHeaders,
  );
  if (stream == null) {
    return false;
  }
  try {
    stream.close(body);
  } catch (error, stackTrace) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_write_error',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    return false;
  }
  return true;
}

Future<void> _handleMcpHttpRequestForBinding(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  required ListenerSettings? listenerSettings,
  required HttpRouteSettings route,
  required SessionProfileSettings? sessionProfile,
}) async {
  final httpMethod = request.method.trim().toUpperCase();
  final mcpSessionId = _mcpHeaderValue(binding, request, _mcpSessionIdHeader);
  final requestMcpProtocolVersion = _mcpHeaderValue(
    binding,
    request,
    _mcpProtocolVersionHeader,
  );
  final responseMcpProtocolVersion =
      requestMcpProtocolVersion != null &&
          _mcpSupportedHttpProtocolVersions.contains(requestMcpProtocolVersion)
      ? requestMcpProtocolVersion
      : mcp.mcpLatestSessionProtocolVersion;
  final statelessHttpRequest =
      requestMcpProtocolVersion == mcp.mcpLatestStatelessProtocolVersion;
  final streamableHttpRequest =
      httpMethod == 'POST' &&
      !statelessHttpRequest &&
      _mcpAcceptRequestsStreamableHttpSession(binding, request);
  final responseMcpSessionId = statelessHttpRequest
      ? null
      : _mcpResponseSessionIdForRequest(
          httpMethod: httpMethod,
          streamableHttpRequest: streamableHttpRequest,
          sessionId: mcpSessionId,
        );

  if (!_mcpOriginAllowed(binding, request, route)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.forbidden,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'Invalid Origin for MCP endpoint',
        sessionId: responseMcpSessionId,
        protocolVersion: responseMcpProtocolVersion,
      ),
    );
    return;
  }

  final corsHeaders = _mcpCorsResponseHeaders(binding, request, route);
  if (httpMethod == 'OPTIONS') {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.noContent,
        headers: _mcpHttpResponseHeaders(
          json: false,
          sessionId: responseMcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extra: <String, String>{
            HttpHeaders.allowHeader: _mcpCorsAllowMethods,
            ..._mcpCorsResponseHeaders(
              binding,
              request,
              route,
              preflight: true,
            ),
          },
        ),
        body: NativeHttpResponseText(''),
      ),
    );
    return;
  }

  if (_mcpProtectedResourceMetadataRequest(binding, request, route)) {
    final metadata = _mcpProtectedResourceMetadata(route)!;
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.ok,
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          HttpHeaders.cacheControlHeader: 'no-store',
          ...corsHeaders,
        },
        body: NativeHttpResponseJson(metadata.body),
      ),
    );
    return;
  }

  if (!statelessHttpRequest &&
      mcpSessionId != null &&
      !_mcpSessionIdHeaderValueValid(mcpSessionId)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'Invalid MCP-Session-Id header',
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  if (!_mcpProtocolVersionHeaderSupported(binding, request)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: mcp.McpErrorCodes.unsupportedProtocolVersion,
        message: 'Unsupported MCP protocol version',
        data: <String, Object?>{
          'supportedVersions': _mcpSupportedHttpProtocolVersions.toList()
            ..sort(),
        },
        protocolVersion: mcp.mcpLatestStatelessProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  if (statelessHttpRequest && httpMethod != 'POST') {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.methodNotAllowed,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'MCP 2026 HTTP endpoints support POST and OPTIONS',
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: <String, String>{
          ...corsHeaders,
          HttpHeaders.allowHeader: 'POST, OPTIONS',
        },
      ),
    );
    return;
  }

  if (httpMethod == 'GET') {
    if (!_mcpAcceptAllowsSseResponse(binding, request)) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.notAcceptable,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'MCP GET responses require an Accept header allowing SSE',
          sessionId: responseMcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
  }

  if (httpMethod != 'GET' && httpMethod != 'POST' && httpMethod != 'DELETE') {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.methodNotAllowed,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'MCP HTTP endpoint supports GET, POST, DELETE and OPTIONS',
        sessionId: responseMcpSessionId,
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: <String, String>{
          ...corsHeaders,
          HttpHeaders.allowHeader: _mcpCorsAllowMethods,
        },
      ),
    );
    return;
  }

  if (httpMethod == 'POST' && !_mcpAcceptAllowsJsonResponse(binding, request)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.notAcceptable,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'MCP POST responses require an Accept header allowing JSON',
        sessionId: responseMcpSessionId,
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  if (statelessHttpRequest &&
      !_mcpAcceptRequestsStreamableHttpSession(binding, request)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.notAcceptable,
        code: mcp.McpErrorCodes.invalidRequest,
        message:
            'MCP 2026 POST requests require an Accept header allowing JSON and SSE',
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  if (httpMethod == 'POST' &&
      !_mcpContentTypeAllowsJsonBody(binding, request)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.unsupportedMediaType,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'MCP POST requests must use a JSON content type',
        sessionId: responseMcpSessionId,
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  final profileRealm = sessionProfile?.realm?.trim();
  final resolvedRealmUri = profileRealm != null && profileRealm.isNotEmpty
      ? profileRealm
      : (request.realm ?? route.action.realm ?? '');
  if (resolvedRealmUri.isEmpty) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.internalServerError,
        code: mcp.McpErrorCodes.internalError,
        message: 'MCP route has no resolved WAMP realm',
        sessionId: responseMcpSessionId,
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  final RouterSession session;
  try {
    final bearer = binding._extractBearerToken(request.headers);
    if (bearer != null) {
      session = await binding._authenticatedHttpSessionForToken(
        token: bearer,
        request: request,
        realmUri: resolvedRealmUri,
        sessionProfile: sessionProfile,
      );
    } else {
      final allowsAnonymous = httpSessionProfileAllowsAnonymous(sessionProfile);
      final requiresBridgeAuth =
          sessionProfile != null &&
          sessionProfile.auth.methods.isNotEmpty &&
          !allowsAnonymous;
      if (requiresBridgeAuth) {
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: _mcpHttpResponseHeaders(
              sessionId: null,
              protocolVersion: responseMcpProtocolVersion,
              extra: <String, String>{
                ...corsHeaders,
                ..._mcpUnauthorizedHeaders(
                  binding,
                  route: route,
                  realm: resolvedRealmUri,
                  authPath: binding._httpAuthPathFor(listenerSettings?.http),
                ),
              },
            ),
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'error',
              'reason': 'unauthorized',
              'message': 'Bearer token required',
            }),
          ),
        );
        return;
      }
      session = await binding._ensureInternalSession(
        realmUri: resolvedRealmUri,
        sessionProfile: sessionProfile?.name,
        authId: sessionProfile?.auth.authId ?? 'anonymous',
        authMethod: 'anonymous',
        authProvider: 'router-http',
        cacheKey: _mcpAnonymousRouteSessionCacheKey(
          request: request,
          route: route,
          realmUri: resolvedRealmUri,
          sessionProfile: sessionProfile,
        ),
        authorizationIsInternal: false,
      );
    }
  } on _HttpUnauthorized catch (error) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.unauthorized,
        headers: _mcpHttpResponseHeaders(
          sessionId: null,
          protocolVersion: responseMcpProtocolVersion,
          extra: <String, String>{
            ...corsHeaders,
            ..._mcpUnauthorizedHeaders(
              binding,
              route: route,
              realm: resolvedRealmUri,
              authPath: binding._httpAuthPathFor(listenerSettings?.http),
            ),
          },
        ),
        body: NativeHttpResponseJson(<String, Object?>{
          'status': 'error',
          'reason': error.reason,
          if (error.message != null) 'message': error.message,
        }),
      ),
    );
    return;
  }

  if (httpMethod == 'POST' &&
      request.nativeBody.length > _mcpMaxRequestBytesForRoute(route)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.requestEntityTooLarge,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'MCP request body exceeds the configured limit',
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  if (httpMethod == 'GET') {
    if (mcpSessionId == null) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'MCP GET requests require an MCP-Session-Id header',
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    final endpoint = binding._mcpEndpointForRoute(
      request: request,
      route: route,
      session: session,
      mcpSessionId: mcpSessionId,
      create: false,
    );
    if (endpoint == null) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.notFound,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'Unknown MCP HTTP session',
          sessionId: mcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    final lastEventId = _mcpHeaderValue(
      binding,
      request,
      _mcpLastEventIdHeader,
    );
    if (lastEventId != null && !_mcpLastEventIdHeaderValueValid(lastEventId)) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'Invalid Last-Event-ID header',
          sessionId: mcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    try {
      endpoint._validateSseLastEventId(lastEventId);
    } on _UnknownMcpSseEventId {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'Unknown MCP SSE Last-Event-ID',
          sessionId: mcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    final sessionRequestAcquired = endpoint._beginSessionRequest();
    try {
      try {
        await endpoint._refreshTools();
      } catch (error) {
        await _sendMcpCatalogRefreshHttpError(
          binding,
          request: request,
          handshake: handshake,
          error: error,
          sessionId: mcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        );
        return;
      }
      final _RouterMcpSsePollBatch pollBatch;
      try {
        pollBatch = endpoint.ssePollEvents(
          sessionId: mcpSessionId,
          maxResponseBytes: _mcpMaxResponseBytesForRoute(route),
          lastEventId: lastEventId,
        );
      } on _UnknownMcpSseEventId {
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.badRequest,
            code: mcp.McpErrorCodes.invalidRequest,
            message: 'Unknown MCP SSE Last-Event-ID',
            sessionId: mcpSessionId,
            protocolVersion: responseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      } on _McpSsePollEventResponseLimitExceeded {
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.internalServerError,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP SSE event exceeds the configured response limit',
            protocolVersion: responseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      }
      final sent = await _mcpSendSseResponse(
        binding,
        request: request,
        handshake: handshake,
        sessionId: mcpSessionId,
        body: _mcpSseEventsBytes(pollBatch.events),
        protocolVersion: responseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      );
      if (!sent) {
        endpoint.restoreSsePollBatch(pollBatch);
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.internalServerError,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP SSE stream could not be opened',
            sessionId: mcpSessionId,
            protocolVersion: responseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
      } else {
        endpoint.commitSsePollBatch(pollBatch);
      }
    } finally {
      endpoint._endSessionRequest(sessionRequestAcquired);
    }
    return;
  }

  if (httpMethod == 'DELETE') {
    if (mcpSessionId == null) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'MCP DELETE requests require an MCP-Session-Id header',
          protocolVersion: responseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    final removed = await binding._removeMcpEndpointForRoute(
      request: request,
      route: route,
      session: session,
      mcpSessionId: mcpSessionId,
    );
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: removed == null
          ? _mcpJsonRpcHttpError(
              status: HttpStatus.notFound,
              code: mcp.McpErrorCodes.invalidRequest,
              message: 'Unknown MCP HTTP session',
              sessionId: mcpSessionId,
              protocolVersion: responseMcpProtocolVersion,
              extraHeaders: corsHeaders,
            )
          : NativeHttpResponse(
              status: HttpStatus.accepted,
              headers: _mcpHttpResponseHeaders(
                json: false,
                sessionId: mcpSessionId,
                protocolVersion: responseMcpProtocolVersion,
                extra: corsHeaders,
              ),
              body: NativeHttpResponseText(''),
            ),
    );
    return;
  }

  final Object? rawMessage;
  try {
    rawMessage = jsonDecode(utf8.decode(request.body));
  } on FormatException {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.badRequest,
        headers: _mcpHttpResponseHeaders(
          sessionId: responseMcpSessionId,
          protocolVersion: responseMcpProtocolVersion,
          extra: corsHeaders,
        ),
        body: NativeHttpResponseJson(
          mcp.JsonRpcResponse.error(
            null,
            mcp.McpException(
              mcp.McpErrorCodes.parseError,
              'Invalid JSON-RPC message',
            ),
          ).toJson(),
        ),
      ),
    );
    return;
  }

  final requestMethod = _mcpRequestMethod(rawMessage);
  final isInitialize = requestMethod == 'initialize';
  final effectiveResponseMcpProtocolVersion = requestMcpProtocolVersion == null
      ? _mcpNegotiatedInitializeProtocolVersion(rawMessage) ??
            responseMcpProtocolVersion
      : _mcpNegotiatedInitializeProtocolVersion(rawMessage) ??
            responseMcpProtocolVersion;
  final statelessMetadataError = _mcpStatelessMetadataValidationError(
    binding,
    request: request,
    rawMessage: rawMessage,
    extraHeaders: corsHeaders,
  );
  if (statelessMetadataError != null) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: statelessMetadataError,
    );
    return;
  }
  if (statelessHttpRequest && isInitialize) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.notFound,
        code: mcp.McpErrorCodes.methodNotFound,
        message: 'MCP 2026 HTTP does not use initialize',
        id: _recoverDirectJsonRequestId(rawMessage),
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }
  if (isInitialize && streamableHttpRequest && mcpSessionId != null) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: mcp.McpErrorCodes.invalidRequest,
        message:
            'MCP Streamable HTTP initialize requests must not include MCP-Session-Id',
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }
  final standardHeaderError = _mcpStandardHeaderValidationError(
    binding,
    request: request,
    rawMessage: rawMessage,
    requireHeaders: statelessHttpRequest,
    sessionId: responseMcpSessionId,
    protocolVersion: effectiveResponseMcpProtocolVersion,
    extraHeaders: corsHeaders,
  );
  if (standardHeaderError != null) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: standardHeaderError,
    );
    return;
  }
  if (mcpSessionId == null && !isInitialize && streamableHttpRequest) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: mcp.McpErrorCodes.invalidRequest,
        message:
            'MCP Streamable HTTP requests require MCP-Session-Id after initialize',
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }
  final requestMcpSessionId = streamableHttpRequest ? mcpSessionId : null;
  final issuedSessionId =
      requestMcpSessionId == null && isInitialize && streamableHttpRequest
      ? _mcpGenerateHttpSessionId()
      : null;
  final effectiveMcpSessionId = requestMcpSessionId ?? issuedSessionId;
  final endpointAlreadyExisted =
      effectiveMcpSessionId != null &&
      binding._mcpEndpointForRoute(
            request: request,
            route: route,
            session: session,
            mcpSessionId: effectiveMcpSessionId,
            create: false,
          ) !=
          null;
  final _RouterMcpEndpoint? endpoint;
  try {
    endpoint = binding._mcpEndpointForRoute(
      request: request,
      route: route,
      session: session,
      mcpSessionId: effectiveMcpSessionId,
      create: isInitialize || requestMcpSessionId == null,
    );
  } on _McpSessionCapacityExceeded {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.serviceUnavailable,
        code: mcp.McpErrorCodes.internalError,
        message: 'MCP HTTP session capacity is exhausted',
        id: _recoverDirectJsonRequestId(rawMessage),
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }
  if (endpoint == null) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.notFound,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'Unknown MCP HTTP session',
        sessionId: effectiveMcpSessionId,
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      ),
    );
    return;
  }

  final tentativeInitializeSessionId = endpointAlreadyExisted
      ? null
      : issuedSessionId;
  var retainTentativeInitializeEndpoint = false;
  final sessionRequestAcquired = endpoint._beginSessionRequest();
  var refreshIdleDeadline = false;
  try {
    try {
      await endpoint._refreshTools();
    } catch (error) {
      await _sendMcpCatalogRefreshHttpError(
        binding,
        request: request,
        handshake: handshake,
        error: error,
        id: _recoverDirectJsonRequestId(rawMessage),
        sessionId: tentativeInitializeSessionId == null
            ? effectiveMcpSessionId
            : null,
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      );
      return;
    }
    final toolParameterHeaderError = _mcpToolParameterHeaderValidationError(
      binding,
      request: request,
      rawMessage: rawMessage,
      endpoint: endpoint,
      requireHeaders: statelessHttpRequest || streamableHttpRequest,
      sessionId: tentativeInitializeSessionId == null
          ? effectiveMcpSessionId
          : null,
      protocolVersion: effectiveResponseMcpProtocolVersion,
      extraHeaders: corsHeaders,
    );
    if (toolParameterHeaderError != null) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: toolParameterHeaderError,
      );
      return;
    }
    refreshIdleDeadline = true;

    if (statelessHttpRequest && requestMethod == 'subscriptions/listen') {
      final _RouterMcpModernSubscriptionPreparation preparation;
      try {
        preparation = await endpoint.prepareModernSubscription(rawMessage);
      } on _McpRequestScopedListenerCapacityExceeded {
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.serviceUnavailable,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP request-scoped listener capacity is exhausted',
            id: _recoverDirectJsonRequestId(rawMessage),
            protocolVersion: effectiveResponseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      } on mcp.McpException catch (error) {
        final response = endpoint.modernizeResponse(
          mcp.JsonRpcResponse.error(
            _recoverDirectJsonRequestId(rawMessage),
            error,
          ).toJson(),
        );
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.badRequest,
            headers: _mcpHttpResponseHeaders(
              protocolVersion: effectiveResponseMcpProtocolVersion,
              extra: corsHeaders,
            ),
            body: NativeHttpResponseJson(response),
          ),
        );
        return;
      }
      if (preparation.acknowledgmentBytes.length >
          _mcpMaxResponseBytesForRoute(route)) {
        await endpoint.releaseModernSubscriptionPreparation(preparation);
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.internalServerError,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP response body exceeds the configured limit',
            id: _recoverDirectJsonRequestId(rawMessage),
            protocolVersion: effectiveResponseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      }
      final stream = _mcpOpenSseResponse(
        binding,
        request: request,
        handshake: handshake,
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      );
      if (stream == null) {
        await endpoint.releaseModernSubscriptionPreparation(preparation);
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.internalServerError,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP subscription stream could not be opened',
            id: _recoverDirectJsonRequestId(rawMessage),
            protocolVersion: effectiveResponseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      }
      await endpoint.activateModernSubscription(preparation, stream);
      return;
    }

    final rawResponse = await endpoint._handleMessageAfterRefresh(
      rawMessage,
      resourceSubscriptionsAllowed:
          streamableHttpRequest && effectiveMcpSessionId != null,
    );
    final response = statelessHttpRequest
        ? endpoint.modernizeResponse(rawResponse)
        : rawResponse;
    final responseJson = response == null ? null : jsonEncode(response);
    final responseBytes = responseJson == null
        ? null
        : Uint8List.fromList(utf8.encode(responseJson));
    if (responseBytes != null &&
        responseBytes.length > _mcpMaxResponseBytesForRoute(route)) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.internalServerError,
          code: mcp.McpErrorCodes.internalError,
          message: 'MCP response body exceeds the configured limit',
          id: _recoverDirectJsonRequestId(rawMessage),
          protocolVersion: effectiveResponseMcpProtocolVersion,
          extraHeaders: corsHeaders,
        ),
      );
      return;
    }
    final rejectedNewInitialize =
        tentativeInitializeSessionId != null &&
        response is Map &&
        response['error'] is Map;
    final responseSessionId = rejectedNewInitialize
        ? null
        : effectiveMcpSessionId;
    if (response != null &&
        _mcpPostResponsesUseSse(
          binding,
          request,
          route,
          isInitialize: isInitialize,
          sessionId: effectiveMcpSessionId,
        )) {
      final responseBatch = endpoint.ssePostResponseEvents(
        sessionId: effectiveMcpSessionId!,
        responseJson: responseJson!,
      );
      final responseBody = _mcpSseEventsBytes(responseBatch.events);
      if (responseBody.length > _mcpMaxResponseBytesForRoute(route)) {
        endpoint.restoreSsePollBatch(responseBatch);
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: _mcpJsonRpcHttpError(
            status: HttpStatus.internalServerError,
            code: mcp.McpErrorCodes.internalError,
            message: 'MCP response body exceeds the configured limit',
            id: _recoverDirectJsonRequestId(rawMessage),
            protocolVersion: effectiveResponseMcpProtocolVersion,
            extraHeaders: corsHeaders,
          ),
        );
        return;
      }
      final sent = await _mcpSendSseResponse(
        binding,
        request: request,
        handshake: handshake,
        sessionId: effectiveMcpSessionId,
        body: responseBody,
        protocolVersion: effectiveResponseMcpProtocolVersion,
        extraHeaders: corsHeaders,
      );
      if (sent) {
        endpoint.commitSsePollBatch(responseBatch);
        return;
      }
      endpoint.restoreSsePollBatch(responseBatch);
    }
    final responseErrorCode = response is Map && response['error'] is Map
        ? (response['error'] as Map)['code']
        : null;
    final responseStatus = !statelessHttpRequest
        ? HttpStatus.ok
        : switch (responseErrorCode) {
            mcp.McpErrorCodes.methodNotFound => HttpStatus.notFound,
            mcp.McpErrorCodes.missingRequiredClientCapability =>
              HttpStatus.badRequest,
            _ => HttpStatus.ok,
          };
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: response == null
          ? NativeHttpResponse(
              status: HttpStatus.accepted,
              headers: _mcpHttpResponseHeaders(
                json: false,
                sessionId: responseSessionId,
                protocolVersion: effectiveResponseMcpProtocolVersion,
                extra: corsHeaders,
              ),
              body: NativeHttpResponseText(''),
            )
          : NativeHttpResponse(
              status: responseStatus,
              headers: _mcpHttpResponseHeaders(
                sessionId: responseSessionId,
                protocolVersion: effectiveResponseMcpProtocolVersion,
                extra: corsHeaders,
              ),
              body: NativeHttpResponseBytes(responseBytes!),
            ),
    );
    if (tentativeInitializeSessionId != null) {
      retainTentativeInitializeEndpoint = !rejectedNewInitialize;
    }
  } finally {
    try {
      endpoint._endSessionRequest(
        sessionRequestAcquired,
        refreshIdleDeadline: refreshIdleDeadline,
      );
    } finally {
      if (tentativeInitializeSessionId != null &&
          !retainTentativeInitializeEndpoint) {
        await binding._removeMcpEndpointForRoute(
          request: request,
          route: route,
          session: session,
          mcpSessionId: tentativeInitializeSessionId,
        );
      }
    }
  }
}

extension _RouterBindingMcp on RouterBinding {
  String _mcpEndpointKeyForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
    String? mcpSessionId,
  }) {
    final routeKey = route.match.path ?? route.match.prefix ?? request.path;
    return [
      request.listenerId,
      routeKey,
      session.cacheKey ?? session.realmUri,
      session.sessionId,
      mcpSessionId ?? 'legacy',
    ].join(':');
  }

  void _expireIdleMcpEndpoints() {
    final expiredEndpoints = <_RouterMcpEndpoint>[];
    _mcpEndpoints.removeWhere((_, endpoint) {
      if (!endpoint.sessionIdleExpired) {
        return false;
      }
      expiredEndpoints.add(endpoint);
      return true;
    });
    for (final endpoint in expiredEndpoints) {
      unawaited(endpoint.dispose());
    }
  }

  void _expireMcpEndpointIfIdle({
    required String endpointKey,
    required _RouterMcpEndpoint endpoint,
  }) {
    if (!identical(_mcpEndpoints[endpointKey], endpoint)) {
      return;
    }
    if (!endpoint.sessionIdleExpired) {
      // A Timer may wake slightly before the Stopwatch reaches the deadline.
      // Preserve the original idle interval and schedule the remaining delay
      // instead of silently losing proactive expiry.
      endpoint._armSessionIdleDeadline(resetStopwatch: false);
      return;
    }
    _mcpEndpoints.remove(endpointKey);
    unawaited(endpoint.dispose());
  }

  _RouterMcpEndpoint? _mcpEndpointForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
    String? mcpSessionId,
    bool create = true,
  }) {
    _expireIdleMcpEndpoints();
    final key = _mcpEndpointKeyForRoute(
      request: request,
      route: route,
      session: session,
      mcpSessionId: mcpSessionId,
    );
    final existing = _mcpEndpoints[key];
    if (existing != null) {
      return existing;
    }
    if (!create) {
      return null;
    }
    if (mcpSessionId != null) {
      final activeSessionCount = _mcpEndpoints.values
          .where(
            (endpoint) =>
                endpoint.mcpSessionId != null &&
                endpoint.listenerId == request.listenerId &&
                identical(endpoint.route, route),
          )
          .length;
      if (activeSessionCount >= _mcpMaxSessionCountForRoute(route)) {
        throw const _McpSessionCapacityExceeded();
      }
    }
    final endpoint = _RouterMcpEndpoint(
      binding: this,
      endpointKey: key,
      listenerId: request.listenerId,
      route: route,
      session: session,
      mcpSessionId: mcpSessionId,
      sessionIdleTimeout: _mcpSessionIdleTimeoutForRoute(route),
    );
    _mcpEndpoints[key] = endpoint;
    return endpoint;
  }

  void _reserveMcpRequestScopedListener(_RouterMcpEndpoint target) {
    final admittedListenerCount = _mcpEndpoints.values
        .where(
          (endpoint) =>
              endpoint.listenerId == target.listenerId &&
              identical(endpoint.route, target.route),
        )
        .fold<int>(
          0,
          (count, endpoint) =>
              count +
              endpoint._modernSubscriptionPreparationCount +
              endpoint._modernSubscriptions.length,
        );
    if (admittedListenerCount >=
        _mcpMaxRequestScopedListenerCountForRoute(target.route)) {
      throw const _McpRequestScopedListenerCapacityExceeded();
    }
    target._modernSubscriptionPreparationCount++;
  }

  void _reserveMcpWampSubscription(_RouterMcpEndpoint target) {
    final admittedSubscriptionCount = _mcpEndpoints.values
        .where(
          (endpoint) =>
              endpoint.listenerId == target.listenerId &&
              identical(endpoint.route, target.route),
        )
        .fold<int>(
          0,
          (count, endpoint) =>
              count +
              endpoint._wampSubscriptionPreparationCount +
              endpoint._wampSubscriptions.length,
        );
    if (admittedSubscriptionCount >=
        _mcpMaxWampSubscriptionCountForRoute(target.route)) {
      throw const _McpWampSubscriptionCapacityExceeded();
    }
    target._wampSubscriptionPreparationCount++;
  }

  Future<_RouterMcpEndpoint?> _removeMcpEndpointForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
    required String mcpSessionId,
  }) async {
    _expireIdleMcpEndpoints();
    final endpoint = _mcpEndpoints.remove(
      _mcpEndpointKeyForRoute(
        request: request,
        route: route,
        session: session,
        mcpSessionId: mcpSessionId,
      ),
    );
    await endpoint?.dispose();
    return endpoint;
  }
}

final class _RouterMcpSseEvent {
  const _RouterMcpSseEvent({
    required this.id,
    required this.streamId,
    required this.sequence,
    required this.data,
    this.retryMs,
  });

  final String id;
  final String streamId;
  final int sequence;
  final String data;
  final int? retryMs;

  int get encodedByteLength =>
      _mcpSseEventBytes(id: id, data: data, retryMs: retryMs).length;
}

final class _RouterMcpSsePollBatch {
  const _RouterMcpSsePollBatch({
    required this.events,
    required this.newEvents,
    required this.pendingMessages,
    required this.previousStreamSequences,
    required this.reservedStreamSequences,
  });

  final List<_RouterMcpSseEvent> events;
  final List<_RouterMcpSseEvent> newEvents;
  final List<mcp.JsonMap> pendingMessages;
  final Map<String, int?> previousStreamSequences;
  final Map<String, int> reservedStreamSequences;
}

final class _McpSessionCapacityExceeded implements Exception {
  const _McpSessionCapacityExceeded();
}

final class _McpRequestScopedListenerCapacityExceeded implements Exception {
  const _McpRequestScopedListenerCapacityExceeded();
}

final class _McpWampSubscriptionCapacityExceeded implements Exception {
  const _McpWampSubscriptionCapacityExceeded();

  @override
  String toString() => 'MCP WAMP subscription capacity is exhausted';
}

final class _McpWampSubscriptionQueueLimitExceeded implements Exception {
  const _McpWampSubscriptionQueueLimitExceeded();

  @override
  String toString() =>
      'MCP WAMP subscription queue limit exceeds configured maximum';
}

final class _McpSsePollEventResponseLimitExceeded implements Exception {
  const _McpSsePollEventResponseLimitExceeded({
    required this.requiredBytes,
    required this.limit,
  });

  final int requiredBytes;
  final int limit;
}

final class _McpRequestScopedSseEventResponseLimitExceeded
    implements Exception {
  const _McpRequestScopedSseEventResponseLimitExceeded({
    required this.requiredBytes,
    required this.limit,
  });

  final int requiredBytes;
  final int limit;

  @override
  String toString() =>
      'MCP request-scoped SSE event requires $requiredBytes bytes, '
      'exceeding the configured $limit-byte response limit';
}

final class _UnknownMcpSseEventId implements Exception {
  const _UnknownMcpSseEventId(this.eventId);

  final String eventId;
}

class _RouterMcpSubscriptionFilter {
  _RouterMcpSubscriptionFilter({
    this.toolsListChanged = false,
    this.promptsListChanged = false,
    this.resourcesListChanged = false,
    Iterable<String> resourceSubscriptions = const <String>[],
  }) : resourceSubscriptions = List<String>.unmodifiable(resourceSubscriptions);

  final bool toolsListChanged;
  final bool promptsListChanged;
  final bool resourcesListChanged;
  List<String> resourceSubscriptions;

  mcp.JsonMap toJson() => <String, Object?>{
    if (toolsListChanged) 'toolsListChanged': true,
    if (promptsListChanged) 'promptsListChanged': true,
    if (resourcesListChanged) 'resourcesListChanged': true,
    if (resourceSubscriptions.isNotEmpty)
      'resourceSubscriptions': <String>[...resourceSubscriptions],
  };

  void retainResourceSubscriptions(Set<String> retainedResourceUris) {
    final retained = <String>[
      for (final uri in resourceSubscriptions)
        if (retainedResourceUris.contains(uri)) uri,
    ];
    if (retained.length == resourceSubscriptions.length) {
      return;
    }
    resourceSubscriptions = List<String>.unmodifiable(retained);
  }

  bool allows(String method, mcp.JsonMap params) {
    switch (method) {
      case 'notifications/tools/list_changed':
        return toolsListChanged;
      case 'notifications/prompts/list_changed':
        return promptsListChanged;
      case 'notifications/resources/list_changed':
        return resourcesListChanged;
      case 'notifications/resources/updated':
        final uri = params['uri'];
        return uri is String && resourceSubscriptions.contains(uri);
      default:
        return false;
    }
  }
}

class _RouterMcpModernSubscriptionPreparation {
  _RouterMcpModernSubscriptionPreparation({
    required this.requestId,
    required this.notifications,
    required this.acknowledgmentBytes,
  });

  final Object requestId;
  final _RouterMcpSubscriptionFilter notifications;
  final Uint8List acknowledgmentBytes;
  bool released = false;
}

class _RouterMcpModernSubscription {
  _RouterMcpModernSubscription({
    required this.token,
    required this.requestId,
    required this.notifications,
    required this.stream,
  });

  final int token;
  final Object requestId;
  final _RouterMcpSubscriptionFilter notifications;
  final NativeHttpResponseStream stream;
  Timer? heartbeat;
}

final class _McpAuthorizationCheckFailed implements Exception {
  const _McpAuthorizationCheckFailed(this.errorType);

  final String errorType;

  @override
  String toString() => 'MCP authorization check failed';
}

class _RouterMcpEndpoint {
  _RouterMcpEndpoint({
    required this.binding,
    required this.endpointKey,
    required this.listenerId,
    required this.route,
    required this.session,
    required this.mcpSessionId,
    required this.sessionIdleTimeout,
  }) {
    final options = route.action.options;
    final resourceSubscriptionsEnabled = _hasConfiguredResourceSubscriptions(
      options,
    );
    server = mcp.McpServer(
      serverInfo: _mcpServerInfoForOptions(options),
      resources: _configuredResources(
        options,
        procedureReader: _readConfiguredResource,
      ),
      resourceTemplates: _configuredResourceTemplates(options),
      prompts: _configuredPrompts(options),
      instructions: _mcpInstructionsForOptions(options),
      onSubscribeResource: resourceSubscriptionsEnabled
          ? _subscribeResource
          : null,
      onUnsubscribeResource: resourceSubscriptionsEnabled
          ? _unsubscribeResource
          : null,
      toolListPageSize: _intOptionAny(options, const [
        'tool_list_page_size',
        'toolListPageSize',
      ]),
      promptListPageSize: _intOptionAny(options, const [
        'prompt_list_page_size',
        'promptListPageSize',
      ]),
      resourceListPageSize: _intOptionAny(options, const [
        'resource_list_page_size',
        'resourceListPageSize',
      ]),
      resourceTemplateListPageSize: _intOptionAny(options, const [
        'resource_template_list_page_size',
        'resourceTemplateListPageSize',
      ]),
      capabilities: _mcpServerCapabilitiesForOptions(options),
    );
    _armSessionIdleDeadline();
  }

  final RouterBinding binding;
  final String endpointKey;
  final int listenerId;
  final HttpRouteSettings route;
  final RouterSession session;
  final String? mcpSessionId;
  final Duration? sessionIdleTimeout;
  final Stopwatch _sessionIdleStopwatch = Stopwatch()..start();
  Timer? _sessionIdleTimer;
  int _activeSessionRequests = 0;
  bool _refreshIdleDeadlineAfterRequests = false;
  Future<void>? _disposeFuture;
  late final mcp.McpServer server;
  late final RealmAuthorizationProviderCache _authorizationProviderCache =
      RealmAuthorizationProviderCache(binding.settings);
  String? _toolSignature;
  String? _wampApiSignature;
  String? _resourceSignature;
  final mcp.McpWampPubSubState _wampPubSubState = mcp.McpWampPubSubState();
  Future<void> _catalogRefreshTail = Future<void>.value();
  final List<_RouterMcpSseEvent> _sseHistory = <_RouterMcpSseEvent>[];
  int _sseHistoryBytes = 0;
  final List<mcp.JsonMap> _pendingSseMessages = <mcp.JsonMap>[];
  final Set<String> _pendingOrInFlightSseNotificationKeys = <String>{};
  final Map<String, int> _sseStreamSequences = <String, int>{};
  final Set<mcp.McpWampSubscription> _wampSubscriptions =
      <mcp.McpWampSubscription>{};
  int _wampSubscriptionPreparationCount = 0;
  int _nextSseStream = 0;
  int _nextModernSubscription = 0;

  final Map<int, _RouterMcpModernSubscription> _modernSubscriptions =
      <int, _RouterMcpModernSubscription>{};
  int _modernSubscriptionPreparationCount = 0;
  final Map<String, Future<mcp.McpWampSubscription>>
  _sharedResourceUpdateSubscriptions =
      <String, Future<mcp.McpWampSubscription>>{};
  final Map<String, int> _modernResourcePreparationCounts = <String, int>{};

  final Set<String> _streamableResourceSubscriptions = <String>{};

  bool get sessionIdleExpired {
    final timeout = sessionIdleTimeout;
    return mcpSessionId != null &&
        timeout != null &&
        _activeSessionRequests == 0 &&
        _sessionIdleStopwatch.elapsed >= timeout;
  }

  void _armSessionIdleDeadline({bool resetStopwatch = true}) {
    final timeout = sessionIdleTimeout;
    if (mcpSessionId == null ||
        timeout == null ||
        _activeSessionRequests != 0 ||
        _disposeFuture != null) {
      return;
    }
    if (resetStopwatch) {
      _sessionIdleStopwatch.reset();
    }
    final remaining = timeout - _sessionIdleStopwatch.elapsed;
    _sessionIdleTimer?.cancel();
    _sessionIdleTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        _sessionIdleTimer = null;
        binding._expireMcpEndpointIfIdle(
          endpointKey: endpointKey,
          endpoint: this,
        );
      },
    );
  }

  bool _beginSessionRequest() {
    if (mcpSessionId == null ||
        sessionIdleTimeout == null ||
        _disposeFuture != null) {
      return false;
    }
    _activeSessionRequests++;
    _sessionIdleTimer?.cancel();
    _sessionIdleTimer = null;
    return true;
  }

  void _endSessionRequest(bool acquired, {bool refreshIdleDeadline = true}) {
    if (!acquired) {
      return;
    }
    assert(_activeSessionRequests > 0);
    // One accepted request makes the concurrent group active, but the new
    // idle interval starts only after every request hold has been released.
    _refreshIdleDeadlineAfterRequests |= refreshIdleDeadline;
    _activeSessionRequests--;
    if (_activeSessionRequests == 0) {
      final resetStopwatch = _refreshIdleDeadlineAfterRequests;
      _refreshIdleDeadlineAfterRequests = false;
      _armSessionIdleDeadline(resetStopwatch: resetStopwatch);
    }
  }

  bool ownsSession(RouterSession candidate) => identical(candidate, session);

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _sessionIdleTimer?.cancel();
    _sessionIdleTimer = null;
    _sessionIdleStopwatch.stop();
    server.shutdown();

    final modernSubscriptionTokens = _modernSubscriptions.keys.toList(
      growable: false,
    );
    for (final token in modernSubscriptionTokens) {
      await _closeModernSubscription(token, graceful: true);
    }

    final resourceSubscriptions = _sharedResourceUpdateSubscriptions.values
        .toList(growable: false);
    _sharedResourceUpdateSubscriptions.clear();
    _streamableResourceSubscriptions.clear();
    _modernResourcePreparationCounts.clear();
    for (final subscriptionFuture in resourceSubscriptions) {
      try {
        await _releaseWampSubscription(await subscriptionFuture);
      } catch (_) {
        // Best-effort cleanup during endpoint disposal.
      }
    }

    final subscriptions = _wampSubscriptions.toList(growable: false);
    _wampSubscriptions.clear();
    for (final subscription in subscriptions) {
      try {
        await _releaseWampSubscription(subscription);
      } catch (_) {
        // Best-effort cleanup during endpoint disposal.
      }
    }
  }

  Future<Object?> _handleMessageAfterRefresh(
    Object? rawMessage, {
    required bool resourceSubscriptionsAllowed,
  }) async {
    if (rawMessage is List) {
      return _handleBatchMessage(
        rawMessage,
        resourceSubscriptionsAllowed: resourceSubscriptionsAllowed,
      );
    }
    return _handleSingleMessage(
      rawMessage,
      resourceSubscriptionsAllowed: resourceSubscriptionsAllowed,
    );
  }

  Object? modernizeResponse(Object? response) {
    if (response is! Map || response['result'] is! Map) {
      return response;
    }
    final result = <String, Object?>{
      for (final entry in (response['result'] as Map).entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final rawMetadata = result['_meta'];
    final metadata = <String, Object?>{
      if (rawMetadata is Map)
        for (final entry in rawMetadata.entries)
          if (entry.key is String) entry.key as String: entry.value,
      'io.modelcontextprotocol/serverInfo': server.serverInfo.toJson(),
    };
    return <String, Object?>{
      for (final entry in response.entries)
        if (entry.key is String) entry.key as String: entry.value,
      'result': <String, Object?>{
        ...result,
        'resultType': result['resultType'] ?? 'complete',
        '_meta': metadata,
      },
    };
  }

  Future<Object?> _handleBatchMessage(
    List<Object?> rawMessages, {
    required bool resourceSubscriptionsAllowed,
  }) async {
    if (rawMessages.isEmpty) {
      return mcp.JsonRpcResponse.error(
        null,
        mcp.McpException(
          mcp.McpErrorCodes.invalidRequest,
          'JSON-RPC batch must not be empty',
        ),
      ).toJson();
    }
    final duplicateRequestId = _mcpDuplicateJsonRpcBatchRequestId(rawMessages);
    if (duplicateRequestId != null) {
      return mcp.JsonRpcResponse.error(
        null,
        mcp.McpException(
          mcp.McpErrorCodes.invalidRequest,
          'JSON-RPC batch contained duplicate request id $duplicateRequestId',
        ),
      ).toJson();
    }
    final responses = <Object?>[];
    for (final rawMessage in rawMessages) {
      final response = await _handleSingleMessage(
        rawMessage,
        resourceSubscriptionsAllowed: resourceSubscriptionsAllowed,
      );
      if (response != null) {
        if (response is List) {
          responses.addAll(response);
        } else {
          responses.add(response);
        }
      }
    }
    return responses.isEmpty ? null : responses;
  }

  Future<Object?> _handleSingleMessage(
    Object? rawMessage, {
    required bool resourceSubscriptionsAllowed,
  }) async {
    if (rawMessage is List) {
      return mcp.JsonRpcResponse.error(
        null,
        mcp.McpException(
          mcp.McpErrorCodes.invalidRequest,
          'JSON-RPC batch entries must be request objects',
        ),
      ).toJson();
    }
    final method = _mcpRequestMethod(rawMessage);
    if (method == 'resources/subscribe' || method == 'resources/unsubscribe') {
      if (!resourceSubscriptionsAllowed) {
        if (rawMessage is Map && !rawMessage.containsKey('id')) {
          return null;
        }
        return mcp.JsonRpcResponse.error(
          _recoverDirectJsonRequestId(rawMessage),
          mcp.McpException(
            mcp.McpErrorCodes.invalidRequest,
            '$method requires a Streamable HTTP session',
          ),
        ).toJson();
      }
      return server.handleMessage(rawMessage);
    }
    final directResponse = await _handleDirectJsonMessage(rawMessage);
    if (directResponse != null) {
      return directResponse.response;
    }
    return server.handleMessage(rawMessage);
  }

  void _validateSseLastEventId(String? lastEventId) {
    if (lastEventId == null || lastEventId.isEmpty) {
      return;
    }
    if (!_sseHistory.any((event) => event.id == lastEventId)) {
      throw _UnknownMcpSseEventId(lastEventId);
    }
  }

  _RouterMcpSsePollBatch ssePollEvents({
    required String sessionId,
    required int maxResponseBytes,
    String? lastEventId,
  }) {
    var streamId = 's${++_nextSseStream}';
    final replay = <_RouterMcpSseEvent>[];
    if (lastEventId != null && lastEventId.isNotEmpty) {
      final lastEvent = _sseHistory
          .where((event) => event.id == lastEventId)
          .firstOrNull;
      if (lastEvent == null) {
        throw _UnknownMcpSseEventId(lastEventId);
      }
      streamId = lastEvent.streamId;
      replay.addAll(
        _sseHistory.where(
          (event) =>
              event.streamId == streamId && event.sequence > lastEvent.sequence,
        ),
      );
    }
    final previousStreamSequence = _sseStreamSequences[streamId];

    int eventByteLength(_RouterMcpSseEvent event) {
      return _mcpSseEventBytes(
        id: event.id,
        data: event.data,
        retryMs: event.retryMs,
      ).length;
    }

    final events = <_RouterMcpSseEvent>[];
    final newEvents = <_RouterMcpSseEvent>[];
    final pendingMessages = <mcp.JsonMap>[];
    var responseByteLength = 0;
    var replayTruncated = false;
    for (final event in replay) {
      final candidateByteLength = eventByteLength(event);
      if (responseByteLength + candidateByteLength > maxResponseBytes) {
        if (events.isEmpty) {
          throw _McpSsePollEventResponseLimitExceeded(
            requiredBytes: candidateByteLength,
            limit: maxResponseBytes,
          );
        }
        replayTruncated = true;
        break;
      }
      events.add(event);
      responseByteLength += candidateByteLength;
    }
    var responseHasRetry = events.any((event) => event.retryMs != null);

    if (!replayTruncated) {
      for (final message in _pendingSseMessages) {
        final sequence = (_sseStreamSequences[streamId] ?? 0) + 1;
        final event = _RouterMcpSseEvent(
          id: '$sessionId:$streamId:$sequence',
          streamId: streamId,
          sequence: sequence,
          data: jsonEncode(message),
          retryMs: responseHasRetry ? null : 1000,
        );
        final candidateByteLength = eventByteLength(event);
        if (responseByteLength + candidateByteLength > maxResponseBytes) {
          if (events.isEmpty) {
            final oversizedMessage = _pendingSseMessages.removeAt(0);
            _pendingOrInFlightSseNotificationKeys.remove(
              jsonEncode(oversizedMessage),
            );
            throw _McpSsePollEventResponseLimitExceeded(
              requiredBytes: candidateByteLength,
              limit: maxResponseBytes,
            );
          }
          break;
        }
        _sseStreamSequences[streamId] = sequence;
        events.add(event);
        newEvents.add(event);
        pendingMessages.add(message);
        responseByteLength += candidateByteLength;
        responseHasRetry = responseHasRetry || event.retryMs != null;
      }
      if (pendingMessages.isNotEmpty) {
        _pendingSseMessages.removeRange(0, pendingMessages.length);
      }
    }

    if (events.isEmpty) {
      final sequence = (_sseStreamSequences[streamId] ?? 0) + 1;
      final event = _RouterMcpSseEvent(
        id: '$sessionId:$streamId:$sequence',
        streamId: streamId,
        sequence: sequence,
        data: '',
        retryMs: 1000,
      );
      final candidateByteLength = eventByteLength(event);
      if (candidateByteLength > maxResponseBytes) {
        throw _McpSsePollEventResponseLimitExceeded(
          requiredBytes: candidateByteLength,
          limit: maxResponseBytes,
        );
      }
      _sseStreamSequences[streamId] = sequence;
      events.add(event);
      newEvents.add(event);
    }

    return _RouterMcpSsePollBatch(
      events: events,
      newEvents: newEvents,
      pendingMessages: pendingMessages,
      previousStreamSequences: newEvents.isEmpty
          ? const <String, int?>{}
          : <String, int?>{streamId: previousStreamSequence},
      reservedStreamSequences: newEvents.isEmpty
          ? const <String, int>{}
          : <String, int>{streamId: _sseStreamSequences[streamId]!},
    );
  }

  _RouterMcpSsePollBatch ssePostResponseEvents({
    required String sessionId,
    required String responseJson,
  }) {
    final streamId = 's${++_nextSseStream}';
    final previousStreamSequence = _sseStreamSequences[streamId];
    final primer = _nextSseEvent(
      sessionId: sessionId,
      streamId: streamId,
      retryMs: 1000,
    );
    final responseEvent = _nextSseEvent(
      sessionId: sessionId,
      streamId: streamId,
      data: responseJson,
    );
    return _RouterMcpSsePollBatch(
      events: <_RouterMcpSseEvent>[primer, responseEvent],
      newEvents: <_RouterMcpSseEvent>[primer, responseEvent],
      pendingMessages: const <mcp.JsonMap>[],
      previousStreamSequences: <String, int?>{streamId: previousStreamSequence},
      reservedStreamSequences: <String, int>{
        streamId: _sseStreamSequences[streamId]!,
      },
    );
  }

  void commitSsePollBatch(_RouterMcpSsePollBatch batch) {
    for (final message in batch.pendingMessages) {
      _pendingOrInFlightSseNotificationKeys.remove(jsonEncode(message));
    }
    for (final event in batch.newEvents) {
      _rememberSseEvent(event);
    }
  }

  void restoreSsePollBatch(_RouterMcpSsePollBatch batch) {
    _restoreMcpSseSequenceReservations(
      streamSequences: _sseStreamSequences,
      previousSequences: batch.previousStreamSequences,
      reservedSequences: batch.reservedStreamSequences,
    );
    if (batch.pendingMessages.isNotEmpty) {
      _pendingSseMessages.insertAll(0, batch.pendingMessages);
    }
  }

  _RouterMcpSseEvent _nextSseEvent({
    required String sessionId,
    required String streamId,
    String data = '',
    int? retryMs,
  }) {
    final sequence = (_sseStreamSequences[streamId] ?? 0) + 1;
    _sseStreamSequences[streamId] = sequence;
    return _RouterMcpSseEvent(
      id: '$sessionId:$streamId:$sequence',
      streamId: streamId,
      sequence: sequence,
      data: data,
      retryMs: retryMs,
    );
  }

  void _rememberSseEvent(_RouterMcpSseEvent event) {
    _sseHistory.add(event);
    _sseHistoryBytes += event.encodedByteLength;
    final maxHistoryBytes = _mcpMaxSseHistoryBytesForRoute(route);
    while (_sseHistory.length > _mcpSseEventHistoryLimit ||
        _sseHistoryBytes > maxHistoryBytes) {
      final removed = _sseHistory.removeAt(0);
      _sseHistoryBytes -= removed.encodedByteLength;
      if (!_sseHistory.any((event) => event.streamId == removed.streamId)) {
        _sseStreamSequences.remove(removed.streamId);
      }
    }
  }

  void _enqueueServerNotification(String method, {mcp.JsonMap? params}) {
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      if (params != null && params.isNotEmpty) 'params': params,
    };
    final notificationKey = jsonEncode(message);
    if (!_pendingOrInFlightSseNotificationKeys.add(notificationKey)) {
      return;
    }
    _pendingSseMessages.add(message);
  }

  void _enqueueResourceUpdatedNotification(String uri) {
    _enqueueServerNotification(
      'notifications/resources/updated',
      params: <String, Object?>{'uri': uri},
    );
  }

  Future<_RouterMcpModernSubscriptionPreparation> prepareModernSubscription(
    Object? rawMessage,
  ) async {
    final request = _directJsonRequestFrom(rawMessage);
    if (request.method != 'subscriptions/listen' || request.isNotification) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidRequest,
        'subscriptions/listen must be a JSON-RPC request with an id',
      );
    }
    final requestId = request.id!;
    final requested = _modernSubscriptionFilterFrom(
      request.params['notifications'],
    );
    final grantedResources = <String>[];
    binding._reserveMcpRequestScopedListener(this);
    try {
      for (final uri in requested.resourceSubscriptions) {
        if (server.resources[uri] == null) {
          continue;
        }
        final config = _configuredResourceForUri(route.action.options, uri);
        if (config == null) {
          continue;
        }
        final updateTopic = _configuredResourceUpdateTopic(config);
        if (updateTopic == null ||
            !await _isAuthorized(AuthorizationAction.subscribe, updateTopic)) {
          continue;
        }
        await _ensureResourceUpdateSubscription(uri, updateTopic);
        _modernResourcePreparationCounts.update(
          uri,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        grantedResources.add(uri);
      }
    } catch (_) {
      _releaseModernSubscriptionCapacity();
      for (final uri in grantedResources) {
        final count = _modernResourcePreparationCounts[uri];
        if (count == null || count <= 1) {
          _modernResourcePreparationCounts.remove(uri);
        } else {
          _modernResourcePreparationCounts[uri] = count - 1;
        }
      }
      await _cleanupUnusedResourceSubscriptions();
      rethrow;
    }
    final notifications = _RouterMcpSubscriptionFilter(
      toolsListChanged: requested.toolsListChanged,
      resourcesListChanged:
          requested.resourcesListChanged &&
          _hasConfiguredDynamicResources(route.action.options),
      resourceSubscriptions: grantedResources,
    );
    return _RouterMcpModernSubscriptionPreparation(
      requestId: requestId,
      notifications: notifications,
      acknowledgmentBytes: _mcpRequestScopedSseMessageBytes(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/subscriptions/acknowledged',
        'params': <String, Object?>{
          '_meta': <String, Object?>{
            'io.modelcontextprotocol/subscriptionId': requestId,
          },
          'notifications': notifications.toJson(),
        },
      }),
    );
  }

  _RouterMcpSubscriptionFilter _modernSubscriptionFilterFrom(Object? value) {
    if (value is! Map) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'subscriptions/listen.params.notifications must be an object',
      );
    }
    final notifications = mcp.jsonMapFrom(
      value,
      label: 'subscriptions/listen.params.notifications',
    );

    bool requested(String field) {
      final value = notifications[field];
      if (value == null) {
        return false;
      }
      if (value is! bool) {
        throw mcp.McpException(
          mcp.McpErrorCodes.invalidParams,
          'subscriptions/listen notification filter $field must be a boolean',
        );
      }
      return value;
    }

    final rawResources = notifications['resourceSubscriptions'];
    final resources = <String>[];
    if (rawResources != null) {
      if (rawResources is! List) {
        throw mcp.McpException(
          mcp.McpErrorCodes.invalidParams,
          'subscriptions/listen resourceSubscriptions must be a list',
        );
      }
      final seen = <String>{};
      for (final value in rawResources) {
        if (value is! String) {
          throw mcp.McpException(
            mcp.McpErrorCodes.invalidParams,
            'subscriptions/listen resourceSubscriptions must contain strings',
          );
        }
        final uri = _mcpValidatedResourceUri(
          value,
          'subscriptions/listen resourceSubscriptions entries',
        );
        if (!seen.add(uri)) {
          throw mcp.McpException(
            mcp.McpErrorCodes.invalidParams,
            'subscriptions/listen resourceSubscriptions must not contain '
            'duplicates',
          );
        }
        resources.add(uri);
      }
    }

    return _RouterMcpSubscriptionFilter(
      toolsListChanged: requested('toolsListChanged'),
      promptsListChanged: requested('promptsListChanged'),
      resourcesListChanged: requested('resourcesListChanged'),
      resourceSubscriptions: resources,
    );
  }

  Future<void> _ensureResourceUpdateSubscription(
    String uri,
    String topic,
  ) async {
    final existing = _sharedResourceUpdateSubscriptions[uri];
    if (existing != null) {
      await existing;
      return;
    }
    final subscriptionFuture = _subscribeAuthorized(
      mcp.McpWampSubscribeRequest(topic: topic, queueLimit: 1),
      (_) {
        _sendModernNotification(
          'notifications/resources/updated',
          params: <String, Object?>{'uri': uri},
        );
        if (_streamableResourceSubscriptions.contains(uri)) {
          _enqueueResourceUpdatedNotification(uri);
        }
      },
    );
    _sharedResourceUpdateSubscriptions[uri] = subscriptionFuture;
    try {
      await subscriptionFuture;
    } catch (_) {
      if (identical(
        _sharedResourceUpdateSubscriptions[uri],
        subscriptionFuture,
      )) {
        _sharedResourceUpdateSubscriptions.remove(uri);
      }
      rethrow;
    }
  }

  Future<bool> activateModernSubscription(
    _RouterMcpModernSubscriptionPreparation preparation,
    NativeHttpResponseStream stream,
  ) async {
    final token = ++_nextModernSubscription;
    final subscription = _RouterMcpModernSubscription(
      token: token,
      requestId: preparation.requestId,
      notifications: preparation.notifications,
      stream: stream,
    );
    _modernSubscriptions[token] = subscription;
    await _releaseModernSubscriptionPreparation(preparation);
    if (!_writeModernSubscriptionBytes(
      subscription,
      preparation.acknowledgmentBytes,
    )) {
      await _closeModernSubscription(token);
      return false;
    }
    subscription.heartbeat = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _sendModernHeartbeat(token),
    );
    return true;
  }

  void _releaseModernSubscriptionCapacity() {
    assert(_modernSubscriptionPreparationCount > 0);
    if (_modernSubscriptionPreparationCount > 0) {
      _modernSubscriptionPreparationCount--;
    }
  }

  Future<void> releaseModernSubscriptionPreparation(
    _RouterMcpModernSubscriptionPreparation preparation,
  ) async {
    await _releaseModernSubscriptionPreparation(preparation);
  }

  Future<void> _releaseModernSubscriptionPreparation(
    _RouterMcpModernSubscriptionPreparation preparation,
  ) async {
    if (preparation.released) {
      return;
    }
    preparation.released = true;
    _releaseModernSubscriptionCapacity();
    for (final uri in preparation.notifications.resourceSubscriptions) {
      final count = _modernResourcePreparationCounts[uri];
      if (count == null || count <= 1) {
        _modernResourcePreparationCounts.remove(uri);
      } else {
        _modernResourcePreparationCounts[uri] = count - 1;
      }
    }
    await _cleanupUnusedResourceSubscriptions();
  }

  void _sendModernHeartbeat(int token) {
    final subscription = _modernSubscriptions[token];
    if (subscription == null) {
      return;
    }
    try {
      subscription.stream.add(_mcpRequestScopedSseHeartbeatBytes());
    } catch (error, stackTrace) {
      _reportModernSubscriptionWriteError(error, stackTrace);
      unawaited(_closeModernSubscription(token));
    }
  }

  void _sendModernNotification(
    String method, {
    mcp.JsonMap params = const <String, Object?>{},
  }) {
    for (final subscription in _modernSubscriptions.values.toList(
      growable: false,
    )) {
      if (!subscription.notifications.allows(method, params)) {
        continue;
      }
      final rawMetadata = params['_meta'];
      final metadata = <String, Object?>{
        if (rawMetadata is Map)
          for (final entry in rawMetadata.entries)
            if (entry.key is String) entry.key as String: entry.value,
        'io.modelcontextprotocol/subscriptionId': subscription.requestId,
      };
      final message = <String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        'params': <String, Object?>{...params, '_meta': metadata},
      };
      if (!_writeModernSubscriptionMessage(subscription, message)) {
        unawaited(_closeModernSubscription(subscription.token));
      }
    }
  }

  bool _writeModernSubscriptionMessage(
    _RouterMcpModernSubscription subscription,
    Object? message,
  ) {
    try {
      return _writeModernSubscriptionBytes(
        subscription,
        _mcpRequestScopedSseMessageBytes(message),
      );
    } catch (error, stackTrace) {
      _reportModernSubscriptionWriteError(error, stackTrace);
      return false;
    }
  }

  bool _writeModernSubscriptionBytes(
    _RouterMcpModernSubscription subscription,
    Uint8List body,
  ) {
    try {
      final limit = _mcpMaxResponseBytesForRoute(route);
      if (body.length > limit) {
        throw _McpRequestScopedSseEventResponseLimitExceeded(
          requiredBytes: body.length,
          limit: limit,
        );
      }
      subscription.stream.add(body);
      return true;
    } catch (error, stackTrace) {
      _reportModernSubscriptionWriteError(error, stackTrace);
      return false;
    }
  }

  void _reportModernSubscriptionWriteError(
    Object error,
    StackTrace stackTrace,
  ) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_request_scoped_sse_write_error',
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }

  Future<void> _closeModernSubscription(
    int token, {
    bool graceful = false,
  }) async {
    final subscription = _modernSubscriptions.remove(token);
    if (subscription == null) {
      return;
    }
    subscription.heartbeat?.cancel();
    try {
      if (graceful && !subscription.stream.isClosed) {
        final body = _mcpRequestScopedSseMessageBytes(<String, Object?>{
          'jsonrpc': '2.0',
          'id': subscription.requestId,
          'result': <String, Object?>{
            'resultType': 'complete',
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/serverInfo': server.serverInfo.toJson(),
              'io.modelcontextprotocol/subscriptionId': subscription.requestId,
            },
          },
        });
        final limit = _mcpMaxResponseBytesForRoute(route);
        if (body.length > limit) {
          _reportModernSubscriptionWriteError(
            _McpRequestScopedSseEventResponseLimitExceeded(
              requiredBytes: body.length,
              limit: limit,
            ),
            StackTrace.current,
          );
          subscription.stream.close();
        } else {
          subscription.stream.close(body);
        }
      } else {
        subscription.stream.close();
      }
    } catch (error, stackTrace) {
      _reportModernSubscriptionWriteError(error, stackTrace);
    }
    await _cleanupUnusedResourceSubscriptions();
  }

  Future<void> _reconcileResourceSubscriptionAuthorization(
    Map<String, Future<bool>> authorizationDecisions,
    Set<String> visibleResourceUris,
  ) async {
    final ownedResourceUris = <String>{
      ..._streamableResourceSubscriptions,
      for (final subscription in _modernSubscriptions.values)
        ...subscription.notifications.resourceSubscriptions,
    };
    final authorizedResourceUris = <String>{};
    for (final uri in ownedResourceUris) {
      if (!visibleResourceUris.contains(uri)) {
        continue;
      }
      final config = _configuredResourceForUri(route.action.options, uri);
      final updateTopic = config == null
          ? null
          : _configuredResourceUpdateTopic(config);
      if (updateTopic != null &&
          await _isCatalogAuthorized(
            authorizationDecisions,
            AuthorizationAction.subscribe,
            updateTopic,
          )) {
        authorizedResourceUris.add(uri);
      }
    }

    _streamableResourceSubscriptions.removeWhere(
      (uri) => !authorizedResourceUris.contains(uri),
    );
    for (final subscription in _modernSubscriptions.values) {
      subscription.notifications.retainResourceSubscriptions(
        authorizedResourceUris,
      );
    }
    await _cleanupUnusedResourceSubscriptions();
  }

  Future<void> _cleanupUnusedResourceSubscriptions({
    bool bestEffort = true,
  }) async {
    final usedResources = <String>{
      ..._streamableResourceSubscriptions,
      for (final subscription in _modernSubscriptions.values)
        ...subscription.notifications.resourceSubscriptions,
      for (final entry in _modernResourcePreparationCounts.entries)
        if (entry.value > 0) entry.key,
    };
    final unusedResources = _sharedResourceUpdateSubscriptions.keys
        .where((uri) => !usedResources.contains(uri))
        .toList(growable: false);
    for (final uri in unusedResources) {
      final subscriptionFuture = _sharedResourceUpdateSubscriptions.remove(uri);
      if (subscriptionFuture == null) {
        continue;
      }
      try {
        await _releaseWampSubscription(await subscriptionFuture);
      } catch (_) {
        _sharedResourceUpdateSubscriptions.putIfAbsent(
          uri,
          () => subscriptionFuture,
        );
        if (!bestEffort) {
          rethrow;
        }
        // Best-effort cleanup after a resource subscription owner releases it.
      }
    }
  }

  Future<List<mcp.McpResourceContent>> _readConfiguredResource(
    Map<String, Object?> config,
    mcp.McpResourceRequest request,
  ) async {
    final procedure =
        _stringFrom(config['read_procedure']) ??
        _stringFrom(config['readProcedure']);
    if (procedure == null) {
      throw StateError(
        'MCP dynamic resource ${request.uri} has no read procedure',
      );
    }
    if (!await _isAuthorized(AuthorizationAction.call, procedure)) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidRequest,
        'Not authorized to read MCP resource ${request.uri}',
      );
    }
    final call = mcp.McpWampToolCall(
      procedure: procedure,
      request: mcp.McpToolRequest(
        name: 'resources/read',
        arguments: <String, Object?>{'uri': request.uri},
      ),
      payload: mcp.McpWampCallPayload(arguments: <Object?>[request.uri]),
    );
    final payload = await _callAuthorized(call);
    final body = <String, Object?>{};
    final arguments = payload.arguments;
    if (arguments != null) {
      body['arguments'] = mcp.mcpWampJsonCompatible(arguments);
    }
    final argumentsKeywords = payload.argumentsKeywords;
    if (argumentsKeywords != null) {
      body['argumentsKeywords'] = mcp.mcpWampJsonCompatible(argumentsKeywords);
    }
    final customDetails = payload.customDetails;
    if (customDetails != null) {
      body['details'] = mcp.mcpWampJsonCompatible(customDetails);
    }
    final mimeType =
        _stringFrom(config['mime_type']) ??
        _stringFrom(config['mimeType']) ??
        'application/json';
    return <mcp.McpResourceContent>[
      mcp.McpTextResourceContent(
        uri: request.uri,
        mimeType: mimeType,
        text: jsonEncode(body),
      ),
    ];
  }

  Future<void> _subscribeResource(mcp.McpResourceRequest request) async {
    final config = _configuredResourceForUri(route.action.options, request.uri);
    if (config == null || server.resources[request.uri] == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.resourceNotFound,
        'Resource not found',
        data: <String, Object?>{'uri': request.uri},
      );
    }
    final updateTopic = _configuredResourceUpdateTopic(config);
    if (updateTopic == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'MCP resource ${request.uri} does not support subscriptions',
      );
    }
    if (!await _isAuthorized(AuthorizationAction.subscribe, updateTopic)) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidRequest,
        'Not authorized to subscribe to MCP resource ${request.uri}',
      );
    }
    if (_streamableResourceSubscriptions.contains(request.uri)) {
      await _ensureResourceUpdateSubscription(request.uri, updateTopic);
      return;
    }

    _streamableResourceSubscriptions.add(request.uri);
    try {
      await _ensureResourceUpdateSubscription(request.uri, updateTopic);
    } catch (_) {
      _streamableResourceSubscriptions.remove(request.uri);
      await _cleanupUnusedResourceSubscriptions();
      rethrow;
    }
  }

  Future<void> _unsubscribeResource(mcp.McpResourceRequest request) async {
    if (!_streamableResourceSubscriptions.contains(request.uri)) {
      return;
    }
    final config = _configuredResourceForUri(route.action.options, request.uri);
    final updateTopic = config == null
        ? null
        : _configuredResourceUpdateTopic(config);
    if (updateTopic == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'MCP resource ${request.uri} does not support subscriptions',
      );
    }
    if (!await _isAuthorized(AuthorizationAction.unsubscribe, updateTopic)) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidRequest,
        'Not authorized to unsubscribe from MCP resource ${request.uri}',
      );
    }
    if (!_streamableResourceSubscriptions.remove(request.uri)) {
      return;
    }
    try {
      await _cleanupUnusedResourceSubscriptions(bestEffort: false);
    } catch (_) {
      _streamableResourceSubscriptions.add(request.uri);
      rethrow;
    }
  }

  Future<_DirectJsonMessageResponse?> _handleDirectJsonMessage(
    Object? rawMessage,
  ) async {
    if (rawMessage is! Map) {
      return null;
    }
    final rawMethod = rawMessage['method'];
    if (rawMethod is! String) {
      return null;
    }

    final isNotification = !rawMessage.containsKey('id');
    final recoveredId = _recoverDirectJsonRequestId(rawMessage);
    if (containsMcpWhitespaceOrControl(rawMethod)) {
      if (isNotification) {
        return const _DirectJsonMessageResponse(null);
      }
      return _DirectJsonMessageResponse(
        mcp.JsonRpcResponse.error(
          recoveredId,
          mcp.McpException(
            mcp.McpErrorCodes.invalidRequest,
            'JSON-RPC method must not contain whitespace or control characters',
          ),
        ).toJson(),
      );
    }
    if (!_isDirectJsonMethod(rawMethod)) {
      return null;
    }
    try {
      final request = _directJsonRequestFrom(rawMessage);
      final result = await _handleDirectJsonRequest(
        request.method,
        request.params,
      );
      return _DirectJsonMessageResponse(
        request.isNotification
            ? null
            : mcp.JsonRpcResponse.result(request.id, result).toJson(),
      );
    } on mcp.McpException catch (error) {
      if (isNotification) {
        return const _DirectJsonMessageResponse(null);
      }
      return _DirectJsonMessageResponse(
        mcp.JsonRpcResponse.error(recoveredId, error).toJson(),
      );
    } catch (error) {
      if (isNotification) {
        return const _DirectJsonMessageResponse(null);
      }
      return _DirectJsonMessageResponse(
        mcp.JsonRpcResponse.error(
          recoveredId,
          mcp.McpException(mcp.McpErrorCodes.internalError, error.toString()),
        ).toJson(),
      );
    }
  }

  bool _isDirectJsonMethod(String method) {
    return method == 'server/discover' ||
        method == 'ping' ||
        method == 'tools/list' ||
        method == 'tools/call' ||
        method == 'connectanum.tools.list' ||
        method == 'connectanum.tool.call' ||
        method == 'connectanum.tools.call' ||
        method == 'resources/list' ||
        method == 'resources/read' ||
        method == 'resources/templates/list' ||
        method == 'prompts/list' ||
        method == 'prompts/get' ||
        (method.contains('.') && server.tools[method] != null);
  }

  Future<mcp.JsonMap> _handleDirectJsonRequest(
    String method,
    mcp.JsonMap params,
  ) async {
    switch (method) {
      case 'server/discover':
        return <String, Object?>{
          'supportedVersions': <String>[mcp.mcpLatestStatelessProtocolVersion],
          'capabilities': server.capabilities.toJson(),
          if (server.instructions != null) 'instructions': server.instructions,
        };
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
      case 'connectanum.tools.list':
        return _listDirectJsonTools(method, params);
      case 'tools/call':
      case 'connectanum.tool.call':
      case 'connectanum.tools.call':
        return _callDirectJsonTool(method, params);
      case 'resources/list':
        return _listDirectJsonResources(params);
      case 'resources/read':
        return _readDirectJsonResource(params);
      case 'resources/templates/list':
        return _listDirectJsonResourceTemplates(params);
      case 'prompts/list':
        return _listDirectJsonPrompts(params);
      case 'prompts/get':
        return _getDirectJsonPrompt(params);
      default:
        final tool = server.tools[method];
        if (tool != null && method.contains('.')) {
          return _callDirectJsonToolByName(method, params);
        }
        throw mcp.McpException(
          mcp.McpErrorCodes.methodNotFound,
          'Unknown router JSON method: $method',
        );
    }
  }

  mcp.JsonMap _listDirectJsonTools(String method, mcp.JsonMap params) {
    final cursor = _mcpValidatedOptionalCursor(
      params['cursor'],
      '$method.params.cursor',
    );
    final page = server.tools.listPage(cursor: cursor);
    final result = <String, Object?>{
      'tools': [for (final tool in page.tools) tool.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<mcp.JsonMap> _callDirectJsonTool(
    String method,
    mcp.JsonMap params,
  ) async {
    final name = _mcpValidatedToolName(params['name'], '$method.params.name');
    final request = mcp.McpToolRequest.fromCallParams(
      name: name,
      params: params,
    );
    return _callDirectJsonToolByName(
      name,
      request.arguments,
      inputResponses: request.inputResponses,
      requestState: request.requestState,
      clientCapabilities: request.clientCapabilities,
    );
  }

  mcp.JsonMap _listDirectJsonResources(mcp.JsonMap params) {
    final cursor = _mcpValidatedOptionalCursor(
      params['cursor'],
      'resources/list.params.cursor',
    );
    final page = server.resources.listPage(cursor: cursor);
    final result = <String, Object?>{
      'resources': [for (final resource in page.resources) resource.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<mcp.JsonMap> _readDirectJsonResource(mcp.JsonMap params) async {
    final uri = _mcpValidatedResourceUri(
      params['uri'],
      'resources/read.params.uri',
    );
    final resource = server.resources[uri];
    if (resource == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.resourceNotFound,
        'Resource not found',
        data: <String, Object?>{'uri': uri},
      );
    }
    final contents = await resource.read(mcp.McpResourceRequest(uri: uri));
    return <String, Object?>{
      'contents': [for (final content in contents) content.toJson()],
    };
  }

  mcp.JsonMap _listDirectJsonResourceTemplates(mcp.JsonMap params) {
    final cursor = _mcpValidatedOptionalCursor(
      params['cursor'],
      'resources/templates/list.params.cursor',
    );
    final page = server.resources.listTemplatePage(cursor: cursor);
    final result = <String, Object?>{
      'resourceTemplates': [
        for (final template in page.templates) template.toJson(),
      ],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  mcp.JsonMap _listDirectJsonPrompts(mcp.JsonMap params) {
    final cursor = _mcpValidatedOptionalCursor(
      params['cursor'],
      'prompts/list.params.cursor',
    );
    final page = server.prompts.listPage(cursor: cursor);
    final result = <String, Object?>{
      'prompts': [for (final prompt in page.prompts) prompt.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<mcp.JsonMap> _getDirectJsonPrompt(mcp.JsonMap params) async {
    final name = _mcpValidatedPromptName(
      params['name'],
      'prompts/get.params.name',
    );
    final arguments = _directJsonPromptArgumentsFrom(params['arguments']);
    final prompt = server.prompts[name];
    if (prompt == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'Unknown MCP prompt: $name',
      );
    }
    prompt.validateArguments(arguments);
    final result = await prompt.handler(
      mcp.McpPromptRequest(name: name, arguments: arguments),
    );
    return result.toJson();
  }

  Map<String, String> _directJsonPromptArgumentsFrom(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    if (value is! Map) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'prompts/get.params.arguments must be an object',
      );
    }
    final arguments = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final argumentValue = entry.value;
      if (key is! String || argumentValue is! String) {
        throw mcp.McpException(
          mcp.McpErrorCodes.invalidParams,
          'prompts/get.params.arguments must contain only string values',
        );
      }
      arguments[key] = argumentValue;
    }
    return arguments;
  }

  Future<mcp.JsonMap> _callDirectJsonToolByName(
    String name,
    mcp.JsonMap arguments, {
    Map<String, mcp.JsonMap> inputResponses = const <String, mcp.JsonMap>{},
    String? requestState,
    mcp.JsonMap clientCapabilities = const <String, Object?>{},
  }) async {
    final tool = server.tools[name];
    if (tool == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'Unknown MCP tool: $name',
      );
    }
    final request = mcp.McpToolRequest(
      name: name,
      arguments: arguments,
      inputResponses: inputResponses,
      requestState: requestState,
      clientCapabilities: clientCapabilities,
    );
    try {
      final result = await tool.handler(request);
      return result.toJson(clientCapabilities: request.clientCapabilities);
    } on mcp.McpException {
      rethrow;
    } catch (error) {
      return mcp.McpToolResult.error(error.toString()).toJson();
    }
  }

  Future<void> _performCatalogRefresh() async {
    final authorizationDecisions = <String, Future<bool>>{};
    final api = await _buildApi(authorizationDecisions);
    final resources = await _visibleConfiguredResources(authorizationDecisions);
    final tools = api.toTools(
      call: _call,
      publish: _publish,
      subscribe: _subscribe,
      unsubscribe: _unsubscribe,
      includePubSubTools: _boolOptionAny(route.action.options, const [
        'include_pubsub_tools',
        'includePubsubTools',
      ], defaultValue: true),
      maxBufferedEventBytes: _mcpMaxWampSubscriptionQueueBytesForRoute(route),
      pubSubState: _wampPubSubState,
    );
    final toolSignature = jsonEncode([for (final tool in tools) tool.toJson()]);
    final resourceSignature = jsonEncode([
      for (final resource in resources) resource.toJson(),
    ]);
    final procedures = [...api.procedures]
      ..sort((left, right) => left.procedure.compareTo(right.procedure));
    final topics = [...api.topics]
      ..sort((left, right) => left.topic.compareTo(right.topic));
    final apiSignature = jsonEncode({
      'tools': toolSignature,
      if (api.name != null) 'name': api.name,
      if (api.metadata.isNotEmpty) 'metadata': api.metadata,
      'procedures': [for (final procedure in procedures) procedure.toJson()],
      'topics': [for (final topic in topics) topic.toJson()],
    });
    final apiChanged = apiSignature != _wampApiSignature;
    final resourcesChanged = resourceSignature != _resourceSignature;
    await _reconcileResourceSubscriptionAuthorization(authorizationDecisions, {
      for (final resource in resources) resource.uri,
    });
    if (!apiChanged && !resourcesChanged) {
      return;
    }
    if (apiChanged) {
      server.tools.replaceAll(tools);
      if (_toolSignature != null && toolSignature != _toolSignature) {
        if (server.state == mcp.McpServerState.initialized) {
          _enqueueServerNotification('notifications/tools/list_changed');
        }
        _sendModernNotification('notifications/tools/list_changed');
      }
      _toolSignature = toolSignature;
      _wampApiSignature = apiSignature;
    }
    if (resourcesChanged) {
      server.resources.replaceAll(resources);
      if (_resourceSignature != null) {
        if (server.state == mcp.McpServerState.initialized) {
          _enqueueServerNotification('notifications/resources/list_changed');
        }
        _sendModernNotification('notifications/resources/list_changed');
      }
      _resourceSignature = resourceSignature;
    }
  }

  Future<List<mcp.McpResource>> _visibleConfiguredResources(
    Map<String, Future<bool>> authorizationDecisions,
  ) async {
    final options = route.action.options;
    final visible = <mcp.McpResource>[];
    for (final resource in _configuredResources(
      options,
      procedureReader: _readConfiguredResource,
    )) {
      final config = _configuredResourceForUri(options, resource.uri);
      final readProcedure = config == null
          ? null
          : _stringFrom(config['read_procedure']) ??
                _stringFrom(config['readProcedure']);
      if (readProcedure == null ||
          await _isCatalogAuthorized(
            authorizationDecisions,
            AuthorizationAction.call,
            readProcedure,
          )) {
        visible.add(resource);
      }
    }
    return visible;
  }

  Future<bool> _isCatalogAuthorized(
    Map<String, Future<bool>> authorizationDecisions,
    AuthorizationAction action,
    String uri,
  ) {
    final key = '${action.name}\u0000$uri';
    return authorizationDecisions.putIfAbsent(
      key,
      () => _isAuthorized(action, uri),
    );
  }

  Future<void> _refreshTools() {
    final refresh = _catalogRefreshTail.then<void>(
      (_) => _performCatalogRefresh(),
      onError: (Object _, StackTrace _) => _performCatalogRefresh(),
    );
    _catalogRefreshTail = refresh;
    return refresh;
  }

  Future<mcp.McpWampApi> _buildApi(
    Map<String, Future<bool>> authorizationDecisions,
  ) async {
    final options = route.action.options;
    final procedures = <String, mcp.McpWampProcedure>{
      for (final procedure in _configuredProcedures(options))
        procedure.procedure: procedure,
    };
    final topics = <String, mcp.McpWampTopic>{
      for (final topic in _configuredTopics(options)) topic.topic: topic,
    };
    final includeRegistered = _boolOptionAny(options, const [
      'include_registered_procedures',
      'includeRegisteredProcedures',
    ], defaultValue: true);
    final includeSubscriptions = _boolOptionAny(options, const [
      'include_subscribed_topics',
      'includeSubscribedTopics',
    ], defaultValue: true);
    if (includeRegistered || includeSubscriptions) {
      final snapshot = await _snapshot();
      if (includeRegistered) {
        for (final registration in snapshot.registrations) {
          if (registration.matchPolicy != ProcedureMatchPolicy.exact) {
            continue;
          }
          final details = registration.callees.isEmpty
              ? const <String, Object?>{}
              : registration.callees.first.details;
          final metadata = _metadataFromDetails(details);
          procedures.putIfAbsent(
            registration.procedure,
            () => mcp.McpWampProcedure(
              procedure: registration.procedure,
              title: _stringFrom(details['title']),
              description:
                  _stringFrom(details['description']) ??
                  metadata?.description ??
                  metadata?.shortDescription,
              inputSchema:
                  _schemaFromDetails(details, 'input') ??
                  metadata?.inputJsonSchema,
              outputSchema:
                  _schemaFromDetails(details, 'output') ??
                  metadata?.outputJsonSchema,
              metadata: metadata,
              allowCall: _allowCallFrom(details),
            ),
          );
        }
      }
      if (includeSubscriptions) {
        for (final subscription in snapshot.subscriptions) {
          final details = subscription.options;
          final metadata = _metadataFromDetails(details);
          topics.putIfAbsent(
            subscription.topic,
            () => mcp.McpWampTopic(
              topic: subscription.topic,
              title: _stringFrom(details['title']),
              description:
                  _stringFrom(details['description']) ??
                  metadata?.description ??
                  metadata?.shortDescription,
              eventSchema:
                  _schemaFromDetails(details, 'event') ??
                  metadata?.outputJsonSchema,
              metadata: metadata,
            ),
          );
        }
      }
    }
    _addPublishedEventTopics(topics, procedures.values);

    final includeStandardMetaApi = _boolOptionAny(options, const [
      'include_standard_meta_api',
      'includeStandardMetaApi',
    ], defaultValue: true);
    if (includeStandardMetaApi) {
      for (final procedure in mcp.McpWampStandardMetaApi.procedures) {
        procedures.putIfAbsent(procedure.procedure, () => procedure);
      }
      for (final topic in mcp.McpWampStandardMetaApi.topics) {
        topics.putIfAbsent(topic.topic, () => topic);
      }
    }

    final filteredProcedures = <mcp.McpWampProcedure>[];
    for (final procedure in procedures.values) {
      final exposeStandardMetaProcedure =
          includeStandardMetaApi &&
          _isStandardMetaProcedure(procedure.procedure);
      if (exposeStandardMetaProcedure ||
          !procedure.allowCall ||
          await _isCatalogAuthorized(
            authorizationDecisions,
            AuthorizationAction.call,
            procedure.procedure,
          )) {
        filteredProcedures.add(procedure);
      }
    }

    final filteredTopics = <mcp.McpWampTopic>[];
    for (final topic in topics.values) {
      final allowPublish =
          topic.allowPublish &&
          await _isCatalogAuthorized(
            authorizationDecisions,
            AuthorizationAction.publish,
            topic.topic,
          );
      final allowSubscribe =
          topic.allowSubscribe &&
          await _isCatalogAuthorized(
            authorizationDecisions,
            AuthorizationAction.subscribe,
            topic.topic,
          );
      if (!allowPublish && !allowSubscribe) {
        continue;
      }
      filteredTopics.add(
        _topicWithPermissions(
          topic,
          allowPublish: allowPublish,
          allowSubscribe: allowSubscribe,
        ),
      );
    }

    return mcp.McpWampApi(
      name: _stringOptionAny(options, const ['name']) ?? 'connectanum-router',
      procedures: filteredProcedures,
      topics: filteredTopics,
      includeStandardMetaApi: false,
      includePublishedEventTopics: false,
      metadata: <String, Object?>{
        'realm': session.realmUri,
        'routerHosted': true,
        if (session.authId != null) 'authid': session.authId,
        if (session.authRole != null) 'authrole': session.authRole,
        if (session.authMethod != null) 'authmethod': session.authMethod,
      },
    );
  }

  Future<bool> _isAuthorized(AuthorizationAction action, String uri) async {
    final realmSettings = _realmSettings();
    if (realmSettings == null) {
      return false;
    }
    try {
      final provider = await _authorizationProviderCache.providerFor(
        realmSettings,
      );
      final decision = await RealmAuthorizer.authorize(
        realmSettings: realmSettings,
        provider: provider,
        request: AuthorizationRequest(
          realmUri: session.realmUri,
          action: action,
          uri: uri,
          sessionId: session.sessionId,
          connectionId: null,
          authId: session.authId,
          authRole: session.authRole,
          authMethod: session.authMethod,
          authProvider: session.authProvider,
          isInternal: session.authorizationIsInternal,
        ),
      );
      return decision.allowed;
    } catch (error) {
      final errorType = error.runtimeType.toString();
      binding.onEvent?.call({
        'source': 'binding',
        'type': 'mcp_authorization_error',
        'realm': session.realmUri,
        'action': action.name,
        'errorType': errorType,
      });
      throw _McpAuthorizationCheckFailed(errorType);
    }
  }

  RealmSettings? _realmSettings() {
    for (final realm in binding.settings.realms) {
      if (realm.name == session.realmUri) {
        return realm;
      }
    }
    return null;
  }

  int get _wampCallTimeoutMs {
    final routeTimeout = _intOptionAny(route.action.options, const <String>[
      'call_timeout_ms',
      'callTimeoutMs',
    ]);
    if (routeTimeout != null && routeTimeout > 0) {
      return routeTimeout;
    }
    final realmTimeout = _realmSettings()?.limits.callTimeoutMs;
    return realmTimeout != null && realmTimeout > 0
        ? realmTimeout
        : _mcpDefaultWampCallTimeoutMs;
  }

  call_msg.CallOptions _boundedCallOptions(call_msg.CallOptions? options) {
    final bounded = options ?? call_msg.CallOptions();
    final requestedTimeout = bounded.timeout;
    final timeoutMs = _wampCallTimeoutMs;
    if (requestedTimeout == null ||
        requestedTimeout <= 0 ||
        requestedTimeout > timeoutMs) {
      bounded.timeout = timeoutMs;
    }
    return bounded;
  }

  Future<ResultPayload> _call(mcp.McpWampToolCall call) async {
    final metaResult = await _handleMetaCall(call);
    if (metaResult != null) {
      return metaResult;
    }
    if (!await _isAuthorized(AuthorizationAction.call, call.procedure)) {
      throw StateError('Not authorized to call ${call.procedure}');
    }
    return _callSessionAuthorized(call);
  }

  Future<ResultPayload> _callAuthorized(mcp.McpWampToolCall call) async {
    final metaResult = await _handleMetaCall(call);
    if (metaResult != null) {
      return metaResult;
    }
    return _callSessionAuthorized(call);
  }

  Future<ResultPayload> _callSessionAuthorized(mcp.McpWampToolCall call) async {
    final result = await session
        .call(
          call.procedure,
          arguments: call.payload.arguments,
          argumentsKeywords: call.payload.argumentsKeywords,
          options: _boundedCallOptions(call.payload.options),
        )
        .firstWhere((result) => !result.isProgressive());
    return result.toPayload();
  }

  Future<mcp.McpWampPublication?> _publish(
    mcp.McpWampPublishRequest request,
  ) async {
    if (!await _isAuthorized(AuthorizationAction.publish, request.topic)) {
      throw StateError('Not authorized to publish ${request.topic}');
    }
    final published = await session.publish(
      request.topic,
      arguments: request.arguments,
      argumentsKeywords: request.argumentsKeywords,
      options: request.options,
    );
    return mcp.McpWampPublication(
      publicationId: published?.publicationId,
      acknowledged: published != null,
    );
  }

  Future<mcp.McpWampSubscription> _subscribe(
    mcp.McpWampSubscribeRequest request,
    void Function(mcp.McpWampEvent event) onEvent,
  ) async {
    if (!await _isAuthorized(AuthorizationAction.subscribe, request.topic)) {
      throw StateError('Not authorized to subscribe ${request.topic}');
    }
    return _subscribeAuthorized(request, onEvent);
  }

  Future<mcp.McpWampSubscription> _subscribeAuthorized(
    mcp.McpWampSubscribeRequest request,
    void Function(mcp.McpWampEvent event) onEvent,
  ) async {
    if (request.queueLimit > _mcpMaxWampSubscriptionQueueLimitForRoute(route)) {
      throw const _McpWampSubscriptionQueueLimitExceeded();
    }

    binding._reserveMcpWampSubscription(this);
    try {
      final subscribed = await session.subscribe(
        request.topic,
        options: request.options,
      );
      try {
        subscribed.onEventPayload(
          (event) => onEvent(mcp.McpWampEvent.fromPayload(event)),
        );
        final subscription = mcp.McpWampSubscription(
          topic: request.topic,
          subscriptionId: subscribed.subscriptionId,
          sessionSubscription: subscribed,
        );
        _wampSubscriptions.add(subscription);
        return subscription;
      } catch (_) {
        try {
          await session.releaseSubscription(subscribed);
        } catch (_) {
          // Preserve the original setup failure.
        }
        rethrow;
      }
    } finally {
      assert(_wampSubscriptionPreparationCount > 0);
      _wampSubscriptionPreparationCount--;
    }
  }

  Future<void> _unsubscribe(mcp.McpWampSubscription subscription) async {
    if (!await _isAuthorized(
      AuthorizationAction.unsubscribe,
      subscription.topic,
    )) {
      throw StateError('Not authorized to unsubscribe ${subscription.topic}');
    }
    await _releaseWampSubscription(subscription);
  }

  Future<void> _releaseWampSubscription(
    mcp.McpWampSubscription subscription,
  ) async {
    final sessionSubscription = subscription.sessionSubscription;
    if (sessionSubscription != null) {
      await session.releaseSubscription(sessionSubscription);
    } else {
      final subscriptionId = subscription.subscriptionId;
      if (subscriptionId != null) {
        await session.unsubscribe(subscriptionId);
      }
    }
    _wampSubscriptions.remove(subscription);
  }

  List<SessionInfo> _visibleMetaSessions(Iterable<SessionInfo> sessions) {
    return <SessionInfo>[
      for (final candidate in sessions)
        if (candidate.id == session.sessionId) candidate,
    ];
  }

  Future<List<RegistrationSnapshot>> _visibleMetaRegistrations(
    Iterable<RegistrationSnapshot> registrations,
  ) async {
    final visible = <RegistrationSnapshot>[];
    for (final registration in registrations) {
      if (await _isAuthorized(
        AuthorizationAction.call,
        registration.procedure,
      )) {
        visible.add(registration);
      }
    }
    return visible;
  }

  Future<List<RegistrationSnapshot>> _visibleConfiguredMetaRegistrations(
    Iterable<RegistrationSnapshot> visibleRegistrations,
  ) async {
    final procedures = _configuredProcedures(route.action.options);
    if (procedures.isEmpty) {
      return const <RegistrationSnapshot>[];
    }

    final visibleExactProcedures = <String>{
      for (final registration in visibleRegistrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.exact)
          registration.procedure,
    };

    final visible = <RegistrationSnapshot>[];
    for (var index = 0; index < procedures.length; index += 1) {
      final procedure = procedures[index];
      if (visibleExactProcedures.contains(procedure.procedure)) {
        continue;
      }
      if (procedure.allowCall &&
          !await _isAuthorized(AuthorizationAction.call, procedure.procedure)) {
        continue;
      }
      visible.add(
        RegistrationSnapshot(
          registrationId: _mcpConfiguredRegistrationIdBase + index,
          procedure: procedure.procedure,
          policy: InvocationPolicy.single,
          matchPolicy: ProcedureMatchPolicy.exact,
          callees: const <RegistrationRecord>[],
        ),
      );
    }
    return visible;
  }

  Future<List<SubscriptionSnapshot>> _visibleMetaSubscriptions(
    Iterable<SubscriptionSnapshot> subscriptions,
  ) async {
    final visible = <SubscriptionSnapshot>[];
    for (final subscription in subscriptions) {
      final canPublish = await _isAuthorized(
        AuthorizationAction.publish,
        subscription.topic,
      );
      final canSubscribe = await _isAuthorized(
        AuthorizationAction.subscribe,
        subscription.topic,
      );
      if (canPublish || canSubscribe) {
        visible.add(subscription);
      }
    }
    return visible;
  }

  Future<List<SubscriptionSnapshot>> _visibleConfiguredMetaSubscriptions(
    Iterable<SubscriptionSnapshot> visibleSubscriptions,
  ) async {
    final topics = _configuredTopics(route.action.options);
    if (topics.isEmpty) {
      return const <SubscriptionSnapshot>[];
    }

    final visibleExactTopics = <String>{
      for (final subscription in visibleSubscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.exact)
          subscription.topic,
    };

    final visible = <SubscriptionSnapshot>[];
    for (var index = 0; index < topics.length; index += 1) {
      final topic = topics[index];
      if (visibleExactTopics.contains(topic.topic)) {
        continue;
      }
      final canPublish =
          topic.allowPublish &&
          await _isAuthorized(AuthorizationAction.publish, topic.topic);
      final canSubscribe =
          topic.allowSubscribe &&
          await _isAuthorized(AuthorizationAction.subscribe, topic.topic);
      if (!canPublish && !canSubscribe) {
        continue;
      }
      visible.add(
        SubscriptionSnapshot(
          id: _mcpConfiguredSubscriptionIdBase + index,
          topic: topic.topic,
          matchPolicy: TopicMatchPolicy.exact,
          subscribers: const <SubscriberRecord>[],
          options: <String, Object?>{
            if (!topic.metadata.isEmpty)
              '_ai_meta_data': topic.metadata.toJson(),
          },
        ),
      );
    }
    return visible;
  }

  Future<RealmSnapshot> _snapshot() {
    final boss = binding._boss;
    if (boss == null) {
      throw StateError('Router MCP endpoint requires a running boss');
    }
    return boss.fetchRealmSnapshot(session.realmUri);
  }

  Future<ResultPayload?> _handleMetaCall(mcp.McpWampToolCall call) async {
    if (!call.procedure.startsWith('wamp.')) {
      return null;
    }
    final snapshot = await _snapshot();
    final visibleSessions = _visibleMetaSessions(snapshot.sessions);
    final visibleSessionIds = {
      for (final session in visibleSessions) session.id,
    };
    final visibleRegistrations = await _visibleMetaRegistrations(
      snapshot.registrations,
    );
    visibleRegistrations.addAll(
      await _visibleConfiguredMetaRegistrations(visibleRegistrations),
    );
    final visibleSubscriptions = await _visibleMetaSubscriptions(
      snapshot.subscriptions,
    );
    visibleSubscriptions.addAll(
      await _visibleConfiguredMetaSubscriptions(visibleSubscriptions),
    );
    switch (call.procedure) {
      case 'wamp.session.count':
        return _resultPayload(
          argumentsKeywords: {'count': visibleSessions.length},
        );
      case 'wamp.session.list':
        return _resultPayload(
          argumentsKeywords: {
            'session_ids': [for (final session in visibleSessions) session.id],
          },
        );
      case 'wamp.session.get':
        final id = _firstIntArgument(call);
        final sessionInfo = visibleSessions
            .where((session) => session.id == id)
            .firstOrNull;
        if (sessionInfo == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_session'],
          );
        }
        return _resultPayload(
          argumentsKeywords: {'details': _sessionDetails(sessionInfo)},
        );
      case 'wamp.registration.list':
        return _resultPayload(
          argumentsKeywords: _idsByProcedureMatchPolicy(visibleRegistrations),
        );
      case 'wamp.registration.lookup':
        final procedure = _firstStringArgument(call);
        final match = _matchOption(call);
        return _resultPayload(
          arguments: [
            for (final registration in visibleRegistrations)
              if (registration.procedure == procedure &&
                  (match == null ||
                      _procedureMatchPolicyName(registration.matchPolicy) ==
                          match))
                registration.registrationId,
          ],
        );
      case 'wamp.registration.match':
        final procedure = _firstStringArgument(call);
        final match = visibleRegistrations.where((registration) {
          return procedure != null &&
              _registrationMatches(registration, procedure);
        }).firstOrNull;
        return _resultPayload(
          arguments: [if (match != null) match.registrationId],
        );
      case 'wamp.registration.get':
        final id = _firstIntArgument(call);
        final registration = _registrationById(visibleRegistrations, id);
        if (registration == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_procedure'],
          );
        }
        return _resultPayload(
          argumentsKeywords: _registrationDetails(registration),
        );
      case 'wamp.registration.list_callees':
        final registration = _registrationById(
          visibleRegistrations,
          _firstIntArgument(call),
        );
        final visibleCallees = [
          for (final callee
              in registration?.callees ?? const <RegistrationRecord>[])
            if (visibleSessionIds.contains(callee.sessionId)) callee,
        ];
        return _resultPayload(
          arguments: [for (final callee in visibleCallees) callee.sessionId],
        );
      case 'wamp.registration.count_callees':
        final registration = _registrationById(
          visibleRegistrations,
          _firstIntArgument(call),
        );
        final visibleCallees = [
          for (final callee
              in registration?.callees ?? const <RegistrationRecord>[])
            if (visibleSessionIds.contains(callee.sessionId)) callee,
        ];
        return _resultPayload(arguments: [visibleCallees.length]);
      case 'wamp.subscription.list':
        return _resultPayload(
          argumentsKeywords: _idsBySubscriptionMatchPolicy(
            visibleSubscriptions,
          ),
        );
      case 'wamp.subscription.lookup':
        final topic = _firstStringArgument(call);
        final match = _matchOption(call);
        return _resultPayload(
          arguments: [
            for (final subscription in visibleSubscriptions)
              if (subscription.topic == topic &&
                  (match == null ||
                      _topicMatchPolicyName(subscription.matchPolicy) == match))
                subscription.id,
          ],
        );
      case 'wamp.subscription.match':
        final topic = _firstStringArgument(call);
        return _resultPayload(
          arguments: [
            for (final subscription in visibleSubscriptions)
              if (topic != null && _subscriptionMatches(subscription, topic))
                subscription.id,
          ],
        );
      case 'wamp.subscription.get':
        final subscription = _subscriptionById(
          visibleSubscriptions,
          _firstIntArgument(call),
        );
        if (subscription == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_subscription'],
          );
        }
        return _resultPayload(
          argumentsKeywords: _subscriptionDetails(subscription),
        );
      case 'wamp.subscription.list_subscribers':
        final subscription = _subscriptionById(
          visibleSubscriptions,
          _firstIntArgument(call),
        );
        final visibleSubscribers = [
          for (final subscriber
              in subscription?.subscribers ?? const <SubscriberRecord>[])
            if (visibleSessionIds.contains(subscriber.sessionId)) subscriber,
        ];
        return _resultPayload(
          arguments: [
            for (final subscriber in visibleSubscribers) subscriber.sessionId,
          ],
        );
      case 'wamp.subscription.count_subscribers':
        final subscription = _subscriptionById(
          visibleSubscriptions,
          _firstIntArgument(call),
        );
        final visibleSubscribers = [
          for (final subscriber
              in subscription?.subscribers ?? const <SubscriberRecord>[])
            if (visibleSessionIds.contains(subscriber.sessionId)) subscriber,
        ];
        return _resultPayload(arguments: [visibleSubscribers.length]);
      default:
        return null;
    }
  }
}

_DirectJsonRequest _directJsonRequestFrom(Object? rawMessage) {
  if (rawMessage is! Map) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC message must be an object',
    );
  }
  final message = mcp.jsonMapFrom(rawMessage, label: 'message');
  if (message['jsonrpc'] != '2.0') {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC version must be 2.0',
    );
  }
  final method = message['method'];
  if (method is! String || method.isEmpty) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC method must be a non-empty string',
    );
  }
  if (containsMcpWhitespaceOrControl(method)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC method must not contain whitespace or control characters',
    );
  }
  if (message.containsKey('result') || message.containsKey('error')) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC request must not contain result or error',
    );
  }
  final hasId = message.containsKey('id');
  final id = hasId ? message['id'] : null;
  if (hasId && !mcp.isJsonRpcRequestId(id)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC id must be a string or integer',
    );
  }
  final hasParams = message.containsKey('params');
  if (hasParams && message['params'] == null) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidParams,
      'params must be an object',
    );
  }
  return _DirectJsonRequest(
    id: id,
    isNotification: !hasId,
    method: method,
    params: hasParams
        ? mcp.jsonMapFrom(message['params'])
        : const <String, Object?>{},
  );
}

Object? _mcpDuplicateJsonRpcBatchRequestId(List<Object?> rawMessages) {
  final seenIds = <Object?>[];
  for (final rawMessage in rawMessages) {
    if (rawMessage is! Map || !rawMessage.containsKey('id')) {
      continue;
    }
    final id = rawMessage['id'];
    if (!mcp.isJsonRpcRequestId(id)) {
      continue;
    }
    if (seenIds.any((seenId) => seenId == id)) {
      return id;
    }
    seenIds.add(id);
  }
  return null;
}

Object? _recoverDirectJsonRequestId(Object? rawMessage) {
  if (rawMessage is! Map || !rawMessage.containsKey('id')) {
    return null;
  }
  final id = rawMessage['id'];
  return mcp.isJsonRpcId(id) ? id : null;
}

class _DirectJsonRequest {
  const _DirectJsonRequest({
    required this.id,
    required this.isNotification,
    required this.method,
    required this.params,
  });

  final Object? id;
  final bool isNotification;
  final String method;
  final mcp.JsonMap params;
}

class _DirectJsonMessageResponse {
  const _DirectJsonMessageResponse(this.response);

  final mcp.JsonMap? response;
}

String _mcpAnonymousRouteSessionCacheKey({
  required RouterHttpRequest request,
  required HttpRouteSettings route,
  required String realmUri,
  required SessionProfileSettings? sessionProfile,
}) {
  final routeKey = route.match.path ?? route.match.prefix ?? request.path;
  final profileKey = sessionProfile?.name ?? 'anonymous';
  return [
    'http-mcp-anonymous',
    request.listenerId,
    routeKey,
    realmUri,
    profileKey,
  ].join(':');
}

ResultPayload _resultPayload({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
}) {
  return (
    callRequestId: 0,
    progress: false,
    pptScheme: null,
    pptSerializer: null,
    pptCipher: null,
    pptKeyId: null,
    customDetails: null,
    arguments: arguments,
    argumentsKeywords: argumentsKeywords,
  );
}

List<mcp.McpWampProcedure> _configuredProcedures(Map<String, Object?> options) {
  final entries = options['procedures'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map) _procedureFromConfig(entry.cast<String, Object?>()),
  ];
}

List<mcp.McpWampTopic> _configuredTopics(Map<String, Object?> options) {
  final entries = options['topics'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map) _topicFromConfig(entry.cast<String, Object?>()),
  ];
}

void _validateMcpRouteOptions(Map<String, Object?> options) {
  try {
    _mcpProtectedResourceMetadataFromOptions(options);
    _validateMcpPostResponseOptions(options);
    _validateMcpRouteOptionShapes(options);
    _validateMcpSseHistoryByteOptions(options);
    _configuredProcedures(options);
    _configuredTopics(options);
    _configuredResources(options);
    _configuredResourceTemplates(options);
    _configuredPrompts(options);
  } on FormatException catch (error) {
    throw StateError('Invalid MCP route options: ${error.message}');
  } on ArgumentError catch (error) {
    throw StateError('Invalid MCP route options: ${error.message}');
  }
}

void _validateMcpRouteOptionShapes(Map<String, Object?> options) {
  for (final key in const <String>[
    'name',
    'version',
    'title',
    'description',
    'instructions',
  ]) {
    _validateMcpStringConfigOption(options, 'route', key);
  }

  for (final key in const <String>[
    'include_registered_procedures',
    'includeRegisteredProcedures',
    'include_subscribed_topics',
    'includeSubscribedTopics',
    'include_pubsub_tools',
    'includePubsubTools',
    'include_standard_meta_api',
    'includeStandardMetaApi',
  ]) {
    _validateMcpBoolRouteOption(options, key);
  }

  for (final key in const <String>[
    'tool_list_page_size',
    'toolListPageSize',
    'prompt_list_page_size',
    'promptListPageSize',
    'resource_list_page_size',
    'resourceListPageSize',
    'resource_template_list_page_size',
    'resourceTemplateListPageSize',
    'max_request_bytes',
    'maxRequestBytes',
    'max_response_bytes',
    'maxResponseBytes',
    'max_sse_history_bytes',
    'maxSseHistoryBytes',
    'max_session_count',
    'maxSessionCount',
    'max_request_scoped_listener_count',
    'maxRequestScopedListenerCount',
    'max_wamp_subscription_count',
    'maxWampSubscriptionCount',
    'max_wamp_subscription_queue_limit',
    'maxWampSubscriptionQueueLimit',
    'max_wamp_subscription_queue_bytes',
    'maxWampSubscriptionQueueBytes',
    'call_timeout_ms',
    'callTimeoutMs',
  ]) {
    _validateMcpPositiveIntRouteOption(options, key);
  }

  for (final key in const <String>[
    'session_idle_timeout_ms',
    'sessionIdleTimeoutMs',
  ]) {
    _validateMcpNonNegativeIntConfigOption(options, 'route', key);
  }

  for (final key in const <String>[
    'procedures',
    'topics',
    'resources',
    'resource_templates',
    'resourceTemplates',
    'prompts',
  ]) {
    _validateMcpObjectListRouteOption(options, key);
  }

  _validateMcpAllowedOriginsRouteOption(options);
  _validateMcpConfiguredRouteOptionShapes(options);
}

void _validateMcpSseHistoryByteOptions(Map<String, Object?> options) {
  final maxResponseBytes =
      _intOptionAny(options, const <String>[
        'max_response_bytes',
        'maxResponseBytes',
      ]) ??
      _mcpDefaultMaxResponseBytes;
  final maxHistoryBytes =
      _intOptionAny(options, const <String>[
        'max_sse_history_bytes',
        'maxSseHistoryBytes',
      ]) ??
      maxResponseBytes;
  if (maxHistoryBytes < maxResponseBytes) {
    throw const FormatException(
      'MCP max_sse_history_bytes must be at least max_response_bytes',
    );
  }
}

void _validateMcpBoolRouteOption(Map<String, Object?> options, String key) {
  final value = options[key];
  if (value != null && value is! bool) {
    throw FormatException('MCP $key must be a boolean');
  }
}

void _validateMcpPositiveIntRouteOption(
  Map<String, Object?> options,
  String key,
) {
  final value = options[key];
  if (value != null && (value is! int || value <= 0)) {
    throw FormatException('MCP $key must be a positive integer');
  }
}

void _validateMcpObjectListRouteOption(
  Map<String, Object?> options,
  String key,
) {
  final value = options[key];
  if (value == null) {
    return;
  }
  if (value is! List) {
    throw FormatException('MCP $key must be a list of objects');
  }
  for (var i = 0; i < value.length; i += 1) {
    final entry = value[i];
    if (entry is! Map) {
      throw FormatException('MCP $key[$i] must be an object');
    }
    for (final entryKey in entry.keys) {
      if (entryKey is! String) {
        throw FormatException('MCP $key[$i] keys must be strings');
      }
    }
  }
}

void _validateMcpAllowedOriginsRouteOption(Map<String, Object?> options) {
  for (final key in const <String>[
    'allowedOrigins',
    'allowed_origins',
    'allowedOrigin',
    'allowed_origin',
    'origins',
  ]) {
    final value = options[key];
    if (value == null || value is String) {
      continue;
    }
    if (value is Iterable && value.every((origin) => origin is String)) {
      continue;
    }
    throw FormatException('MCP $key must be a string or list of strings');
  }
}

void _validateMcpConfiguredRouteOptionShapes(Map<String, Object?> options) {
  _validateMcpProcedureRouteOptionShapes(options);
  _validateMcpTopicRouteOptionShapes(options);
  _validateMcpResourceRouteOptionShapes(options);
  _validateMcpPromptRouteOptionShapes(options);
}

void _validateMcpProcedureRouteOptionShapes(Map<String, Object?> options) {
  final entries = options['procedures'];
  if (entries is! List) {
    return;
  }
  for (var i = 0; i < entries.length; i += 1) {
    final config = (entries[i] as Map).cast<String, Object?>();
    final label = 'procedures[$i]';
    for (final key in const <String>[
      'procedure',
      'uri',
      'tool_name',
      'toolName',
      'name',
      'title',
      'description',
    ]) {
      _validateMcpStringConfigOption(config, label, key);
    }
    for (final key in const <String>['allow_call', 'allowCall', 'callable']) {
      _validateMcpBoolConfigOption(config, label, key);
    }
    for (final key in const <String>[
      'input_schema',
      'inputSchema',
      'input_json_schema',
      'inputJsonSchema',
      'output_schema',
      'outputSchema',
      'output_json_schema',
      'outputJsonSchema',
    ]) {
      _validateMcpJsonObjectConfigOption(config, label, key);
    }
    _validateMcpMetadataConfigOptionShapes(config, label);
  }
}

void _validateMcpTopicRouteOptionShapes(Map<String, Object?> options) {
  final entries = options['topics'];
  if (entries is! List) {
    return;
  }
  for (var i = 0; i < entries.length; i += 1) {
    final config = (entries[i] as Map).cast<String, Object?>();
    final label = 'topics[$i]';
    for (final key in const <String>['topic', 'uri', 'title', 'description']) {
      _validateMcpStringConfigOption(config, label, key);
    }
    for (final key in const <String>[
      'allow_publish',
      'allow_subscribe',
      'allowPublish',
      'allowSubscribe',
    ]) {
      _validateMcpBoolConfigOption(config, label, key);
    }
    for (final key in const <String>[
      'event_schema',
      'eventSchema',
      'event_json_schema',
      'eventJsonSchema',
    ]) {
      _validateMcpJsonObjectConfigOption(config, label, key);
    }
    _validateMcpMetadataConfigOptionShapes(config, label);
  }
}

void _validateMcpResourceRouteOptionShapes(Map<String, Object?> options) {
  final entries = options['resources'];
  if (entries is List) {
    for (var i = 0; i < entries.length; i += 1) {
      final config = (entries[i] as Map).cast<String, Object?>();
      final label = 'resources[$i]';
      for (final key in const <String>[
        'uri',
        'name',
        'title',
        'description',
        'mime_type',
        'mimeType',
        'text',
        'content',
        'blob',
        'read_procedure',
        'readProcedure',
        'update_topic',
        'updateTopic',
      ]) {
        _validateMcpStringConfigOption(config, label, key);
      }
      _validateMcpNonNegativeIntConfigOption(config, label, 'size');
    }
  }

  for (final optionKey in const <String>[
    'resource_templates',
    'resourceTemplates',
  ]) {
    final templates = options[optionKey];
    if (templates is! List) {
      continue;
    }
    for (var i = 0; i < templates.length; i += 1) {
      final config = (templates[i] as Map).cast<String, Object?>();
      final label = '$optionKey[$i]';
      for (final key in const <String>[
        'uri_template',
        'uriTemplate',
        'name',
        'title',
        'description',
        'mime_type',
        'mimeType',
      ]) {
        _validateMcpStringConfigOption(config, label, key);
      }
    }
  }
}

void _validateMcpPromptRouteOptionShapes(Map<String, Object?> options) {
  final entries = options['prompts'];
  if (entries is! List) {
    return;
  }
  for (var i = 0; i < entries.length; i += 1) {
    final config = (entries[i] as Map).cast<String, Object?>();
    final label = 'prompts[$i]';
    for (final key in const <String>[
      'name',
      'title',
      'description',
      'text',
      'content',
      'result_description',
      'resultDescription',
    ]) {
      _validateMcpStringConfigOption(config, label, key);
    }
    _validateMcpNestedObjectListConfigOption(config, label, 'arguments');
    _validateMcpNestedObjectListConfigOption(config, label, 'messages');

    final arguments = config['arguments'];
    if (arguments is List) {
      for (var j = 0; j < arguments.length; j += 1) {
        final argument = (arguments[j] as Map).cast<String, Object?>();
        final argumentLabel = '$label.arguments[$j]';
        for (final key in const <String>['name', 'title', 'description']) {
          _validateMcpStringConfigOption(argument, argumentLabel, key);
        }
        _validateMcpBoolConfigOption(argument, argumentLabel, 'required');
      }
    }

    final messages = config['messages'];
    if (messages is List) {
      for (var j = 0; j < messages.length; j += 1) {
        final message = (messages[j] as Map).cast<String, Object?>();
        final messageLabel = '$label.messages[$j]';
        for (final key in const <String>['role', 'text', 'content']) {
          _validateMcpStringConfigOption(message, messageLabel, key);
        }
      }
    }
  }
}

void _validateMcpBoolConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value != null && value is! bool) {
    throw FormatException('MCP $label.$key must be a boolean');
  }
}

void _validateMcpNonNegativeIntConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value != null && (value is! int || value < 0)) {
    throw FormatException('MCP $label.$key must be a non-negative integer');
  }
}

void _validateMcpJsonObjectConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value == null) {
    return;
  }
  _validateMcpJsonObjectValueConfigOption(value, 'MCP $label.$key');
}

void _validateMcpJsonObjectValueConfigOption(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be an object');
  }
  _validateMcpJsonMapConfigOption(value, label);
}

void _validateMcpJsonMapConfigOption(Map value, String label) {
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label keys must be strings');
    }
    _validateMcpJsonValueConfigOption(entry.value, '$label.$key');
  }
}

void _validateMcpJsonValueConfigOption(Object? value, String label) {
  if (value == null || value is String || value is bool) {
    return;
  }
  if (value is num) {
    if (value is double && !value.isFinite) {
      throw FormatException('$label must be a finite number');
    }
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i += 1) {
      _validateMcpJsonValueConfigOption(value[i], '$label[$i]');
    }
    return;
  }
  if (value is Map) {
    _validateMcpJsonMapConfigOption(value, label);
    return;
  }
  throw FormatException('$label must be JSON-compatible');
}

void _validateMcpStringConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value != null && value is! String) {
    throw FormatException('MCP $label.$key must be a string');
  }
}

void _validateMcpStringListConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value == null) {
    return;
  }
  if (value is! List) {
    throw FormatException('MCP $label.$key must be a list of strings');
  }
  for (var i = 0; i < value.length; i += 1) {
    if (value[i] is! String) {
      throw FormatException('MCP $label.$key[$i] must be a string');
    }
  }
}

void _validateMcpMetadataAnnotationsConfigOption(
  Map<String, Object?> config,
  String label,
) {
  final annotations = config['annotations'];
  if (annotations == null) {
    return;
  }
  if (annotations is! Map) {
    throw FormatException('MCP $label.annotations must be an object');
  }
  for (final entry in annotations.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('MCP $label.annotations keys must be strings');
    }
    if (const <String>{
      'read_only_hint',
      'readOnlyHint',
      'destructive_hint',
      'destructiveHint',
      'idempotent_hint',
      'idempotentHint',
      'open_world_hint',
      'openWorldHint',
    }.contains(key)) {
      if (entry.value is! bool) {
        throw FormatException('MCP $label.annotations.$key must be a boolean');
      }
    }
  }
}

void _validateMcpMetadataConfigOptionShapes(
  Map<String, Object?> config,
  String label,
) {
  for (final metadataKey in const <String>[
    '_ai_meta_data',
    'ai_meta_data',
    'aiMetaData',
    'metadata',
  ]) {
    final metadata = config[metadataKey];
    if (metadata == null) {
      continue;
    }
    if (metadata is! Map) {
      throw FormatException('MCP $label.$metadataKey must be an object');
    }
    for (final entryKey in metadata.keys) {
      if (entryKey is! String) {
        throw FormatException('MCP $label.$metadataKey keys must be strings');
      }
    }
    final metadataConfig = metadata.cast<String, Object?>();
    for (final key in const <String>[
      'short_description',
      'shortDescription',
      'description',
      'domain',
      'entity',
    ]) {
      _validateMcpStringConfigOption(
        metadataConfig,
        '$label.$metadataKey',
        key,
      );
    }
    for (final key in const <String>[
      'verbs',
      'tags',
      'synonyms',
      'publishes_events',
      'publishesEvents',
    ]) {
      _validateMcpStringListConfigOption(
        metadataConfig,
        '$label.$metadataKey',
        key,
      );
    }
    for (final schemaKey in const <String>[
      'input_json_schema',
      'inputJsonSchema',
      'output_json_schema',
      'outputJsonSchema',
    ]) {
      _validateMcpJsonObjectConfigOption(
        metadataConfig,
        '$label.$metadataKey',
        schemaKey,
      );
    }
    for (final key in const <String>[
      'read_only_hint',
      'readOnlyHint',
      'destructive_hint',
      'destructiveHint',
      'idempotent_hint',
      'idempotentHint',
      'open_world_hint',
      'openWorldHint',
    ]) {
      _validateMcpBoolConfigOption(metadataConfig, '$label.$metadataKey', key);
    }
    _validateMcpMetadataAnnotationsConfigOption(
      metadataConfig,
      '$label.$metadataKey',
    );
  }
}

void _validateMcpNestedObjectListConfigOption(
  Map<String, Object?> config,
  String label,
  String key,
) {
  final value = config[key];
  if (value == null) {
    return;
  }
  if (value is! List) {
    throw FormatException('MCP $label.$key must be a list of objects');
  }
  for (var i = 0; i < value.length; i += 1) {
    final entry = value[i];
    if (entry is! Map) {
      throw FormatException('MCP $label.$key[$i] must be an object');
    }
    for (final entryKey in entry.keys) {
      if (entryKey is! String) {
        throw FormatException('MCP $label.$key[$i] keys must be strings');
      }
    }
  }
}

void _validateMcpPostResponseOptions(Map<String, Object?> options) {
  for (final key in const <String>[
    'post_response_transport',
    'postResponseTransport',
  ]) {
    final transport = options[key];
    if (transport == null) {
      continue;
    }
    final mode = _stringFrom(transport)?.trim().toLowerCase();
    if (mode == null || !_mcpPostResponseTransportModes.contains(mode)) {
      throw FormatException(
        'MCP $key must be one of auto, disabled, false, json, off, sse, '
        'stream, or streamable',
      );
    }
  }

  for (final key in const <String>[
    'stream_post_responses',
    'streamPostResponses',
  ]) {
    final streamPostResponses = options[key];
    if (streamPostResponses != null && streamPostResponses is! bool) {
      throw FormatException('MCP $key must be a boolean');
    }
  }
}

typedef _ConfiguredResourceProcedureReader =
    Future<List<mcp.McpResourceContent>> Function(
      Map<String, Object?> config,
      mcp.McpResourceRequest request,
    );

List<mcp.McpResource> _configuredResources(
  Map<String, Object?> options, {
  _ConfiguredResourceProcedureReader? procedureReader,
}) {
  final entries = options['resources'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map)
        _resourceFromConfig(
          entry.cast<String, Object?>(),
          procedureReader: procedureReader,
        ),
  ];
}

List<mcp.McpResourceTemplate> _configuredResourceTemplates(
  Map<String, Object?> options,
) {
  final entries = options['resource_templates'] ?? options['resourceTemplates'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map)
        _resourceTemplateFromConfig(entry.cast<String, Object?>()),
  ];
}

List<mcp.McpPrompt> _configuredPrompts(Map<String, Object?> options) {
  final entries = options['prompts'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map) _promptFromConfig(entry.cast<String, Object?>()),
  ];
}

Map<String, Object?>? _configuredResourceForUri(
  Map<String, Object?> options,
  String uri,
) {
  final entries = options['resources'];
  if (entries is! List) {
    return null;
  }
  for (final entry in entries) {
    if (entry is! Map) {
      continue;
    }
    final config = entry.cast<String, Object?>();
    if (_stringFrom(config['uri']) == uri) {
      return config;
    }
  }
  return null;
}

String? _configuredResourceUpdateTopic(Map<String, Object?> config) =>
    _stringFrom(config['update_topic']) ?? _stringFrom(config['updateTopic']);

bool _hasConfiguredResourceSubscriptions(Map<String, Object?> options) {
  final entries = options['resources'];
  if (entries is! List) {
    return false;
  }
  return entries.whereType<Map>().any(
    (entry) =>
        _configuredResourceUpdateTopic(entry.cast<String, Object?>()) != null,
  );
}

bool _hasConfiguredDynamicResources(Map<String, Object?> options) {
  final entries = options['resources'];
  if (entries is! List) {
    return false;
  }
  return entries.whereType<Map>().any((entry) {
    final config = entry.cast<String, Object?>();
    return _stringFrom(config['read_procedure']) != null ||
        _stringFrom(config['readProcedure']) != null;
  });
}

mcp.McpServerCapabilities _mcpServerCapabilitiesForOptions(
  Map<String, Object?> options,
) {
  final hasResources =
      _configuredResources(options).isNotEmpty ||
      _configuredResourceTemplates(options).isNotEmpty;
  return mcp.McpServerCapabilities(
    tools: const mcp.McpToolCapabilities(listChanged: true),
    prompts: _configuredPrompts(options).isNotEmpty
        ? const mcp.McpPromptCapabilities()
        : null,
    resources: hasResources
        ? mcp.McpResourceCapabilities(
            subscribe: _hasConfiguredResourceSubscriptions(options),
            listChanged: _hasConfiguredDynamicResources(options),
          )
        : null,
  );
}

mcp.McpServerInfo _mcpServerInfoForOptions(Map<String, Object?> options) {
  return mcp.McpServerInfo(
    name: _stringOptionAny(options, const ['name']) ?? 'connectanum-router',
    version: _stringOptionAny(options, const ['version']) ?? '3.0.0-beta',
    title: _stringOptionAny(options, const ['title']),
    description: _stringOptionAny(options, const ['description']),
  );
}

String _mcpInstructionsForOptions(Map<String, Object?> options) {
  return _stringOptionAny(options, const ['instructions']) ??
      'This MCP endpoint is hosted by the Connectanum router and uses '
          'the route-authenticated WAMP principal for calls and pub/sub.';
}

mcp.McpWampProcedure _procedureFromConfig(Map<String, Object?> config) {
  final procedure =
      _stringFrom(config['procedure']) ??
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP procedure config requires procedure or uri'));
  final metadata = _metadataFromDetails(config);
  return mcp.McpWampProcedure(
    procedure: procedure,
    toolName:
        _stringFrom(config['tool_name']) ??
        _stringFrom(config['toolName']) ??
        _stringFrom(config['name']),
    title: _stringFrom(config['title']),
    description:
        _stringFrom(config['description']) ?? metadata?.shortDescription,
    inputSchema:
        _schemaFromDetails(config, 'input') ?? metadata?.inputJsonSchema,
    outputSchema:
        _schemaFromDetails(config, 'output') ?? metadata?.outputJsonSchema,
    metadata: metadata,
    allowCall: _allowCallFrom(config),
  );
}

mcp.McpWampTopic _topicFromConfig(Map<String, Object?> config) {
  final topic =
      _stringFrom(config['topic']) ??
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP topic config requires topic or uri'));
  final metadata = _metadataFromDetails(config);
  return mcp.McpWampTopic(
    topic: topic,
    title: _stringFrom(config['title']),
    description:
        _stringFrom(config['description']) ?? metadata?.shortDescription,
    eventSchema:
        _schemaFromDetails(config, 'event') ?? metadata?.outputJsonSchema,
    allowPublish: _boolOptionAny(config, const [
      'allow_publish',
      'allowPublish',
    ], defaultValue: true),
    allowSubscribe: _boolOptionAny(config, const [
      'allow_subscribe',
      'allowSubscribe',
    ], defaultValue: true),
    metadata: metadata,
  );
}

mcp.McpResource _resourceFromConfig(
  Map<String, Object?> config, {
  _ConfiguredResourceProcedureReader? procedureReader,
}) {
  final uri =
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP resource config requires uri'));
  final name =
      _stringFrom(config['name']) ?? _stringFrom(config['title']) ?? uri;
  final configuredMimeType =
      _stringFrom(config['mime_type']) ?? _stringFrom(config['mimeType']);
  final text = _stringFrom(config['text']) ?? _stringFrom(config['content']);
  final blob = _stringFrom(config['blob']);
  final readProcedure =
      _stringFrom(config['read_procedure']) ??
      _stringFrom(config['readProcedure']);
  final updateTopic =
      _stringFrom(config['update_topic']) ?? _stringFrom(config['updateTopic']);
  final hasStaticContent = text != null || blob != null;
  if (readProcedure != null && hasStaticContent) {
    throw FormatException(
      'MCP resource config for $uri cannot combine read_procedure with '
      'text, content, or blob',
    );
  }
  if (readProcedure == null && !hasStaticContent) {
    throw FormatException(
      'MCP resource config for $uri requires text, content, blob, or '
      'read_procedure',
    );
  }
  if (updateTopic != null && readProcedure == null) {
    throw FormatException(
      'MCP resource config for $uri update_topic requires read_procedure',
    );
  }
  final mimeType =
      configuredMimeType ?? (readProcedure == null ? null : 'application/json');
  return mcp.McpResource(
    uri: uri,
    name: name,
    title: _stringFrom(config['title']),
    description: _stringFrom(config['description']),
    mimeType: mimeType,
    size: _intOption(config, 'size'),
    read: readProcedure == null
        ? (_) async => <mcp.McpResourceContent>[
            if (text != null)
              mcp.McpTextResourceContent(
                uri: uri,
                text: text,
                mimeType: mimeType,
              )
            else
              mcp.McpBlobResourceContent(
                uri: uri,
                blob: blob!,
                mimeType: mimeType,
              ),
          ]
        : (request) {
            final reader = procedureReader;
            if (reader == null) {
              throw StateError(
                'MCP dynamic resource $uri has no procedure reader',
              );
            }
            return reader(config, request);
          },
  );
}

mcp.McpResourceTemplate _resourceTemplateFromConfig(
  Map<String, Object?> config,
) {
  final uriTemplate =
      _stringFrom(config['uri_template']) ??
      _stringFrom(config['uriTemplate']) ??
      (throw FormatException(
        'MCP resource template config requires uri_template or uriTemplate',
      ));
  final name =
      _stringFrom(config['name']) ??
      _stringFrom(config['title']) ??
      uriTemplate;
  return mcp.McpResourceTemplate(
    uriTemplate: uriTemplate,
    name: name,
    title: _stringFrom(config['title']),
    description: _stringFrom(config['description']),
    mimeType:
        _stringFrom(config['mime_type']) ?? _stringFrom(config['mimeType']),
  );
}

mcp.McpPrompt _promptFromConfig(Map<String, Object?> config) {
  final name =
      _stringFrom(config['name']) ??
      (throw FormatException('MCP prompt config requires name'));
  final messages = _configuredPromptMessages(config);
  final text = _stringFrom(config['text']) ?? _stringFrom(config['content']);
  if (messages.isEmpty && text == null) {
    throw FormatException(
      'MCP prompt config for $name requires messages, text, or content',
    );
  }
  return mcp.McpPrompt(
    name: name,
    title: _stringFrom(config['title']),
    description: _stringFrom(config['description']),
    arguments: _configuredPromptArguments(config),
    handler: (request) async {
      if (messages.isNotEmpty) {
        return mcp.McpPromptResult(
          description:
              _stringFrom(config['result_description']) ??
              _stringFrom(config['resultDescription']) ??
              _stringFrom(config['description']),
          messages: [
            for (final message in messages)
              mcp.McpPromptMessage(
                role: message.role,
                content: mcp.McpTextContent(
                  _renderConfiguredPromptText(message.text, request.arguments),
                ),
              ),
          ],
        );
      }
      return mcp.McpPromptResult.text(
        _renderConfiguredPromptText(text!, request.arguments),
        description:
            _stringFrom(config['result_description']) ??
            _stringFrom(config['resultDescription']) ??
            _stringFrom(config['description']),
      );
    },
  );
}

List<mcp.McpPromptArgument> _configuredPromptArguments(
  Map<String, Object?> config,
) {
  final entries = config['arguments'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map)
        _promptArgumentFromConfig(entry.cast<String, Object?>()),
  ];
}

mcp.McpPromptArgument _promptArgumentFromConfig(Map<String, Object?> config) {
  final name =
      _stringFrom(config['name']) ??
      (throw FormatException('MCP prompt argument config requires name'));
  return mcp.McpPromptArgument(
    name: name,
    title: _stringFrom(config['title']),
    description: _stringFrom(config['description']),
    required: _boolOption(config, 'required', defaultValue: false),
  );
}

List<_ConfiguredPromptMessage> _configuredPromptMessages(
  Map<String, Object?> config,
) {
  final entries = config['messages'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map)
        _configuredPromptMessageFromConfig(entry.cast<String, Object?>()),
  ];
}

_ConfiguredPromptMessage _configuredPromptMessageFromConfig(
  Map<String, Object?> config,
) {
  final roleName = _stringFrom(config['role']) ?? 'user';
  final role = switch (roleName) {
    'assistant' => mcp.McpPromptRole.assistant,
    'user' => mcp.McpPromptRole.user,
    _ => throw FormatException(
      'MCP prompt message role must be user or assistant',
    ),
  };
  final text =
      _stringFrom(config['text']) ??
      _stringFrom(config['content']) ??
      (throw FormatException('MCP prompt message config requires text'));
  return _ConfiguredPromptMessage(role: role, text: text);
}

String _renderConfiguredPromptText(String text, Map<String, String> arguments) {
  var rendered = text;
  for (final entry in arguments.entries) {
    rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
  }
  return rendered;
}

class _ConfiguredPromptMessage {
  const _ConfiguredPromptMessage({required this.role, required this.text});

  final mcp.McpPromptRole role;
  final String text;
}

void _addPublishedEventTopics(
  Map<String, mcp.McpWampTopic> topics,
  Iterable<mcp.McpWampProcedure> procedures,
) {
  for (final procedure in procedures) {
    for (final topic in procedure.metadata.publishesEvents) {
      if (topic.isEmpty) {
        continue;
      }
      topics.putIfAbsent(
        topic,
        () => mcp.McpWampTopic(
          topic: topic,
          title: topic,
          description: 'Event published by ${procedure.procedure}.',
        ),
      );
    }
  }
}

mcp.McpWampTopic _topicWithPermissions(
  mcp.McpWampTopic topic, {
  required bool allowPublish,
  required bool allowSubscribe,
}) {
  if (topic.allowPublish == allowPublish &&
      topic.allowSubscribe == allowSubscribe) {
    return topic;
  }
  return mcp.McpWampTopic(
    topic: topic.topic,
    title: topic.title,
    description: topic.description,
    eventSchema: topic.eventSchema,
    metadata: topic.metadata,
    allowPublish: allowPublish,
    allowSubscribe: allowSubscribe,
  );
}

mcp.McpWampApiMetadata? _metadataFromDetails(Map<String, Object?> details) {
  final raw =
      details['_ai_meta_data'] ??
      details['ai_meta_data'] ??
      details['aiMetaData'] ??
      details['metadata'];
  if (raw is! Map) {
    return null;
  }
  final map = raw.cast<String, Object?>();
  return mcp.McpWampApiMetadata(
    shortDescription:
        _stringFrom(map['short_description']) ??
        _stringFrom(map['shortDescription']),
    description: _stringFrom(map['description']),
    domain: _stringFrom(map['domain']),
    entity: _stringFrom(map['entity']),
    verbs: _stringListFrom(map['verbs']),
    tags: _stringListFrom(map['tags']),
    synonyms: _stringListFrom(map['synonyms']),
    publishesEvents: _stringListFrom(
      map['publishes_events'] ?? map['publishesEvents'],
    ),
    inputJsonSchema:
        _jsonMapFrom(map['input_json_schema']) ??
        _jsonMapFrom(map['inputJsonSchema']),
    outputJsonSchema:
        _jsonMapFrom(map['output_json_schema']) ??
        _jsonMapFrom(map['outputJsonSchema']),
    danger: _dangerFrom(map['danger']),
    readOnlyHint: _annotationBool(map, 'read_only_hint', 'readOnlyHint'),
    destructiveHint: _annotationBool(
      map,
      'destructive_hint',
      'destructiveHint',
    ),
    idempotentHint: _annotationBool(map, 'idempotent_hint', 'idempotentHint'),
    openWorldHint: _annotationBool(map, 'open_world_hint', 'openWorldHint'),
  );
}

bool _allowCallFrom(Map<String, Object?> config) {
  final allowCall = config['allow_call'] ?? config['allowCall'];
  if (allowCall is bool) {
    return allowCall;
  }
  final callable = config['callable'];
  if (callable is bool) {
    return callable;
  }
  return true;
}

bool _dangerFrom(Object? value) {
  if (value == null || value == false) {
    return false;
  }
  if (value == true) {
    return true;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'false') {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded == null || decoded == false) {
        return false;
      }
    } on FormatException {
      // Non-empty danger strings are treated as a safety warning.
    }
    return true;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return false;
}

bool? _annotationBool(
  Map<String, Object?> map,
  String snakeKey,
  String camelKey,
) {
  final direct = map[snakeKey] ?? map[camelKey];
  if (direct is bool) {
    return direct;
  }
  final annotations = map['annotations'];
  if (annotations is Map) {
    final value = annotations[camelKey] ?? annotations[snakeKey];
    if (value is bool) {
      return value;
    }
  }
  return null;
}

Map<String, Object?>? _schemaFromDetails(
  Map<String, Object?> details,
  String prefix,
) {
  return _jsonMapFrom(details['${prefix}_schema']) ??
      _jsonMapFrom(details['${prefix}Schema']) ??
      _jsonMapFrom(details['${prefix}_json_schema']) ??
      _jsonMapFrom(details['${prefix}JsonSchema']);
}

Map<String, dynamic> _idsByProcedureMatchPolicy(
  Iterable<RegistrationSnapshot> registrations,
) {
  return <String, dynamic>{
    'exact': [
      for (final registration in registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.exact)
          registration.registrationId,
    ],
    'prefix': [
      for (final registration in registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.prefix)
          registration.registrationId,
    ],
    'wildcard': [
      for (final registration in registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.wildcard)
          registration.registrationId,
    ],
  };
}

Map<String, dynamic> _idsBySubscriptionMatchPolicy(
  Iterable<SubscriptionSnapshot> subscriptions,
) {
  return <String, dynamic>{
    'exact': [
      for (final subscription in subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.exact) subscription.id,
    ],
    'prefix': [
      for (final subscription in subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.prefix)
          subscription.id,
    ],
    'wildcard': [
      for (final subscription in subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.wildcard)
          subscription.id,
    ],
  };
}

Map<String, dynamic> _sessionDetails(SessionInfo session) {
  return <String, dynamic>{
    'id': session.id,
    if (session.authId != null) 'authid': session.authId,
    if (session.authRole != null) 'authrole': session.authRole,
    if (session.authMethod != null) 'authmethod': session.authMethod,
    if (session.authProvider != null) 'authprovider': session.authProvider,
    'roles': session.roles,
    'worker_id': session.workerId,
    'connection_id': session.connectionId,
    'last_activity': session.lastActivity.toIso8601String(),
    if (session.protocol != null)
      'protocol': listenerProtocolToString(session.protocol!),
  };
}

Map<String, dynamic> _registrationDetails(RegistrationSnapshot registration) {
  final details = registration.callees.isEmpty
      ? const <String, Object?>{}
      : registration.callees.first.details;
  return <String, dynamic>{
    'id': registration.registrationId,
    'created': registration.created.toUtc().toIso8601String(),
    'uri': registration.procedure,
    'match': _procedureMatchPolicyName(registration.matchPolicy),
    'invoke': registration.policy.name,
    if (details['_ai_meta_data'] != null)
      '_ai_meta_data': details['_ai_meta_data'],
  };
}

Map<String, dynamic> _subscriptionDetails(SubscriptionSnapshot subscription) {
  return <String, dynamic>{
    'id': subscription.id,
    'created': subscription.created.toUtc().toIso8601String(),
    'uri': subscription.topic,
    'match': _topicMatchPolicyName(subscription.matchPolicy),
    if (subscription.options['_ai_meta_data'] != null)
      '_ai_meta_data': subscription.options['_ai_meta_data'],
  };
}

RegistrationSnapshot? _registrationById(
  Iterable<RegistrationSnapshot> registrations,
  int? id,
) {
  if (id == null) {
    return null;
  }
  for (final registration in registrations) {
    if (registration.registrationId == id) {
      return registration;
    }
  }
  return null;
}

SubscriptionSnapshot? _subscriptionById(
  Iterable<SubscriptionSnapshot> subscriptions,
  int? id,
) {
  if (id == null) {
    return null;
  }
  for (final subscription in subscriptions) {
    if (subscription.id == id) {
      return subscription;
    }
  }
  return null;
}

bool _registrationMatches(RegistrationSnapshot registration, String procedure) {
  switch (registration.matchPolicy) {
    case ProcedureMatchPolicy.exact:
      return registration.procedure == procedure;
    case ProcedureMatchPolicy.prefix:
      return procedure == registration.procedure ||
          procedure.startsWith('${registration.procedure}.') ||
          (registration.procedure.endsWith('.') &&
              procedure.startsWith(registration.procedure));
    case ProcedureMatchPolicy.wildcard:
      final pattern = registration.procedure.split('.');
      final candidate = procedure.split('.');
      if (pattern.length != candidate.length) {
        return false;
      }
      for (var i = 0; i < pattern.length; i += 1) {
        if (pattern[i].isNotEmpty && pattern[i] != candidate[i]) {
          return false;
        }
      }
      return true;
  }
}

bool _subscriptionMatches(SubscriptionSnapshot subscription, String topic) {
  switch (subscription.matchPolicy) {
    case TopicMatchPolicy.exact:
      return subscription.topic == topic;
    case TopicMatchPolicy.prefix:
      return topic.startsWith(subscription.topic);
    case TopicMatchPolicy.wildcard:
      final pattern = subscription.topic.split('.');
      final candidate = topic.split('.');
      if (pattern.length != candidate.length) {
        return false;
      }
      for (var i = 0; i < pattern.length; i += 1) {
        if (pattern[i].isNotEmpty && pattern[i] != candidate[i]) {
          return false;
        }
      }
      return true;
  }
}

String _procedureMatchPolicyName(ProcedureMatchPolicy policy) =>
    switch (policy) {
      ProcedureMatchPolicy.exact => 'exact',
      ProcedureMatchPolicy.prefix => 'prefix',
      ProcedureMatchPolicy.wildcard => 'wildcard',
    };

String _topicMatchPolicyName(TopicMatchPolicy policy) => switch (policy) {
  TopicMatchPolicy.exact => 'exact',
  TopicMatchPolicy.prefix => 'prefix',
  TopicMatchPolicy.wildcard => 'wildcard',
};

String? _firstStringArgument(mcp.McpWampToolCall call) {
  final first = call.payload.arguments?.firstOrNull;
  if (first is String) {
    return first;
  }
  final kwargs = call.payload.argumentsKeywords;
  return _stringFrom(kwargs?['uri']) ??
      _stringFrom(kwargs?['procedure']) ??
      _stringFrom(kwargs?['topic']);
}

int? _firstIntArgument(mcp.McpWampToolCall call) {
  final first = call.payload.arguments?.firstOrNull;
  if (first is int) {
    return first;
  }
  final kwargs = call.payload.argumentsKeywords;
  final candidate =
      kwargs?['id'] ?? kwargs?['registration'] ?? kwargs?['subscription'];
  if (candidate is int) {
    return candidate;
  }
  return null;
}

String? _matchOption(mcp.McpWampToolCall call) {
  final second =
      call.payload.arguments != null && call.payload.arguments!.length > 1
      ? call.payload.arguments![1]
      : null;
  if (second is Map) {
    return _stringFrom(second['match']);
  }
  return _stringFrom(call.payload.argumentsKeywords?['match']);
}

String? _stringFrom(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String? _stringOptionAny(Map<String, Object?> options, Iterable<String> keys) {
  for (final key in keys) {
    final value = _stringFrom(options[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

List<String> _stringListFrom(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final entry in value)
      if (entry is String) entry,
  ];
}

Map<String, Object?>? _jsonMapFrom(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

bool _boolOption(
  Map<String, Object?> options,
  String key, {
  required bool defaultValue,
}) {
  final value = options[key];
  return value is bool ? value : defaultValue;
}

bool _boolOptionAny(
  Map<String, Object?> options,
  Iterable<String> keys, {
  required bool defaultValue,
}) {
  for (final key in keys) {
    final value = options[key];
    if (value is bool) {
      return value;
    }
  }
  return defaultValue;
}

int? _intOption(Map<String, Object?> options, String key) {
  final value = options[key];
  return value is int ? value : null;
}

int? _intOptionAny(Map<String, Object?> options, Iterable<String> keys) {
  for (final key in keys) {
    final value = _intOption(options, key);
    if (value != null) {
      return value;
    }
  }
  return null;
}
