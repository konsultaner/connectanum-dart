// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:connectanum_router/connectanum_router.dart';

const String _realm = 'example.realm';

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
  final mcpClient = McpStreamableHttpClient(_mcpEndpoint(binding));

  try {
    await _registerExampleApi(serviceSession);
    await _smokeMcpEndpoint(mcpClient);

    final endpoint = _mcpEndpoint(binding);
    print('Router-hosted MCP endpoint is running at $endpoint');
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
    if (mcpClient.sessionId != null) {
      try {
        await mcpClient.deleteSession();
      } on Object {
        // The process is shutting down; connection teardown is best-effort.
      }
    }
    mcpClient.close(force: true);
    await serviceSession.close();
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
}

Uri _mcpEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: '/mcp',
  );
}

RouterSettings _buildSettings() {
  final realm = RealmSettingsBuilder(_realm)
    ..addAuthMethod('anonymous')
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
      const HttpListenerSettings(
        sessionProfile: 'public-http',
        routes: [
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/mcp'),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              options: {
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
              },
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

Future<void> _smokeMcpEndpoint(McpStreamableHttpClient client) async {
  final directTools = await client.listConnectanumToolsDirect(
    id: 'example-direct-tools',
  );
  final directToolNames = {
    for (final tool in directTools.tools) tool['name'] as String,
  };
  if (!directToolNames.contains('example.task.lookup')) {
    throw StateError('MCP tool catalog did not expose example.task.lookup.');
  }

  final directResult = await client.callConnectanumMethodDirect(
    'example.task.lookup',
    id: 'example-direct-call',
    params: const {'taskId': 'T-direct'},
  );
  print('Direct JSON-RPC result: ${jsonEncode(directResult)}');

  final directResources = await client.listResources(
    id: 'example-direct-resources',
    directJson: true,
  );
  if (!directResources.resources.any(
    (resource) => resource['uri'] == 'app://example/context',
  )) {
    throw StateError('Direct JSON-RPC resources/list did not expose context.');
  }

  final directResource = await client.readResource(
    'app://example/context',
    id: 'example-direct-resource-read',
    directJson: true,
  );
  if (!jsonEncode(directResource).contains('Router-hosted MCP example')) {
    throw StateError('Direct JSON-RPC resources/read did not return context.');
  }

  final directPrompt = await client.getPrompt(
    'summarize-task',
    id: 'example-direct-prompt',
    arguments: const {'taskId': 'T-direct'},
    directJson: true,
  );
  if (!jsonEncode(directPrompt).contains('T-direct')) {
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
    id: 'example-tools-call',
    arguments: const {'taskId': 'T-streamable'},
  );
  print('Streamable MCP tool result: ${jsonEncode(streamableResult)}');

  final streamableTemplates = await client.listResourceTemplates(
    id: 'example-template-list',
  );
  if (!streamableTemplates.resourceTemplates.any(
    (template) => template['uriTemplate'] == 'app://example/tasks/{taskId}',
  )) {
    throw StateError('Streamable MCP did not expose resource template.');
  }

  final streamablePrompt = await client.getPrompt(
    'summarize-task',
    id: 'example-prompt-get',
    arguments: const {'taskId': 'T-streamable'},
  );
  if (!jsonEncode(streamablePrompt).contains('T-streamable')) {
    throw StateError('Streamable MCP prompt did not render taskId.');
  }
}
