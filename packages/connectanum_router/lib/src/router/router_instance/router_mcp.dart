part of '../router_instance.dart';

const String _mcpSessionIdHeader = 'MCP-Session-Id';
const String _mcpProtocolVersionHeader = 'MCP-Protocol-Version';
const String _mcpLastEventIdHeader = 'Last-Event-ID';
const String _mcpSseContentType = 'text/event-stream';
const String _mcpJsonContentType = 'application/json';
const int _mcpSseEventHistoryLimit = 128;
const Set<String> _mcpSupportedHttpProtocolVersions = <String>{
  '2025-03-26',
  '2025-06-18',
  mcp.mcpLatestProtocolVersion,
};

Map<String, String> _mcpHttpResponseHeaders({
  bool json = true,
  String? sessionId,
  Map<String, String> extra = const <String, String>{},
}) {
  return <String, String>{
    if (json) HttpHeaders.contentTypeHeader: _mcpJsonContentType,
    _mcpProtocolVersionHeader: mcp.mcpLatestProtocolVersion,
    if (sessionId != null && sessionId.isNotEmpty)
      _mcpSessionIdHeader: sessionId,
    ...extra,
  };
}

Map<String, Object?> _mcpJsonRpcErrorPayload({
  required int code,
  required String message,
  Object? id,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message},
  };
}

NativeHttpResponse _mcpJsonRpcHttpError({
  required int status,
  required int code,
  required String message,
  Object? id,
  String? sessionId,
  Map<String, String> extraHeaders = const <String, String>{},
}) {
  return NativeHttpResponse(
    status: status,
    headers: _mcpHttpResponseHeaders(sessionId: sessionId, extra: extraHeaders),
    body: NativeHttpResponseJson(
      _mcpJsonRpcErrorPayload(code: code, message: message, id: id),
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

bool _mcpProtocolVersionHeaderSupported(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final value = _mcpHeaderValue(binding, request, _mcpProtocolVersionHeader);
  return value == null || _mcpSupportedHttpProtocolVersions.contains(value);
}

Set<String> _mcpAcceptTypes(RouterBinding binding, RouterHttpRequest request) {
  final accept = _mcpHeaderValue(binding, request, HttpHeaders.acceptHeader);
  if (accept == null) {
    return const <String>{};
  }
  return {
    for (final part in accept.split(','))
      part.split(';').first.trim().toLowerCase(),
  }..remove('');
}

bool _mcpAcceptAllowsJsonResponse(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  if (accepted.isEmpty) {
    return true;
  }
  return accepted.contains(_mcpJsonContentType) ||
      accepted.contains('application/*') ||
      accepted.contains('*/*');
}

bool _mcpAcceptAllowsSseResponse(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  return accepted.contains(_mcpSseContentType) || accepted.contains('*/*');
}

bool _mcpAcceptRequestsStreamableHttpSession(
  RouterBinding binding,
  RouterHttpRequest request,
) {
  final accepted = _mcpAcceptTypes(binding, request);
  return accepted.contains(_mcpJsonContentType) &&
      accepted.contains(_mcpSseContentType);
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

  final mode = _stringFrom(
    route.action.options['post_response_transport'],
  )?.trim().toLowerCase();
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
  return _boolOption(
    route.action.options,
    'stream_post_responses',
    defaultValue: true,
  );
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

String? _mcpRequestMethod(Object? rawMessage) {
  if (rawMessage is Map) {
    final method = rawMessage['method'];
    if (method is String) {
      return method;
    }
  }
  return null;
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

Future<bool> _mcpSendSseResponse(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  required String sessionId,
  required List<_RouterMcpSseEvent> events,
}) async {
  final handle = handshake?.handle ?? request.handshakeHandle;
  if (handle <= 0) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_missing_handshake',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
    });
    return false;
  }
  final NativeHttpResponseStream stream;
  try {
    stream = binding.runtime.openHttpResponseStream(
      handshakeHandle: handle,
      status: HttpStatus.ok,
      headers: _mcpHttpResponseHeaders(
        json: false,
        sessionId: sessionId,
        extra: const <String, String>{
          HttpHeaders.contentTypeHeader: 'text/event-stream; charset=utf-8',
          HttpHeaders.cacheControlHeader: 'no-cache',
          'X-Accel-Buffering': 'no',
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
    return false;
  } on NativeTransportException catch (error, stackTrace) {
    binding.onEvent?.call({
      'source': 'binding',
      'type': 'mcp_sse_stream_open_error',
      'connectionId': request.connectionId,
      'listenerId': request.listenerId,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    return false;
  }
  try {
    stream.close(_mcpSseEventsBytes(events));
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

  if (!_mcpOriginAllowed(binding, request, route)) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.forbidden,
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'Invalid Origin for MCP endpoint',
        sessionId: mcpSessionId,
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
        code: mcp.McpErrorCodes.invalidRequest,
        message: 'Unsupported MCP protocol version header',
        sessionId: mcpSessionId,
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
          sessionId: mcpSessionId,
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
        message: 'MCP HTTP endpoint supports GET, POST and DELETE',
        sessionId: mcpSessionId,
        extraHeaders: const <String, String>{
          HttpHeaders.allowHeader: 'GET, POST, DELETE',
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
        sessionId: mcpSessionId,
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
        sessionId: mcpSessionId,
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
        sessionId: mcpSessionId,
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
              sessionId: mcpSessionId,
              extra: binding._httpUnauthorizedHeaders(
                realm: resolvedRealmUri,
                authPath: binding._httpAuthPathFor(listenerSettings?.http),
              ),
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
      );
    }
  } on _HttpUnauthorized catch (error) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.unauthorized,
        headers: _mcpHttpResponseHeaders(
          sessionId: mcpSessionId,
          extra: binding._httpUnauthorizedHeaders(
            realm: resolvedRealmUri,
            authPath: binding._httpAuthPathFor(listenerSettings?.http),
          ),
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

  if (httpMethod == 'GET') {
    if (mcpSessionId == null) {
      await binding._sendImmediateHttpResponse(
        request: request,
        handshake: handshake,
        response: _mcpJsonRpcHttpError(
          status: HttpStatus.badRequest,
          code: mcp.McpErrorCodes.invalidRequest,
          message: 'MCP GET requests require an MCP-Session-Id header',
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
        ),
      );
      return;
    }
    await endpoint._refreshTools();
    final lastEventId = _mcpHeaderValue(
      binding,
      request,
      _mcpLastEventIdHeader,
    );
    final _RouterMcpSsePollBatch pollBatch;
    try {
      pollBatch = endpoint.ssePollEvents(
        sessionId: mcpSessionId,
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
        ),
      );
      return;
    }
    final sent = await _mcpSendSseResponse(
      binding,
      request: request,
      handshake: handshake,
      sessionId: mcpSessionId,
      events: pollBatch.events,
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
        ),
      );
    } else {
      endpoint.commitSsePollBatch(pollBatch);
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
        ),
      );
      return;
    }
    final removed = binding._removeMcpEndpointForRoute(
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
            )
          : NativeHttpResponse(
              status: HttpStatus.accepted,
              headers: _mcpHttpResponseHeaders(
                json: false,
                sessionId: mcpSessionId,
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
        headers: _mcpHttpResponseHeaders(sessionId: mcpSessionId),
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
  final streamableHttpRequest = _mcpAcceptRequestsStreamableHttpSession(
    binding,
    request,
  );
  if (mcpSessionId == null && !isInitialize && streamableHttpRequest) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: _mcpJsonRpcHttpError(
        status: HttpStatus.badRequest,
        code: mcp.McpErrorCodes.invalidRequest,
        message:
            'MCP Streamable HTTP requests require MCP-Session-Id after initialize',
      ),
    );
    return;
  }
  final issuedSessionId =
      mcpSessionId == null && isInitialize && streamableHttpRequest
      ? _mcpGenerateHttpSessionId()
      : null;
  final effectiveMcpSessionId = mcpSessionId ?? issuedSessionId;
  final endpoint = binding._mcpEndpointForRoute(
    request: request,
    route: route,
    session: session,
    mcpSessionId: effectiveMcpSessionId,
    create: isInitialize || mcpSessionId == null,
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
      ),
    );
    return;
  }

  final response = await endpoint.handleMessage(rawMessage);
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
      response: response,
    );
    final sent = await _mcpSendSseResponse(
      binding,
      request: request,
      handshake: handshake,
      sessionId: effectiveMcpSessionId,
      events: responseBatch.events,
    );
    if (sent) {
      endpoint.commitSsePollBatch(responseBatch);
      return;
    }
  }
  await binding._sendImmediateHttpResponse(
    request: request,
    handshake: handshake,
    response: response == null
        ? NativeHttpResponse(
            status: HttpStatus.accepted,
            headers: _mcpHttpResponseHeaders(
              json: false,
              sessionId: effectiveMcpSessionId,
            ),
            body: NativeHttpResponseText(''),
          )
        : NativeHttpResponse(
            status: HttpStatus.ok,
            headers: _mcpHttpResponseHeaders(sessionId: effectiveMcpSessionId),
            body: NativeHttpResponseJson(response),
          ),
  );
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

  _RouterMcpEndpoint? _mcpEndpointForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
    String? mcpSessionId,
    bool create = true,
  }) {
    final key = _mcpEndpointKeyForRoute(
      request: request,
      route: route,
      session: session,
      mcpSessionId: mcpSessionId,
    );
    if (!create) {
      return _mcpEndpoints[key];
    }
    return _mcpEndpoints.putIfAbsent(
      key,
      () => _RouterMcpEndpoint(binding: this, route: route, session: session),
    );
  }

  _RouterMcpEndpoint? _removeMcpEndpointForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
    required String mcpSessionId,
  }) {
    final endpoint = _mcpEndpoints.remove(
      _mcpEndpointKeyForRoute(
        request: request,
        route: route,
        session: session,
        mcpSessionId: mcpSessionId,
      ),
    );
    endpoint?.dispose();
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
}

final class _RouterMcpSsePollBatch {
  const _RouterMcpSsePollBatch({
    required this.events,
    required this.newEvents,
    required this.pendingMessages,
  });

  final List<_RouterMcpSseEvent> events;
  final List<_RouterMcpSseEvent> newEvents;
  final List<mcp.JsonMap> pendingMessages;
}

final class _UnknownMcpSseEventId implements Exception {
  const _UnknownMcpSseEventId(this.eventId);

  final String eventId;
}

class _RouterMcpEndpoint {
  _RouterMcpEndpoint({
    required this.binding,
    required this.route,
    required this.session,
  }) : server = mcp.McpServer(
         serverInfo: const mcp.McpServerInfo(
           name: 'connectanum-router',
           version: '0.1.0',
         ),
         instructions:
             'This MCP endpoint is hosted by the Connectanum router and uses '
             'the route-authenticated WAMP principal for calls and pub/sub.',
         toolListPageSize: _intOption(
           route.action.options,
           'tool_list_page_size',
         ),
         capabilities: const mcp.McpServerCapabilities(
           tools: mcp.McpToolCapabilities(listChanged: true),
         ),
       );

  final RouterBinding binding;
  final HttpRouteSettings route;
  final RouterSession session;
  final mcp.McpServer server;
  late final RealmAuthorizationProviderCache _authorizationProviderCache =
      RealmAuthorizationProviderCache(binding.settings);
  String? _toolSignature;
  final List<_RouterMcpSseEvent> _sseHistory = <_RouterMcpSseEvent>[];
  final List<mcp.JsonMap> _pendingSseMessages = <mcp.JsonMap>[];
  final Map<String, int> _sseStreamSequences = <String, int>{};
  int _nextSseStream = 0;

  bool ownsSession(RouterSession candidate) => identical(candidate, session);

  void dispose() {
    server.shutdown();
  }

  Future<mcp.JsonMap?> handleMessage(Object? rawMessage) async {
    await _refreshTools();
    final directResponse = await _handleDirectJsonMessage(rawMessage);
    if (directResponse != null) {
      return directResponse.response;
    }
    return server.handleMessage(rawMessage);
  }

  _RouterMcpSsePollBatch ssePollEvents({
    required String sessionId,
    String? lastEventId,
  }) {
    var streamId = 's${++_nextSseStream}';
    final replay = <_RouterMcpSseEvent>[];
    if (lastEventId != null) {
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

    final events = <_RouterMcpSseEvent>[...replay];
    final newEvents = <_RouterMcpSseEvent>[];
    final pendingMessages = List<mcp.JsonMap>.of(_pendingSseMessages);
    _pendingSseMessages.clear();
    for (final message in pendingMessages) {
      final event = _nextSseEvent(
        sessionId: sessionId,
        streamId: streamId,
        data: jsonEncode(message),
      );
      events.add(event);
      newEvents.add(event);
    }

    if (events.isEmpty) {
      final event = _nextSseEvent(
        sessionId: sessionId,
        streamId: streamId,
        retryMs: 1000,
      );
      events.add(event);
      newEvents.add(event);
    } else if (newEvents.isNotEmpty &&
        !events.any((event) => event.retryMs != null)) {
      final last = newEvents.removeLast();
      final replacement = _RouterMcpSseEvent(
        id: last.id,
        streamId: last.streamId,
        sequence: last.sequence,
        data: last.data,
        retryMs: 1000,
      );
      final index = events.lastIndexWhere((event) => event.id == last.id);
      if (index >= 0) {
        events[index] = replacement;
      }
      newEvents.add(replacement);
    }

    return _RouterMcpSsePollBatch(
      events: events,
      newEvents: newEvents,
      pendingMessages: pendingMessages,
    );
  }

  _RouterMcpSsePollBatch ssePostResponseEvents({
    required String sessionId,
    required mcp.JsonMap response,
  }) {
    final streamId = 's${++_nextSseStream}';
    final primer = _nextSseEvent(
      sessionId: sessionId,
      streamId: streamId,
      retryMs: 1000,
    );
    final responseEvent = _nextSseEvent(
      sessionId: sessionId,
      streamId: streamId,
      data: jsonEncode(response),
    );
    return _RouterMcpSsePollBatch(
      events: <_RouterMcpSseEvent>[primer, responseEvent],
      newEvents: <_RouterMcpSseEvent>[primer, responseEvent],
      pendingMessages: const <mcp.JsonMap>[],
    );
  }

  void commitSsePollBatch(_RouterMcpSsePollBatch batch) {
    for (final event in batch.newEvents) {
      _rememberSseEvent(event);
    }
  }

  void restoreSsePollBatch(_RouterMcpSsePollBatch batch) {
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
    while (_sseHistory.length > _mcpSseEventHistoryLimit) {
      final removed = _sseHistory.removeAt(0);
      if (!_sseHistory.any((event) => event.streamId == removed.streamId)) {
        _sseStreamSequences.remove(removed.streamId);
      }
    }
  }

  void _enqueueServerNotification(String method, {mcp.JsonMap? params}) {
    _pendingSseMessages.add(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      if (params != null && params.isNotEmpty) 'params': params,
    });
  }

  Future<_DirectJsonMessageResponse?> _handleDirectJsonMessage(
    Object? rawMessage,
  ) async {
    if (rawMessage is! Map) {
      return null;
    }
    final rawMethod = rawMessage['method'];
    if (rawMethod is! String || !_isDirectJsonMethod(rawMethod)) {
      return null;
    }

    final recoveredId = _recoverDirectJsonRequestId(rawMessage);
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
      return _DirectJsonMessageResponse(
        mcp.JsonRpcResponse.error(recoveredId, error).toJson(),
      );
    } catch (error) {
      return _DirectJsonMessageResponse(
        mcp.JsonRpcResponse.error(
          recoveredId,
          mcp.McpException(mcp.McpErrorCodes.internalError, error.toString()),
        ).toJson(),
      );
    }
  }

  bool _isDirectJsonMethod(String method) {
    return method == 'connectanum.tools.list' ||
        method == 'connectanum.tool.call' ||
        method == 'connectanum.tools.call' ||
        (method.contains('.') && server.tools[method] != null);
  }

  Future<mcp.JsonMap> _handleDirectJsonRequest(
    String method,
    mcp.JsonMap params,
  ) async {
    switch (method) {
      case 'connectanum.tools.list':
        return _listDirectJsonTools(params);
      case 'connectanum.tool.call':
      case 'connectanum.tools.call':
        return _callDirectJsonTool(params);
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

  mcp.JsonMap _listDirectJsonTools(mcp.JsonMap params) {
    final cursor = params['cursor'];
    if (cursor != null && cursor is! String) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'connectanum.tools.list.params.cursor must be a string',
      );
    }
    final page = server.tools.listPage(cursor: cursor as String?);
    final result = <String, Object?>{
      'tools': [for (final tool in page.tools) tool.toJson()],
    };
    final nextCursor = page.nextCursor;
    if (nextCursor != null) {
      result['nextCursor'] = nextCursor;
    }
    return result;
  }

  Future<mcp.JsonMap> _callDirectJsonTool(mcp.JsonMap params) async {
    final name = params['name'];
    if (name is! String) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'connectanum.tool.call.params.name must be a string',
      );
    }
    final arguments = mcp.jsonMapFrom(
      params['arguments'],
      label: 'connectanum.tool.call.params.arguments',
    );
    return _callDirectJsonToolByName(name, arguments);
  }

  Future<mcp.JsonMap> _callDirectJsonToolByName(
    String name,
    mcp.JsonMap arguments,
  ) async {
    final tool = server.tools[name];
    if (tool == null) {
      throw mcp.McpException(
        mcp.McpErrorCodes.invalidParams,
        'Unknown MCP tool: $name',
      );
    }
    try {
      final result = await tool.handler(
        mcp.McpToolRequest(name: name, arguments: arguments),
      );
      return result.toJson();
    } catch (error) {
      return mcp.McpToolResult.error(error.toString()).toJson();
    }
  }

  Future<void> _refreshTools() async {
    final api = await _buildApi();
    final tools = api.toTools(
      call: _call,
      publish: _publish,
      subscribe: _subscribe,
      unsubscribe: _unsubscribe,
      includePubSubTools: _boolOption(
        route.action.options,
        'include_pubsub_tools',
        defaultValue: true,
      ),
    );
    final signature = jsonEncode([for (final tool in tools) tool.toJson()]);
    if (signature == _toolSignature) {
      return;
    }
    server.tools.replaceAll(tools);
    if (_toolSignature != null &&
        server.state == mcp.McpServerState.initialized) {
      _enqueueServerNotification('notifications/tools/list_changed');
    }
    _toolSignature = signature;
  }

  Future<mcp.McpWampApi> _buildApi() async {
    final options = route.action.options;
    final procedures = <String, mcp.McpWampProcedure>{
      for (final procedure in _configuredProcedures(options))
        procedure.procedure: procedure,
    };
    final topics = <String, mcp.McpWampTopic>{
      for (final topic in _configuredTopics(options)) topic.topic: topic,
    };
    final includeRegistered = _boolOption(
      options,
      'include_registered_procedures',
      defaultValue: true,
    );
    final includeSubscriptions = _boolOption(
      options,
      'include_subscribed_topics',
      defaultValue: true,
    );
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

    final includeStandardMetaApi = _boolOption(
      options,
      'include_standard_meta_api',
      defaultValue: true,
    );
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
          await _isAuthorized(AuthorizationAction.call, procedure.procedure)) {
        filteredProcedures.add(procedure);
      }
    }

    final filteredTopics = <mcp.McpWampTopic>[];
    for (final topic in topics.values) {
      final allowPublish =
          topic.allowPublish &&
          await _isAuthorized(AuthorizationAction.publish, topic.topic);
      final allowSubscribe =
          topic.allowSubscribe &&
          await _isAuthorized(AuthorizationAction.subscribe, topic.topic);
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
      name: _stringFrom(options['name']) ?? 'connectanum-router',
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
        isInternal: true,
      ),
    );
    return decision.allowed;
  }

  RealmSettings? _realmSettings() {
    for (final realm in binding.settings.realms) {
      if (realm.name == session.realmUri) {
        return realm;
      }
    }
    return null;
  }

  Future<ResultPayload> _call(mcp.McpWampToolCall call) async {
    final metaResult = await _handleMetaCall(call);
    if (metaResult != null) {
      return metaResult;
    }
    final result = await session
        .call(
          call.procedure,
          arguments: call.payload.arguments,
          argumentsKeywords: call.payload.argumentsKeywords,
          options: call.payload.options,
        )
        .firstWhere((result) => !result.isProgressive());
    return result.toPayload();
  }

  Future<mcp.McpWampPublication?> _publish(
    mcp.McpWampPublishRequest request,
  ) async {
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
    final subscribed = await session.subscribe(
      request.topic,
      options: request.options,
    );
    subscribed.onEventPayload(
      (event) => onEvent(mcp.McpWampEvent.fromPayload(event)),
    );
    return mcp.McpWampSubscription(
      topic: request.topic,
      subscriptionId: subscribed.subscriptionId,
    );
  }

  Future<void> _unsubscribe(mcp.McpWampSubscription subscription) async {
    final subscriptionId = subscription.subscriptionId;
    if (subscriptionId != null) {
      await session.unsubscribe(subscriptionId);
    }
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
    final visibleRegistrations = await _visibleMetaRegistrations(
      snapshot.registrations,
    );
    final visibleSubscriptions = await _visibleMetaSubscriptions(
      snapshot.subscriptions,
    );
    switch (call.procedure) {
      case 'wamp.session.count':
        return _resultPayload(
          argumentsKeywords: {'count': snapshot.sessions.length},
        );
      case 'wamp.session.list':
        return _resultPayload(
          argumentsKeywords: {
            'session_ids': [
              for (final session in snapshot.sessions) session.id,
            ],
          },
        );
      case 'wamp.session.get':
        final id = _firstIntArgument(call);
        final sessionInfo = snapshot.sessions
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
        return _resultPayload(
          arguments: [
            for (final callee
                in registration?.callees ?? const <RegistrationRecord>[])
              callee.sessionId,
          ],
        );
      case 'wamp.registration.count_callees':
        final registration = _registrationById(
          visibleRegistrations,
          _firstIntArgument(call),
        );
        return _resultPayload(arguments: [registration?.callees.length ?? 0]);
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
        return _resultPayload(
          arguments: [
            for (final subscriber
                in subscription?.subscribers ?? const <SubscriberRecord>[])
              subscriber.sessionId,
          ],
        );
      case 'wamp.subscription.count_subscribers':
        final subscription = _subscriptionById(
          visibleSubscriptions,
          _firstIntArgument(call),
        );
        return _resultPayload(
          arguments: [subscription?.subscribers.length ?? 0],
        );
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
  final hasId = message.containsKey('id');
  final id = hasId ? message['id'] : null;
  if (hasId && !mcp.isJsonRpcId(id)) {
    throw mcp.McpException(
      mcp.McpErrorCodes.invalidRequest,
      'JSON-RPC id must be a string, number, or null',
    );
  }
  return _DirectJsonRequest(
    id: id,
    isNotification: !hasId,
    method: method,
    params: mcp.jsonMapFrom(message['params']),
  );
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

mcp.McpWampProcedure _procedureFromConfig(Map<String, Object?> config) {
  final procedure =
      _stringFrom(config['procedure']) ??
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP procedure config requires procedure or uri'));
  final metadata = _metadataFromDetails(config);
  return mcp.McpWampProcedure(
    procedure: procedure,
    toolName: _stringFrom(config['tool_name']) ?? _stringFrom(config['name']),
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
    allowPublish: _boolOption(config, 'allow_publish', defaultValue: true),
    allowSubscribe: _boolOption(config, 'allow_subscribe', defaultValue: true),
    metadata: metadata,
  );
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

int? _intOption(Map<String, Object?> options, String key) {
  final value = options[key];
  return value is int ? value : null;
}
