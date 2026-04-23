import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP tools', () {
    test('tools/list returns typed tool definitions', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 10,
        'method': 'tools/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      final tools = result['tools'] as List<Object?>;
      expect(tools, hasLength(1));
      expect(tools.single, {
        'name': 'echo',
        'description': 'Echoes text arguments.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      });
    });

    test('tools/call passes arguments to the registered tool', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 11,
        'method': 'tools/call',
        'params': {
          'name': 'echo',
          'arguments': {'text': 'hello'},
        },
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {'echo': 'hello'});
      expect(result['content'], [
        {'type': 'text', 'text': 'hello'},
      ]);
    });

    test(
      'tool execution failures are tool results, not protocol errors',
      () async {
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          tools: [
            McpTool(name: 'fail', handler: (_) => throw StateError('boom')),
          ],
        );
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 12,
          'method': 'tools/call',
          'params': {'name': 'fail'},
        });

        expect(response?['error'], isNull);
        final result = response?['result'] as Map<String, Object?>;
        expect(result['isError'], isTrue);
        expect(result['content'], [
          {'type': 'text', 'text': 'Bad state: boom'},
        ]);
      },
    );

    test('unknown tools are invalid params errors', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 13,
        'method': 'tools/call',
        'params': {'name': 'missing'},
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });
  });
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-test', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'echo',
      description: 'Echoes text arguments.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(text, structuredContent: {'echo': text});
      },
    ),
  ],
);

Future<void> _initializeAndStart(McpServer server) async {
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
      'protocolVersion': mcpLatestProtocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
    },
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
