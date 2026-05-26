import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpServer lifecycle', () {
    test(
      'initialize negotiates the current protocol and advertises tools',
      () async {
        final server = _server();

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': mcpLatestProtocolVersion,
            'capabilities': {},
            'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
          },
        });

        expect(response?['id'], 1);
        final result = response?['result'] as Map<String, Object?>;
        expect(result['protocolVersion'], mcpLatestProtocolVersion);
        expect(result['capabilities'], {'tools': <String, Object?>{}});
        expect(result['serverInfo'], {
          'name': 'connectanum-test',
          'version': '0.1.0',
        });
        expect(server.state, McpServerState.created);
      },
    );

    test('initialize keeps supported older protocol versions', () async {
      final server = _server();

      final result = await _initializeResult(server, '2025-06-18');

      expect(result['protocolVersion'], '2025-06-18');
    });

    test('initialize falls back to latest for unsupported versions', () async {
      final server = _server();

      final result = await _initializeResult(server, '2099-01-01');

      expect(result['protocolVersion'], mcpLatestProtocolVersion);
    });

    test(
      'requires initialized notification before operation requests',
      () async {
        final server = _server();
        await _initialize(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.serverNotInitialized);
      },
    );

    test('initialized notification enters operation phase', () async {
      final server = _server();
      await _initialize(server);

      final notificationResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });

      expect(notificationResponse, isNull);
      expect(server.state, McpServerState.initialized);
    });

    test('responds to ping requests after initialization', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'ping',
        'method': 'ping',
      });

      expect(response?['id'], 'ping');
      expect(response?['result'], isEmpty);
    });

    test('unknown methods return method-not-found errors', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'bad-method',
        'method': 'tools/unknown',
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.methodNotFound);
    });

    test('malformed requests return invalid-request errors', () async {
      final server = _server();

      final response = await server.handleMessage({
        'jsonrpc': '1.0',
        'id': 'bad-version',
        'method': 'initialize',
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], 'bad-version');
      expect(error['code'], McpErrorCodes.invalidRequest);
    });

    test('rejects null JSON-RPC request ids', () async {
      final server = _server();

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': null,
        'method': 'initialize',
        'params': {
          'protocolVersion': mcpLatestProtocolVersion,
          'capabilities': {},
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
        },
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], isNull);
      expect(error['code'], McpErrorCodes.invalidRequest);
      expect(error['message'], contains('string or number'));
    });

    test('handles JSON-RPC batches and omits notification responses', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage([
        {'jsonrpc': '2.0', 'id': 'tools', 'method': 'tools/list'},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 'bad-method', 'method': 'tools/unknown'},
      ]);

      expect(response, isA<List<Object?>>());
      final responses = (response as List).cast<Map<String, Object?>>();
      expect(responses, hasLength(2));
      expect(responses[0]['id'], 'tools');
      expect(responses[0]['result'], isA<Map<String, Object?>>());
      expect(responses[1]['id'], 'bad-method');
      final error = responses[1]['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.methodNotFound);
    });

    test('empty JSON-RPC batches return invalid-request errors', () async {
      final server = _server();

      final response = await server.handleMessage(const []);

      expect(response, isA<Map<String, Object?>>());
      final error =
          (response as Map<String, Object?>)['error'] as Map<String, Object?>;
      expect(response['id'], isNull);
      expect(error['code'], McpErrorCodes.invalidRequest);
    });

    test('closed servers reject further requests', () async {
      final server = _server();
      await _initializeAndStart(server);

      server.shutdown();
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/list',
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.serverClosed);
    });
  });
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-test', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'ping',
      description: 'Returns pong.',
      handler: (_) => McpToolResult.text('pong'),
    ),
  ],
);

Future<void> _initialize(McpServer server) async {
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
}

Future<Map<String, Object?>> _initializeResult(
  McpServer server,
  String protocolVersion,
) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 'initialize-$protocolVersion',
    'method': 'initialize',
    'params': {
      'protocolVersion': protocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
    },
  });
  return (response?['result'] as Map).cast<String, Object?>();
}

Future<void> _initializeAndStart(McpServer server) async {
  await _initialize(server);
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
