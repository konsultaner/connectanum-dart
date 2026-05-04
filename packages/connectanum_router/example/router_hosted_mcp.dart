// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:connectanum_router/connectanum_router.dart';

const String _realm = 'example.realm';
const String _authPath = '/auth';
const String _publicMcpPath = '/mcp';
const String _secureMcpPath = '/mcp/secure';
const String _ticketAuthId = 'mcp-user';
const String _ticketSecret = 'mcp-demo-ticket';

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
    await _smokeMcpEndpoint(publicMcpClient, label: 'public');

    await _assertSecureMcpRequiresBearer(binding);
    final bearerToken = await _issueTicketHttpToken(binding);
    secureMcpClient = McpStreamableHttpClient.withBearerToken(
      _mcpEndpoint(binding, secure: true),
      bearerToken,
    );
    await _smokeMcpEndpoint(secureMcpClient, label: 'secure');

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

Future<String> _issueTicketHttpToken(RouterBinding binding) async {
  final httpClient = HttpClient();
  try {
    final challenge = await _postJson(httpClient, _authEndpoint(binding), {
      'realm': _realm,
      'authmethod': 'ticket',
      'authid': _ticketAuthId,
    });
    if (challenge.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'HTTP auth challenge returned ${challenge.statusCode}: '
        '${challenge.body}',
      );
    }
    final challengeBody = _jsonMap(challenge.json, 'auth challenge');
    final state = challengeBody['state'];
    if (state is! String || state.isEmpty) {
      throw StateError('HTTP auth challenge did not return a state token.');
    }

    final authenticate = await TicketAuthentication(
      _ticketSecret,
    ).challenge(Extra());
    final success = await _postJson(httpClient, _authEndpoint(binding), {
      'state': state,
      'signature': authenticate.signature,
      'extra': authenticate.extra,
    });
    if (success.statusCode != HttpStatus.ok) {
      throw StateError(
        'HTTP auth token request returned ${success.statusCode}: '
        '${success.body}',
      );
    }
    final successBody = _jsonMap(success.json, 'auth success');
    final token = successBody['access_token'];
    if (token is! String || token.isEmpty) {
      throw StateError('HTTP auth success did not return an access token.');
    }
    return token;
  } finally {
    httpClient.close(force: true);
  }
}

Future<({String body, Object? json, int statusCode})> _postJson(
  HttpClient client,
  Uri uri,
  Map<String, Object?> payload,
) async {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  final bodyBytes = utf8.encode(jsonEncode(payload));
  request.contentLength = bodyBytes.length;
  request.add(bodyBytes);

  final response = await request.close();
  final body = await utf8.decodeStream(response);
  return (
    body: body,
    json: body.isEmpty ? null : jsonDecode(body),
    statusCode: response.statusCode,
  );
}

Map<String, Object?> _jsonMap(Object? value, String label) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw StateError('Expected $label response to be a JSON object.');
}

Future<void> _smokeMcpEndpoint(
  McpStreamableHttpClient client, {
  required String label,
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
}
