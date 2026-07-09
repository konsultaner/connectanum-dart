import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

const _supportedMcpProtocolVersions = <String>[
  '2025-03-26',
  '2025-06-18',
  McpStreamableHttpClient.latestProtocolVersion,
];
final _mcpToolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage(stdout);
    return;
  }

  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage(stderr);
    exitCode = 64;
    return;
  }

  if (options.dryRun) {
    _printDryRunSummary(stdout, options);
    return;
  }

  final clientContext = await _createClient(options);
  final client = clientContext.client;
  try {
    await _runDirectJsonExample(client, options);
    await _runDirectBatchExample(client, options);
    await _runDirectWampMetadataExample(client, options);
    if (options.pubsubTopic != null) {
      await _runDirectPubSubExample(client, options);
    }
    await _runStreamableSessionExample(
      client,
      options,
      authorizationHeader: clientContext.authorizationHeader,
    );
  } finally {
    try {
      await _deleteStreamableSession(client);
    } finally {
      client.close(force: true);
    }
  }

  if (options.authLifecycleSmoke) {
    await _runAuthLifecycleSmoke(options);
  }
}

Future<_ClientContext> _createClient(_Options options) async {
  if (options.authEndpoint != null) {
    final authClient = ConnectanumHttpAuthClient(
      options.authEndpoint!,
      httpClient: _shortLivedHttpClient(),
      closeHttpClient: true,
    );
    try {
      final grant = await authClient.issueTicketToken(
        realm: options.authRealm!,
        authId: options.authId!,
        ticket: options.ticket!,
      );
      return _ClientContext(
        McpStreamableHttpClient.withAuthGrant(
          options.endpoint,
          grant,
          httpClient: _shortLivedHttpClient(),
          defaultProtocolVersion: options.protocolVersion,
          closeHttpClient: true,
        ),
        authorizationHeader: 'Bearer ${grant.accessToken}',
      );
    } finally {
      authClient.close(force: true);
    }
  }

  final bearerToken = options.bearerToken;
  if (bearerToken != null) {
    return _ClientContext(
      McpStreamableHttpClient.withBearerToken(
        options.endpoint,
        bearerToken,
        httpClient: _shortLivedHttpClient(),
        defaultProtocolVersion: options.protocolVersion,
        closeHttpClient: true,
      ),
      authorizationHeader: 'Bearer $bearerToken',
    );
  }

  return _ClientContext(
    McpStreamableHttpClient(
      options.endpoint,
      httpClient: _shortLivedHttpClient(),
      defaultProtocolVersion: options.protocolVersion,
      closeHttpClient: true,
    ),
  );
}

class _ClientContext {
  const _ClientContext(this.client, {this.authorizationHeader});

  final McpStreamableHttpClient client;
  final String? authorizationHeader;
}

void _printDryRunSummary(IOSink sink, _Options options) {
  final authMode = switch ((options.bearerToken, options.authEndpoint)) {
    (String(), _) => 'bearer',
    (_, Uri()) => 'ticket',
    _ => 'none',
  };

  sink.writeln(
    jsonEncode({
      'dryRun': true,
      'endpoint': options.endpoint.toString(),
      'authMode': authMode,
      'protocolVersion': options.protocolVersion,
      if (options.authEndpoint != null)
        'authEndpoint': options.authEndpoint.toString(),
      if (options.authRealm != null) 'realm': options.authRealm,
      if (options.authId != null) 'authId': options.authId,
      if (options.authLifecycleSmoke) 'authLifecycleSmoke': true,
      if (options.toolName != null)
        'tool': {'name': options.toolName, 'arguments': options.toolArguments},
      if (options.resourceUri != null) ...{
        'resourceUri': options.resourceUri,
        'resourceTemplates': true,
      },
      if (options.promptName != null)
        'prompt': {
          'name': options.promptName,
          'arguments': options.promptArguments,
        },
      if (options.wampProcedure != null) ...{
        'wampProcedure': options.wampProcedure,
        'configuredRegistrationMetadata': true,
      },
      if (options.wampTopic != null) ...{
        'wampTopic': options.wampTopic,
        'configuredSubscriptionMetadata': true,
      },
      if (options.pubsubTopic != null)
        'pubsub': {
          'topic': options.pubsubTopic,
          'event': options.pubsubEvent,
          'subscriptionMetadata': true,
        },
    }),
  );
}

// This example is a short-lived CLI, so avoid keeping HTTP sockets alive
// after its final request completes.
HttpClient _shortLivedHttpClient() => HttpClient()..idleTimeout = Duration.zero;

Future<void> _deleteStreamableSession(McpStreamableHttpClient client) async {
  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Streamable session delete did not clear local session state.',
    );
  }
}

Future<void> _runAuthLifecycleSmoke(_Options options) async {
  final authEndpoint = options.authEndpoint;
  if (authEndpoint == null) {
    throw StateError('Auth lifecycle smoke requires --auth-url.');
  }

  final authClient = ConnectanumHttpAuthClient(
    authEndpoint,
    httpClient: _shortLivedHttpClient(),
    closeHttpClient: true,
  );
  McpStreamableHttpClient? refreshedClient;
  McpStreamableHttpClient? revokedClient;
  try {
    final grant = await authClient.issueTicketToken(
      realm: options.authRealm!,
      authId: options.authId!,
      ticket: options.ticket!,
      headers: const <String, String>{
        'x-consumer-trace': 'router-hosted-client-auth-lifecycle-issue',
      },
    );
    final refreshToken = grant.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('Auth lifecycle smoke did not receive a refresh token.');
    }

    final refreshed = await authClient.refreshToken(
      refreshToken,
      headers: const <String, String>{
        'x-consumer-trace': 'router-hosted-client-auth-lifecycle-refresh',
      },
    );
    final refreshedRefreshToken = refreshed.refreshToken;
    if (refreshedRefreshToken == null || refreshedRefreshToken.isEmpty) {
      throw StateError('Auth lifecycle smoke did not rotate a refresh token.');
    }

    refreshedClient = McpStreamableHttpClient.withAuthGrant(
      options.endpoint,
      refreshed,
      httpClient: _shortLivedHttpClient(),
      defaultProtocolVersion: options.protocolVersion,
      closeHttpClient: true,
    );
    await refreshedClient.pingDirect(
      id: 'auth-lifecycle-refreshed-direct-ping',
      headers: const <String, String>{
        'x-consumer-trace': 'auth-lifecycle-refreshed-direct-ping',
      },
    );
    if (refreshedClient.sessionId != null ||
        refreshedClient.lastEventId != null) {
      throw StateError('Auth lifecycle direct ping created Streamable state.');
    }

    await refreshedClient.initialize(
      id: 'auth-lifecycle-refreshed-initialize',
      headers: const <String, String>{
        'x-consumer-trace': 'auth-lifecycle-refreshed-initialize',
      },
    );
    final refreshedSessionId = refreshedClient.sessionId;
    if (refreshedSessionId == null || refreshedSessionId.isEmpty) {
      throw StateError(
        'Auth lifecycle refreshed grant did not initialize a Streamable session.',
      );
    }
    await refreshedClient.notifyInitialized(
      headers: const <String, String>{
        'x-consumer-trace': 'auth-lifecycle-refreshed-initialized',
      },
    );
    await _deleteStreamableSession(refreshedClient);
    refreshedClient.close(force: true);
    refreshedClient = null;

    await authClient.revokeToken(
      refreshed.accessToken,
      headers: const <String, String>{
        'x-consumer-trace': 'router-hosted-client-auth-lifecycle-revoke-access',
      },
    );
    revokedClient = McpStreamableHttpClient.withAuthGrant(
      options.endpoint,
      refreshed,
      httpClient: _shortLivedHttpClient(),
      defaultProtocolVersion: options.protocolVersion,
      closeHttpClient: true,
    );
    await _expectMcpUnauthorized(
      () async {
        await revokedClient!.pingDirect(
          id: 'auth-lifecycle-revoked-direct-ping',
          headers: const <String, String>{
            'x-consumer-trace': 'auth-lifecycle-revoked-direct-ping',
          },
        );
      },
      acceptedMessage: 'Auth lifecycle smoke accepted a revoked access token.',
      rejectionLabel: 'Auth lifecycle revoked access token',
    );
    if (revokedClient.sessionId != null || revokedClient.lastEventId != null) {
      throw StateError('Auth lifecycle revoked ping changed Streamable state.');
    }

    await authClient.revokeToken(
      refreshedRefreshToken,
      tokenTypeHint: 'refresh_token',
      headers: const <String, String>{
        'x-consumer-trace':
            'router-hosted-client-auth-lifecycle-revoke-refresh',
      },
    );
    await _expectAuthRefreshUnauthorized(authClient, refreshedRefreshToken);

    stdout.writeln(
      jsonEncode({
        'authLifecycle': {
          'issued': true,
          'refreshed': true,
          'refreshedDirectPing': true,
          'refreshedStreamableSession': true,
          'revokedAccessRejected': true,
          'revokedRefreshRejected': true,
        },
      }),
    );
  } finally {
    refreshedClient?.close(force: true);
    revokedClient?.close(force: true);
    authClient.close(force: true);
  }
}

Future<void> _expectMcpUnauthorized(
  Future<void> Function() request, {
  required String acceptedMessage,
  required String rejectionLabel,
}) async {
  try {
    await request();
    throw StateError(acceptedMessage);
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        '$rejectionLabel returned ${error.statusCode}, expected '
        '${HttpStatus.unauthorized}.',
      );
    }
  }
}

Future<void> _expectAuthRefreshUnauthorized(
  ConnectanumHttpAuthClient authClient,
  String refreshToken,
) async {
  try {
    await authClient.refreshToken(
      refreshToken,
      headers: const <String, String>{
        'x-consumer-trace': 'auth-lifecycle-refresh-revoked',
      },
    );
    throw StateError('Auth lifecycle smoke accepted a revoked refresh token.');
  } on ConnectanumHttpAuthException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Auth lifecycle revoked refresh token returned ${error.statusCode}, '
        'expected ${HttpStatus.unauthorized}.',
      );
    }
  }
}

void _expectStreamableStateUnchanged(
  McpStreamableHttpClient client, {
  required String? sessionId,
  required String? lastEventId,
  required String label,
}) {
  if (client.sessionId != sessionId || client.lastEventId != lastEventId) {
    throw StateError('$label changed Streamable state.');
  }
}

Future<void> _expectInvalidLastEventIdRejected(
  McpStreamableHttpClient client, {
  required String sessionId,
  required String? lastEventId,
}) async {
  try {
    await client.poll(
      lastEventId: '$sessionId:missing:1',
      headers: const <String, String>{
        'x-consumer-trace':
            'router-hosted-client-streamable-invalid-last-event-id',
      },
    );
    throw StateError('Streamable invalid Last-Event-ID was accepted.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Streamable invalid Last-Event-ID returned ${error.statusCode}, '
        'expected ${HttpStatus.badRequest}.',
      );
    }
    if (!error.body.contains('Last-Event-ID')) {
      throw StateError(
        'Streamable invalid Last-Event-ID rejection did not name the header.',
      );
    }
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: 'Streamable invalid Last-Event-ID',
  );
}

Future<void> _expectEmptyLastEventIdStartsFreshPoll(
  McpStreamableHttpClient client, {
  required String sessionId,
  required String? lastEventId,
}) async {
  final events = await client.poll(
    lastEventId: '',
    headers: const <String, String>{
      'x-consumer-trace': 'router-hosted-client-streamable-empty-last-event-id',
    },
  );
  if (events.isEmpty) {
    throw StateError('Streamable empty Last-Event-ID returned no SSE events.');
  }
  final nextLastEventId = client.lastEventId;
  if (client.sessionId != sessionId ||
      nextLastEventId == null ||
      nextLastEventId.isEmpty) {
    throw StateError('Streamable empty Last-Event-ID lost session state.');
  }
  if (lastEventId != null && nextLastEventId == lastEventId) {
    throw StateError(
      'Streamable empty Last-Event-ID reused the previous SSE cursor.',
    );
  }
}

Future<void> _expectMalformedSessionIdRejected(
  McpStreamableHttpClient client,
  String? authorizationHeader, {
  required String sessionId,
  required String? lastEventId,
}) async {
  final httpClient = _shortLivedHttpClient();
  try {
    final request = await httpClient.postUrl(client.endpoint);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('MCP-Protocol-Version', client.protocolVersion);
    request.headers.set('MCP-Session-Id', 'malformed session');
    request.headers.set(
      'x-consumer-trace',
      'router-hosted-client-streamable-malformed-session-id',
    );
    if (authorizationHeader != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorizationHeader);
    }
    request.headers.contentType = ContentType.json;
    request.contentLength = 0;

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Streamable malformed MCP-Session-Id returned '
        '${response.statusCode}, expected ${HttpStatus.badRequest}.',
      );
    }
    if (response.headers.value('MCP-Session-Id') != null) {
      throw StateError(
        'Streamable malformed MCP-Session-Id rejection echoed a session id.',
      );
    }
    if (!body.contains('MCP-Session-Id')) {
      throw StateError(
        'Streamable malformed MCP-Session-Id rejection did not name the header.',
      );
    }
  } finally {
    httpClient.close(force: true);
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: 'Streamable malformed MCP-Session-Id',
  );
}

Future<void> _expectDirectJsonStaleSessionIdIgnored(
  McpStreamableHttpClient client,
  String? authorizationHeader, {
  required String sessionId,
  required String? lastEventId,
}) async {
  final httpClient = _shortLivedHttpClient();
  try {
    final request = await httpClient.postUrl(client.endpoint);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('MCP-Protocol-Version', client.protocolVersion);
    request.headers.set('MCP-Session-Id', 'unknown-direct-json-session-id');
    request.headers.set(
      'x-consumer-trace',
      'router-hosted-client-direct-json-stale-session-id',
    );
    if (authorizationHeader != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorizationHeader);
    }
    request.headers.contentType = ContentType.json;
    final payload = utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 'direct-json-stale-session-id',
        'method': 'tools/list',
        'params': {},
      }),
    );
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Direct JSON stale MCP-Session-Id returned ${response.statusCode}, '
        'expected ${HttpStatus.ok}: $body',
      );
    }
    if (response.headers.value('MCP-Session-Id') != null) {
      throw StateError('Direct JSON stale MCP-Session-Id echoed a session id.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> ||
        decoded['id'] != 'direct-json-stale-session-id' ||
        decoded['result'] is! Map<String, Object?>) {
      throw StateError('Direct JSON stale MCP-Session-Id returned $body.');
    }
  } finally {
    httpClient.close(force: true);
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: 'Direct JSON stale MCP-Session-Id',
  );
}

Future<void> _runDirectJsonExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final ping = await client.pingDirect(id: 'direct-ping');
  stdout.writeln(jsonEncode({'directPing': ping}));

  final standardCatalog = await client.listToolsDirect(
    id: 'direct-standard-tools',
  );
  final catalog = await client.listConnectanumToolsDirect(id: 'direct-tools');
  stdout.writeln(
    jsonEncode({
      'directStandardTools': [
        for (final tool in standardCatalog.tools) tool['name'],
      ],
      if (standardCatalog.nextCursor != null)
        'directStandardNextCursor': standardCatalog.nextCursor,
      'directTools': [for (final tool in catalog.tools) tool['name']],
      if (catalog.nextCursor != null) 'nextCursor': catalog.nextCursor,
    }),
  );

  final toolName = options.toolName;
  if (toolName != null) {
    _expectCatalogContainsValue(
      catalog: catalog.tools,
      field: 'name',
      value: toolName,
      label: 'Direct tool',
    );
    _expectCatalogContainsValue(
      catalog: standardCatalog.tools,
      field: 'name',
      value: toolName,
      label: 'Direct standard tool',
    );
    final methodCatalog = await client.callConnectanumMethodDirect(
      'connectanum.tools.list',
      id: 'direct-tools-method',
    );
    final methodToolCatalog = methodCatalog['tools'];
    _expectCatalogContainsValue(
      catalog: methodToolCatalog,
      field: 'name',
      value: toolName,
      label: 'Direct tool method list',
    );
    final result = _expectToolResultSucceeded(
      await client.callConnectanumToolDirect(
        toolName,
        id: 'direct-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Direct tool call',
    );
    final standardResult = _expectToolResultSucceeded(
      await client.callToolDirect(
        toolName,
        id: 'direct-standard-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Direct standard tool call',
    );
    final methodResult = _expectToolResultSucceeded(
      await client.callConnectanumMethodDirect(
        'connectanum.tool.call',
        id: 'direct-tool-call-method',
        params: <String, Object?>{
          'name': toolName,
          'arguments': options.toolArguments,
        },
      ),
      label: 'Direct tool method call',
    );
    stdout.writeln(
      jsonEncode({
        'directToolResult': result,
        'directStandardToolResult': standardResult,
        'directToolMethodCatalog': methodToolCatalog,
        'directToolMethodResult': methodResult,
      }),
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    final resources = await client.listResourcesDirect(id: 'direct-resources');
    _expectCatalogContainsValue(
      catalog: resources.resources,
      field: 'uri',
      value: resourceUri,
      label: 'Direct resource',
    );
    final resourceTemplates = await client.listResourceTemplatesDirect(
      id: 'direct-resource-templates',
    );
    final content = await client.readResourceDirect(
      resourceUri,
      id: 'direct-resource-read',
    );
    final methodResources = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-list-method',
        'method': 'resources/list',
        'params': {},
      }),
      'direct-resource-list-method',
      label: 'Direct JSON resource method list',
    );
    _expectCatalogContainsValue(
      catalog: methodResources['resources'],
      field: 'uri',
      value: resourceUri,
      label: 'Direct JSON resource method list',
    );
    final methodResourceTemplates = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-templates-method',
        'method': 'resources/templates/list',
        'params': {},
      }),
      'direct-resource-templates-method',
      label: 'Direct JSON resource template method list',
    );
    final methodContent = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-resource-read-method',
        'method': 'resources/read',
        'params': {'uri': resourceUri},
      }),
      'direct-resource-read-method',
      label: 'Direct JSON resource method read',
    );
    stdout.writeln(
      jsonEncode({
        'directResources': [
          for (final resource in resources.resources) resource['uri'],
        ],
        'directResourceTemplates': [
          for (final template in resourceTemplates.resourceTemplates)
            template['uriTemplate'],
        ],
        if (resourceTemplates.nextCursor != null)
          'directResourceTemplateNextCursor': resourceTemplates.nextCursor,
        'directResourceContent': content,
        'directResourceMethodResources': methodResources['resources'],
        'directResourceMethodTemplates':
            methodResourceTemplates['resourceTemplates'],
        'directResourceMethodContent': methodContent,
      }),
    );
  }

  final promptName = options.promptName;
  if (promptName != null) {
    final prompts = await client.listPromptsDirect(id: 'direct-prompts');
    _expectCatalogContainsValue(
      catalog: prompts.prompts,
      field: 'name',
      value: promptName,
      label: 'Direct prompt',
    );
    final prompt = await client.getPromptDirect(
      promptName,
      id: 'direct-prompt-get',
      arguments: options.promptArguments,
    );
    final methodPrompts = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-prompts-method',
        'method': 'prompts/list',
        'params': {},
      }),
      'direct-prompts-method',
      label: 'Direct JSON prompt method list',
    );
    _expectCatalogContainsValue(
      catalog: methodPrompts['prompts'],
      field: 'name',
      value: promptName,
      label: 'Direct JSON prompt method list',
    );
    final methodPrompt = _responseResult(
      await client.postDirect({
        'jsonrpc': '2.0',
        'id': 'direct-prompt-get-method',
        'method': 'prompts/get',
        'params': {'name': promptName, 'arguments': options.promptArguments},
      }),
      'direct-prompt-get-method',
      label: 'Direct JSON prompt method get',
    );
    stdout.writeln(
      jsonEncode({
        'directPrompts': [for (final prompt in prompts.prompts) prompt['name']],
        'directPrompt': prompt,
        'directPromptMethodCatalog': methodPrompts['prompts'],
        'directPromptMethod': methodPrompt,
      }),
    );
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON',
  );
}

Future<void> _runDirectBatchExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final messages = <McpJsonMap>[
    {
      'jsonrpc': '2.0',
      'id': 'direct-batch-standard-tools',
      'method': 'tools/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': 'direct-batch-tools',
      'method': 'connectanum.tools.list',
      'params': {},
    },
  ];

  final toolName = options.toolName;
  if (toolName != null) {
    messages.add(
      _toolCallBatchRequest(
        id: 'direct-batch-standard-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: false,
      ),
    );
    messages.add(
      _toolCallBatchRequest(
        id: 'direct-batch-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: true,
      ),
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resources',
      'method': 'resources/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': resourceUri},
    });
  }

  final promptName = options.promptName;
  if (promptName != null) {
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    });
    messages.add({
      'jsonrpc': '2.0',
      'id': 'direct-batch-prompt-get',
      'method': 'prompts/get',
      'params': {'name': promptName, 'arguments': options.promptArguments},
    });
  }

  final wampProcedure = options.wampProcedure;
  final wampTopic = options.wampTopic;
  final includeWampMetadata = wampProcedure != null || wampTopic != null;
  if (includeWampMetadata) {
    messages.addAll([
      {
        'jsonrpc': '2.0',
        'id': 'direct-batch-wamp-session-count',
        'method': 'wamp.session.count',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': 'direct-batch-wamp-session-list',
        'method': 'wamp.session.list',
        'params': {},
      },
    ]);
  }

  if (wampProcedure != null) {
    messages.addAll([
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-procedure-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'procedure'},
        directJson: true,
      ),
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-procedure-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampProcedure, 'kind': 'procedure'},
        directJson: true,
      ),
    ]);
  }

  if (wampTopic != null) {
    messages.addAll([
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-topic-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'topic'},
        directJson: true,
      ),
      _toolCallBatchRequest(
        id: 'direct-batch-wamp-topic-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampTopic, 'kind': 'topic'},
        directJson: true,
      ),
    ]);
  }

  final batchResponses = await client.postBatchDirect(
    messages,
    headers: const {'x-consumer-trace': 'router-hosted-client-direct-batch'},
  );
  final responseIds = _expectBatchResponses(batchResponses, [
    for (final message in messages) message['id']! as String,
  ], label: 'Direct JSON');
  if (toolName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-standard-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Direct JSON batch standard tool',
    );
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Direct JSON batch tool',
    );
  }
  if (resourceUri != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-resources',
      catalogKey: 'resources',
      field: 'uri',
      value: resourceUri,
      label: 'Direct JSON batch resource',
    );
  }
  if (promptName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'direct-batch-prompts',
      catalogKey: 'prompts',
      field: 'name',
      value: promptName,
      label: 'Direct JSON batch prompt',
    );
  }
  Map<String, Object?>? batchWampSessionMetadata;
  if (includeWampMetadata) {
    final sessionDiscovery = _expectWampSessionMetaBatchDiscovery(
      batchResponses,
      countId: 'direct-batch-wamp-session-count',
      listId: 'direct-batch-wamp-session-list',
      label: 'Direct JSON batch WAMP session metadata',
    );
    final selectedSessionId = sessionDiscovery['selectedSessionId']! as int;
    final sessionGetId = 'direct-batch-wamp-session-get';
    final sessionGetResponses = await client.postBatchDirect(
      [
        {
          'jsonrpc': '2.0',
          'id': sessionGetId,
          'method': 'wamp.session.get',
          'params': {'id': selectedSessionId},
        },
      ],
      headers: const {
        'x-consumer-trace':
            'router-hosted-client-direct-batch-wamp-session-get',
      },
    );
    final detailResponseIds = _expectBatchResponses(
      sessionGetResponses,
      [sessionGetId],
      label: 'Direct JSON batch WAMP session metadata details',
    );
    final sessionDetails = _expectWampSessionMetaBatchDetails(
      sessionGetResponses,
      getId: sessionGetId,
      selectedSessionId: selectedSessionId,
      label: 'Direct JSON batch WAMP session metadata',
    );
    batchWampSessionMetadata = <String, Object?>{
      ...sessionDiscovery,
      ...sessionDetails,
      'detailResponseIds': detailResponseIds,
    };
  }
  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON batch',
  );
  final directBatch = <String, Object?>{'responseIds': responseIds};
  if (batchWampSessionMetadata != null) {
    directBatch['wampSessionMetadata'] = batchWampSessionMetadata;
  }
  stdout.writeln(jsonEncode({'directBatch': directBatch}));
}

McpJsonMap _toolCallBatchRequest({
  required String id,
  required String name,
  required McpJsonMap arguments,
  required bool directJson,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'method': directJson ? 'connectanum.tool.call' : 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  };
}

List<String> _expectBatchResponses(
  List<McpJsonMap>? responses,
  List<String> expectedIds, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  if (responses.length != expectedIds.length) {
    throw StateError(
      '$label batch returned ${responses.length} responses for '
      '${expectedIds.length} requests.',
    );
  }

  final responseIds = <String>[];
  for (final response in responses) {
    final id = response['id'];
    if (id is! String) {
      throw StateError('$label batch response had a non-string id.');
    }
    if (response.containsKey('error')) {
      throw StateError(
        '$label batch response $id errored: ${response['error']}',
      );
    }
    responseIds.add(id);
  }

  final missingIds = [
    for (final expectedId in expectedIds)
      if (!responseIds.contains(expectedId)) expectedId,
  ];
  if (missingIds.isNotEmpty) {
    throw StateError('$label batch missed responses for $missingIds.');
  }
  return responseIds;
}

void _expectBatchCatalogContains(
  List<McpJsonMap>? responses, {
  required String id,
  required String catalogKey,
  required String field,
  required String value,
  required String label,
}) {
  final result = _batchResult(responses, id, label: label);
  _expectCatalogContainsValue(
    catalog: result[catalogKey],
    field: field,
    value: value,
    label: label,
  );
}

McpJsonMap _batchResult(
  List<McpJsonMap>? responses,
  String id, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  for (final response in responses) {
    if (response['id'] != id) {
      continue;
    }
    final result = response['result'];
    if (result is Map) {
      return result.cast<String, Object?>();
    }
    throw StateError('$label batch response $id had a non-object result.');
  }
  throw StateError('$label batch missed response $id.');
}

McpJsonMap _responseResult(
  McpJsonMap? response,
  String id, {
  required String label,
}) {
  if (response == null) {
    throw StateError('$label returned no response.');
  }
  if (response['id'] != id) {
    throw StateError(
      '$label returned response id ${response['id']} instead of $id.',
    );
  }
  final result = response['result'];
  if (result is Map) {
    return result.cast<String, Object?>();
  }
  if (response.containsKey('error')) {
    throw StateError('$label returned error ${jsonEncode(response['error'])}.');
  }
  throw StateError('$label response had a non-object result.');
}

Future<void> _runDirectWampMetadataExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final procedure = options.wampProcedure;
  final topic = options.wampTopic;
  if (procedure == null && topic == null) {
    return;
  }

  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final metadata = <String, Object?>{};

  final sessionMetadata = await _expectWampSessionMetaDirect(
    client,
    countId: 'direct-wamp-session-count',
    listId: 'direct-wamp-session-list',
    getId: 'direct-wamp-session-get',
  );
  metadata['sessionCount'] = sessionMetadata['count'];
  metadata['sessionMetadata'] = sessionMetadata;

  if (procedure != null) {
    final procedures = await client.listWampApiDirect(
      id: 'direct-wamp-procedure-api-list',
      kind: 'procedure',
    );
    final procedureCatalog = procedures['procedures'];
    _expectWampCatalogContains(
      catalog: procedureCatalog,
      uri: procedure,
      label: 'Direct WAMP procedure',
    );
    final methodProcedures = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.list',
        id: 'direct-wamp-procedure-api-list-method',
        params: const <String, Object?>{'kind': 'procedure'},
      ),
      label: 'Direct WAMP procedure method list',
    );
    final methodProcedureCatalog = methodProcedures['procedures'];
    _expectWampCatalogContains(
      catalog: methodProcedureCatalog,
      uri: procedure,
      label: 'Direct WAMP procedure method',
    );
    final description = await client.describeWampApiDirect(
      procedure,
      id: 'direct-wamp-procedure-api-describe',
      kind: 'procedure',
    );
    final methodDescription = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.describe',
        id: 'direct-wamp-procedure-api-describe-method',
        params: <String, Object?>{'uri': procedure, 'kind': 'procedure'},
      ),
      label: 'Direct WAMP procedure method describe',
    );
    _expectWampCatalogContains(
      catalog: [methodDescription],
      uri: procedure,
      label: 'Direct WAMP procedure method describe',
    );
    final registration = await client.matchWampRegistrationDirect(
      procedure,
      id: 'direct-wamp-registration-match',
    );
    final configuredRegistrationMetadata =
        await _expectConfiguredWampRegistrationMetaDirect(client, procedure);
    metadata['procedure'] = {
      'name': procedure,
      'catalog': procedureCatalog,
      'methodCatalog': methodProcedureCatalog,
      'description': description,
      'methodDescription': methodDescription,
      'registration': _wampMetaResultJson(registration),
      'configuredRegistrationMetadata': configuredRegistrationMetadata,
    };
  }

  if (topic != null) {
    final topics = await client.listWampApiDirect(
      id: 'direct-wamp-topic-api-list',
      kind: 'topic',
    );
    final topicCatalog = topics['topics'];
    _expectWampCatalogContains(
      catalog: topicCatalog,
      uri: topic,
      label: 'Direct WAMP topic',
    );
    final methodTopics = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.list',
        id: 'direct-wamp-topic-api-list-method',
        params: const <String, Object?>{'kind': 'topic'},
      ),
      label: 'Direct WAMP topic method list',
    );
    final methodTopicCatalog = methodTopics['topics'];
    _expectWampCatalogContains(
      catalog: methodTopicCatalog,
      uri: topic,
      label: 'Direct WAMP topic method',
    );
    final description = await client.describeWampApiDirect(
      topic,
      id: 'direct-wamp-topic-api-describe',
      kind: 'topic',
    );
    final methodDescription = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.api.describe',
        id: 'direct-wamp-topic-api-describe-method',
        params: <String, Object?>{'uri': topic, 'kind': 'topic'},
      ),
      label: 'Direct WAMP topic method describe',
    );
    _expectWampCatalogContains(
      catalog: [methodDescription],
      uri: topic,
      label: 'Direct WAMP topic method describe',
    );
    final configuredSubscriptionMetadata =
        await _expectConfiguredWampSubscriptionMetaDirect(client, topic);
    metadata['topic'] = {
      'name': topic,
      'catalog': topicCatalog,
      'methodCatalog': methodTopicCatalog,
      'description': description,
      'methodDescription': methodDescription,
      'configuredSubscriptionMetadata': configuredSubscriptionMetadata,
    };
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct WAMP metadata',
  );

  stdout.writeln(jsonEncode({'directWampMetadata': metadata}));
}

McpJsonMap _expectToolResultSucceeded(
  McpJsonMap result, {
  required String label,
}) {
  if (result['isError'] == true) {
    throw StateError('$label returned an error: ${jsonEncode(result)}.');
  }
  return result;
}

McpJsonMap _structuredContentFromToolResult(
  McpJsonMap result, {
  required String label,
}) {
  final toolResult = _expectToolResultSucceeded(result, label: label);
  final structuredContent = toolResult['structuredContent'];
  if (structuredContent is Map) {
    return structuredContent.cast<String, Object?>();
  }
  throw StateError('$label returned no structured content.');
}

Map<String, Object?> _wampMetaResultJson(
  McpStreamableWampMetaCallResult result,
) {
  return {
    'procedure': result.procedure,
    'arguments': result.arguments,
    'argumentsKeywords': result.argumentsKeywords,
  };
}

Future<Map<String, Object?>> _expectWampSessionMetaDirect(
  McpStreamableHttpClient client, {
  String label = 'Direct JSON WAMP session metadata',
  String countId = 'direct-wamp-session-count',
  String listId = 'direct-wamp-session-list',
  String getId = 'direct-wamp-session-get',
}) async {
  final count = await client.countWampSessionsDirect(id: countId);
  final countValue = _integerMetaId(count.argumentsKeywords['count']);
  if (countValue == null || countValue < 1) {
    throw StateError('$label returned invalid session count: $countValue.');
  }

  final list = await client.listWampSessionsDirect(id: listId);
  final sessionIds = _integerMetaIds(
    list.argumentsKeywords['session_ids'],
    '$label session list',
  );
  if (sessionIds.isEmpty) {
    throw StateError('$label returned no session ids.');
  }
  if (countValue < sessionIds.length) {
    throw StateError(
      '$label count $countValue was smaller than listed sessions $sessionIds.',
    );
  }

  final selectedSessionId = sessionIds.first;
  final session = await client.getWampSessionDirect(
    selectedSessionId,
    id: getId,
  );
  final details = session.argumentsKeywords['details'];
  if (details is! Map) {
    throw StateError('$label session get returned no details map.');
  }
  final detailSessionId = _integerMetaId(details['id'] ?? details['session']);
  if (detailSessionId != selectedSessionId) {
    throw StateError(
      '$label session get returned session $detailSessionId, expected '
      '$selectedSessionId.',
    );
  }

  return <String, Object?>{
    'count': _wampMetaResultJson(count),
    'list': _wampMetaResultJson(list),
    'selectedSessionId': selectedSessionId,
    'selectedSession': _wampMetaResultJson(session),
  };
}

McpJsonMap _structuredContentFromWampMetaBatchResult(
  McpJsonMap result, {
  required String label,
}) {
  final toolResult = _expectToolResultSucceeded(result, label: label);
  final structuredContent = toolResult['structuredContent'];
  if (structuredContent is Map) {
    return structuredContent.cast<String, Object?>();
  }
  if (toolResult['procedure'] is String) {
    return toolResult;
  }
  throw StateError('$label returned no structured content.');
}

McpJsonMap _wampMetaBatchArgumentsKeywords(
  McpJsonMap result, {
  required String label,
}) {
  final argumentsKeywords = result['argumentsKeywords'];
  if (argumentsKeywords is Map) {
    return argumentsKeywords.cast<String, Object?>();
  }
  throw StateError('$label returned no argumentsKeywords map.');
}

Map<String, Object?> _wampMetaBatchResultJson(McpJsonMap result) {
  return {
    'procedure': result['procedure'],
    'arguments': result['arguments'],
    'argumentsKeywords': result['argumentsKeywords'],
  };
}

Map<String, Object?> _expectWampSessionMetaBatchDiscovery(
  List<McpJsonMap>? responses, {
  required String countId,
  required String listId,
  required String label,
}) {
  final count = _structuredContentFromWampMetaBatchResult(
    _batchResult(responses, countId, label: '$label session count'),
    label: '$label session count',
  );
  final countValue = _integerMetaId(
    _wampMetaBatchArgumentsKeywords(
      count,
      label: '$label session count',
    )['count'],
  );
  if (countValue == null || countValue < 1) {
    throw StateError(
      '$label batch returned invalid session count: $countValue.',
    );
  }

  final list = _structuredContentFromWampMetaBatchResult(
    _batchResult(responses, listId, label: '$label session list'),
    label: '$label session list',
  );
  final sessionIds = _integerMetaIds(
    _wampMetaBatchArgumentsKeywords(
      list,
      label: '$label session list',
    )['session_ids'],
    '$label session list',
  );
  if (sessionIds.isEmpty) {
    throw StateError('$label batch returned no session ids.');
  }
  if (countValue < sessionIds.length) {
    throw StateError(
      '$label batch count $countValue was smaller than listed sessions '
      '$sessionIds.',
    );
  }

  return <String, Object?>{
    'count': _wampMetaBatchResultJson(count),
    'list': _wampMetaBatchResultJson(list),
    'selectedSessionId': sessionIds.first,
  };
}

Map<String, Object?> _expectWampSessionMetaBatchDetails(
  List<McpJsonMap>? responses, {
  required String getId,
  required int selectedSessionId,
  required String label,
}) {
  final session = _structuredContentFromWampMetaBatchResult(
    _batchResult(responses, getId, label: '$label session get'),
    label: '$label session get',
  );
  final details = _wampMetaBatchArgumentsKeywords(
    session,
    label: '$label session get',
  )['details'];
  if (details is! Map) {
    throw StateError('$label batch session get returned no details map.');
  }
  final detailSessionId = _integerMetaId(details['id'] ?? details['session']);
  if (detailSessionId != selectedSessionId) {
    throw StateError(
      '$label batch session get returned session $detailSessionId, expected '
      '$selectedSessionId.',
    );
  }

  return <String, Object?>{
    'selectedSession': _wampMetaBatchResultJson(session),
  };
}

typedef _WampMetaCall = Future<McpStreamableWampMetaCallResult> Function();
typedef _WampMetaByIdCall =
    Future<McpStreamableWampMetaCallResult> Function(int subscriptionId);

Future<Map<String, Object?>> _expectConfiguredWampRegistrationMetaDirect(
  McpStreamableHttpClient client,
  String procedure, {
  String label = 'Direct JSON configured WAMP registration metadata',
  String lookupId = 'direct-wamp-configured-registration-lookup',
  String matchId = 'direct-wamp-configured-registration-match',
  String listId = 'direct-wamp-configured-registration-list',
  String getId = 'direct-wamp-configured-registration-get',
  String calleesId = 'direct-wamp-configured-registration-callees',
  String calleeCountId = 'direct-wamp-configured-registration-callee-count',
}) {
  return _expectConfiguredWampRegistrationMeta(
    procedure: procedure,
    label: label,
    lookup: () => client.lookupWampRegistrationDirect(
      procedure,
      id: lookupId,
      match: 'exact',
    ),
    match: () => client.matchWampRegistrationDirect(procedure, id: matchId),
    list: () => client.listWampRegistrationsDirect(id: listId),
    get: (registrationId) =>
        client.getWampRegistrationDirect(registrationId, id: getId),
    listCallees: (registrationId) =>
        client.listWampRegistrationCalleesDirect(registrationId, id: calleesId),
    countCallees: (registrationId) => client.countWampRegistrationCalleesDirect(
      registrationId,
      id: calleeCountId,
    ),
  );
}

Future<Map<String, Object?>> _expectConfiguredWampRegistrationMetaStreamable(
  McpStreamableHttpClient client,
  String procedure,
) {
  return _expectConfiguredWampRegistrationMeta(
    procedure: procedure,
    label: 'Streamable configured WAMP registration metadata',
    lookup: () => client.lookupWampRegistration(
      procedure,
      id: 'streamable-wamp-configured-registration-lookup',
      match: 'exact',
    ),
    match: () => client.matchWampRegistration(
      procedure,
      id: 'streamable-wamp-configured-registration-match',
    ),
    list: () => client.listWampRegistrations(
      id: 'streamable-wamp-configured-registration-list',
    ),
    get: (registrationId) => client.getWampRegistration(
      registrationId,
      id: 'streamable-wamp-configured-registration-get',
    ),
    listCallees: (registrationId) => client.listWampRegistrationCallees(
      registrationId,
      id: 'streamable-wamp-configured-registration-callees',
    ),
    countCallees: (registrationId) => client.countWampRegistrationCallees(
      registrationId,
      id: 'streamable-wamp-configured-registration-callee-count',
    ),
  );
}

Future<Map<String, Object?>> _expectConfiguredWampRegistrationMeta({
  required String procedure,
  required String label,
  required _WampMetaCall lookup,
  required _WampMetaCall match,
  required _WampMetaCall list,
  required _WampMetaByIdCall get,
  required _WampMetaByIdCall listCallees,
  required _WampMetaByIdCall countCallees,
}) async {
  final lookupResult = await lookup();
  _expectWampMetaProcedure(
    lookupResult,
    'wamp.registration.lookup',
    label: '$label lookup',
  );
  final lookupIds = _integerMetaIds(
    lookupResult.arguments,
    '$label lookup arguments',
  );
  if (lookupIds.isEmpty) {
    throw StateError(
      '$label lookup returned no registration id for $procedure.',
    );
  }
  final registrationId = lookupIds.first;

  final matchResult = await match();
  _expectWampMetaProcedure(
    matchResult,
    'wamp.registration.match',
    label: '$label match',
  );
  final matchIds = _integerMetaIds(
    matchResult.arguments,
    '$label match arguments',
  );
  if (!matchIds.contains(registrationId)) {
    throw StateError('$label match did not include lookup id $registrationId.');
  }

  final listResult = await list();
  _expectWampMetaProcedure(
    listResult,
    'wamp.registration.list',
    label: '$label list',
  );
  final exactRegistrationIds = _integerMetaIds(
    listResult.argumentsKeywords['exact'],
    '$label list exact registrations',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError('$label list did not include lookup id $registrationId.');
  }

  final detailsResult = await get(registrationId);
  _expectWampMetaProcedure(
    detailsResult,
    'wamp.registration.get',
    label: '$label get',
  );
  if (detailsResult.argumentsKeywords['uri'] != procedure) {
    throw StateError(
      '$label details returned ${detailsResult.argumentsKeywords['uri']}, '
      'expected $procedure.',
    );
  }

  final calleesResult = await listCallees(registrationId);
  _expectWampMetaProcedure(
    calleesResult,
    'wamp.registration.list_callees',
    label: '$label callees',
  );
  final calleeIds = _integerMetaIds(
    calleesResult.arguments,
    '$label callee arguments',
  );
  if (calleeIds.isNotEmpty) {
    throw StateError(
      '$label configured registration exposed live callees: '
      '${jsonEncode(calleeIds)}.',
    );
  }

  final calleeCountResult = await countCallees(registrationId);
  _expectWampMetaProcedure(
    calleeCountResult,
    'wamp.registration.count_callees',
    label: '$label callee count',
  );
  final calleeCount = _singleIntegerMetaArgument(
    calleeCountResult,
    '$label callee count',
  );
  if (calleeCount != 0) {
    throw StateError(
      '$label configured registration callee count was $calleeCount, '
      'expected 0.',
    );
  }

  return <String, Object?>{
    'procedure': procedure,
    'registrationId': registrationId,
    'lookup': _wampMetaResultJson(lookupResult),
    'match': _wampMetaResultJson(matchResult),
    'list': _wampMetaResultJson(listResult),
    'details': _wampMetaResultJson(detailsResult),
    'callees': _wampMetaResultJson(calleesResult),
    'calleeCount': _wampMetaResultJson(calleeCountResult),
  };
}

Future<Map<String, Object?>> _expectConfiguredWampSubscriptionMetaDirect(
  McpStreamableHttpClient client,
  String topic, {
  String label = 'Direct JSON configured WAMP subscription metadata',
  String lookupId = 'direct-wamp-configured-subscription-lookup',
  String matchId = 'direct-wamp-configured-subscription-match',
  String listId = 'direct-wamp-configured-subscription-list',
  String getId = 'direct-wamp-configured-subscription-get',
  String subscribersId = 'direct-wamp-configured-subscription-subscribers',
  String subscriberCountId =
      'direct-wamp-configured-subscription-subscriber-count',
}) {
  return _expectConfiguredWampSubscriptionMeta(
    topic: topic,
    label: label,
    lookup: () => client.lookupWampSubscriptionDirect(
      topic,
      id: lookupId,
      match: 'exact',
    ),
    match: () => client.matchWampSubscriptionDirect(topic, id: matchId),
    list: () => client.listWampSubscriptionsDirect(id: listId),
    get: (subscriptionId) =>
        client.getWampSubscriptionDirect(subscriptionId, id: getId),
    listSubscribers: (subscriptionId) =>
        client.listWampSubscriptionSubscribersDirect(
          subscriptionId,
          id: subscribersId,
        ),
    countSubscribers: (subscriptionId) =>
        client.countWampSubscriptionSubscribersDirect(
          subscriptionId,
          id: subscriberCountId,
        ),
  );
}

Future<Map<String, Object?>> _expectConfiguredWampSubscriptionMetaStreamable(
  McpStreamableHttpClient client,
  String topic,
) {
  return _expectConfiguredWampSubscriptionMeta(
    topic: topic,
    label: 'Streamable configured WAMP subscription metadata',
    lookup: () => client.lookupWampSubscription(
      topic,
      id: 'streamable-wamp-configured-subscription-lookup',
      match: 'exact',
    ),
    match: () => client.matchWampSubscription(
      topic,
      id: 'streamable-wamp-configured-subscription-match',
    ),
    list: () => client.listWampSubscriptions(
      id: 'streamable-wamp-configured-subscription-list',
    ),
    get: (subscriptionId) => client.getWampSubscription(
      subscriptionId,
      id: 'streamable-wamp-configured-subscription-get',
    ),
    listSubscribers: (subscriptionId) => client.listWampSubscriptionSubscribers(
      subscriptionId,
      id: 'streamable-wamp-configured-subscription-subscribers',
    ),
    countSubscribers: (subscriptionId) =>
        client.countWampSubscriptionSubscribers(
          subscriptionId,
          id: 'streamable-wamp-configured-subscription-subscriber-count',
        ),
  );
}

Future<Map<String, Object?>> _expectConfiguredWampSubscriptionMeta({
  required String topic,
  required String label,
  required _WampMetaCall lookup,
  required _WampMetaCall match,
  required _WampMetaCall list,
  required _WampMetaByIdCall get,
  required _WampMetaByIdCall listSubscribers,
  required _WampMetaByIdCall countSubscribers,
}) async {
  final lookupResult = await lookup();
  _expectWampMetaProcedure(
    lookupResult,
    'wamp.subscription.lookup',
    label: '$label lookup',
  );
  final lookupIds = _integerMetaIds(
    lookupResult.arguments,
    '$label lookup arguments',
  );
  if (lookupIds.isEmpty) {
    throw StateError('$label lookup returned no subscription id for $topic.');
  }
  final subscriptionId = lookupIds.first;

  final matchResult = await match();
  _expectWampMetaProcedure(
    matchResult,
    'wamp.subscription.match',
    label: '$label match',
  );
  final matchIds = _integerMetaIds(
    matchResult.arguments,
    '$label match arguments',
  );
  if (!matchIds.contains(subscriptionId)) {
    throw StateError('$label match did not include lookup id $subscriptionId.');
  }

  final listResult = await list();
  _expectWampMetaProcedure(
    listResult,
    'wamp.subscription.list',
    label: '$label list',
  );
  final exactSubscriptionIds = _integerMetaIds(
    listResult.argumentsKeywords['exact'],
    '$label list exact subscriptions',
  );
  if (!exactSubscriptionIds.contains(subscriptionId)) {
    throw StateError('$label list did not include lookup id $subscriptionId.');
  }

  final detailsResult = await get(subscriptionId);
  _expectWampMetaProcedure(
    detailsResult,
    'wamp.subscription.get',
    label: '$label get',
  );
  if (detailsResult.argumentsKeywords['uri'] != topic) {
    throw StateError(
      '$label details returned ${detailsResult.argumentsKeywords['uri']}, '
      'expected $topic.',
    );
  }

  final subscribersResult = await listSubscribers(subscriptionId);
  _expectWampMetaProcedure(
    subscribersResult,
    'wamp.subscription.list_subscribers',
    label: '$label subscribers',
  );
  final subscriberIds = _integerMetaIds(
    subscribersResult.arguments,
    '$label subscriber arguments',
  );
  if (subscriberIds.isNotEmpty) {
    throw StateError(
      '$label configured subscription exposed live subscribers: '
      '${jsonEncode(subscriberIds)}.',
    );
  }

  final subscriberCountResult = await countSubscribers(subscriptionId);
  _expectWampMetaProcedure(
    subscriberCountResult,
    'wamp.subscription.count_subscribers',
    label: '$label subscriber count',
  );
  final subscriberCount = _singleIntegerMetaArgument(
    subscriberCountResult,
    '$label subscriber count',
  );
  if (subscriberCount != 0) {
    throw StateError(
      '$label configured subscription subscriber count was $subscriberCount, '
      'expected 0.',
    );
  }

  return <String, Object?>{
    'topic': topic,
    'subscriptionId': subscriptionId,
    'lookup': _wampMetaResultJson(lookupResult),
    'match': _wampMetaResultJson(matchResult),
    'list': _wampMetaResultJson(listResult),
    'details': _wampMetaResultJson(detailsResult),
    'subscribers': _wampMetaResultJson(subscribersResult),
    'subscriberCount': _wampMetaResultJson(subscriberCountResult),
  };
}

void _expectWampMetaProcedure(
  McpStreamableWampMetaCallResult result,
  String expectedProcedure, {
  required String label,
}) {
  if (result.procedure != expectedProcedure) {
    throw StateError(
      '$label returned ${result.procedure}, expected $expectedProcedure.',
    );
  }
}

List<int> _integerMetaIds(Object? value, String label) {
  if (value is! Iterable) {
    throw StateError('$label was not a list of integer ids.');
  }
  final ids = <int>[];
  for (final entry in value) {
    final id = _integerMetaId(entry);
    if (id == null) {
      throw StateError('$label contained a non-integer id: $entry.');
    }
    ids.add(id);
  }
  return ids;
}

int _singleIntegerMetaArgument(
  McpStreamableWampMetaCallResult result,
  String label,
) {
  final values = _integerMetaIds(result.arguments, label);
  if (values.length != 1) {
    throw StateError('$label expected one integer value, got $values.');
  }
  return values.single;
}

int? _integerMetaId(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

void _expectWampCatalogContains({
  required Object? catalog,
  required String uri,
  required String label,
}) {
  if (!_wampCatalogContainsUri(catalog, uri)) {
    throw StateError('$label catalog did not include $uri.');
  }
}

bool _wampCatalogContainsUri(Object? catalog, String uri) {
  return _catalogContainsValue(catalog: catalog, field: 'uri', value: uri);
}

void _expectCatalogContainsValue({
  required Object? catalog,
  required String field,
  required String value,
  required String label,
}) {
  if (!_catalogContainsValue(catalog: catalog, field: field, value: value)) {
    throw StateError('$label catalog did not include $value.');
  }
}

void _expectWampSubscription(
  McpStreamableWampSubscriptionResult subscription, {
  required String topic,
  required int queueLimit,
  required String label,
}) {
  if (subscription.topic != topic) {
    throw StateError(
      '$label returned subscription for ${subscription.topic}, expected $topic.',
    );
  }
  if (subscription.handle.isEmpty) {
    throw StateError('$label returned an empty subscription handle.');
  }
  if (subscription.queueLimit != queueLimit) {
    throw StateError(
      '$label returned queue limit ${subscription.queueLimit}, '
      'expected $queueLimit.',
    );
  }
}

void _expectWampPublication(
  McpStreamableWampPublicationResult publication, {
  required String topic,
  required String label,
}) {
  if (publication.topic != topic) {
    throw StateError(
      '$label returned publication for ${publication.topic}, expected $topic.',
    );
  }
  if (!publication.acknowledged) {
    throw StateError('$label did not acknowledge publication to $topic.');
  }
  if (publication.publicationId == null) {
    throw StateError(
      '$label acknowledged publication without a publication id.',
    );
  }
}

void _expectWampEventBatch(
  McpStreamableWampEventBatch events, {
  required String handle,
  required String topic,
  required Object? expectedEvent,
  required String label,
}) {
  if (events.handle != handle) {
    throw StateError(
      '$label returned events for handle ${events.handle}, expected $handle.',
    );
  }
  if (events.topic != topic) {
    throw StateError(
      '$label returned events for ${events.topic}, expected $topic.',
    );
  }
  if (events.dropped != 0) {
    throw StateError(
      '$label reported ${events.dropped} dropped pub/sub events.',
    );
  }
  if (events.remaining != 0) {
    throw StateError(
      '$label left ${events.remaining} pub/sub events queued after polling.',
    );
  }
  final observed = events.events.any(
    (event) => _jsonValueEquals(event['argumentsKeywords'], expectedEvent),
  );
  if (!observed) {
    throw StateError(
      'Published event was not observed on $label topic $topic.',
    );
  }
}

bool _canObserveExampleTaskLookup(_Options options) =>
    options.toolName == 'example.task.lookup' &&
    options.pubsubTopic == 'example.events.task';

McpJsonMap _taskLookupEvent(String taskId) => <String, Object?>{
  'taskId': taskId,
  'status': 'open',
  'source': 'router-hosted-mcp-example',
  'event': 'task.lookup',
};

bool _catalogContainsValue({
  required Object? catalog,
  required String field,
  required String value,
}) {
  if (catalog is! Iterable<Object?>) {
    return false;
  }
  for (final entry in catalog) {
    if (entry is Map && entry[field] == value) {
      return true;
    }
  }
  return false;
}

Future<McpJsonMap> _runActiveDirectJsonExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  final streamableSessionId = client.sessionId;
  if (streamableSessionId == null) {
    throw StateError(
      'Streamable active direct JSON requires an active Streamable session.',
    );
  }
  final previousEventId = client.lastEventId;
  final details = <String, Object?>{};
  final batchMessages = <McpJsonMap>[
    {
      'jsonrpc': '2.0',
      'id': 'streamable-active-direct-batch-tools',
      'method': 'tools/list',
      'params': {},
    },
  ];

  final tools = await client.listToolsDirect(
    id: 'streamable-active-direct-tools',
  );
  details['tools'] = [for (final tool in tools.tools) tool['name']];

  final toolName = options.toolName;
  if (toolName != null) {
    _expectCatalogContainsValue(
      catalog: tools.tools,
      field: 'name',
      value: toolName,
      label: 'Streamable active direct JSON tool',
    );
    batchMessages.add(
      _toolCallBatchRequest(
        id: 'streamable-active-direct-batch-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: true,
      ),
    );
    details['toolResult'] = _expectToolResultSucceeded(
      await client.callToolDirect(
        toolName,
        id: 'streamable-active-direct-standard-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Streamable active direct JSON standard tool call',
    );
    details['toolMethodResult'] = _expectToolResultSucceeded(
      await client.callConnectanumMethodDirect(
        'connectanum.tool.call',
        id: 'streamable-active-direct-tool-call-method',
        params: <String, Object?>{
          'name': toolName,
          'arguments': options.toolArguments,
        },
      ),
      label: 'Streamable active direct JSON tool method call',
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    batchMessages.addAll([
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-resources',
        'method': 'resources/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-resource-templates',
        'method': 'resources/templates/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-resource-read',
        'method': 'resources/read',
        'params': {'uri': resourceUri},
      },
    ]);
    final resources = await client.listResourcesDirect(
      id: 'streamable-active-direct-resources',
    );
    _expectCatalogContainsValue(
      catalog: resources.resources,
      field: 'uri',
      value: resourceUri,
      label: 'Streamable active direct JSON resource',
    );
    final resourceTemplates = await client.listResourceTemplatesDirect(
      id: 'streamable-active-direct-resource-templates',
    );
    details['resources'] = <String, Object?>{
      'uris': [for (final resource in resources.resources) resource['uri']],
      'templates': <String, Object?>{
        'uriTemplates': [
          for (final template in resourceTemplates.resourceTemplates)
            template['uriTemplate'],
        ],
        if (resourceTemplates.nextCursor != null)
          'nextCursor': resourceTemplates.nextCursor,
      },
      'content': await client.readResourceDirect(
        resourceUri,
        id: 'streamable-active-direct-resource-read',
      ),
    };
  }

  final promptName = options.promptName;
  if (promptName != null) {
    batchMessages.addAll([
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-prompts',
        'method': 'prompts/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-prompt-get',
        'method': 'prompts/get',
        'params': {'name': promptName, 'arguments': options.promptArguments},
      },
    ]);
    final prompts = await client.listPromptsDirect(
      id: 'streamable-active-direct-prompts',
    );
    _expectCatalogContainsValue(
      catalog: prompts.prompts,
      field: 'name',
      value: promptName,
      label: 'Streamable active direct JSON prompt',
    );
    details['prompts'] = <String, Object?>{
      'names': [for (final prompt in prompts.prompts) prompt['name']],
      'prompt': await client.getPromptDirect(
        promptName,
        id: 'streamable-active-direct-prompt-get',
        arguments: options.promptArguments,
      ),
    };
  }

  final wampProcedure = options.wampProcedure;
  final wampTopic = options.wampTopic;
  if (wampProcedure != null || wampTopic != null) {
    final metadata = <String, Object?>{};
    final sessionMetadata = await _expectWampSessionMetaDirect(
      client,
      label: 'Streamable active direct JSON WAMP session metadata',
      countId: 'streamable-active-direct-wamp-session-count',
      listId: 'streamable-active-direct-wamp-session-list',
      getId: 'streamable-active-direct-wamp-session-get',
    );
    metadata['sessionCount'] = sessionMetadata['count'];
    metadata['sessionMetadata'] = sessionMetadata;
    batchMessages.addAll([
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-wamp-session-count',
        'method': 'wamp.session.count',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': 'streamable-active-direct-batch-wamp-session-list',
        'method': 'wamp.session.list',
        'params': {},
      },
    ]);
    if (wampProcedure != null) {
      batchMessages.add(
        _toolCallBatchRequest(
          id: 'streamable-active-direct-batch-wamp-procedure-api-list',
          name: 'connectanum.api.list',
          arguments: const {'kind': 'procedure'},
          directJson: true,
        ),
      );
      final procedures = await client.listWampApiDirect(
        id: 'streamable-active-direct-wamp-procedure-api-list',
        kind: 'procedure',
      );
      final procedureCatalog = procedures['procedures'];
      _expectWampCatalogContains(
        catalog: procedureCatalog,
        uri: wampProcedure,
        label: 'Streamable active direct JSON WAMP procedure',
      );
      final configuredRegistrationMetadata =
          await _expectConfiguredWampRegistrationMetaDirect(
            client,
            wampProcedure,
            label:
                'Streamable active direct JSON configured WAMP registration metadata',
            lookupId:
                'streamable-active-direct-wamp-configured-registration-lookup',
            matchId:
                'streamable-active-direct-wamp-configured-registration-match',
            listId:
                'streamable-active-direct-wamp-configured-registration-list',
            getId: 'streamable-active-direct-wamp-configured-registration-get',
            calleesId:
                'streamable-active-direct-wamp-configured-registration-callees',
            calleeCountId:
                'streamable-active-direct-wamp-configured-registration-callee-count',
          );
      metadata['procedure'] = <String, Object?>{
        'catalog': procedureCatalog,
        'description': await client.describeWampApiDirect(
          wampProcedure,
          id: 'streamable-active-direct-wamp-procedure-api-describe',
          kind: 'procedure',
        ),
        'configuredRegistrationMetadata': configuredRegistrationMetadata,
      };
    }
    if (wampTopic != null) {
      batchMessages.add(
        _toolCallBatchRequest(
          id: 'streamable-active-direct-batch-wamp-topic-api-list',
          name: 'connectanum.api.list',
          arguments: const {'kind': 'topic'},
          directJson: true,
        ),
      );
      final topics = await client.listWampApiDirect(
        id: 'streamable-active-direct-wamp-topic-api-list',
        kind: 'topic',
      );
      final topicCatalog = topics['topics'];
      _expectWampCatalogContains(
        catalog: topicCatalog,
        uri: wampTopic,
        label: 'Streamable active direct JSON WAMP topic',
      );
      final configuredSubscriptionMetadata =
          await _expectConfiguredWampSubscriptionMetaDirect(
            client,
            wampTopic,
            label:
                'Streamable active direct JSON configured WAMP subscription metadata',
            lookupId:
                'streamable-active-direct-wamp-configured-subscription-lookup',
            matchId:
                'streamable-active-direct-wamp-configured-subscription-match',
            listId:
                'streamable-active-direct-wamp-configured-subscription-list',
            getId: 'streamable-active-direct-wamp-configured-subscription-get',
            subscribersId:
                'streamable-active-direct-wamp-configured-subscription-subscribers',
            subscriberCountId:
                'streamable-active-direct-wamp-configured-subscription-subscriber-count',
          );
      metadata['topic'] = <String, Object?>{
        'catalog': topicCatalog,
        'description': await client.describeWampApiDirect(
          wampTopic,
          id: 'streamable-active-direct-wamp-topic-api-describe',
          kind: 'topic',
        ),
        'configuredSubscriptionMetadata': configuredSubscriptionMetadata,
      };
    }
    details['wampMetadata'] = metadata;
  }

  final batchResponses = await client.postBatchDirect(
    batchMessages,
    headers: const <String, String>{
      'x-consumer-trace': 'router-hosted-client-streamable-active-direct-batch',
    },
  );
  final responseIds = _expectBatchResponses(batchResponses, [
    for (final message in batchMessages) message['id']! as String,
  ], label: 'Streamable active direct JSON');
  if (toolName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-active-direct-batch-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Streamable active direct JSON batch tool',
    );
  }
  if (resourceUri != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-active-direct-batch-resources',
      catalogKey: 'resources',
      field: 'uri',
      value: resourceUri,
      label: 'Streamable active direct JSON batch resource',
    );
    final resourceTemplateBatchResult = _batchResult(
      batchResponses,
      'streamable-active-direct-batch-resource-templates',
      label: 'Streamable active direct JSON batch resource templates',
    );
    final resourceDetails = details['resources'];
    if (resourceDetails is Map<String, Object?>) {
      resourceDetails['batchResourceTemplates'] =
          resourceTemplateBatchResult['resourceTemplates'];
      if (resourceTemplateBatchResult['nextCursor'] != null) {
        resourceDetails['batchResourceTemplateNextCursor'] =
            resourceTemplateBatchResult['nextCursor'];
      }
    }
  }
  if (promptName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-active-direct-batch-prompts',
      catalogKey: 'prompts',
      field: 'name',
      value: promptName,
      label: 'Streamable active direct JSON batch prompt',
    );
  }
  if (wampProcedure != null || wampTopic != null) {
    final sessionDiscovery = _expectWampSessionMetaBatchDiscovery(
      batchResponses,
      countId: 'streamable-active-direct-batch-wamp-session-count',
      listId: 'streamable-active-direct-batch-wamp-session-list',
      label: 'Streamable active direct JSON batch WAMP session metadata',
    );
    final selectedSessionId = sessionDiscovery['selectedSessionId']! as int;
    final sessionGetId = 'streamable-active-direct-batch-wamp-session-get';
    final sessionGetResponses = await client.postBatchDirect(
      [
        {
          'jsonrpc': '2.0',
          'id': sessionGetId,
          'method': 'wamp.session.get',
          'params': {'id': selectedSessionId},
        },
      ],
      headers: const <String, String>{
        'x-consumer-trace':
            'router-hosted-client-streamable-active-direct-batch-wamp-session-get',
      },
    );
    final detailResponseIds = _expectBatchResponses(
      sessionGetResponses,
      [sessionGetId],
      label:
          'Streamable active direct JSON batch WAMP session metadata details',
    );
    final sessionDetails = _expectWampSessionMetaBatchDetails(
      sessionGetResponses,
      getId: sessionGetId,
      selectedSessionId: selectedSessionId,
      label: 'Streamable active direct JSON batch WAMP session metadata',
    );
    final metadata = details['wampMetadata'];
    if (metadata is Map<String, Object?>) {
      metadata['batchSessionMetadata'] = <String, Object?>{
        ...sessionDiscovery,
        ...sessionDetails,
        'detailResponseIds': detailResponseIds,
      };
    }
  }
  _expectStreamableStateUnchanged(
    client,
    sessionId: streamableSessionId,
    lastEventId: previousEventId,
    label: 'Streamable active direct JSON',
  );

  return <String, Object?>{
    'sessionUnchanged': true,
    'batch': <String, Object?>{'responseIds': responseIds},
    ...details,
  };
}

Future<void> _runDirectPubSubExample(
  McpStreamableHttpClient client,
  _Options options,
) async {
  const queueLimit = 10;
  final topic = options.pubsubTopic!;
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscription = await client.subscribeWampTopicDirect(
    topic,
    id: 'direct-pubsub-subscribe',
    queueLimit: queueLimit,
  );
  _expectWampSubscription(
    subscription,
    topic: topic,
    queueLimit: queueLimit,
    label: 'Direct JSON pub/sub',
  );

  try {
    final subscriptionMeta = await client.matchWampSubscriptionDirect(
      topic,
      id: 'direct-wamp-subscription-match',
    );
    final publication = await client.publishWampEventDirect(
      topic,
      id: 'direct-pubsub-publish',
      argumentsKeywords: options.pubsubEvent,
      acknowledge: true,
    );
    _expectWampPublication(
      publication,
      topic: topic,
      label: 'Direct JSON pub/sub',
    );
    final events = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      events,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: options.pubsubEvent,
      label: 'Direct JSON pub/sub',
    );
    final methodPubsubEvent = <String, Object?>{
      'methodEvent': options.pubsubEvent,
    };
    final methodPublication = _structuredContentFromToolResult(
      await client.callConnectanumMethodDirect(
        'connectanum.pubsub.publish',
        id: 'direct-pubsub-publish-method',
        params: <String, Object?>{
          'topic': topic,
          'argumentsKeywords': methodPubsubEvent,
          'acknowledge': true,
        },
      ),
      label: 'Direct JSON pub/sub method publish',
    );
    if (methodPublication['topic'] != topic) {
      throw StateError(
        'Direct JSON pub/sub method publish returned topic '
        '${methodPublication['topic']}, expected $topic.',
      );
    }
    if (methodPublication['acknowledged'] != true) {
      throw StateError(
        'Direct JSON pub/sub method publish did not acknowledge publication.',
      );
    }
    if (methodPublication['publicationId'] == null) {
      throw StateError(
        'Direct JSON pub/sub method publish acknowledged without '
        'a publication id.',
      );
    }
    final methodEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-method-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      methodEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: methodPubsubEvent,
      label: 'Direct JSON pub/sub method poll',
    );
    final notificationEvent = <String, Object?>{
      'notificationEvent': options.pubsubEvent,
    };
    await client.notifyWampEventDirect(
      topic,
      argumentsKeywords: notificationEvent,
    );
    final notificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      notificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: notificationEvent,
      label: 'Direct JSON pub/sub notification poll',
    );
    final methodNotificationEvent = <String, Object?>{
      'methodNotificationEvent': options.pubsubEvent,
    };
    await client.notifyConnectanumMethodDirect(
      'connectanum.pubsub.publish',
      params: <String, Object?>{
        'topic': topic,
        'argumentsKeywords': methodNotificationEvent,
      },
    );
    final methodNotificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'direct-pubsub-method-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      methodNotificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: methodNotificationEvent,
      label: 'Direct JSON pub/sub method notification poll',
    );
    McpStreamableWampEventBatch? standardToolNotificationEvents;
    McpStreamableWampEventBatch? connectanumToolNotificationEvents;
    McpStreamableWampEventBatch? toolMethodNotificationEvents;
    if (_canObserveExampleTaskLookup(options)) {
      final toolName = options.toolName!;
      const standardToolNotificationTaskId =
          'T-direct-standard-tool-notification';
      await client.notifyToolDirect(
        toolName,
        arguments: const {'taskId': standardToolNotificationTaskId},
        headers: const <String, String>{
          'x-consumer-trace':
              'router-hosted-client-direct-standard-tool-notification',
        },
      );
      standardToolNotificationEvents = await client.pollWampEventsDirect(
        subscription.handle,
        id: 'direct-tool-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        standardToolNotificationEvents,
        handle: subscription.handle,
        topic: topic,
        expectedEvent: _taskLookupEvent(standardToolNotificationTaskId),
        label: 'Direct JSON standard tool notification poll',
      );

      const connectanumToolNotificationTaskId =
          'T-direct-connectanum-tool-notification';
      await client.notifyConnectanumToolDirect(
        toolName,
        arguments: const {'taskId': connectanumToolNotificationTaskId},
        headers: const <String, String>{
          'x-consumer-trace':
              'router-hosted-client-direct-connectanum-tool-notification',
        },
      );
      connectanumToolNotificationEvents = await client.pollWampEventsDirect(
        subscription.handle,
        id: 'direct-connectanum-tool-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        connectanumToolNotificationEvents,
        handle: subscription.handle,
        topic: topic,
        expectedEvent: _taskLookupEvent(connectanumToolNotificationTaskId),
        label: 'Direct JSON Connectanum tool notification poll',
      );

      const toolMethodNotificationTaskId = 'T-direct-tool-method-notification';
      await client.notifyConnectanumMethodDirect(
        'connectanum.tool.call',
        params: const <String, Object?>{
          'name': 'example.task.lookup',
          'arguments': {'taskId': toolMethodNotificationTaskId},
        },
        headers: const <String, String>{
          'x-consumer-trace':
              'router-hosted-client-direct-tool-method-notification',
        },
      );
      toolMethodNotificationEvents = await client.pollWampEventsDirect(
        subscription.handle,
        id: 'direct-tool-method-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        toolMethodNotificationEvents,
        handle: subscription.handle,
        topic: topic,
        expectedEvent: _taskLookupEvent(toolMethodNotificationTaskId),
        label: 'Direct JSON tool method notification poll',
      );
    }
    stdout.writeln(
      jsonEncode({
        'pubsubTopic': topic,
        'subscription': <String, Object?>{
          'handle': subscription.handle,
          'topic': subscription.topic,
          'queueLimit': subscription.queueLimit,
          if (subscription.subscriptionId != null)
            'subscriptionId': subscription.subscriptionId,
        },
        'subscriptionMetadata': _wampMetaResultJson(subscriptionMeta),
        'publication': <String, Object?>{
          'topic': publication.topic,
          'acknowledged': publication.acknowledged,
          if (publication.publicationId != null)
            'publicationId': publication.publicationId,
        },
        'events': events.events,
        'methodPublication': methodPublication,
        'methodEvents': methodEvents.events,
        'notificationEvents': notificationEvents.events,
        'methodNotificationEvents': methodNotificationEvents.events,
        if (standardToolNotificationEvents != null)
          'toolNotificationEvents': standardToolNotificationEvents.events,
        if (connectanumToolNotificationEvents != null)
          'connectanumToolNotificationEvents':
              connectanumToolNotificationEvents.events,
        if (toolMethodNotificationEvents != null)
          'toolMethodNotificationEvents': toolMethodNotificationEvents.events,
        'dropped': events.dropped,
        'remaining': events.remaining,
      }),
    );
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'direct-pubsub-unsubscribe',
    );
  }

  _expectStreamableStateUnchanged(
    client,
    sessionId: previousSessionId,
    lastEventId: previousEventId,
    label: 'Direct JSON pub/sub',
  );
}

Future<McpJsonMap> _runActiveDirectPubSubExample(
  McpStreamableHttpClient client,
  _Options options, {
  required String topic,
  required int queueLimit,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  if (previousSessionId == null) {
    throw StateError(
      'Active direct JSON pub/sub requires an active Streamable session.',
    );
  }

  final subscription = await client.subscribeWampTopicDirect(
    topic,
    id: 'streamable-active-direct-pubsub-subscribe',
    queueLimit: queueLimit,
  );
  _expectWampSubscription(
    subscription,
    topic: topic,
    queueLimit: queueLimit,
    label: 'Streamable active direct JSON pub/sub',
  );

  try {
    final notificationEvent = <String, Object?>{
      'activeDirectNotificationEvent': options.pubsubEvent,
    };
    await client.notifyWampEventDirect(
      topic,
      argumentsKeywords: notificationEvent,
    );
    final notificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'streamable-active-direct-pubsub-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      notificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: notificationEvent,
      label: 'Streamable active direct JSON pub/sub notification poll',
    );

    final methodNotificationEvent = <String, Object?>{
      'activeDirectMethodNotificationEvent': options.pubsubEvent,
    };
    await client.notifyConnectanumMethodDirect(
      'connectanum.pubsub.publish',
      params: <String, Object?>{
        'topic': topic,
        'argumentsKeywords': methodNotificationEvent,
      },
    );
    final methodNotificationEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'streamable-active-direct-pubsub-method-notification-poll',
      limit: queueLimit,
    );
    _expectWampEventBatch(
      methodNotificationEvents,
      handle: subscription.handle,
      topic: topic,
      expectedEvent: methodNotificationEvent,
      label: 'Streamable active direct JSON pub/sub method notification poll',
    );

    return <String, Object?>{
      'sessionUnchanged': true,
      'subscription': <String, Object?>{
        'handle': subscription.handle,
        'topic': subscription.topic,
        'queueLimit': subscription.queueLimit,
        if (subscription.subscriptionId != null)
          'subscriptionId': subscription.subscriptionId,
      },
      'notificationEvents': notificationEvents.events,
      'methodNotificationEvents': methodNotificationEvents.events,
      'dropped': notificationEvents.dropped,
      'remaining': notificationEvents.remaining,
    };
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'streamable-active-direct-pubsub-unsubscribe',
    );
    _expectStreamableStateUnchanged(
      client,
      sessionId: previousSessionId,
      lastEventId: previousEventId,
      label: 'Streamable active direct JSON pub/sub',
    );
  }
}

Future<void> _runStreamableSessionExample(
  McpStreamableHttpClient client,
  _Options options, {
  String? authorizationHeader,
}) async {
  final initialize = await client.initialize(
    id: 'streamable-initialize',
    clientInfo: const <String, Object?>{
      'name': 'connectanum-mcp-router-hosted-client-example',
      'version': '0.1.0',
    },
  );
  final streamableSessionId = client.sessionId;
  if (streamableSessionId == null) {
    throw StateError('Streamable initialize did not establish a session id.');
  }
  await client.notifyInitialized(
    headers: const <String, String>{
      'x-consumer-trace': 'router-hosted-client-streamable-initialized',
    },
  );
  if (client.sessionId != streamableSessionId) {
    throw StateError('Streamable initialized notification changed session id.');
  }

  final ping = await client.ping(id: 'streamable-ping');
  if (client.sessionId != streamableSessionId) {
    throw StateError('Streamable ping changed session id.');
  }
  final eventIdBeforeInvalidPoll = client.lastEventId;
  await _expectInvalidLastEventIdRejected(
    client,
    sessionId: streamableSessionId,
    lastEventId: eventIdBeforeInvalidPoll,
  );
  final eventIdBeforeEmptyLastEventIdPoll = client.lastEventId;
  await _expectEmptyLastEventIdStartsFreshPoll(
    client,
    sessionId: streamableSessionId,
    lastEventId: eventIdBeforeEmptyLastEventIdPoll,
  );
  final eventIdBeforeMalformedSession = client.lastEventId;
  await _expectMalformedSessionIdRejected(
    client,
    authorizationHeader,
    sessionId: streamableSessionId,
    lastEventId: eventIdBeforeMalformedSession,
  );
  final eventIdBeforeDirectStaleSession = client.lastEventId;
  await _expectDirectJsonStaleSessionIdIgnored(
    client,
    authorizationHeader,
    sessionId: streamableSessionId,
    lastEventId: eventIdBeforeDirectStaleSession,
  );

  final tools = await client.listTools(id: 'streamable-tools');
  final streamable = <String, Object?>{
    'protocolVersion': client.protocolVersion,
    'sessionId': streamableSessionId,
    'initialize': initialize['result'],
    'initializedNotification': {'accepted': true},
    'ping': ping,
    'invalidLastEventId': {'rejected': true, 'sessionUnchanged': true},
    'emptyLastEventId': {'accepted': true, 'sessionUnchanged': true},
    'malformedSessionId': {'rejected': true, 'sessionUnchanged': true},
    'directJsonStaleSessionId': {'ignored': true, 'sessionUnchanged': true},
    'tools': [for (final tool in tools.tools) tool['name']],
  };

  final toolName = options.toolName;
  final streamableBatchMessages = <McpJsonMap>[
    {
      'jsonrpc': '2.0',
      'id': 'streamable-batch-tools',
      'method': 'tools/list',
      'params': {},
    },
  ];
  if (toolName != null) {
    _expectCatalogContainsValue(
      catalog: tools.tools,
      field: 'name',
      value: toolName,
      label: 'Streamable tool',
    );
    streamableBatchMessages.add(
      _toolCallBatchRequest(
        id: 'streamable-batch-tool-call',
        name: toolName,
        arguments: options.toolArguments,
        directJson: false,
      ),
    );
    final methodCatalog = await client.callConnectanumMethod(
      'connectanum.tools.list',
      id: 'streamable-tools-method',
    );
    final methodToolCatalog = methodCatalog['tools'];
    _expectCatalogContainsValue(
      catalog: methodToolCatalog,
      field: 'name',
      value: toolName,
      label: 'Streamable tool method list',
    );
    streamable['toolResult'] = _expectToolResultSucceeded(
      await client.callTool(
        toolName,
        id: 'streamable-tool-call',
        arguments: options.toolArguments,
      ),
      label: 'Streamable tool call',
    );
    streamable['toolMethodCatalog'] = methodToolCatalog;
    streamable['toolMethodResult'] = _expectToolResultSucceeded(
      await client.callConnectanumMethod(
        'connectanum.tool.call',
        id: 'streamable-tool-call-method',
        params: <String, Object?>{
          'name': toolName,
          'arguments': options.toolArguments,
        },
      ),
      label: 'Streamable tool method call',
    );
  }

  final resourceUri = options.resourceUri;
  if (resourceUri != null) {
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resources',
      'method': 'resources/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': resourceUri},
    });
    final resources = await client.listResources(id: 'streamable-resources');
    _expectCatalogContainsValue(
      catalog: resources.resources,
      field: 'uri',
      value: resourceUri,
      label: 'Streamable resource',
    );
    streamable['resources'] = <String, Object?>{
      'uris': [for (final resource in resources.resources) resource['uri']],
      if (resources.nextCursor != null) 'nextCursor': resources.nextCursor,
    };
    final resourceTemplates = await client.listResourceTemplates(
      id: 'streamable-resource-templates',
    );
    streamable['resourceTemplates'] = <String, Object?>{
      'uriTemplates': [
        for (final template in resourceTemplates.resourceTemplates)
          template['uriTemplate'],
      ],
      if (resourceTemplates.nextCursor != null)
        'nextCursor': resourceTemplates.nextCursor,
    };
    streamable['resourceContent'] = await client.readResource(
      resourceUri,
      id: 'streamable-resource-read',
    );
    final methodResources = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-list-method',
        'method': 'resources/list',
        'params': {},
      }),
      'streamable-resource-list-method',
      label: 'Streamable resource method list',
    );
    _expectCatalogContainsValue(
      catalog: methodResources['resources'],
      field: 'uri',
      value: resourceUri,
      label: 'Streamable resource method list',
    );
    final methodResourceTemplates = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-templates-method',
        'method': 'resources/templates/list',
        'params': {},
      }),
      'streamable-resource-templates-method',
      label: 'Streamable resource template method list',
    );
    final methodContent = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-resource-read-method',
        'method': 'resources/read',
        'params': {'uri': resourceUri},
      }),
      'streamable-resource-read-method',
      label: 'Streamable resource method read',
    );
    streamable['resourceMethods'] = <String, Object?>{
      'resources': methodResources['resources'],
      'resourceTemplates': methodResourceTemplates['resourceTemplates'],
      'content': methodContent,
    };
  }

  final promptName = options.promptName;
  if (promptName != null) {
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    });
    streamableBatchMessages.add({
      'jsonrpc': '2.0',
      'id': 'streamable-batch-prompt-get',
      'method': 'prompts/get',
      'params': {'name': promptName, 'arguments': options.promptArguments},
    });
    final prompts = await client.listPrompts(id: 'streamable-prompts');
    _expectCatalogContainsValue(
      catalog: prompts.prompts,
      field: 'name',
      value: promptName,
      label: 'Streamable prompt',
    );
    streamable['prompts'] = <String, Object?>{
      'names': [for (final prompt in prompts.prompts) prompt['name']],
      if (prompts.nextCursor != null) 'nextCursor': prompts.nextCursor,
    };
    streamable['prompt'] = await client.getPrompt(
      promptName,
      id: 'streamable-prompt-get',
      arguments: options.promptArguments,
    );
    final methodPrompts = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-prompts-method',
        'method': 'prompts/list',
        'params': {},
      }),
      'streamable-prompts-method',
      label: 'Streamable prompt method list',
    );
    _expectCatalogContainsValue(
      catalog: methodPrompts['prompts'],
      field: 'name',
      value: promptName,
      label: 'Streamable prompt method list',
    );
    final methodPrompt = _responseResult(
      await client.post({
        'jsonrpc': '2.0',
        'id': 'streamable-prompt-get-method',
        'method': 'prompts/get',
        'params': {'name': promptName, 'arguments': options.promptArguments},
      }),
      'streamable-prompt-get-method',
      label: 'Streamable prompt method get',
    );
    streamable['promptMethods'] = <String, Object?>{
      'prompts': methodPrompts['prompts'],
      'prompt': methodPrompt,
    };
  }

  final wampProcedure = options.wampProcedure;
  final wampTopic = options.wampTopic;
  if (wampProcedure != null) {
    streamableBatchMessages.addAll([
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-procedure-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'procedure'},
        directJson: false,
      ),
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-procedure-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampProcedure, 'kind': 'procedure'},
        directJson: false,
      ),
    ]);
  }
  if (wampTopic != null) {
    streamableBatchMessages.addAll([
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-topic-api-list',
        name: 'connectanum.api.list',
        arguments: const {'kind': 'topic'},
        directJson: false,
      ),
      _toolCallBatchRequest(
        id: 'streamable-batch-wamp-topic-api-describe',
        name: 'connectanum.api.describe',
        arguments: {'uri': wampTopic, 'kind': 'topic'},
        directJson: false,
      ),
    ]);
  }
  final batchResponses = await client.postBatch(
    streamableBatchMessages,
    headers: const {
      'x-consumer-trace': 'router-hosted-client-streamable-batch',
    },
  );
  final responseIds = _expectBatchResponses(batchResponses, [
    for (final message in streamableBatchMessages) message['id']! as String,
  ], label: 'Streamable');
  if (toolName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-tools',
      catalogKey: 'tools',
      field: 'name',
      value: toolName,
      label: 'Streamable batch tool',
    );
  }
  if (resourceUri != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-resources',
      catalogKey: 'resources',
      field: 'uri',
      value: resourceUri,
      label: 'Streamable batch resource',
    );
  }
  if (promptName != null) {
    _expectBatchCatalogContains(
      batchResponses,
      id: 'streamable-batch-prompts',
      catalogKey: 'prompts',
      field: 'name',
      value: promptName,
      label: 'Streamable batch prompt',
    );
  }
  streamable['batch'] = <String, Object?>{'responseIds': responseIds};
  if (client.sessionId != streamableSessionId) {
    throw StateError('Streamable batch changed session id.');
  }

  if (wampProcedure != null || wampTopic != null) {
    final metadata = <String, Object?>{};

    final sessionCount = await client.countWampSessions(
      id: 'streamable-wamp-session-count',
    );
    metadata['sessionCount'] = _wampMetaResultJson(sessionCount);

    if (wampProcedure != null) {
      final procedures = await client.listWampApi(
        id: 'streamable-wamp-procedure-api-list',
        kind: 'procedure',
      );
      final procedureCatalog = procedures['procedures'];
      _expectWampCatalogContains(
        catalog: procedureCatalog,
        uri: wampProcedure,
        label: 'Streamable WAMP procedure',
      );
      final methodProcedureCatalog = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.list',
          id: 'streamable-wamp-procedure-api-list-method',
          params: const <String, Object?>{'kind': 'procedure'},
        ),
        label: 'Streamable WAMP procedure method list',
      )['procedures'];
      _expectWampCatalogContains(
        catalog: methodProcedureCatalog,
        uri: wampProcedure,
        label: 'Streamable WAMP procedure method list',
      );
      final description = await client.describeWampApi(
        wampProcedure,
        id: 'streamable-wamp-procedure-api-describe',
        kind: 'procedure',
      );
      final methodDescription = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.describe',
          id: 'streamable-wamp-procedure-api-describe-method',
          params: <String, Object?>{'uri': wampProcedure, 'kind': 'procedure'},
        ),
        label: 'Streamable WAMP procedure method describe',
      );
      final registration = await client.matchWampRegistration(
        wampProcedure,
        id: 'streamable-wamp-registration-match',
      );
      final configuredRegistrationMetadata =
          await _expectConfiguredWampRegistrationMetaStreamable(
            client,
            wampProcedure,
          );
      metadata['procedure'] = <String, Object?>{
        'name': wampProcedure,
        'catalog': procedureCatalog,
        'description': description,
        'methodCatalog': methodProcedureCatalog,
        'methodDescription': methodDescription,
        'registration': _wampMetaResultJson(registration),
        'configuredRegistrationMetadata': configuredRegistrationMetadata,
      };
    }

    if (wampTopic != null) {
      final topics = await client.listWampApi(
        id: 'streamable-wamp-topic-api-list',
        kind: 'topic',
      );
      final topicCatalog = topics['topics'];
      _expectWampCatalogContains(
        catalog: topicCatalog,
        uri: wampTopic,
        label: 'Streamable WAMP topic',
      );
      final methodTopicCatalog = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.list',
          id: 'streamable-wamp-topic-api-list-method',
          params: const <String, Object?>{'kind': 'topic'},
        ),
        label: 'Streamable WAMP topic method list',
      )['topics'];
      _expectWampCatalogContains(
        catalog: methodTopicCatalog,
        uri: wampTopic,
        label: 'Streamable WAMP topic method list',
      );
      final description = await client.describeWampApi(
        wampTopic,
        id: 'streamable-wamp-topic-api-describe',
        kind: 'topic',
      );
      final methodDescription = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.api.describe',
          id: 'streamable-wamp-topic-api-describe-method',
          params: <String, Object?>{'uri': wampTopic, 'kind': 'topic'},
        ),
        label: 'Streamable WAMP topic method describe',
      );
      final configuredSubscriptionMetadata =
          await _expectConfiguredWampSubscriptionMetaStreamable(
            client,
            wampTopic,
          );
      metadata['topic'] = <String, Object?>{
        'name': wampTopic,
        'catalog': topicCatalog,
        'description': description,
        'methodCatalog': methodTopicCatalog,
        'methodDescription': methodDescription,
        'configuredSubscriptionMetadata': configuredSubscriptionMetadata,
      };
    }

    streamable['wampMetadata'] = metadata;
    if (client.sessionId != streamableSessionId) {
      throw StateError('Streamable WAMP metadata changed session id.');
    }
  }

  streamable['activeDirectJson'] = await _runActiveDirectJsonExample(
    client,
    options,
  );

  final pubsubTopic = options.pubsubTopic;
  if (pubsubTopic != null) {
    const queueLimit = 10;
    final activeDirectJsonPubSub = await _runActiveDirectPubSubExample(
      client,
      options,
      topic: pubsubTopic,
      queueLimit: queueLimit,
    );
    final subscription = await client.subscribeWampTopic(
      pubsubTopic,
      id: 'streamable-pubsub-subscribe',
      queueLimit: queueLimit,
    );
    _expectWampSubscription(
      subscription,
      topic: pubsubTopic,
      queueLimit: queueLimit,
      label: 'Streamable pub/sub',
    );

    try {
      final subscriptionMeta = await client.matchWampSubscription(
        pubsubTopic,
        id: 'streamable-wamp-subscription-match',
      );
      final publication = await client.publishWampEvent(
        pubsubTopic,
        id: 'streamable-pubsub-publish',
        argumentsKeywords: options.pubsubEvent,
        acknowledge: true,
      );
      _expectWampPublication(
        publication,
        topic: pubsubTopic,
        label: 'Streamable pub/sub',
      );
      final events = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        events,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: options.pubsubEvent,
        label: 'Streamable pub/sub',
      );
      final methodPubsubEvent = <String, Object?>{
        'methodEvent': options.pubsubEvent,
      };
      final methodPublication = _structuredContentFromToolResult(
        await client.callConnectanumMethod(
          'connectanum.pubsub.publish',
          id: 'streamable-pubsub-publish-method',
          params: <String, Object?>{
            'topic': pubsubTopic,
            'argumentsKeywords': methodPubsubEvent,
            'acknowledge': true,
          },
        ),
        label: 'Streamable pub/sub method publish',
      );
      if (methodPublication['topic'] != pubsubTopic) {
        throw StateError(
          'Streamable pub/sub method publish returned topic '
          '${methodPublication['topic']}, expected $pubsubTopic.',
        );
      }
      if (methodPublication['acknowledged'] != true) {
        throw StateError(
          'Streamable pub/sub method publish did not acknowledge publication.',
        );
      }
      if (methodPublication['publicationId'] == null) {
        throw StateError(
          'Streamable pub/sub method publish acknowledged without '
          'a publication id.',
        );
      }
      final methodEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-method-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        methodEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: methodPubsubEvent,
        label: 'Streamable pub/sub method poll',
      );
      final notificationEvent = <String, Object?>{
        'notificationEvent': options.pubsubEvent,
      };
      await client.notifyWampEvent(
        pubsubTopic,
        argumentsKeywords: notificationEvent,
      );
      final notificationEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        notificationEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: notificationEvent,
        label: 'Streamable pub/sub notification poll',
      );
      final methodNotificationEvent = <String, Object?>{
        'methodNotificationEvent': options.pubsubEvent,
      };
      await client.notifyConnectanumMethod(
        'connectanum.pubsub.publish',
        params: <String, Object?>{
          'topic': pubsubTopic,
          'argumentsKeywords': methodNotificationEvent,
        },
      );
      final methodNotificationEvents = await client.pollWampEvents(
        subscription.handle,
        id: 'streamable-pubsub-method-notification-poll',
        limit: queueLimit,
      );
      _expectWampEventBatch(
        methodNotificationEvents,
        handle: subscription.handle,
        topic: pubsubTopic,
        expectedEvent: methodNotificationEvent,
        label: 'Streamable pub/sub method notification poll',
      );
      McpStreamableWampEventBatch? toolNotificationEvents;
      McpStreamableWampEventBatch? toolMethodNotificationEvents;
      if (_canObserveExampleTaskLookup(options)) {
        final toolName = options.toolName!;
        const toolNotificationTaskId = 'T-streamable-tool-notification';
        await client.notifyTool(
          toolName,
          arguments: const {'taskId': toolNotificationTaskId},
          headers: const <String, String>{
            'x-consumer-trace':
                'router-hosted-client-streamable-tool-notification',
          },
        );
        if (client.sessionId != streamableSessionId) {
          throw StateError('Streamable tool notification changed session id.');
        }
        toolNotificationEvents = await client.pollWampEvents(
          subscription.handle,
          id: 'streamable-tool-notification-poll',
          limit: queueLimit,
        );
        _expectWampEventBatch(
          toolNotificationEvents,
          handle: subscription.handle,
          topic: pubsubTopic,
          expectedEvent: _taskLookupEvent(toolNotificationTaskId),
          label: 'Streamable standard tool notification poll',
        );

        const toolMethodNotificationTaskId =
            'T-streamable-tool-method-notification';
        await client.notifyConnectanumMethod(
          'connectanum.tool.call',
          params: const <String, Object?>{
            'name': 'example.task.lookup',
            'arguments': {'taskId': toolMethodNotificationTaskId},
          },
          headers: const <String, String>{
            'x-consumer-trace':
                'router-hosted-client-streamable-tool-method-notification',
          },
        );
        if (client.sessionId != streamableSessionId) {
          throw StateError(
            'Streamable tool method notification changed session id.',
          );
        }
        toolMethodNotificationEvents = await client.pollWampEvents(
          subscription.handle,
          id: 'streamable-tool-method-notification-poll',
          limit: queueLimit,
        );
        _expectWampEventBatch(
          toolMethodNotificationEvents,
          handle: subscription.handle,
          topic: pubsubTopic,
          expectedEvent: _taskLookupEvent(toolMethodNotificationTaskId),
          label: 'Streamable tool method notification poll',
        );
      }
      streamable['pubsub'] = <String, Object?>{
        'topic': pubsubTopic,
        'subscription': <String, Object?>{
          'handle': subscription.handle,
          'topic': subscription.topic,
          'queueLimit': subscription.queueLimit,
          if (subscription.subscriptionId != null)
            'subscriptionId': subscription.subscriptionId,
        },
        'subscriptionMetadata': _wampMetaResultJson(subscriptionMeta),
        'publication': <String, Object?>{
          'topic': publication.topic,
          'acknowledged': publication.acknowledged,
          if (publication.publicationId != null)
            'publicationId': publication.publicationId,
        },
        'events': events.events,
        'methodPublication': methodPublication,
        'methodEvents': methodEvents.events,
        'notificationEvents': notificationEvents.events,
        'methodNotificationEvents': methodNotificationEvents.events,
        'activeDirectJson': activeDirectJsonPubSub,
        if (toolNotificationEvents != null)
          'toolNotificationEvents': toolNotificationEvents.events,
        if (toolMethodNotificationEvents != null)
          'toolMethodNotificationEvents': toolMethodNotificationEvents.events,
        'dropped': events.dropped,
        'remaining': events.remaining,
      };
    } finally {
      await client.unsubscribeWampTopic(
        subscription.handle,
        id: 'streamable-pubsub-unsubscribe',
      );
    }
  }

  stdout.writeln(jsonEncode({'streamable': streamable}));
}

final class _Options {
  const _Options({
    required this.endpoint,
    required this.protocolVersion,
    required this.toolArguments,
    required this.promptArguments,
    required this.pubsubEvent,
    required this.authLifecycleSmoke,
    required this.dryRun,
    this.bearerToken,
    this.authEndpoint,
    this.authRealm,
    this.authId,
    this.ticket,
    this.toolName,
    this.resourceUri,
    this.promptName,
    this.wampProcedure,
    this.wampTopic,
    this.pubsubTopic,
  });

  final Uri endpoint;
  final String protocolVersion;
  final String? bearerToken;
  final Uri? authEndpoint;
  final String? authRealm;
  final String? authId;
  final String? ticket;
  final String? toolName;
  final McpJsonMap toolArguments;
  final String? resourceUri;
  final String? promptName;
  final Map<String, String> promptArguments;
  final String? wampProcedure;
  final String? wampTopic;
  final String? pubsubTopic;
  final McpJsonMap pubsubEvent;
  final bool authLifecycleSmoke;
  final bool dryRun;

  static _Options parse(List<String> args) {
    final values = _parseOptions(args);
    final endpoint = _requiredUri(values, '--endpoint');
    final protocolVersion = _protocolVersionOption(values);
    final bearerToken = _bearerTokenOption(values);
    final authEndpoint = _optionalUri(values, '--auth-url');
    final authRealm = _mcpSelectorOption(values, '--realm');
    final authId = _mcpSelectorOption(values, '--auth-id');
    final ticket = _nonEmptyStringOption(values, '--ticket');
    final authLifecycleSmoke = values.containsKey('--auth-lifecycle-smoke');

    if (bearerToken != null && authEndpoint != null) {
      throw const FormatException(
        'Use either --bearer-token or --auth-url, not both.',
      );
    }

    final authValues = [authEndpoint, authRealm, authId, ticket];
    if (authValues.any((value) => value != null) &&
        authValues.any((value) => value == null)) {
      throw const FormatException(
        'Use --auth-url, --realm, --auth-id, and --ticket together.',
      );
    }
    if (authLifecycleSmoke && authEndpoint == null) {
      throw const FormatException(
        'Use --auth-lifecycle-smoke together with --auth-url.',
      );
    }

    if (values.containsKey('--tool-arguments') &&
        !values.containsKey('--tool')) {
      throw const FormatException('Use --tool-arguments together with --tool.');
    }
    if (values.containsKey('--prompt-arguments') &&
        !values.containsKey('--prompt')) {
      throw const FormatException(
        'Use --prompt-arguments together with --prompt.',
      );
    }
    if (values.containsKey('--pubsub-event') &&
        !values.containsKey('--pubsub-topic')) {
      throw const FormatException(
        'Use --pubsub-event together with --pubsub-topic.',
      );
    }

    return _Options(
      endpoint: endpoint,
      protocolVersion: protocolVersion,
      bearerToken: bearerToken,
      authEndpoint: authEndpoint,
      authRealm: authRealm,
      authId: authId,
      ticket: ticket,
      toolName: _mcpToolNameOption(values, '--tool'),
      toolArguments: _jsonObjectOption(
        values,
        '--tool-arguments',
        const <String, Object?>{},
      ),
      resourceUri: _mcpResourceUriOption(values, '--resource-uri'),
      promptName: _mcpSelectorOption(values, '--prompt'),
      promptArguments: _jsonStringMapOption(
        values,
        '--prompt-arguments',
        const <String, String>{},
      ),
      wampProcedure: _mcpSelectorOption(values, '--wamp-procedure'),
      wampTopic: _mcpSelectorOption(values, '--wamp-topic'),
      pubsubTopic: _mcpSelectorOption(values, '--pubsub-topic'),
      pubsubEvent: _jsonObjectOption(
        values,
        '--pubsub-event',
        const <String, Object?>{'source': 'router-hosted-client-example'},
      ),
      authLifecycleSmoke: authLifecycleSmoke,
      dryRun: values.containsKey('--dry-run'),
    );
  }
}

String _protocolVersionOption(Map<String, String> values) {
  final value =
      values['--protocol-version'] ??
      McpStreamableHttpClient.latestProtocolVersion;
  if (_supportedMcpProtocolVersions.contains(value)) {
    return value;
  }
  throw FormatException(
    'Unsupported MCP protocol version "$value". Supported versions: '
    '${_supportedMcpProtocolVersions.join(', ')}.',
  );
}

String? _bearerTokenOption(Map<String, String> values) {
  final rawToken = values['--bearer-token'];
  if (rawToken == null) {
    return null;
  }
  final token = rawToken.trim();
  if (token.isEmpty) {
    throw const FormatException('Bearer token must not be empty.');
  }
  if (_containsMcpWhitespaceOrControl(token)) {
    throw const FormatException(
      'Bearer token must not contain whitespace or control characters.',
    );
  }
  return token;
}

String? _nonEmptyStringOption(Map<String, String> values, String option) {
  final value = values[option];
  if (value == null) {
    return null;
  }
  if (value.runes.every(_isMcpWhitespaceOrControlRune)) {
    throw FormatException('$option must not be empty.');
  }
  return value;
}

String? _mcpToolNameOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (!_mcpToolNamePattern.hasMatch(value)) {
    throw FormatException(
      '$option must be 1-128 ASCII letters, digits, underscores, hyphens, '
      'or dots.',
    );
  }
  return value;
}

String? _mcpSelectorOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (_containsMcpWhitespaceOrControl(value)) {
    throw FormatException(
      '$option must not contain whitespace or control characters.',
    );
  }
  return value;
}

String? _mcpResourceUriOption(Map<String, String> values, String option) {
  final value = _nonEmptyStringOption(values, option);
  if (value == null) {
    return null;
  }
  if (_containsMcpWhitespaceOrControl(value)) {
    throw FormatException(
      '$option must not contain whitespace or control characters.',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('$option must be an absolute URI with a scheme.');
  }
  return value;
}

bool _containsMcpWhitespaceOrControl(String value) {
  for (final rune in value.runes) {
    if (_isMcpWhitespaceOrControlRune(rune)) {
      return true;
    }
  }
  return false;
}

bool _isMcpWhitespaceOrControlRune(int rune) {
  return rune <= 0x20 ||
      (rune >= 0x7f && rune <= 0x9f) ||
      rune == 0xa0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200a) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f ||
      rune == 0x3000 ||
      rune == 0xfeff;
}

Map<String, String> _parseOptions(List<String> args) {
  const valueOptions = {
    '--endpoint',
    '--protocol-version',
    '--bearer-token',
    '--auth-url',
    '--realm',
    '--auth-id',
    '--ticket',
    '--tool',
    '--tool-arguments',
    '--resource-uri',
    '--prompt',
    '--prompt-arguments',
    '--wamp-procedure',
    '--wamp-topic',
    '--pubsub-topic',
    '--pubsub-event',
  };
  const flagOptions = {'--dry-run', '--auth-lifecycle-smoke'};

  final values = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final option = args[index];
    if (flagOptions.contains(option)) {
      if (values.containsKey(option)) {
        throw FormatException('Duplicate option: $option.');
      }
      values[option] = 'true';
      continue;
    }
    if (!valueOptions.contains(option)) {
      throw FormatException('Unknown option: $option');
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw FormatException('Missing value for $option.');
    }
    if (values.containsKey(option)) {
      throw FormatException('Duplicate option: $option.');
    }
    values[option] = args[index + 1];
    index += 1;
  }
  return values;
}

Uri _requiredUri(Map<String, String> values, String option) {
  final value = values[option];
  if (value == null) {
    throw FormatException('Missing required $option.');
  }
  return _httpUri(value, option);
}

Uri? _optionalUri(Map<String, String> values, String option) {
  final value = values[option];
  return value == null ? null : _httpUri(value, option);
}

Uri _httpUri(String value, String option) {
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    throw FormatException('$option must be an absolute http or https URL.');
  }
  if ((uri.scheme != 'http' && uri.scheme != 'https') || !uri.hasAuthority) {
    throw FormatException('$option must be an absolute http or https URL.');
  }
  return uri;
}

bool _jsonValueEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonValueEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_jsonValueEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

McpJsonMap _jsonObjectOption(
  Map<String, String> values,
  String option,
  McpJsonMap defaultValue,
) {
  final value = values[option];
  if (value == null) {
    return defaultValue;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(value);
  } on FormatException {
    throw FormatException('$option must be valid JSON.');
  }
  if (decoded is! Map) {
    throw FormatException('$option must be a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

Map<String, String> _jsonStringMapOption(
  Map<String, String> values,
  String option,
  Map<String, String> defaultValue,
) {
  final decoded = _jsonObjectOption(values, option, defaultValue);
  return decoded.map((key, value) {
    if (value is! String) {
      throw FormatException('$option values must be strings.');
    }
    return MapEntry(key, value);
  });
}

void _printUsage(IOSink sink) {
  sink.writeln('''
Usage:
  dart run connectanum_mcp:router_hosted_client \\
    --endpoint http://127.0.0.1:8080/mcp [options]

Options:
  --bearer-token TOKEN              Use a bearer-protected MCP route.
  --protocol-version VERSION        MCP protocol version header to send.
  --auth-url URL                    Issue a ticket auth grant from this URL.
  --realm REALM                     Realm for --auth-url ticket grants.
  --auth-id AUTHID                  Auth id for --auth-url ticket grants.
  --ticket TICKET                   Ticket secret for --auth-url grants.
  --auth-lifecycle-smoke            Refresh/revoke ticket auth grant lifecycle (requires --auth-url).
  --tool NAME                       Call this direct JSON tool.
  --tool-arguments JSON_OBJECT      Arguments for --tool.
  --resource-uri URI                Read this resource and list templates through direct JSON and Streamable HTTP.
  --prompt NAME                     Get this prompt through direct JSON and Streamable HTTP.
  --prompt-arguments JSON_OBJECT    String arguments for --prompt.
  --wamp-procedure URI              Describe and match this WAMP procedure through direct JSON and Streamable HTTP.
  --wamp-topic URI                  Describe this WAMP topic through direct JSON and Streamable HTTP.
  --pubsub-topic TOPIC              Exercise direct JSON and Streamable pub/sub helpers.
  --pubsub-event JSON_OBJECT        Event kwargs for --pubsub-topic.
  --dry-run                         Validate options without HTTP requests.
''');
}
