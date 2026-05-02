import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpStdioTransport', () {
    test('processes line-delimited JSON-RPC requests', () async {
      final output = StringBuffer();
      final transport = McpStdioTransport(
        server: _server(),
        input: _input([
          {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {
              'protocolVersion': mcpLatestProtocolVersion,
              'capabilities': {},
              'clientInfo': {'name': 'stdio-test', 'version': '1.0.0'},
            },
          },
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'id': 3, 'method': 'resources/list'},
          {
            'jsonrpc': '2.0',
            'id': 4,
            'method': 'resources/read',
            'params': {'uri': 'app://example/context'},
          },
          {'jsonrpc': '2.0', 'id': 5, 'method': 'prompts/list'},
          {
            'jsonrpc': '2.0',
            'id': 6,
            'method': 'prompts/get',
            'params': {
              'name': 'echo.summary',
              'arguments': {'text': 'hello'},
            },
          },
        ]),
        output: output,
      );

      await transport.run();

      final responses = _responses(output);
      expect(responses, hasLength(6));
      expect(responses[0]['id'], 1);
      expect(responses[1]['id'], 2);
      expect(responses[2]['id'], 3);
      expect(responses[3]['id'], 4);
      expect(responses[4]['id'], 5);
      expect(responses[5]['id'], 6);

      final initializeResult = responses[0]['result'] as Map<String, Object?>;
      expect(initializeResult['capabilities'], {
        'tools': <String, Object?>{},
        'prompts': <String, Object?>{},
        'resources': <String, Object?>{},
      });

      final toolsResult = responses[1]['result'] as Map<String, Object?>;
      expect(toolsResult['tools'], [
        {
          'name': 'echo',
          'description': 'Echoes text arguments.',
          'inputSchema': {'type': 'object', 'additionalProperties': false},
        },
      ]);

      final resourcesResult = responses[2]['result'] as Map<String, Object?>;
      expect(resourcesResult['resources'], [
        {
          'uri': 'app://example/context',
          'name': 'example-context',
          'title': 'Example Context',
          'description': 'Static context from the stdio test server.',
          'mimeType': 'application/json',
        },
      ]);

      final readResult = responses[3]['result'] as Map<String, Object?>;
      expect(readResult['contents'], [
        {
          'uri': 'app://example/context',
          'mimeType': 'application/json',
          'text': '{"server":"connectanum-stdio","tools":["echo"]}',
        },
      ]);

      final promptsResult = responses[4]['result'] as Map<String, Object?>;
      expect(promptsResult['prompts'], [
        {
          'name': 'echo.summary',
          'title': 'Echo Summary',
          'description': 'Builds a prompt around an echo request.',
          'arguments': [
            {'name': 'text', 'description': 'Text to summarize.'},
          ],
        },
      ]);

      final promptResult = responses[5]['result'] as Map<String, Object?>;
      expect(promptResult['description'], 'Echo prompt for hello.');
      expect(promptResult['messages'], [
        {
          'role': 'user',
          'content': {
            'type': 'text',
            'text': 'Summarize this echo request: hello',
          },
        },
      ]);
      expect(transport.server.state, McpServerState.closed);
    });

    test('returns parse errors and continues reading later lines', () async {
      final output = StringBuffer();
      final transport = McpStdioTransport(
        server: _server(),
        input: Stream.value(
          utf8.encode(
            '{"jsonrpc": "2.0", "id": 1, "method": "initialize", '
            '"params": {"protocolVersion": "$mcpLatestProtocolVersion"}}\n'
            'not-json\n'
            '{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}\n',
          ),
        ),
        output: output,
        shutdownServerOnDone: false,
      );

      await transport.run();

      final responses = _responses(output);
      expect(responses, hasLength(3));
      final parseError = responses[1]['error'] as Map<String, Object?>;
      expect(responses[1]['id'], isNull);
      expect(parseError['code'], McpErrorCodes.parseError);
      final lifecycleError = responses[2]['error'] as Map<String, Object?>;
      expect(lifecycleError['code'], McpErrorCodes.serverNotInitialized);
      expect(transport.server.state, McpServerState.created);
    });

    test('supports direct line handling for embedders', () async {
      final output = StringBuffer();
      final server = _server();
      final transport = McpStdioTransport(
        server: server,
        input: const Stream<List<int>>.empty(),
        output: output,
      );

      await transport.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'init',
          'method': 'initialize',
          'params': {'protocolVersion': mcpLatestProtocolVersion},
        }),
      );

      final responses = _responses(output);
      expect(responses.single['id'], 'init');
      expect(server.state, McpServerState.created);
    });
  });
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-stdio', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'echo',
      description: 'Echoes text arguments.',
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(text, structuredContent: {'echo': text});
      },
    ),
  ],
  prompts: [
    McpPrompt(
      name: 'echo.summary',
      title: 'Echo Summary',
      description: 'Builds a prompt around an echo request.',
      arguments: [
        McpPromptArgument(name: 'text', description: 'Text to summarize.'),
      ],
      handler: (request) {
        final text = request.arguments['text'] ?? '';
        return McpPromptResult.text(
          'Summarize this echo request: $text',
          description: 'Echo prompt for $text.',
        );
      },
    ),
  ],
  resources: [
    McpResource(
      uri: 'app://example/context',
      name: 'example-context',
      title: 'Example Context',
      description: 'Static context from the stdio test server.',
      mimeType: 'application/json',
      read: (request) => [
        McpTextResourceContent(
          uri: request.uri,
          mimeType: 'application/json',
          text: '{"server":"connectanum-stdio","tools":["echo"]}',
        ),
      ],
    ),
  ],
);

Stream<List<int>> _input(List<Map<String, Object?>> messages) {
  final lines = messages.map(jsonEncode).join('\n');
  return Stream.value(utf8.encode('$lines\n'));
}

List<Map<String, Object?>> _responses(StringBuffer output) => [
  for (final line in const LineSplitter().convert(output.toString()))
    jsonDecode(line) as Map<String, Object?>,
];
