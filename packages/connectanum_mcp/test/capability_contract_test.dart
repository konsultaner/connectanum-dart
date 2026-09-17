import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('resource capability defaults do not promise notifications', () {
    const capabilities = McpResourceCapabilities();
    expect(capabilities.subscribe, isFalse);
    expect(capabilities.listChanged, isFalse);
    expect(capabilities.toJson(), isEmpty);
    expect(const McpResourceCapabilities(subscribe: true).toJson(), {
      'subscribe': true,
    });
    expect(const McpResourceCapabilities(listChanged: true).toJson(), {
      'listChanged': true,
    });
  });

  test('explicit server capabilities are preserved on the wire', () async {
    const capabilities = McpServerCapabilities(
      tools: null,
      resources: McpResourceCapabilities(listChanged: true),
    );
    final server = _server(capabilities: capabilities);
    addTearDown(server.shutdown);
    expect(server.capabilities, same(capabilities));
    final result = await _initialize(server);
    expect(result['capabilities'], {
      'resources': {'listChanged': true},
    });
    expect(result, isNot(contains('instructions')));
  });

  for (final promptCompletion in [false, true]) {
    for (final templateCompletion in [false, true]) {
      test(
        'completion advertised for prompt=$promptCompletion template=$templateCompletion',
        () async {
          final template = McpResourceTemplate(
            uriTemplate: 'app:///item/{id}',
            name: 'item',
            complete: templateCompletion
                ? (_) => McpCompletionResult(values: ['one'])
                : null,
          );
          final registry = McpResourceRegistry(templates: [template]);
          expect(registry.hasCompletions, templateCompletion);
          final server = McpServer(
            serverInfo: _info,
            prompts: [
              McpPrompt(
                name: 'prompt',
                arguments: [McpPromptArgument(name: 'id')],
                handler: (_) => McpPromptResult.text('text'),
                complete: promptCompletion
                    ? (_) => McpCompletionResult(values: ['one'])
                    : null,
              ),
            ],
            resourceTemplates: [template],
          );
          addTearDown(server.shutdown);
          final result = await _initialize(server);
          expect(result['capabilities'], {
            'tools': {},
            'prompts': {},
            'resources': {},
            if (promptCompletion || templateCompletion) 'completions': {},
          });
        },
      );
    }
  }

  test(
    'unknown template completion variable never reaches the handler',
    () async {
      var called = false;
      final server = McpServer(
        serverInfo: _info,
        resourceTemplates: [
          McpResourceTemplate(
            uriTemplate: 'app:///item/{id}',
            name: 'item',
            complete: (_) {
              called = true;
              return McpCompletionResult(values: ['one']);
            },
          ),
        ],
      );
      addTearDown(server.shutdown);
      await _initialize(server);
      await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'complete',
        'method': 'completion/complete',
        'params': {
          'ref': {'type': 'ref/resource', 'uri': 'app:///item/{id}'},
          'argument': {'name': 'undeclared', 'value': ''},
        },
      });
      expect(response!['error'], {
        'code': McpErrorCodes.invalidParams,
        'message':
            'Unknown MCP resource-template completion argument: undeclared',
      });
      expect(called, isFalse);
    },
  );

  for (final value in <String?>[null, '', 'Help']) {
    test(
      'optional prompt description and server instructions preserve $value',
      () async {
        expect(
          McpPromptResult(messages: const [], description: value).toJson(),
          {
            'messages': [],
            if (value != null) 'description': value,
          },
        );
        final server = _server(instructions: value);
        addTearDown(server.shutdown);
        final result = await _initialize(server);
        if (value == null) {
          expect(result, isNot(contains('instructions')));
        } else {
          expect(result['instructions'], value);
        }
      },
    );
  }
  test('error payload omits absent details rather than emitting null', () {
    expect(McpException(-1, 'failure').toJson(), {
      'code': -1,
      'message': 'failure',
    });
    expect(McpException(-1, 'failure', data: {}).toJson(), {
      'code': -1,
      'message': 'failure',
      'data': {},
    });
  });

  final hints = <(McpToolAnnotations, Map<String, Object?>)>[
    (const McpToolAnnotations(), {}),
    (const McpToolAnnotations(title: ''), {'title': ''}),
    for (final value in [false, true]) ...[
      (McpToolAnnotations(readOnlyHint: value), {'readOnlyHint': value}),
      (McpToolAnnotations(destructiveHint: value), {'destructiveHint': value}),
      (McpToolAnnotations(idempotentHint: value), {'idempotentHint': value}),
      (McpToolAnnotations(openWorldHint: value), {'openWorldHint': value}),
    ],
  ];
  for (final (annotations, expected) in hints) {
    test('individual tool annotations preserve explicit values $expected', () {
      expect(annotations.isEmpty, expected.isEmpty);
      expect(annotations.toJson(), expected);
      final tool = McpTool(
        name: 'tool',
        title: 'Visible title',
        annotations: annotations,
        handler: (_) => McpToolResult.text('ok'),
      );
      final json = tool.toJson();
      expect(json['title'], 'Visible title');
      if (expected.isEmpty) {
        expect(json, isNot(contains('annotations')));
      } else {
        expect(json['annotations'], expected);
      }
    });
  }
}

const _info = McpServerInfo(name: 'consumer', version: '1');

McpServer _server({
  McpServerCapabilities? capabilities,
  String? instructions,
}) => McpServer(
  serverInfo: _info,
  capabilities: capabilities,
  instructions: instructions,
);

Future<Map<String, Object?>> _initialize(McpServer server) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
  });
  expect(response, isNot(contains('error')));
  return response!['result'] as Map<String, Object?>;
}
