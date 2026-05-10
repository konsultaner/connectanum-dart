// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_router/connectanum_router.dart';

const String _realm = 'example.realm';
const String _authPath = '/auth';
const String _publicMcpPath = '/mcp';
const String _secureMcpPath = '/mcp/secure';
const String _ticketAuthId = 'mcp-user';
const String _ticketSecret = 'mcp-demo-ticket';
const List<String> _supportedOlderProtocolVersions = [
  '2025-03-26',
  '2025-06-18',
];
const String _unsupportedProtocolVersion = '2099-01-01';

Future<void> main(List<String> args) async {
  final smokeAndExit = args.contains('--smoke-and-exit');
  String? nativeLibraryPath;
  for (final arg in args) {
    if (!arg.startsWith('--')) {
      nativeLibraryPath = arg;
      break;
    }
  }

  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}\n'
      'Install Rust so Dart build hooks can compile ct_ffi, set '
      'CONNECTANUM_NATIVE_LIB, or pass the native library path as the first '
      'argument.',
    );
    exitCode = 64;
    return;
  }

  runtime.start();

  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: _buildSettings(),
  );

  final binding = router.start(runtime);
  final serviceSession = await binding.createInternalSession(
    realmUri: _realm,
    authId: 'router-hosted-mcp-example',
    authRole: 'service',
  );
  final publicMcpClient = McpStreamableHttpClient(_mcpEndpoint(binding));
  McpStreamableHttpClient? secureMcpClient;

  try {
    await _registerExampleApi(serviceSession);
    await _smokeMcpProtocolVersionCompatibility(binding, label: 'public');
    await _smokeMcpEndpoint(
      publicMcpClient,
      label: 'public',
      serviceSession: serviceSession,
    );

    await _assertSecureMcpRequiresBearer(binding);
    final grant = await _issueTicketHttpGrant(binding);
    final bearerToken = grant.accessToken;
    await _smokeMcpProtocolVersionCompatibility(
      binding,
      label: 'secure',
      secure: true,
      bearerToken: bearerToken,
    );
    secureMcpClient = McpStreamableHttpClient.withBearerToken(
      _mcpEndpoint(binding, secure: true),
      bearerToken,
    );
    await _smokeMcpEndpoint(
      secureMcpClient,
      label: 'secure',
      serviceSession: serviceSession,
    );
    await _smokeSecureMcpRefreshAndRevocation(binding, grant);

    final endpoint = _mcpEndpoint(binding);
    final secureEndpoint = _mcpEndpoint(binding, secure: true);
    print('Router-hosted MCP endpoint is running at $endpoint');
    print('Bearer-protected MCP endpoint is running at $secureEndpoint');
    print('The example registered WAMP procedure example.task.lookup.');
    print(
      'Direct JSON-RPC clients can POST connectanum.tools.list, '
      'connectanum.tool.call, or example.task.lookup to the same endpoint.',
    );

    if (!smokeAndExit) {
      print('Press Ctrl+C to stop.');
      await Future.any([
        ProcessSignal.sigint.watch().first,
        ProcessSignal.sigterm.watch().first,
      ]);
    }
  } finally {
    await _closeMcpClient(publicMcpClient);
    final secureClient = secureMcpClient;
    if (secureClient != null) {
      await _closeMcpClient(secureClient);
    }
    await serviceSession.close();
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
}

Uri _mcpEndpoint(RouterBinding binding, {bool secure = false}) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: secure ? _secureMcpPath : _publicMcpPath,
  );
}

Uri _authEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _authPath,
  );
}

RouterSettings _buildSettings() {
  const mcpOptions = <String, Object?>{
    'include_registered_procedures': true,
    'include_standard_meta_api': true,
    'include_pubsub_tools': true,
    'topics': [
      {
        'topic': 'example.events.task',
        'title': 'Task events',
        'description': 'Events emitted by task procedures.',
        'event_json_schema': {
          'type': 'object',
          'properties': {
            'taskId': {'type': 'string'},
          },
        },
        'metadata': {
          'short_description': 'Task lifecycle event stream',
          'domain': 'example',
          'entity': 'task',
          'verbs': ['publish', 'subscribe'],
          'tags': ['safe', 'demo', 'event'],
        },
      },
    ],
    'resources': [
      {
        'uri': 'app://example/context',
        'name': 'Example context',
        'title': 'Router-hosted MCP example context',
        'description': 'Static context exposed by the router.',
        'mime_type': 'text/markdown',
        'text':
            '# Router-hosted MCP example\n'
            'This endpoint exposes WAMP tools, pub/sub helpers, '
            'resources, and prompts from one router route.',
      },
    ],
    'resource_templates': [
      {
        'uri_template': 'app://example/tasks/{taskId}',
        'name': 'Example task template',
        'description': 'Template URI shape for task context.',
        'mime_type': 'application/json',
      },
    ],
    'prompts': [
      {
        'name': 'summarize-task',
        'title': 'Summarize task',
        'description': 'Builds a prompt for summarizing a task.',
        'arguments': [
          {
            'name': 'taskId',
            'description': 'Task identifier to summarize.',
            'required': true,
          },
        ],
        'messages': [
          {
            'role': 'user',
            'text':
                'Summarize task {{taskId}} using the '
                'router-hosted MCP context.',
          },
        ],
      },
    ],
  };

  final realm = RealmSettingsBuilder(_realm)
    ..addAuthMethod('anonymous')
    ..addAuthMethod('ticket', options: const {'authenticator': 'ticket-demo'})
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('example.task.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('example.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('example.task.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('example.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('service')..addPermissionFromBuilder(
        PermissionSettingsBuilder('example.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'call',
            'publish',
            'subscribe',
            'unsubscribe',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder('mcp-http', '127.0.0.1:0')
    ..setSessionProfile('public-wamp')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      HttpListenerSettings(
        sessionProfile: 'public-http',
        routes: [
          HttpRouteSettings(
            match: const HttpRouteMatch(path: _authPath),
            action: const HttpRouteAction(
              type: HttpRouteActionType.auth,
              sessionProfile: 'mcp-ticket',
              options: {
                'allow_insecure_transport': true,
                'token_ttl_ms': 60000,
                'refresh_token_ttl_ms': 300000,
                'rotate_refresh_tokens': true,
              },
            ),
          ),
          HttpRouteSettings(
            match: const HttpRouteMatch(path: _publicMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              options: mcpOptions,
            ),
          ),
          HttpRouteSettings(
            match: const HttpRouteMatch(path: _secureMcpPath),
            action: const HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-ticket',
              options: {...mcpOptions, 'allow_insecure_transport': true},
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return (RouterSettingsBuilder()
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        ..addRealmFromBuilder(realm)
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-wamp')
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-http'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-public')
            ..setRealm(_realm)
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-ticket')
            ..setRealm(_realm)
            ..setAuthMethods(const ['ticket']),
        )
        ..addAuthenticator(
          'ticket-demo',
          const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                _ticketAuthId: {
                  'ticket': _ticketSecret,
                  'role': 'member',
                  'provider': 'example-local',
                },
              },
            },
          ),
        )
        ..addListenerFromBuilder(listener))
      .build();
}

Future<void> _registerExampleApi(RouterSession serviceSession) async {
  final registration = await serviceSession.register(
    'example.task.lookup',
    options: RegisterOptions(
      custom: const {
        '_ai_meta_data': {
          'short_description': 'Look up task state',
          'description': 'Returns a small task status document.',
          'domain': 'example',
          'entity': 'task',
          'verbs': ['lookup'],
          'tags': ['safe', 'demo'],
          'publishes_events': ['example.events.task'],
          'input_json_schema': {
            'type': 'object',
            'properties': {
              'taskId': {'type': 'string'},
            },
            'required': ['taskId'],
          },
          'output_json_schema': {
            'type': 'object',
            'properties': {
              'taskId': {'type': 'string'},
              'status': {'type': 'string'},
            },
          },
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ),
  );

  registration.onInvoke((invocation) {
    final taskId = invocation.argumentsKeywords?['taskId'] ?? 'unknown';
    invocation.respondWith(
      argumentsKeywords: {
        'taskId': taskId,
        'status': 'open',
        'source': 'router-hosted-mcp-example',
      },
    );
  });
}

Future<void> _closeMcpClient(McpStreamableHttpClient client) async {
  if (client.sessionId != null) {
    try {
      await client.deleteSession();
    } on Object {
      // The process is shutting down; connection teardown is best-effort.
    }
  }
  client.close(force: true);
}

Future<void> _assertSecureMcpRequiresBearer(RouterBinding binding) async {
  final client = McpStreamableHttpClient(_mcpEndpoint(binding, secure: true));
  try {
    await client.listResources(
      id: 'secure-unauthenticated-resources',
      directJson: true,
    );
    throw StateError('Bearer-protected MCP endpoint accepted no credentials.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Bearer-protected MCP endpoint returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized}.',
      );
    }
    print('Secure MCP endpoint rejects unauthenticated requests.');
  } finally {
    client.close(force: true);
  }
}

Future<ConnectanumHttpAuthGrant> _issueTicketHttpGrant(
  RouterBinding binding,
) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    return await authClient.issueTicketToken(
      realm: _realm,
      authId: _ticketAuthId,
      ticket: _ticketSecret,
    );
  } finally {
    authClient.close(force: true);
  }
}

Future<void> _assertSecureMcpRejectsBearer(
  RouterBinding binding,
  String bearerToken, {
  required String acceptedMessage,
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    bearerToken,
  );
  try {
    await client.listConnectanumToolsDirect(id: 'secure-rejected-bearer-tools');
    throw StateError(acceptedMessage);
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Bearer-protected MCP endpoint returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for a rejected token.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _assertTicketRefreshRejected(
  RouterBinding binding,
  String refreshToken, {
  required String acceptedMessage,
}) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    await authClient.refreshToken(refreshToken);
    throw StateError(acceptedMessage);
  } on ConnectanumHttpAuthException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'HTTP auth bridge returned ${error.statusCode} instead of '
        '${HttpStatus.unauthorized} for a rejected refresh token.',
      );
    }
  } finally {
    authClient.close(force: true);
  }
}

Future<McpStreamableHttpClient> _openSecureMcpSession(
  RouterBinding binding,
  String bearerToken, {
  required String label,
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    bearerToken,
  );
  try {
    await client.initialize(id: '$label-active-session-initialize');
    await client.notifyInitialized();
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Secure Streamable MCP session did not initialize.');
    }
    return client;
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

Future<void> _assertActiveStreamableSessionRejectsBearer(
  McpStreamableHttpClient client, {
  required String label,
  required String acceptedMessage,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Secure Streamable MCP rejection smoke has no session.');
  }
  final lastEventId = client.lastEventId;

  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  try {
    await client.listTools(id: '$label-rejected-session-tools');
    throw StateError(acceptedMessage);
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Active Streamable MCP request returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for a rejected token.',
      );
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Active Streamable MCP request did not clear rejected session state.',
    );
  }
}

Future<void> _smokeSecureMcpRefreshedBearer(
  RouterBinding binding,
  String bearerToken,
) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    bearerToken,
  );
  try {
    final directTools = await client.listConnectanumToolsDirect(
      id: 'secure-refreshed-direct-tools',
    );
    if (!directTools.tools.any(
      (tool) => tool['name'] == 'example.task.lookup',
    )) {
      throw StateError('Refreshed bearer did not expose direct MCP tools.');
    }

    await client.initialize(id: 'secure-refreshed-initialize');
    await client.notifyInitialized();
    final streamableTools = await client.listTools(
      id: 'secure-refreshed-tools',
    );
    if (!streamableTools.tools.any(
      (tool) => tool['name'] == 'example.task.lookup',
    )) {
      throw StateError('Refreshed bearer did not expose Streamable MCP tools.');
    }
    await client.deleteSession();
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError('Refreshed bearer session cleanup left session state.');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _smokeSecureMcpRefreshAndRevocation(
  RouterBinding binding,
  ConnectanumHttpAuthGrant grant,
) async {
  final refreshToken = grant.refreshToken;
  if (refreshToken == null || refreshToken.isEmpty) {
    throw StateError('HTTP auth bridge did not issue a refresh token.');
  }

  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  McpStreamableHttpClient? rotatedSessionClient;
  McpStreamableHttpClient? revokedSessionClient;
  try {
    rotatedSessionClient = await _openSecureMcpSession(
      binding,
      grant.accessToken,
      label: 'secure-rotated',
    );

    final refreshed = await authClient.refreshToken(refreshToken);
    if (refreshed.accessToken == grant.accessToken) {
      throw StateError('HTTP auth bridge refresh reused the access token.');
    }
    final rotatedRefreshToken = refreshed.refreshToken;
    if (rotatedRefreshToken == null || rotatedRefreshToken.isEmpty) {
      throw StateError(
        'HTTP auth bridge refresh did not rotate refresh token.',
      );
    }
    if (rotatedRefreshToken == refreshToken) {
      throw StateError('HTTP auth bridge refresh reused the refresh token.');
    }

    await _assertActiveStreamableSessionRejectsBearer(
      rotatedSessionClient,
      label: 'secure-rotated',
      acceptedMessage:
          'Streamable MCP session accepted a rotated access token.',
    );
    rotatedSessionClient.close(force: true);
    rotatedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      grant.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a rotated access token.',
    );
    await _assertTicketRefreshRejected(
      binding,
      refreshToken,
      acceptedMessage: 'HTTP auth bridge accepted a rotated refresh token.',
    );

    await _smokeSecureMcpRefreshedBearer(binding, refreshed.accessToken);

    revokedSessionClient = await _openSecureMcpSession(
      binding,
      refreshed.accessToken,
      label: 'secure-revoked',
    );
    await authClient.revokeToken(
      rotatedRefreshToken,
      tokenTypeHint: 'refresh_token',
    );
    await _assertActiveStreamableSessionRejectsBearer(
      revokedSessionClient,
      label: 'secure-revoked',
      acceptedMessage:
          'Streamable MCP session accepted a revoked access token.',
    );
    revokedSessionClient.close(force: true);
    revokedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      refreshed.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a revoked access token.',
    );
    await _assertTicketRefreshRejected(
      binding,
      rotatedRefreshToken,
      acceptedMessage: 'HTTP auth bridge accepted a revoked refresh token.',
    );
  } finally {
    rotatedSessionClient?.close(force: true);
    revokedSessionClient?.close(force: true);
    authClient.close(force: true);
  }
}

McpStreamableHttpClient _protocolVersionClient(
  Uri endpoint, {
  required String defaultProtocolVersion,
  String? bearerToken,
}) {
  final token = bearerToken;
  if (token == null) {
    return McpStreamableHttpClient(
      endpoint,
      defaultProtocolVersion: defaultProtocolVersion,
    );
  }
  return McpStreamableHttpClient.withBearerToken(
    endpoint,
    token,
    defaultProtocolVersion: defaultProtocolVersion,
  );
}

Future<void> _smokeMcpProtocolVersionCompatibility(
  RouterBinding binding, {
  required String label,
  bool secure = false,
  String? bearerToken,
}) async {
  final endpoint = _mcpEndpoint(binding, secure: secure);
  for (final version in _supportedOlderProtocolVersions) {
    await _smokeSupportedMcpProtocolVersion(
      endpoint,
      version,
      label: label,
      bearerToken: bearerToken,
    );
  }
  await _assertUnsupportedMcpProtocolVersionRejected(
    endpoint,
    label: label,
    bearerToken: bearerToken,
  );
}

Future<void> _smokeSupportedMcpProtocolVersion(
  Uri endpoint,
  String protocolVersion, {
  required String label,
  String? bearerToken,
}) async {
  final client = _protocolVersionClient(
    endpoint,
    defaultProtocolVersion: protocolVersion,
    bearerToken: bearerToken,
  );
  try {
    final initializeId = '$label-$protocolVersion-initialize';
    final initialize = await client.initialize(id: initializeId);
    if (initialize['id'] != initializeId) {
      throw StateError(
        'MCP $label initialize with $protocolVersion returned the wrong id.',
      );
    }
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'MCP $label initialize with $protocolVersion did not set a session id.',
      );
    }
    if (client.protocolVersion !=
        McpStreamableHttpClient.latestProtocolVersion) {
      throw StateError(
        'MCP $label did not negotiate $protocolVersion to '
        '${McpStreamableHttpClient.latestProtocolVersion}.',
      );
    }
    await client.notifyInitialized();
    final ping = await client.ping(id: '$label-$protocolVersion-ping');
    if (ping.isNotEmpty) {
      throw StateError('MCP $label ping with $protocolVersion returned data.');
    }
    await client.deleteSession();
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP $label deleteSession with $protocolVersion left session state.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _assertUnsupportedMcpProtocolVersionRejected(
  Uri endpoint, {
  required String label,
  String? bearerToken,
}) async {
  final client = _protocolVersionClient(
    endpoint,
    defaultProtocolVersion: _unsupportedProtocolVersion,
    bearerToken: bearerToken,
  );
  try {
    await client.initialize(id: '$label-unsupported-protocol-initialize');
    throw StateError('MCP $label accepted an unsupported protocol version.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      rethrow;
    }
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP $label unsupported protocol rejection left session state.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _smokeMcpEndpoint(
  McpStreamableHttpClient client, {
  required String label,
  required RouterSession serviceSession,
}) async {
  final directTools = await client.listConnectanumToolsDirect(
    id: '$label-direct-tools',
  );
  final directToolNames = {
    for (final tool in directTools.tools) tool['name'] as String,
  };
  if (!directToolNames.contains('example.task.lookup')) {
    throw StateError('MCP tool catalog did not expose example.task.lookup.');
  }

  final directResult = await client.callConnectanumMethodDirect(
    'example.task.lookup',
    id: '$label-direct-call',
    params: {'taskId': 'T-$label-direct'},
  );
  print('[$label] Direct JSON-RPC result: ${jsonEncode(directResult)}');
  await _smokeDirectJsonToolMetaApi(client, label: label);
  await _smokeDirectJsonTopicMetaApi(client, label: label);
  await _smokeDirectJsonErrorRecovery(client, label: label);

  final directResources = await client.listResources(
    id: '$label-direct-resources',
    directJson: true,
  );
  if (!directResources.resources.any(
    (resource) => resource['uri'] == 'app://example/context',
  )) {
    throw StateError('Direct JSON-RPC resources/list did not expose context.');
  }

  final directResource = await client.readResource(
    'app://example/context',
    id: '$label-direct-resource-read',
    directJson: true,
  );
  if (!jsonEncode(directResource).contains('Router-hosted MCP example')) {
    throw StateError('Direct JSON-RPC resources/read did not return context.');
  }

  final directPrompt = await client.getPrompt(
    'summarize-task',
    id: '$label-direct-prompt',
    arguments: {'taskId': 'T-$label-direct'},
    directJson: true,
  );
  if (!jsonEncode(directPrompt).contains('T-$label-direct')) {
    throw StateError('Direct JSON-RPC prompts/get did not render taskId.');
  }

  final directResourcePromptBatch = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-direct-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': 'app://example/context'},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-direct-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-direct-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    },
  ], streamable: false);
  if (directResourcePromptBatch == null ||
      directResourcePromptBatch.length != 3) {
    throw StateError(
      'Direct JSON-RPC resource/prompt batch did not return three responses.',
    );
  }
  if (directResourcePromptBatch[0]['id'] !=
          '$label-direct-batch-resource-read' ||
      !jsonEncode(
        directResourcePromptBatch[0],
      ).contains('Router-hosted MCP example')) {
    throw StateError(
      'Direct JSON-RPC batch resources/read response was invalid.',
    );
  }
  if (directResourcePromptBatch[1]['id'] !=
          '$label-direct-batch-resource-templates' ||
      !jsonEncode(
        directResourcePromptBatch[1],
      ).contains('app://example/tasks/{taskId}')) {
    throw StateError(
      'Direct JSON-RPC batch resources/templates/list response was invalid.',
    );
  }
  if (directResourcePromptBatch[2]['id'] != '$label-direct-batch-prompts' ||
      !jsonEncode(directResourcePromptBatch[2]).contains('summarize-task')) {
    throw StateError(
      'Direct JSON-RPC batch prompts/list response was invalid.',
    );
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Direct JSON-RPC resource/prompt batch changed Streamable state.',
    );
  }

  final directSubscription = await client.subscribeWampTopic(
    'example.events.task',
    id: '$label-direct-subscribe',
    queueLimit: 4,
    directJson: true,
  );
  try {
    final directPublication = await client.publishWampEvent(
      'example.events.task',
      id: '$label-direct-publish',
      argumentsKeywords: {'taskId': 'T-$label-direct-publish'},
      acknowledge: true,
      directJson: true,
    );
    if (!directPublication.acknowledged) {
      throw StateError('Direct JSON-RPC pub/sub publish was not acknowledged.');
    }

    await serviceSession.publish(
      'example.events.task',
      argumentsKeywords: {'taskId': 'T-$label-direct-service'},
      options: PublishOptions(acknowledge: true),
    );
    final directEvents = await _pollMcpEventsUntil(
      client,
      directSubscription.handle,
      label: '$label direct JSON',
      directJson: true,
    );
    if (!jsonEncode(directEvents.events).contains('T-$label-direct-service')) {
      throw StateError('Direct JSON-RPC pub/sub poll did not receive event.');
    }
  } finally {
    await client.unsubscribeWampTopic(
      directSubscription.handle,
      id: '$label-direct-unsubscribe',
      directJson: true,
    );
  }
  await _smokeMcpPubSubQueueOverflow(
    client,
    serviceSession,
    label: label,
    directJson: true,
  );
  await _smokeDirectJsonBatchPubSub(client, serviceSession, label: label);
  await _smokeDirectJsonBatchWampMeta(client, serviceSession, label: label);

  await client.initialize(
    clientInfo: const {'name': 'router_hosted_mcp_example', 'version': '0.1.0'},
  );
  await client.notifyInitialized();

  final streamableTools = await client.listTools(id: 'example-tools-list');
  final streamableToolNames = {
    for (final tool in streamableTools.tools) tool['name'] as String,
  };
  if (!streamableToolNames.contains('example.task.lookup')) {
    throw StateError(
      'Streamable MCP tool catalog did not expose example.task.lookup.',
    );
  }

  final streamableResult = await client.callTool(
    'example.task.lookup',
    id: '$label-tools-call',
    arguments: {'taskId': 'T-$label-streamable'},
  );
  print('[$label] Streamable MCP tool result: ${jsonEncode(streamableResult)}');
  await _smokeStreamableErrorRecovery(client, label: label);

  final streamableBatch = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-batch-tools',
      'method': 'tools/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-batch-call',
      'method': 'tools/call',
      'params': {
        'name': 'example.task.lookup',
        'arguments': {'taskId': 'T-$label-batch'},
      },
    },
    {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
  ]);
  if (streamableBatch == null || streamableBatch.length != 2) {
    throw StateError('Streamable MCP batch did not return two responses.');
  }
  if (streamableBatch[0]['id'] != '$label-batch-tools' ||
      !jsonEncode(streamableBatch[0]).contains('example.task.lookup')) {
    throw StateError('Streamable MCP batch tools/list response was invalid.');
  }
  if (streamableBatch[1]['id'] != '$label-batch-call' ||
      !jsonEncode(streamableBatch[1]).contains('T-$label-batch')) {
    throw StateError('Streamable MCP batch tools/call response was invalid.');
  }

  final streamableSessionId = client.sessionId;
  if (streamableSessionId == null) {
    throw StateError('Streamable MCP example has no initialized session id.');
  }
  final streamableLastEventId = client.lastEventId;
  final streamableResourcePromptBatch = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': 'app://example/context'},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    },
  ]);
  if (streamableResourcePromptBatch == null ||
      streamableResourcePromptBatch.length != 3) {
    throw StateError(
      'Streamable MCP resource/prompt batch did not return three responses.',
    );
  }
  if (streamableResourcePromptBatch[0]['id'] != '$label-batch-resource-read' ||
      !jsonEncode(
        streamableResourcePromptBatch[0],
      ).contains('Router-hosted MCP example')) {
    throw StateError('Streamable MCP batch resources/read response invalid.');
  }
  if (streamableResourcePromptBatch[1]['id'] !=
          '$label-batch-resource-templates' ||
      !jsonEncode(
        streamableResourcePromptBatch[1],
      ).contains('app://example/tasks/{taskId}')) {
    throw StateError(
      'Streamable MCP batch resources/templates/list response was invalid.',
    );
  }
  if (streamableResourcePromptBatch[2]['id'] != '$label-batch-prompts' ||
      !jsonEncode(
        streamableResourcePromptBatch[2],
      ).contains('summarize-task')) {
    throw StateError('Streamable MCP batch prompts/list response was invalid.');
  }
  if (client.sessionId != streamableSessionId) {
    throw StateError(
      'Streamable MCP resource/prompt batch changed session id.',
    );
  }
  final nextEventId = client.lastEventId;
  if (nextEventId == null ||
      nextEventId == streamableLastEventId ||
      !nextEventId.startsWith('$streamableSessionId:')) {
    throw StateError(
      'Streamable MCP resource/prompt batch did not advance SSE state.',
    );
  }

  await _smokeStreamableBatchWampMeta(client, serviceSession, label: label);
  await _smokeStreamableTopicMetaApi(client, label: label);

  final streamableSubscription = await client.subscribeWampTopic(
    'example.events.task',
    id: '$label-streamable-subscribe',
    queueLimit: 4,
  );
  try {
    final streamablePublication = await client.publishWampEvent(
      'example.events.task',
      id: '$label-streamable-publish',
      argumentsKeywords: {'taskId': 'T-$label-streamable-publish'},
      acknowledge: true,
    );
    if (!streamablePublication.acknowledged) {
      throw StateError('Streamable MCP pub/sub publish was not acknowledged.');
    }

    await serviceSession.publish(
      'example.events.task',
      argumentsKeywords: {'taskId': 'T-$label-streamable-service'},
      options: PublishOptions(acknowledge: true),
    );
    final streamableEvents = await _pollMcpEventsUntil(
      client,
      streamableSubscription.handle,
      label: '$label Streamable',
    );
    if (!jsonEncode(
      streamableEvents.events,
    ).contains('T-$label-streamable-service')) {
      throw StateError('Streamable MCP pub/sub poll did not receive event.');
    }
  } finally {
    await client.unsubscribeWampTopic(
      streamableSubscription.handle,
      id: '$label-streamable-unsubscribe',
    );
  }
  await _smokeMcpPubSubQueueOverflow(
    client,
    serviceSession,
    label: label,
    directJson: false,
  );
  await _smokeStreamableBatchPubSub(client, serviceSession, label: label);

  final streamableTemplates = await client.listResourceTemplates(
    id: '$label-template-list',
  );
  if (!streamableTemplates.resourceTemplates.any(
    (template) => template['uriTemplate'] == 'app://example/tasks/{taskId}',
  )) {
    throw StateError('Streamable MCP did not expose resource template.');
  }

  final streamablePrompt = await client.getPrompt(
    'summarize-task',
    id: '$label-prompt-get',
    arguments: {'taskId': 'T-$label-streamable'},
  );
  if (!jsonEncode(streamablePrompt).contains('T-$label-streamable')) {
    throw StateError('Streamable MCP prompt did not render taskId.');
  }

  await _smokeStreamableSessionLifecycle(client, serviceSession, label: label);
}

Future<void> _smokeStreamableSessionLifecycle(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP $label session did not capture an id.');
  }

  final dynamicProcedure = 'example.task.dynamic.$label';
  final registration = await serviceSession.register(
    dynamicProcedure,
    options: RegisterOptions(
      custom: {
        '_ai_meta_data': {
          'short_description': 'Dynamic $label task lookup',
          'description':
              'Procedure registered after MCP initialization to verify '
              'Streamable HTTP GET/SSE polling.',
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ),
  );
  registration.onInvoke((invocation) {
    invocation.respondWith(
      argumentsKeywords: {
        'label': label,
        'source': 'router-hosted-mcp-example',
      },
    );
  });

  final events = await _pollStreamableSessionEventsUntil(
    client,
    label: label,
    headers: <String, String>{'x-consumer-trace': '$label-streamable-poll'},
  );
  final hasToolListChanged = events.any(
    (event) => event.jsonData?['method'] == 'notifications/tools/list_changed',
  );
  if (!hasToolListChanged) {
    throw StateError(
      'Streamable MCP $label GET/SSE poll did not receive tools/list_changed.',
    );
  }
  final eventId = client.lastEventId;
  if (eventId == null || eventId.isEmpty) {
    throw StateError('Streamable MCP $label GET/SSE poll missed event id.');
  }

  final resumedEvents = await client.poll(
    lastEventId: eventId,
    headers: <String, String>{'x-consumer-trace': '$label-streamable-resume'},
  );
  if (resumedEvents.any(
    (event) =>
        event.id == eventId ||
        event.jsonData?['method'] == 'notifications/tools/list_changed',
  )) {
    throw StateError('Streamable MCP $label Last-Event-ID replayed an event.');
  }

  final eventIdAfterResume = client.lastEventId;
  if (eventIdAfterResume == null || eventIdAfterResume.isEmpty) {
    throw StateError('Streamable MCP $label resume lost SSE cursor.');
  }
  await _assertInvalidLastEventIdRejectedWithoutSessionLoss(
    client,
    label: label,
    sessionId: sessionId,
    eventId: eventIdAfterResume,
  );

  await client.deleteSession(
    headers: <String, String>{'x-consumer-trace': '$label-streamable-delete'},
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP $label DELETE left session state.');
  }

  client.sessionId = sessionId;
  client.lastEventId = eventId;
  try {
    await client.listTools(id: '$label-stale-session-tools');
    throw StateError('Deleted Streamable MCP $label session remained usable.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.notFound) {
      rethrow;
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP $label 404 did not clear session state.');
  }

  final recovered = await client.initialize(id: '$label-reinitialize');
  if (recovered['id'] != '$label-reinitialize' || client.sessionId == null) {
    throw StateError('Streamable MCP $label reinitialize after 404 failed.');
  }
  await client.notifyInitialized();
  await client.deleteSession(
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-recovered-delete',
    },
  );
}

Future<void> _assertInvalidLastEventIdRejectedWithoutSessionLoss(
  McpStreamableHttpClient client, {
  required String label,
  required String sessionId,
  required String eventId,
}) async {
  try {
    await client.poll(lastEventId: '$sessionId:missing:1');
    throw StateError(
      'Streamable MCP $label accepted an unknown Last-Event-ID.',
    );
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Streamable MCP $label invalid Last-Event-ID returned '
        '${error.statusCode} instead of ${HttpStatus.badRequest}.',
      );
    }
    if (!error.body.contains('Last-Event-ID')) {
      throw StateError(
        'Streamable MCP $label invalid Last-Event-ID error did not explain '
        'the resume cursor problem.',
      );
    }
  }

  if (client.sessionId != sessionId || client.lastEventId != eventId) {
    throw StateError(
      'Streamable MCP $label invalid Last-Event-ID changed session state.',
    );
  }

  final tools = await client.listTools(
    id: '$label-after-invalid-last-event-id-tools',
  );
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains('example.task.lookup')) {
    throw StateError(
      'Streamable MCP $label session failed after invalid Last-Event-ID.',
    );
  }
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP $label invalid Last-Event-ID recovery lost session id.',
    );
  }
}

Future<List<McpSseEvent>> _pollStreamableSessionEventsUntil(
  McpStreamableHttpClient client, {
  required String label,
  Map<String, String> headers = const <String, String>{},
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final events = await client.poll(headers: headers);
    if (events.any(
      (event) =>
          event.jsonData?['method'] == 'notifications/tools/list_changed',
    )) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for $label Streamable MCP SSE event.');
}

Future<void> _smokeDirectJsonToolMetaApi(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final helperTaskId = 'T-$label-direct-tool-helper';
  final helperResult = await client.callConnectanumToolDirect(
    'example.task.lookup',
    id: '$label-direct-tool-helper',
    arguments: {'taskId': helperTaskId},
  );
  if (!jsonEncode(helperResult).contains(helperTaskId)) {
    throw StateError('Direct JSON-RPC tool helper did not return task id.');
  }

  final pluralAliasTaskId = 'T-$label-direct-tools-call-alias';
  final pluralAliasResult = await client.callConnectanumMethodDirect(
    'connectanum.tools.call',
    id: '$label-direct-tools-call-alias',
    params: {
      'name': 'example.task.lookup',
      'arguments': {'taskId': pluralAliasTaskId},
    },
  );
  if (!jsonEncode(pluralAliasResult).contains(pluralAliasTaskId)) {
    throw StateError('Direct JSON-RPC plural tool alias failed.');
  }

  final toolListId = '$label-direct-generic-tools-list';
  final toolList = await client.request(
    'connectanum.tools.list',
    id: toolListId,
    streamable: false,
    includeSession: false,
  );
  if (toolList['id'] != toolListId ||
      !jsonEncode(toolList['result']).contains('example.task.lookup')) {
    throw StateError('Direct JSON-RPC generic tools/list missed tool.');
  }

  final singularAliasTaskId = 'T-$label-direct-tool-call-alias';
  final singularAliasId = '$label-direct-tool-call-alias';
  final singularAlias = await client.post(
    {
      'jsonrpc': '2.0',
      'id': singularAliasId,
      'method': 'connectanum.tool.call',
      'params': {
        'name': 'example.task.lookup',
        'arguments': {'taskId': singularAliasTaskId},
      },
    },
    streamable: false,
    includeSession: false,
  );
  if (singularAlias == null ||
      singularAlias['id'] != singularAliasId ||
      !jsonEncode(singularAlias).contains(singularAliasTaskId)) {
    throw StateError('Direct JSON-RPC singular tool alias failed.');
  }

  final apiListId = '$label-direct-generic-api-list';
  final apiList = await client.request(
    'connectanum.api.list',
    id: apiListId,
    params: {'kind': 'procedure'},
    streamable: false,
    includeSession: false,
  );
  if (apiList['id'] != apiListId ||
      !jsonEncode(apiList['result']).contains('example.task.lookup')) {
    throw StateError('Direct JSON-RPC generic API list missed procedure.');
  }

  final apiDescribeId = '$label-direct-generic-api-describe';
  final apiDescribe = await client.request(
    'connectanum.api.describe',
    id: apiDescribeId,
    params: {'uri': 'example.task.lookup', 'kind': 'procedure'},
    streamable: false,
    includeSession: false,
  );
  if (apiDescribe['id'] != apiDescribeId ||
      !jsonEncode(apiDescribe['result']).contains('example.task.lookup')) {
    throw StateError('Direct JSON-RPC generic API describe missed procedure.');
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON-RPC tool/meta API changed Streamable state.');
  }
}

Future<void> _smokeDirectJsonTopicMetaApi(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final topicList = await client.listWampApi(
    id: '$label-direct-topic-api-list',
    kind: 'topic',
    directJson: true,
  );
  final topicListJson = jsonEncode(topicList);
  if (!topicListJson.contains('example.events.task') ||
      !topicListJson.contains('Task lifecycle event stream')) {
    throw StateError('Direct JSON-RPC topic API list missed topic metadata.');
  }

  final topicDescription = await client.describeWampApi(
    'example.events.task',
    id: '$label-direct-topic-api-describe',
    kind: 'topic',
    directJson: true,
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (!topicDescriptionJson.contains('example.events.task') ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError(
      'Direct JSON-RPC topic API describe missed topic capabilities.',
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Direct JSON-RPC topic metadata changed Streamable state.',
    );
  }
}

Future<void> _smokeStreamableTopicMetaApi(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null) {
    throw StateError('Streamable topic metadata smoke has no session id.');
  }
  final previousEventId = client.lastEventId;

  final topicList = await client.listWampApi(
    id: '$label-streamable-topic-api-list',
    kind: 'topic',
  );
  final topicListJson = jsonEncode(topicList);
  if (!topicListJson.contains('example.events.task') ||
      !topicListJson.contains('Task lifecycle event stream')) {
    throw StateError('Streamable MCP topic API list missed topic metadata.');
  }

  final topicDescription = await client.describeWampApi(
    'example.events.task',
    id: '$label-streamable-topic-api-describe',
    kind: 'topic',
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (!topicDescriptionJson.contains('example.events.task') ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError(
      'Streamable MCP topic API describe missed topic capabilities.',
    );
  }

  if (client.sessionId != sessionId) {
    throw StateError('Streamable MCP topic metadata changed session id.');
  }
  final nextEventId = client.lastEventId;
  if (nextEventId == null ||
      nextEventId == previousEventId ||
      !nextEventId.startsWith('$sessionId:')) {
    throw StateError(
      'Streamable MCP topic metadata did not advance SSE state.',
    );
  }
}

Future<void> _smokeDirectJsonErrorRecovery(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final missingTool = 'missing.$label.direct.single';
  final errorId = '$label-direct-error-missing';
  try {
    await client.callConnectanumToolDirect(
      missingTool,
      id: errorId,
      arguments: {},
    );
    throw StateError('Direct JSON-RPC accepted missing tool $missingTool.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: errorId,
      method: 'connectanum.tool.call',
      messageSubstring: missingTool,
      label: 'Direct JSON-RPC missing tool',
    );
  }

  final missingResourceUri = 'app://example/missing/$label/direct';
  final resourceErrorId = '$label-direct-resource-error';
  final resourceError = await client.request(
    'resources/read',
    id: resourceErrorId,
    params: {'uri': missingResourceUri},
    streamable: false,
    includeSession: false,
  );
  _expectJsonRpcError(
    resourceError,
    id: resourceErrorId,
    messageSubstring: missingResourceUri,
    label: 'Direct JSON-RPC missing resource',
  );

  final missingPromptName = 'missing-$label-direct-prompt';
  final promptErrorId = '$label-direct-prompt-error';
  final promptError = _jsonObjectFrom(
    await client.post(
      {
        'jsonrpc': '2.0',
        'id': promptErrorId,
        'method': 'prompts/get',
        'params': {'name': missingPromptName, 'arguments': {}},
      },
      streamable: false,
      includeSession: false,
    ),
    label: 'Direct JSON-RPC missing prompt response',
  );
  _expectJsonRpcError(
    promptError,
    id: promptErrorId,
    messageSubstring: missingPromptName,
    label: 'Direct JSON-RPC missing prompt',
  );

  await _smokeDirectJsonBatchErrorIsolation(client, label: label);

  final recoveryTools = await client.listConnectanumToolsDirect(
    id: '$label-direct-error-recovery-tools',
  );
  final recoveryToolNames = {
    for (final tool in recoveryTools.tools) tool['name'] as String,
  };
  if (!recoveryToolNames.contains('example.task.lookup')) {
    throw StateError('Direct JSON-RPC error recovery missed tool catalog.');
  }

  final recoveryResources = await client.request(
    'resources/list',
    id: '$label-direct-resource-error-recovery',
    streamable: false,
    includeSession: false,
  );
  if (!jsonEncode(recoveryResources).contains('app://example/context')) {
    throw StateError('Direct JSON-RPC resource error recovery missed context.');
  }

  final recoveryPrompts = await client.request(
    'prompts/list',
    id: '$label-direct-prompt-error-recovery',
    streamable: false,
    includeSession: false,
  );
  if (!jsonEncode(recoveryPrompts).contains('summarize-task')) {
    throw StateError('Direct JSON-RPC prompt error recovery missed prompt.');
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON-RPC errors changed Streamable state.');
  }
}

Future<void> _smokeDirectJsonBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final taskId = 'T-$label-direct-batch-error-ok';
  final aliasTaskId = 'T-$label-direct-batch-error-alias-ok';
  final missingTool = 'missing.$label.direct.batch';
  final responses = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-api',
        'method': 'connectanum.api.list',
        'params': {'kind': 'procedure'},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-missing',
        'method': 'connectanum.tool.call',
        'params': {'name': missingTool, 'arguments': {}},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-call',
        'method': 'connectanum.tool.call',
        'params': {
          'name': 'example.task.lookup',
          'arguments': {'taskId': taskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-tools-alias',
        'method': 'connectanum.tools.call',
        'params': {
          'name': 'example.task.lookup',
          'arguments': {'taskId': aliasTaskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': {
          'name': 'example.task.lookup',
          'arguments': {'taskId': 'T-$label-direct-batch-notification'},
        },
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (responses == null || responses.length != 4) {
    throw StateError(
      'Direct JSON-RPC batch error smoke returned invalid size.',
    );
  }
  if (responses[0]['id'] != '$label-direct-batch-error-api' ||
      !jsonEncode(responses[0]).contains('example.task.lookup')) {
    throw StateError('Direct JSON-RPC batch error smoke lost API response.');
  }
  _expectJsonRpcError(
    responses[1],
    id: '$label-direct-batch-error-missing',
    messageSubstring: missingTool,
    label: 'Direct JSON-RPC batch missing tool',
  );
  if (responses[2]['id'] != '$label-direct-batch-error-call' ||
      !jsonEncode(responses[2]).contains(taskId)) {
    throw StateError(
      'Direct JSON-RPC batch error smoke lost success response.',
    );
  }
  if (responses[3]['id'] != '$label-direct-batch-error-tools-alias' ||
      !jsonEncode(responses[3]).contains(aliasTaskId)) {
    throw StateError('Direct JSON-RPC batch error smoke lost alias response.');
  }
  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON-RPC batch errors changed Streamable state.');
  }
}

Future<void> _smokeStreamableErrorRecovery(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP error smoke has no initialized session id.',
    );
  }

  var previousEventId = client.lastEventId;
  final missingTool = 'missing.$label.streamable.single';
  final errorId = '$label-streamable-error-missing';
  try {
    await client.callTool(missingTool, id: errorId, arguments: {});
    throw StateError('Streamable MCP accepted missing tool $missingTool.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: errorId,
      method: 'tools/call',
      messageSubstring: missingTool,
      label: 'Streamable MCP missing tool',
    );
  }
  previousEventId = _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP missing tool',
  );

  final recoveryTools = await client.listTools(
    id: '$label-streamable-error-recovery-tools',
  );
  final recoveryToolNames = {
    for (final tool in recoveryTools.tools) tool['name'] as String,
  };
  if (!recoveryToolNames.contains('example.task.lookup')) {
    throw StateError('Streamable MCP tool error recovery missed catalog.');
  }
  previousEventId = _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP tool recovery',
  );

  final missingResourceUri = 'app://example/missing/$label/streamable';
  final resourceErrorId = '$label-streamable-resource-error';
  try {
    await client.readResource(missingResourceUri, id: resourceErrorId);
    throw StateError('Streamable MCP accepted missing resource.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: resourceErrorId,
      method: 'resources/read',
      messageSubstring: missingResourceUri,
      label: 'Streamable MCP missing resource',
    );
  }
  previousEventId = _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP missing resource',
  );

  final missingPromptName = 'missing-$label-streamable-prompt';
  final promptErrorId = '$label-streamable-prompt-error';
  try {
    await client.getPrompt(missingPromptName, id: promptErrorId, arguments: {});
    throw StateError('Streamable MCP accepted missing prompt.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: promptErrorId,
      method: 'prompts/get',
      messageSubstring: missingPromptName,
      label: 'Streamable MCP missing prompt',
    );
  }
  previousEventId = _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP missing prompt',
  );

  await _smokeStreamableBatchErrorIsolation(
    client,
    label: label,
    previousEventId: previousEventId,
  );
  previousEventId = client.lastEventId;

  final recoveryResources = await client.listResources(
    id: '$label-streamable-resource-error-recovery',
  );
  if (!recoveryResources.resources.any(
    (resource) => resource['uri'] == 'app://example/context',
  )) {
    throw StateError('Streamable MCP resource error recovery missed context.');
  }
  previousEventId = _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP resource recovery',
  );

  final recoveryPrompts = await client.listPrompts(
    id: '$label-streamable-prompt-error-recovery',
  );
  if (!recoveryPrompts.prompts.any(
    (prompt) => prompt['name'] == 'summarize-task',
  )) {
    throw StateError('Streamable MCP prompt error recovery missed prompt.');
  }
  _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP prompt recovery',
  );
}

Future<void> _smokeStreamableBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
  required String? previousEventId,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP batch error smoke has no initialized session id.',
    );
  }

  final missingTool = 'missing.$label.streamable.batch';
  final promptTaskId = 'T-$label-streamable-batch-error-prompt';
  final responses = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-tools',
      'method': 'tools/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-missing',
      'method': 'tools/call',
      'params': {'name': missingTool, 'arguments': {}},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-prompt',
      'method': 'prompts/get',
      'params': {
        'name': 'summarize-task',
        'arguments': {'taskId': promptTaskId},
      },
    },
    {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
  ]);
  if (responses == null || responses.length != 3) {
    throw StateError('Streamable MCP batch error smoke returned invalid size.');
  }
  if (responses[0]['id'] != '$label-streamable-batch-error-tools' ||
      !jsonEncode(responses[0]).contains('example.task.lookup')) {
    throw StateError('Streamable MCP batch error smoke lost tools response.');
  }
  _expectJsonRpcError(
    responses[1],
    id: '$label-streamable-batch-error-missing',
    messageSubstring: missingTool,
    label: 'Streamable MCP batch missing tool',
  );
  if (responses[2]['id'] != '$label-streamable-batch-error-prompt' ||
      !jsonEncode(responses[2]).contains(promptTaskId)) {
    throw StateError('Streamable MCP batch error smoke lost prompt response.');
  }
  _expectStreamableEventProgress(
    client,
    sessionId: sessionId,
    previousEventId: previousEventId,
    label: 'Streamable MCP batch error smoke',
  );
}

String _expectStreamableEventProgress(
  McpStreamableHttpClient client, {
  required String sessionId,
  required String? previousEventId,
  required String label,
}) {
  if (client.sessionId != sessionId) {
    throw StateError('$label changed Streamable session id.');
  }
  final eventId = client.lastEventId;
  if (eventId == null ||
      !eventId.startsWith('$sessionId:') ||
      eventId == previousEventId) {
    throw StateError('$label did not advance Streamable SSE state.');
  }
  return eventId;
}

void _expectJsonRpcError(
  Map<String, Object?> response, {
  required Object id,
  required String messageSubstring,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  final error = response['error'];
  if (error is! Map) {
    throw StateError('$label did not return a JSON-RPC error.');
  }
  final encodedError = jsonEncode(error);
  if (!encodedError.contains(messageSubstring)) {
    throw StateError('$label error message was invalid: ${jsonEncode(error)}');
  }
}

void _expectMcpJsonRpcException(
  McpJsonRpcException error, {
  required Object id,
  required String method,
  required String messageSubstring,
  required String label,
}) {
  if (error.id != id) {
    throw StateError('$label exception id was invalid.');
  }
  if (error.method != method) {
    throw StateError('$label exception method was ${error.method}.');
  }
  final encodedError = jsonEncode(error.error);
  if (!encodedError.contains(messageSubstring)) {
    throw StateError(
      '$label exception message was invalid: ${jsonEncode(error.error)}',
    );
  }
}

Future<void> _smokeDirectJsonBatchWampMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final sessionCountId = '$label-direct-batch-wamp-session-count';
  final sessionListId = '$label-direct-batch-wamp-session-list';
  final registrationLookupId = '$label-direct-batch-wamp-registration-lookup';
  final registrationMatchId = '$label-direct-batch-wamp-registration-match';
  final registrationListId = '$label-direct-batch-wamp-registration-list';
  final discovery = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': sessionCountId,
        'method': 'wamp.session.count',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': sessionListId,
        'method': 'wamp.session.list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationLookupId,
        'method': 'wamp.registration.lookup',
        'params': {'uri': 'example.task.lookup'},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationMatchId,
        'method': 'wamp.registration.match',
        'params': {'uri': 'example.task.lookup'},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationListId,
        'method': 'wamp.registration.list',
        'params': {},
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (discovery == null) {
    throw StateError(
      'Direct JSON-RPC batch WAMP meta discovery returned null.',
    );
  }
  final ids = _expectWampRegistrationSessionBatchDiscovery(
    discovery,
    sessionCountId: sessionCountId,
    sessionListId: sessionListId,
    registrationLookupId: registrationLookupId,
    registrationMatchId: registrationMatchId,
    registrationListId: registrationListId,
    serviceSession: serviceSession,
    modeLabel: 'Direct JSON-RPC batch WAMP meta',
  );

  final visibleSessionId = ids[0];
  final registrationId = ids[1];
  final sessionGetId = '$label-direct-batch-wamp-session-get';
  final registrationGetId = '$label-direct-batch-wamp-registration-get';
  final registrationCalleesId = '$label-direct-batch-wamp-registration-callees';
  final registrationCalleeCountId =
      '$label-direct-batch-wamp-registration-callee-count';
  final details = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': sessionGetId,
        'method': 'wamp.session.get',
        'params': {'id': visibleSessionId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationGetId,
        'method': 'wamp.registration.get',
        'params': {'id': registrationId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationCalleesId,
        'method': 'wamp.registration.list_callees',
        'params': {'id': registrationId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationCalleeCountId,
        'method': 'wamp.registration.count_callees',
        'params': {'id': registrationId},
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (details == null) {
    throw StateError('Direct JSON-RPC batch WAMP meta details returned null.');
  }
  _expectWampRegistrationSessionBatchDetails(
    details,
    sessionGetId: sessionGetId,
    registrationGetId: registrationGetId,
    registrationCalleesId: registrationCalleesId,
    registrationCalleeCountId: registrationCalleeCountId,
    visibleSessionId: visibleSessionId,
    serviceSession: serviceSession,
    modeLabel: 'Direct JSON-RPC batch WAMP meta',
  );

  final topicListId = '$label-direct-batch-wamp-topic-list';
  final topicDescribeId = '$label-direct-batch-wamp-topic-describe';
  final topics = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': topicListId,
        'method': 'connectanum.api.list',
        'params': {'kind': 'topic'},
      },
      {
        'jsonrpc': '2.0',
        'id': topicDescribeId,
        'method': 'connectanum.api.describe',
        'params': {'uri': 'example.events.task', 'kind': 'topic'},
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (topics == null) {
    throw StateError('Direct JSON-RPC batch WAMP topic meta returned null.');
  }
  _expectWampTopicBatchMetadata(
    topics,
    topicListId: topicListId,
    topicDescribeId: topicDescribeId,
    topicUri: 'example.events.task',
    topicDescription: 'Task lifecycle event stream',
    modeLabel: 'Direct JSON-RPC batch WAMP topic meta',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Direct JSON-RPC batch WAMP meta changed Streamable state.',
    );
  }
}

Future<void> _smokeStreamableBatchWampMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP batch WAMP meta has no session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch WAMP meta $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch WAMP meta $operation did not advance SSE state.',
      );
    }
    previousEventId = eventId;
  }

  final sessionCountId = '$label-streamable-batch-wamp-session-count';
  final sessionListId = '$label-streamable-batch-wamp-session-list';
  final registrationLookupId =
      '$label-streamable-batch-wamp-registration-lookup';
  final registrationMatchId = '$label-streamable-batch-wamp-registration-match';
  final registrationListId = '$label-streamable-batch-wamp-registration-list';
  final discovery = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': sessionCountId,
      'method': 'tools/call',
      'params': {'name': 'wamp.session.count', 'arguments': {}},
    },
    {
      'jsonrpc': '2.0',
      'id': sessionListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.session.list', 'arguments': {}},
    },
    {
      'jsonrpc': '2.0',
      'id': registrationLookupId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.lookup',
        'arguments': {
          'arguments': ['example.task.lookup'],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationMatchId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.match',
        'arguments': {
          'arguments': ['example.task.lookup'],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.registration.list', 'arguments': {}},
    },
  ]);
  if (discovery == null) {
    throw StateError('Streamable MCP batch WAMP meta discovery returned null.');
  }
  final ids = _expectWampRegistrationSessionBatchDiscovery(
    discovery,
    sessionCountId: sessionCountId,
    sessionListId: sessionListId,
    registrationLookupId: registrationLookupId,
    registrationMatchId: registrationMatchId,
    registrationListId: registrationListId,
    serviceSession: serviceSession,
    modeLabel: 'Streamable MCP batch WAMP meta',
  );
  expectStreamableProgress('discovery batch');

  final visibleSessionId = ids[0];
  final registrationId = ids[1];
  final sessionGetId = '$label-streamable-batch-wamp-session-get';
  final registrationGetId = '$label-streamable-batch-wamp-registration-get';
  final registrationCalleesId =
      '$label-streamable-batch-wamp-registration-callees';
  final registrationCalleeCountId =
      '$label-streamable-batch-wamp-registration-callee-count';
  final details = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': sessionGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.session.get',
        'arguments': {
          'arguments': [visibleSessionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.get',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationCalleesId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.list_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationCalleeCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.count_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
  ]);
  if (details == null) {
    throw StateError('Streamable MCP batch WAMP meta details returned null.');
  }
  _expectWampRegistrationSessionBatchDetails(
    details,
    sessionGetId: sessionGetId,
    registrationGetId: registrationGetId,
    registrationCalleesId: registrationCalleesId,
    registrationCalleeCountId: registrationCalleeCountId,
    visibleSessionId: visibleSessionId,
    serviceSession: serviceSession,
    modeLabel: 'Streamable MCP batch WAMP meta',
  );
  expectStreamableProgress('details batch');

  final topicListId = '$label-streamable-batch-wamp-topic-list';
  final topicDescribeId = '$label-streamable-batch-wamp-topic-describe';
  final topics = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': topicListId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.list',
        'arguments': {'kind': 'topic'},
      },
    },
    {
      'jsonrpc': '2.0',
      'id': topicDescribeId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.describe',
        'arguments': {'uri': 'example.events.task', 'kind': 'topic'},
      },
    },
  ]);
  if (topics == null) {
    throw StateError('Streamable MCP batch WAMP topic meta returned null.');
  }
  _expectWampTopicBatchMetadata(
    topics,
    topicListId: topicListId,
    topicDescribeId: topicDescribeId,
    topicUri: 'example.events.task',
    topicDescription: 'Task lifecycle event stream',
    modeLabel: 'Streamable MCP batch WAMP topic meta',
  );
  expectStreamableProgress('topic metadata batch');
}

List<int> _expectWampRegistrationSessionBatchDiscovery(
  List<McpJsonMap> responses, {
  required String sessionCountId,
  required String sessionListId,
  required String registrationLookupId,
  required String registrationMatchId,
  required String registrationListId,
  required RouterSession serviceSession,
  required String modeLabel,
}) {
  if (responses.length != 5) {
    throw StateError('$modeLabel discovery returned ${responses.length}.');
  }

  final sessionCountContent = _structuredContentFromBatchResponse(
    responses[0],
    id: sessionCountId,
    label: '$modeLabel session count',
  );
  final sessionCountKeywords = _jsonObjectFrom(
    sessionCountContent['argumentsKeywords'],
    label: '$modeLabel session count kwargs',
  );
  final visibleSessionCount = sessionCountKeywords['count'];
  if (visibleSessionCount is! int) {
    throw StateError('$modeLabel session count missed count metadata.');
  }

  final sessionListContent = _structuredContentFromBatchResponse(
    responses[1],
    id: sessionListId,
    label: '$modeLabel session list',
  );
  final sessionListKeywords = _jsonObjectFrom(
    sessionListContent['argumentsKeywords'],
    label: '$modeLabel session list kwargs',
  );
  final sessionIds = _integerMetaIdsFromValue(
    sessionListKeywords['session_ids'],
    '$modeLabel session list',
  );
  if (sessionIds.contains(serviceSession.sessionId)) {
    throw StateError('$modeLabel session list leaked service session.');
  }
  if (sessionIds.length != visibleSessionCount) {
    throw StateError('$modeLabel session count did not match list.');
  }
  if (sessionIds.isEmpty) {
    throw StateError('$modeLabel session list missed visible sessions.');
  }

  final registrationLookupContent = _structuredContentFromBatchResponse(
    responses[2],
    id: registrationLookupId,
    label: '$modeLabel registration lookup',
  );
  final registrationLookupArguments = registrationLookupContent['arguments'];
  if (registrationLookupArguments is! List) {
    throw StateError('$modeLabel registration lookup missed arguments.');
  }
  final registrationId = _singleMetaId(
    registrationLookupArguments.cast<Object?>(),
    '$modeLabel registration lookup',
  );
  if (registrationId <= 0) {
    throw StateError(
      '$modeLabel registration lookup returned invalid id $registrationId.',
    );
  }

  final registrationMatchContent = _structuredContentFromBatchResponse(
    responses[3],
    id: registrationMatchId,
    label: '$modeLabel registration match',
  );
  final registrationMatchArguments = registrationMatchContent['arguments'];
  if (registrationMatchArguments is! List) {
    throw StateError('$modeLabel registration match missed arguments.');
  }
  final matchingRegistrationId = _singleMetaId(
    registrationMatchArguments.cast<Object?>(),
    '$modeLabel registration match',
  );
  if (matchingRegistrationId != registrationId) {
    throw StateError('$modeLabel registration match disagreed with lookup.');
  }

  final registrationListContent = _structuredContentFromBatchResponse(
    responses[4],
    id: registrationListId,
    label: '$modeLabel registration list',
  );
  final registrationListKeywords = _jsonObjectFrom(
    registrationListContent['argumentsKeywords'],
    label: '$modeLabel registration list kwargs',
  );
  final exactRegistrationIds = _integerMetaIdsFromValue(
    registrationListKeywords['exact'],
    '$modeLabel registration list exact',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError(
      '$modeLabel registration list missed example.task.lookup.',
    );
  }

  return [sessionIds.first, registrationId];
}

void _expectWampRegistrationSessionBatchDetails(
  List<McpJsonMap> responses, {
  required String sessionGetId,
  required String registrationGetId,
  required String registrationCalleesId,
  required String registrationCalleeCountId,
  required int visibleSessionId,
  required RouterSession serviceSession,
  required String modeLabel,
}) {
  if (responses.length != 4) {
    throw StateError('$modeLabel details returned ${responses.length}.');
  }

  final sessionGetContent = _structuredContentFromBatchResponse(
    responses[0],
    id: sessionGetId,
    label: '$modeLabel session get',
  );
  final sessionGetKeywords = _jsonObjectFrom(
    sessionGetContent['argumentsKeywords'],
    label: '$modeLabel session get kwargs',
  );
  final sessionDetails = _jsonObjectFrom(
    sessionGetKeywords['details'],
    label: '$modeLabel session details',
  );
  if (sessionDetails['id'] != visibleSessionId) {
    throw StateError('$modeLabel session get missed visible session.');
  }

  final registrationGetContent = _structuredContentFromBatchResponse(
    responses[1],
    id: registrationGetId,
    label: '$modeLabel registration get',
  );
  final registrationGetKeywords = _jsonObjectFrom(
    registrationGetContent['argumentsKeywords'],
    label: '$modeLabel registration get kwargs',
  );
  if (registrationGetKeywords['uri'] != 'example.task.lookup') {
    throw StateError('$modeLabel registration get missed example.task.lookup.');
  }

  final registrationCalleesContent = _structuredContentFromBatchResponse(
    responses[2],
    id: registrationCalleesId,
    label: '$modeLabel registration callees',
  );
  final registrationCalleeArguments = registrationCalleesContent['arguments'];
  if (registrationCalleeArguments is! List) {
    throw StateError('$modeLabel registration callees missed arguments.');
  }
  final calleeIds = _integerMetaIds(
    registrationCalleeArguments.cast<Object?>(),
    '$modeLabel registration callees',
  );
  if (calleeIds.contains(serviceSession.sessionId) || calleeIds.isNotEmpty) {
    throw StateError('$modeLabel registration callees leaked sessions.');
  }

  final registrationCalleeCountContent = _structuredContentFromBatchResponse(
    responses[3],
    id: registrationCalleeCountId,
    label: '$modeLabel registration callee count',
  );
  final registrationCalleeCountArguments =
      registrationCalleeCountContent['arguments'];
  if (registrationCalleeCountArguments is! List) {
    throw StateError('$modeLabel registration callee count missed arguments.');
  }
  final calleeCount = _singleMetaId(
    registrationCalleeCountArguments.cast<Object?>(),
    '$modeLabel registration callee count',
  );
  if (calleeCount != 0) {
    throw StateError('$modeLabel registration callee count leaked sessions.');
  }
}

void _expectWampTopicBatchMetadata(
  List<McpJsonMap> responses, {
  required String topicListId,
  required String topicDescribeId,
  required String topicUri,
  required String topicDescription,
  required String modeLabel,
}) {
  if (responses.length != 2) {
    throw StateError('$modeLabel returned ${responses.length}.');
  }

  final topicListContent = _structuredContentFromBatchResponse(
    responses[0],
    id: topicListId,
    label: '$modeLabel topic list',
  );
  final topicListJson = jsonEncode(topicListContent);
  if (!topicListJson.contains(topicUri) ||
      !topicListJson.contains(topicDescription)) {
    throw StateError('$modeLabel topic list missed $topicUri metadata.');
  }

  final topicDescribeContent = _structuredContentFromBatchResponse(
    responses[1],
    id: topicDescribeId,
    label: '$modeLabel topic describe',
  );
  final topicDescribeJson = jsonEncode(topicDescribeContent);
  if (!topicDescribeJson.contains(topicUri) ||
      !topicDescribeJson.contains('eventSchema') ||
      !topicDescribeJson.contains('allowPublish') ||
      !topicDescribeJson.contains('allowSubscribe')) {
    throw StateError('$modeLabel topic describe missed $topicUri metadata.');
  }
}

Future<void> _smokeDirectJsonBatchWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  required String topic,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final subscriptionLookupId = '$label-direct-batch-wamp-subscription-lookup';
  final subscriptionMatchId = '$label-direct-batch-wamp-subscription-match';
  final subscriptionListId = '$label-direct-batch-wamp-subscription-list';
  final discovery = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': subscriptionLookupId,
        'method': 'wamp.subscription.lookup',
        'params': {'topic': topic},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriptionMatchId,
        'method': 'wamp.subscription.match',
        'params': {'topic': topic},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriptionListId,
        'method': 'wamp.subscription.list',
        'params': {},
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (discovery == null) {
    throw StateError(
      'Direct JSON-RPC batch WAMP subscription meta discovery returned null.',
    );
  }
  final subscriptionId = _expectWampSubscriptionBatchDiscovery(
    discovery,
    subscriptionLookupId: subscriptionLookupId,
    subscriptionMatchId: subscriptionMatchId,
    subscriptionListId: subscriptionListId,
    topic: topic,
    modeLabel: 'Direct JSON-RPC batch WAMP subscription meta',
  );

  final subscriptionGetId = '$label-direct-batch-wamp-subscription-get';
  final subscribersId = '$label-direct-batch-wamp-subscription-subscribers';
  final subscriberCountId =
      '$label-direct-batch-wamp-subscription-subscriber-count';
  final details = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': subscriptionGetId,
        'method': 'wamp.subscription.get',
        'params': {'id': subscriptionId},
      },
      {
        'jsonrpc': '2.0',
        'id': subscribersId,
        'method': 'wamp.subscription.list_subscribers',
        'params': {'id': subscriptionId},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriberCountId,
        'method': 'wamp.subscription.count_subscribers',
        'params': {'id': subscriptionId},
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (details == null) {
    throw StateError(
      'Direct JSON-RPC batch WAMP subscription meta details returned null.',
    );
  }
  _expectWampSubscriptionBatchDetails(
    details,
    subscriptionGetId: subscriptionGetId,
    subscribersId: subscribersId,
    subscriberCountId: subscriberCountId,
    serviceSession: serviceSession,
    topic: topic,
    modeLabel: 'Direct JSON-RPC batch WAMP subscription meta',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Direct JSON-RPC batch WAMP subscription meta changed Streamable state.',
    );
  }
}

Future<void> _smokeStreamableBatchWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  required String topic,
  required void Function(String operation) expectProgress,
}) async {
  final subscriptionLookupId =
      '$label-streamable-batch-wamp-subscription-lookup';
  final subscriptionMatchId = '$label-streamable-batch-wamp-subscription-match';
  final subscriptionListId = '$label-streamable-batch-wamp-subscription-list';
  final discovery = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': subscriptionLookupId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.lookup',
        'arguments': {
          'arguments': [topic],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriptionMatchId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.match',
        'arguments': {
          'arguments': [topic],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriptionListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.subscription.list', 'arguments': {}},
    },
  ]);
  if (discovery == null) {
    throw StateError(
      'Streamable MCP batch WAMP subscription meta discovery returned null.',
    );
  }
  final subscriptionId = _expectWampSubscriptionBatchDiscovery(
    discovery,
    subscriptionLookupId: subscriptionLookupId,
    subscriptionMatchId: subscriptionMatchId,
    subscriptionListId: subscriptionListId,
    topic: topic,
    modeLabel: 'Streamable MCP batch WAMP subscription meta',
  );
  expectProgress('subscription meta discovery batch');

  final subscriptionGetId = '$label-streamable-batch-wamp-subscription-get';
  final subscribersId = '$label-streamable-batch-wamp-subscription-subscribers';
  final subscriberCountId =
      '$label-streamable-batch-wamp-subscription-subscriber-count';
  final details = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': subscriptionGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.get',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscribersId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.list_subscribers',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriberCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.count_subscribers',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
  ]);
  if (details == null) {
    throw StateError(
      'Streamable MCP batch WAMP subscription meta details returned null.',
    );
  }
  _expectWampSubscriptionBatchDetails(
    details,
    subscriptionGetId: subscriptionGetId,
    subscribersId: subscribersId,
    subscriberCountId: subscriberCountId,
    serviceSession: serviceSession,
    topic: topic,
    modeLabel: 'Streamable MCP batch WAMP subscription meta',
  );
  expectProgress('subscription meta details batch');
}

int _expectWampSubscriptionBatchDiscovery(
  List<McpJsonMap> responses, {
  required String subscriptionLookupId,
  required String subscriptionMatchId,
  required String subscriptionListId,
  required String topic,
  required String modeLabel,
}) {
  if (responses.length != 3) {
    throw StateError('$modeLabel discovery returned ${responses.length}.');
  }

  final subscriptionLookupContent = _structuredContentFromBatchResponse(
    responses[0],
    id: subscriptionLookupId,
    label: '$modeLabel subscription lookup',
  );
  final subscriptionLookupArguments = subscriptionLookupContent['arguments'];
  if (subscriptionLookupArguments is! List) {
    throw StateError('$modeLabel subscription lookup missed arguments.');
  }
  final subscriptionId = _singleMetaId(
    subscriptionLookupArguments.cast<Object?>(),
    '$modeLabel subscription lookup',
  );
  if (subscriptionId <= 0) {
    throw StateError(
      '$modeLabel subscription lookup returned invalid id $subscriptionId.',
    );
  }

  final subscriptionMatchContent = _structuredContentFromBatchResponse(
    responses[1],
    id: subscriptionMatchId,
    label: '$modeLabel subscription match',
  );
  final subscriptionMatchArguments = subscriptionMatchContent['arguments'];
  if (subscriptionMatchArguments is! List) {
    throw StateError('$modeLabel subscription match missed arguments.');
  }
  final matchedSubscriptionIds = _integerMetaIds(
    subscriptionMatchArguments.cast<Object?>(),
    '$modeLabel subscription match',
  );
  if (!matchedSubscriptionIds.contains(subscriptionId)) {
    throw StateError('$modeLabel subscription match missed $topic.');
  }

  final subscriptionListContent = _structuredContentFromBatchResponse(
    responses[2],
    id: subscriptionListId,
    label: '$modeLabel subscription list',
  );
  final subscriptionListKeywords = _jsonObjectFrom(
    subscriptionListContent['argumentsKeywords'],
    label: '$modeLabel subscription list kwargs',
  );
  final exactSubscriptionIds = _integerMetaIdsFromValue(
    subscriptionListKeywords['exact'],
    '$modeLabel subscription list exact',
  );
  if (!exactSubscriptionIds.contains(subscriptionId)) {
    throw StateError('$modeLabel subscription list missed $topic.');
  }

  return subscriptionId;
}

void _expectWampSubscriptionBatchDetails(
  List<McpJsonMap> responses, {
  required String subscriptionGetId,
  required String subscribersId,
  required String subscriberCountId,
  required RouterSession serviceSession,
  required String topic,
  required String modeLabel,
}) {
  if (responses.length != 3) {
    throw StateError('$modeLabel details returned ${responses.length}.');
  }

  final subscriptionGetContent = _structuredContentFromBatchResponse(
    responses[0],
    id: subscriptionGetId,
    label: '$modeLabel subscription get',
  );
  final subscriptionGetKeywords = _jsonObjectFrom(
    subscriptionGetContent['argumentsKeywords'],
    label: '$modeLabel subscription get kwargs',
  );
  if (!jsonEncode(subscriptionGetKeywords).contains(topic)) {
    throw StateError('$modeLabel subscription get missed $topic.');
  }

  final subscribersContent = _structuredContentFromBatchResponse(
    responses[1],
    id: subscribersId,
    label: '$modeLabel subscription subscribers',
  );
  final subscriberArguments = subscribersContent['arguments'];
  if (subscriberArguments is! List) {
    throw StateError('$modeLabel subscription subscribers missed arguments.');
  }
  final subscriberIds = _integerMetaIds(
    subscriberArguments.cast<Object?>(),
    '$modeLabel subscription subscribers',
  );
  if (subscriberIds.isEmpty) {
    throw StateError('$modeLabel subscription subscribers was empty.');
  }
  if (subscriberIds.contains(serviceSession.sessionId)) {
    throw StateError('$modeLabel subscription subscribers leaked sessions.');
  }

  final subscriberCountContent = _structuredContentFromBatchResponse(
    responses[2],
    id: subscriberCountId,
    label: '$modeLabel subscription subscriber count',
  );
  final subscriberCountArguments = subscriberCountContent['arguments'];
  if (subscriberCountArguments is! List) {
    throw StateError(
      '$modeLabel subscription subscriber count missed arguments.',
    );
  }
  final subscriberTotal = _singleMetaId(
    subscriberCountArguments.cast<Object?>(),
    '$modeLabel subscription subscriber count',
  );
  if (subscriberTotal != subscriberIds.length) {
    throw StateError(
      '$modeLabel subscription subscriber count did not match visible sessions.',
    );
  }
}

McpJsonMap _jsonObjectFrom(Object? value, {required String label}) {
  if (value is! Map) {
    throw StateError('$label returned ${jsonEncode(value)}.');
  }
  return Map<String, Object?>.from(value);
}

int _singleMetaId(List<Object?> arguments, String label) {
  if (arguments.length != 1 || arguments.single is! int) {
    throw StateError('$label returned ${jsonEncode(arguments)}.');
  }
  return arguments.single as int;
}

List<int> _integerMetaIds(List<Object?> arguments, String label) {
  final ids = <int>[];
  for (final value in arguments) {
    if (value is! int) {
      throw StateError('$label returned ${jsonEncode(arguments)}.');
    }
    ids.add(value);
  }
  return ids;
}

List<int> _integerMetaIdsFromValue(Object? value, String label) {
  if (value is! List) {
    throw StateError('$label returned ${jsonEncode(value)}.');
  }
  return _integerMetaIds(value.cast<Object?>(), label);
}

Future<void> _smokeDirectJsonBatchPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  String? handle;

  try {
    final subscribeId = '$label-direct-batch-pubsub-subscribe';
    final apiListId = '$label-direct-batch-pubsub-api-list';
    final subscribeBatch = await client.postBatch(
      [
        {
          'jsonrpc': '2.0',
          'id': subscribeId,
          'method': 'connectanum.pubsub.subscribe',
          'params': {'topic': 'example.events.task', 'queueLimit': 4},
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'procedure'},
        },
      ],
      streamable: false,
      includeSession: false,
    );
    if (subscribeBatch == null || subscribeBatch.length != 2) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub subscribe did not return two responses.',
      );
    }
    final subscription = _structuredContentFromBatchResponse(
      subscribeBatch[0],
      id: subscribeId,
      label: 'Direct JSON-RPC batch pub/sub subscribe',
    );
    final handleValue = subscription['handle'];
    if (handleValue is! String ||
        handleValue.isEmpty ||
        subscription['topic'] != 'example.events.task' ||
        subscription['queueLimit'] != 4) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub subscribe response was invalid.',
      );
    }
    handle = handleValue;
    if (subscribeBatch[1]['id'] != apiListId ||
        !jsonEncode(subscribeBatch[1]).contains('example.task.lookup')) {
      throw StateError('Direct JSON-RPC batch pub/sub API list was invalid.');
    }
    await _smokeDirectJsonBatchWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
      topic: 'example.events.task',
    );

    final publishId = '$label-direct-batch-pubsub-publish';
    final apiDescribeId = '$label-direct-batch-pubsub-api-describe';
    final publishBatch = await client.postBatch(
      [
        {
          'jsonrpc': '2.0',
          'id': publishId,
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': 'example.events.task',
            'argumentsKeywords': {
              'taskId': 'T-$label-direct-batch-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
        {
          'jsonrpc': '2.0',
          'id': apiDescribeId,
          'method': 'connectanum.api.describe',
          'params': {'uri': 'example.task.lookup', 'kind': 'procedure'},
        },
      ],
      streamable: false,
      includeSession: false,
    );
    if (publishBatch == null || publishBatch.length != 2) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub publish did not return two responses.',
      );
    }
    final publication = _structuredContentFromBatchResponse(
      publishBatch[0],
      id: publishId,
      label: 'Direct JSON-RPC batch pub/sub publish',
    );
    if (publication['topic'] != 'example.events.task' ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub publish response was invalid.',
      );
    }
    if (publishBatch[1]['id'] != apiDescribeId ||
        !jsonEncode(publishBatch[1]).contains('example.task.lookup')) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub API describe was invalid.',
      );
    }

    final serviceTaskId = 'T-$label-direct-batch-pubsub-service';
    await serviceSession.publish(
      'example.events.task',
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _pollDirectJsonBatchPubSubUntil(
      client,
      handle,
      label: label,
      expectedTaskId: serviceTaskId,
    );
  } finally {
    if (handle != null) {
      final unsubscribeId = '$label-direct-batch-pubsub-unsubscribe';
      final apiListId = '$label-direct-batch-pubsub-unsubscribe-api-list';
      final unsubscribeBatch = await client.postBatch(
        [
          {
            'jsonrpc': '2.0',
            'id': unsubscribeId,
            'method': 'connectanum.pubsub.unsubscribe',
            'params': {'handle': handle},
          },
          {
            'jsonrpc': '2.0',
            'id': apiListId,
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
        ],
        streamable: false,
        includeSession: false,
      );
      if (unsubscribeBatch == null || unsubscribeBatch.length != 2) {
        throw StateError(
          'Direct JSON-RPC batch pub/sub unsubscribe did not return two '
          'responses.',
        );
      }
      final unsubscribe = _structuredContentFromBatchResponse(
        unsubscribeBatch[0],
        id: unsubscribeId,
        label: 'Direct JSON-RPC batch pub/sub unsubscribe',
      );
      if (unsubscribe['handle'] != handle ||
          unsubscribe['topic'] != 'example.events.task' ||
          unsubscribe['unsubscribed'] != true) {
        throw StateError(
          'Direct JSON-RPC batch pub/sub unsubscribe response was invalid.',
        );
      }
      if (unsubscribeBatch[1]['id'] != apiListId ||
          !jsonEncode(unsubscribeBatch[1]).contains('example.task.lookup')) {
        throw StateError(
          'Direct JSON-RPC batch pub/sub unsubscribe API list was invalid.',
        );
      }
    }
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON-RPC batch pub/sub changed Streamable state.');
  }
}

Future<void> _pollDirectJsonBatchPubSubUntil(
  McpStreamableHttpClient client,
  String handle, {
  required String label,
  required String expectedTaskId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final pollId = '$label-direct-batch-pubsub-poll-$timestamp';
    final apiListId = '$label-direct-batch-pubsub-poll-api-$timestamp';
    final pollBatch = await client.postBatch(
      [
        {
          'jsonrpc': '2.0',
          'id': pollId,
          'method': 'connectanum.pubsub.poll',
          'params': {'handle': handle, 'limit': 4},
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'procedure'},
        },
      ],
      streamable: false,
      includeSession: false,
    );
    if (pollBatch == null || pollBatch.length != 2) {
      throw StateError(
        'Direct JSON-RPC batch pub/sub poll did not return two responses.',
      );
    }
    final eventBatch = _structuredContentFromBatchResponse(
      pollBatch[0],
      id: pollId,
      label: 'Direct JSON-RPC batch pub/sub poll',
    );
    if (eventBatch['handle'] != handle ||
        eventBatch['topic'] != 'example.events.task') {
      throw StateError('Direct JSON-RPC batch pub/sub poll was invalid.');
    }
    if (pollBatch[1]['id'] != apiListId ||
        !jsonEncode(pollBatch[1]).contains('example.task.lookup')) {
      throw StateError('Direct JSON-RPC batch pub/sub poll API list invalid.');
    }
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for direct JSON-RPC batch pub/sub.');
}

Future<void> _smokeStreamableBatchPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP batch pub/sub has no session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch pub/sub $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch pub/sub $operation did not advance SSE state.',
      );
    }
    previousEventId = eventId;
  }

  String? handle;
  try {
    final subscribeId = '$label-streamable-batch-pubsub-subscribe';
    final apiListId = '$label-streamable-batch-pubsub-api-list';
    final subscribeBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': subscribeId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'example.events.task', 'queueLimit': 4},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': apiListId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.list',
          'arguments': {'kind': 'procedure'},
        },
      },
    ]);
    if (subscribeBatch == null || subscribeBatch.length != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub subscribe did not return two responses.',
      );
    }
    final subscription = _structuredContentFromBatchResponse(
      subscribeBatch[0],
      id: subscribeId,
      label: 'Streamable MCP batch pub/sub subscribe',
    );
    final handleValue = subscription['handle'];
    if (handleValue is! String ||
        handleValue.isEmpty ||
        subscription['topic'] != 'example.events.task' ||
        subscription['queueLimit'] != 4) {
      throw StateError(
        'Streamable MCP batch pub/sub subscribe response was invalid.',
      );
    }
    handle = handleValue;
    if (subscribeBatch[1]['id'] != apiListId ||
        !jsonEncode(subscribeBatch[1]).contains('example.task.lookup')) {
      throw StateError('Streamable MCP batch pub/sub API list was invalid.');
    }
    expectStreamableProgress('subscribe batch');
    await _smokeStreamableBatchWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
      topic: 'example.events.task',
      expectProgress: expectStreamableProgress,
    );

    final publishId = '$label-streamable-batch-pubsub-publish';
    final apiDescribeId = '$label-streamable-batch-pubsub-api-describe';
    final publishBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': publishId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': 'example.events.task',
            'argumentsKeywords': {
              'taskId': 'T-$label-streamable-batch-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': apiDescribeId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.describe',
          'arguments': {'uri': 'example.task.lookup', 'kind': 'procedure'},
        },
      },
    ]);
    if (publishBatch == null || publishBatch.length != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub publish did not return two responses.',
      );
    }
    final publication = _structuredContentFromBatchResponse(
      publishBatch[0],
      id: publishId,
      label: 'Streamable MCP batch pub/sub publish',
    );
    if (publication['topic'] != 'example.events.task' ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Streamable MCP batch pub/sub publish response was invalid.',
      );
    }
    if (publishBatch[1]['id'] != apiDescribeId ||
        !jsonEncode(publishBatch[1]).contains('example.task.lookup')) {
      throw StateError('Streamable MCP batch pub/sub API describe invalid.');
    }
    expectStreamableProgress('publish batch');

    final serviceTaskId = 'T-$label-streamable-batch-pubsub-service';
    await serviceSession.publish(
      'example.events.task',
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _pollStreamableBatchPubSubUntil(
      client,
      handle,
      label: label,
      expectedTaskId: serviceTaskId,
      expectProgress: expectStreamableProgress,
    );
  } finally {
    if (handle != null) {
      final unsubscribeId = '$label-streamable-batch-pubsub-unsubscribe';
      final apiListId = '$label-streamable-batch-pubsub-unsubscribe-api-list';
      final unsubscribeBatch = await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': unsubscribeId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.unsubscribe',
            'arguments': {'handle': handle},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'procedure'},
          },
        },
      ]);
      if (unsubscribeBatch == null || unsubscribeBatch.length != 2) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe did not return two '
          'responses.',
        );
      }
      final unsubscribe = _structuredContentFromBatchResponse(
        unsubscribeBatch[0],
        id: unsubscribeId,
        label: 'Streamable MCP batch pub/sub unsubscribe',
      );
      if (unsubscribe['handle'] != handle ||
          unsubscribe['topic'] != 'example.events.task' ||
          unsubscribe['unsubscribed'] != true) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe response was invalid.',
        );
      }
      if (unsubscribeBatch[1]['id'] != apiListId ||
          !jsonEncode(unsubscribeBatch[1]).contains('example.task.lookup')) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe API list was invalid.',
        );
      }
      expectStreamableProgress('unsubscribe batch');
    }
  }
}

Future<void> _pollStreamableBatchPubSubUntil(
  McpStreamableHttpClient client,
  String handle, {
  required String label,
  required String expectedTaskId,
  required void Function(String operation) expectProgress,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final pollId = '$label-streamable-batch-pubsub-poll-$timestamp';
    final apiListId = '$label-streamable-batch-pubsub-poll-api-$timestamp';
    final pollBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': pollId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': handle, 'limit': 4},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': apiListId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.list',
          'arguments': {'kind': 'procedure'},
        },
      },
    ]);
    if (pollBatch == null || pollBatch.length != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub poll did not return two responses.',
      );
    }
    final eventBatch = _structuredContentFromBatchResponse(
      pollBatch[0],
      id: pollId,
      label: 'Streamable MCP batch pub/sub poll',
    );
    if (eventBatch['handle'] != handle ||
        eventBatch['topic'] != 'example.events.task') {
      throw StateError('Streamable MCP batch pub/sub poll was invalid.');
    }
    if (pollBatch[1]['id'] != apiListId ||
        !jsonEncode(pollBatch[1]).contains('example.task.lookup')) {
      throw StateError('Streamable MCP batch pub/sub poll API list invalid.');
    }
    expectProgress('poll batch');
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for Streamable MCP batch pub/sub.');
}

McpJsonMap _structuredContentFromBatchResponse(
  McpJsonMap response, {
  required Object id,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  final result = response['result'];
  if (result is! Map) {
    throw StateError('$label response did not contain a result object.');
  }
  if (result['isError'] == true) {
    throw StateError('$label returned an MCP tool error.');
  }
  final structuredContent = result['structuredContent'];
  if (structuredContent is! Map) {
    throw StateError('$label response did not contain structured content.');
  }
  return Map<String, Object?>.from(structuredContent);
}

Future<McpStreamableWampEventBatch> _pollMcpEventsUntil(
  McpStreamableHttpClient client,
  String handle, {
  required String label,
  bool directJson = false,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final batch = await client.pollWampEvents(
      handle,
      id: '$label-poll-$attempt',
      directJson: directJson,
    );
    if (batch.events.isNotEmpty) {
      return batch;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Timed out waiting for $label MCP pub/sub events.');
}

Future<void> _smokeMcpPubSubQueueOverflow(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  required bool directJson,
}) async {
  final mode = directJson ? 'Direct JSON-RPC' : 'Streamable MCP';
  final suffix = directJson ? 'direct' : 'streamable';
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscription = await client.subscribeWampTopic(
    'example.events.task',
    id: '$label-$suffix-overflow-subscribe',
    queueLimit: 1,
    directJson: directJson,
  );
  try {
    final taskIds = [
      'T-$label-$suffix-overflow-first',
      'T-$label-$suffix-overflow-second',
      'T-$label-$suffix-overflow-third',
    ];
    for (final taskId in taskIds) {
      await serviceSession.publish(
        'example.events.task',
        argumentsKeywords: {'taskId': taskId},
        options: PublishOptions(acknowledge: true),
      );
    }

    final overflowEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      label: '$label $mode overflow',
      directJson: directJson,
    );
    final encodedEvents = jsonEncode(overflowEvents.events);
    if (overflowEvents.handle != subscription.handle ||
        overflowEvents.topic != 'example.events.task' ||
        overflowEvents.events.length != 1 ||
        overflowEvents.dropped < 2 ||
        overflowEvents.remaining != 0 ||
        !encodedEvents.contains(taskIds.last) ||
        encodedEvents.contains(taskIds.first) ||
        encodedEvents.contains(taskIds[1])) {
      throw StateError(
        '$mode pub/sub queue overflow did not retain only the newest event.',
      );
    }
  } finally {
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-$suffix-overflow-unsubscribe',
      directJson: directJson,
    );
  }

  if (directJson) {
    if (client.sessionId != previousSessionId ||
        client.lastEventId != previousEventId) {
      throw StateError(
        'Direct JSON-RPC pub/sub queue overflow changed Streamable state.',
      );
    }
  } else if (client.sessionId != previousSessionId ||
      client.lastEventId == previousEventId) {
    throw StateError(
      'Streamable MCP pub/sub queue overflow did not preserve session state '
      'and advance SSE state.',
    );
  }
}
