import 'dart:typed_data';

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
      expect(result.containsKey('nextCursor'), isFalse);
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

    test('tools/list paginates with opaque cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        toolListPageSize: 2,
        tools: [_tool('alpha'), _tool('beta'), _tool('gamma')],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 14,
        'method': 'tools/list',
        'params': {},
      });

      final first = firstResponse?['result'] as Map<String, Object?>;
      expect(_toolNames(first), ['alpha', 'beta']);
      final cursor = first['nextCursor'];
      expect(cursor, isA<String>());

      final secondResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 15,
        'method': 'tools/list',
        'params': {'cursor': cursor},
      });

      final second = secondResponse?['result'] as Map<String, Object?>;
      expect(_toolNames(second), ['gamma']);
      expect(second.containsKey('nextCursor'), isFalse);
    });

    test('tools/list returns deterministic name ordering', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        tools: [_tool('gamma'), _tool('alpha'), _tool('beta')],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 19,
        'method': 'tools/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(_toolNames(result), ['alpha', 'beta', 'gamma']);
    });

    test('tools/list rejects invalid cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        toolListPageSize: 1,
        tools: [_tool('echo')],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 16,
        'method': 'tools/list',
        'params': {'cursor': 'not-a-valid-cursor'},
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('tools/list rejects cursors from older registry revisions', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        toolListPageSize: 1,
        tools: [_tool('alpha'), _tool('beta')],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 17,
        'method': 'tools/list',
        'params': {},
      });
      final first = firstResponse?['result'] as Map<String, Object?>;
      final staleCursor = first['nextCursor'];
      expect(staleCursor, isA<String>());

      server.tools.register(_tool('gamma'));
      final staleResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 18,
        'method': 'tools/list',
        'params': {'cursor': staleCursor},
      });

      final error = staleResponse?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('tool registry replaceAll swaps tools and invalidates cursors', () {
      final registry = McpToolRegistry([_tool('alpha'), _tool('beta')], 1);
      final firstPage = registry.listPage();
      expect(
        _toolNames({
          'tools': firstPage.tools.map((tool) => tool.toJson()).toList(),
        }),
        ['alpha'],
      );
      expect(firstPage.nextCursor, isA<String>());

      registry.replaceAll([_tool('gamma')]);

      expect(registry.list().map((tool) => tool.name), ['gamma']);
      expect(
        () => registry.listPage(cursor: firstPage.nextCursor),
        throwsA(
          isA<McpException>().having(
            (error) => error.code,
            'code',
            McpErrorCodes.invalidParams,
          ),
        ),
      );
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

    test('tools/call serializes mixed content blocks', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        tools: [
          McpTool(
            name: 'context',
            handler: (_) => McpToolResult(
              content: [
                McpTextContent(
                  'read this',
                  annotations: McpContentAnnotations(
                    audience: const ['assistant'],
                    priority: 0.6,
                    lastModified: DateTime.utc(2026, 5, 2, 12),
                  ),
                ),
                McpImageContent.bytes(
                  bytes: Uint8List.fromList([1, 2, 3]),
                  mimeType: 'image/png',
                ),
                McpAudioContent.bytes(
                  bytes: Uint8List.fromList([4, 5]),
                  mimeType: 'audio/wav',
                ),
                McpResourceLinkContent(
                  uri: 'app://example/context',
                  name: 'example-context',
                  title: 'Example Context',
                  description: 'Read-only context.',
                  mimeType: 'application/json',
                  size: 23,
                ),
                const McpEmbeddedResourceContent(
                  resource: McpTextResourceContent(
                    uri: 'app://example/context',
                    mimeType: 'application/json',
                    text: '{"ok":true}',
                  ),
                ),
              ],
              structuredContent: {'uri': 'app://example/context'},
            ),
          ),
        ],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 19,
        'method': 'tools/call',
        'params': {'name': 'context'},
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {'uri': 'app://example/context'});
      expect(result['content'], [
        {
          'type': 'text',
          'text': 'read this',
          'annotations': {
            'audience': ['assistant'],
            'priority': 0.6,
            'lastModified': '2026-05-02T12:00:00.000Z',
          },
        },
        {'type': 'image', 'data': 'AQID', 'mimeType': 'image/png'},
        {'type': 'audio', 'data': 'BAU=', 'mimeType': 'audio/wav'},
        {
          'type': 'resource_link',
          'uri': 'app://example/context',
          'name': 'example-context',
          'title': 'Example Context',
          'description': 'Read-only context.',
          'mimeType': 'application/json',
          'size': 23,
        },
        {
          'type': 'resource',
          'resource': {
            'uri': 'app://example/context',
            'mimeType': 'application/json',
            'text': '{"ok":true}',
          },
        },
      ]);
    });

    test('tool content validates required content fields', () {
      expect(
        () => McpImageContent(data: 'AQID', mimeType: ''),
        throwsArgumentError,
      );
      expect(
        () => McpAudioContent(data: 'BAU=', mimeType: ''),
        throwsArgumentError,
      );
      expect(
        () => McpResourceLinkContent(uri: 'relative/context', name: 'context'),
        throwsArgumentError,
      );
      expect(
        () => McpResourceLinkContent(uri: 'app://example/context', name: ''),
        throwsArgumentError,
      );
      expect(
        () => McpResourceLinkContent(
          uri: 'app://example/context',
          name: 'context',
          size: -1,
        ),
        throwsArgumentError,
      );
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
  tools: [_tool('echo', description: 'Echoes text arguments.')],
);

McpTool _tool(String name, {String? description}) => McpTool(
  name: name,
  description: description,
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
);

List<String> _toolNames(Map<String, Object?> listResult) {
  final tools = listResult['tools'] as List<Object?>;
  return [
    for (final tool in tools) (tool as Map<String, Object?>)['name']! as String,
  ];
}

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
