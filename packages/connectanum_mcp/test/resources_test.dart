import 'dart:typed_data';

import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP resources', () {
    test(
      'initialize advertises resources when resources are configured',
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

        final result = response?['result'] as Map<String, Object?>;
        expect(result['capabilities'], {
          'tools': <String, Object?>{},
          'resources': <String, Object?>{},
        });
      },
    );

    test('resources/list returns typed resource definitions', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 10,
        'method': 'resources/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      final resources = result['resources'] as List<Object?>;
      expect(result.containsKey('nextCursor'), isFalse);
      expect(resources, [
        {
          'uri': 'app://tasks/open',
          'name': 'open-tasks',
          'title': 'Open Tasks',
          'description': 'Application tasks ready for review.',
          'mimeType': 'application/json',
          'size': 25,
          'annotations': {
            'audience': ['assistant'],
            'priority': 0.8,
            'lastModified': '2026-05-02T12:00:00.000Z',
          },
        },
      ]);
    });

    test('resources/list paginates with opaque cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resourceListPageSize: 2,
        resources: [
          _resource('app://resource/alpha', 'alpha'),
          _resource('app://resource/beta', 'beta'),
          _resource('app://resource/gamma', 'gamma'),
        ],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 11,
        'method': 'resources/list',
        'params': {},
      });

      final first = firstResponse?['result'] as Map<String, Object?>;
      expect(_resourceNames(first), ['alpha', 'beta']);
      final cursor = first['nextCursor'];
      expect(cursor, isA<String>());

      final secondResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 12,
        'method': 'resources/list',
        'params': {'cursor': cursor},
      });

      final second = secondResponse?['result'] as Map<String, Object?>;
      expect(_resourceNames(second), ['gamma']);
      expect(second.containsKey('nextCursor'), isFalse);
    });

    test('resources/list rejects stale cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resourceListPageSize: 1,
        resources: [
          _resource('app://resource/alpha', 'alpha'),
          _resource('app://resource/beta', 'beta'),
        ],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 13,
        'method': 'resources/list',
        'params': {},
      });
      final first = firstResponse?['result'] as Map<String, Object?>;
      final staleCursor = first['nextCursor'];
      expect(staleCursor, isA<String>());

      server.resources.register(_resource('app://resource/gamma', 'gamma'));
      final staleResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 14,
        'method': 'resources/list',
        'params': {'cursor': staleCursor},
      });

      final error = staleResponse?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('resources/read returns text and binary content', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resources: [
          McpResource(
            uri: 'app://resource/mixed',
            name: 'mixed',
            read: (request) => [
              McpTextResourceContent(
                uri: request.uri,
                mimeType: 'text/plain',
                text: 'hello',
              ),
              McpBlobResourceContent.bytes(
                uri: request.uri,
                mimeType: 'application/octet-stream',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
          ),
        ],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 15,
        'method': 'resources/read',
        'params': {'uri': 'app://resource/mixed'},
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(result['contents'], [
        {
          'uri': 'app://resource/mixed',
          'mimeType': 'text/plain',
          'text': 'hello',
        },
        {
          'uri': 'app://resource/mixed',
          'mimeType': 'application/octet-stream',
          'blob': 'AQID',
        },
      ]);
    });

    test(
      'resources/read reports missing resources as resource errors',
      () async {
        final server = _server();
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 16,
          'method': 'resources/read',
          'params': {'uri': 'app://resource/missing'},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.resourceNotFound);
        expect(error['data'], {'uri': 'app://resource/missing'});
      },
    );

    test('resources/templates/list returns paginated templates', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resourceTemplateListPageSize: 1,
        resourceTemplates: [
          McpResourceTemplate(
            uriTemplate: 'app://tasks/{id}',
            name: 'task',
            title: 'Task',
            description: 'Application task by id.',
            mimeType: 'application/json',
          ),
          McpResourceTemplate(uriTemplate: 'app://users/{id}', name: 'user'),
        ],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 17,
        'method': 'resources/templates/list',
        'params': {},
      });

      final first = firstResponse?['result'] as Map<String, Object?>;
      expect(first['resourceTemplates'], [
        {
          'uriTemplate': 'app://tasks/{id}',
          'name': 'task',
          'title': 'Task',
          'description': 'Application task by id.',
          'mimeType': 'application/json',
        },
      ]);
      final cursor = first['nextCursor'];
      expect(cursor, isA<String>());

      final secondResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 18,
        'method': 'resources/templates/list',
        'params': {'cursor': cursor},
      });

      final second = secondResponse?['result'] as Map<String, Object?>;
      expect(second['resourceTemplates'], [
        {'uriTemplate': 'app://users/{id}', 'name': 'user'},
      ]);
      expect(second.containsKey('nextCursor'), isFalse);
    });
  });
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-test', version: '0.1.0'),
  resources: [
    McpResource(
      uri: 'app://tasks/open',
      name: 'open-tasks',
      title: 'Open Tasks',
      description: 'Application tasks ready for review.',
      mimeType: 'application/json',
      size: 25,
      annotations: McpResourceAnnotations(
        audience: const ['assistant'],
        priority: 0.8,
        lastModified: DateTime.utc(2026, 5, 2, 12),
      ),
      read: (request) => [
        McpTextResourceContent(
          uri: request.uri,
          mimeType: 'application/json',
          text: '{"tasks":[]}',
        ),
      ],
    ),
  ],
);

McpResource _resource(String uri, String name) => McpResource(
  uri: uri,
  name: name,
  read: (request) => [McpTextResourceContent(uri: request.uri, text: name)],
);

List<String> _resourceNames(Map<String, Object?> listResult) {
  final resources = listResult['resources'] as List<Object?>;
  return [
    for (final resource in resources)
      (resource as Map<String, Object?>)['name']! as String,
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
