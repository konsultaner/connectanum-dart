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
            'protocolVersion': mcpLatestSessionProtocolVersion,
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

    test(
      'resource subscription handlers advertise and dispatch lifecycle methods',
      () async {
        final subscribed = <String>[];
        final unsubscribed = <String>[];
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resources: [_resource('app://resource/live', 'live')],
          onSubscribeResource: (request) => subscribed.add(request.uri),
          onUnsubscribeResource: (request) => unsubscribed.add(request.uri),
        );

        final initialize = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': mcpLatestSessionProtocolVersion,
            'capabilities': {},
            'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
          },
        });
        expect(
          initialize?['result'],
          containsPair('capabilities', {
            'tools': <String, Object?>{},
            'resources': <String, Object?>{'subscribe': true},
          }),
        );
        await server.handleMessage({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        });

        final subscribe = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'resources/subscribe',
          'params': {'uri': 'app://resource/live'},
        });
        final unsubscribe = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'resources/unsubscribe',
          'params': {'uri': 'app://resource/live'},
        });

        expect(subscribe?['result'], <String, Object?>{});
        expect(unsubscribe?['result'], <String, Object?>{});
        expect(subscribed, ['app://resource/live']);
        expect(unsubscribed, ['app://resource/live']);
      },
    );

    test(
      'resource subscription methods validate URIs before dispatch',
      () async {
        var dispatches = 0;
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resources: [_resource('app://resource/live', 'live')],
          onSubscribeResource: (_) => dispatches += 1,
          onUnsubscribeResource: (_) => dispatches += 1,
        );
        await _initializeAndStart(server);

        for (final method in const [
          'resources/subscribe',
          'resources/unsubscribe',
        ]) {
          final response = await server.handleMessage({
            'jsonrpc': '2.0',
            'id': method,
            'method': method,
            'params': {'uri': 'relative resource'},
          });
          final error = response?['error'] as Map<String, Object?>;
          expect(error['code'], McpErrorCodes.invalidParams);
        }

        expect(dispatches, 0);
      },
    );

    test('resource subscription methods require configured handlers', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'resources/subscribe',
        'params': {'uri': 'app://tasks/open'},
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.methodNotFound);
    });

    test('resource subscription capability requires paired handlers', () {
      expect(
        () => McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resources: [_resource('app://resource/live', 'live')],
          onSubscribeResource: (_) {},
        ),
        throwsArgumentError,
      );
      expect(
        () => McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resources: [_resource('app://resource/live', 'live')],
          capabilities: const McpServerCapabilities(
            resources: McpResourceCapabilities(subscribe: true),
          ),
        ),
        throwsArgumentError,
      );
    });

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

    test('resources/list returns deterministic URI ordering', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resources: [
          _resource('app://resource/gamma', 'gamma'),
          _resource('app://resource/alpha', 'alpha'),
          _resource('app://resource/beta', 'beta'),
        ],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 19,
        'method': 'resources/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(_resourceNames(result), ['alpha', 'beta', 'gamma']);
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

    test('resources/list rejects malformed cursor strings', () async {
      final server = _server();
      await _initializeAndStart(server);

      for (final cursor in ['', 'cursor with space', 'cursor\nnext']) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'cursor-$cursor',
          'method': 'resources/list',
          'params': {'cursor': cursor},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.invalidParams);
        expect(error['message'], contains('cursor must be a non-empty string'));
      }
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
      'resources/read resolves concrete resource-template URIs',
      () async {
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resourceTemplates: [
            McpResourceTemplate(
              uriTemplate: 'app://tasks/{taskId}',
              name: 'task',
              read: (request, variables) => [
                McpTextResourceContent(
                  uri: request.uri,
                  mimeType: 'text/plain',
                  text: variables['taskId']!,
                ),
              ],
            ),
          ],
        );
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'template-read',
          'method': 'resources/read',
          'params': {'uri': 'app://tasks/A%20B'},
        });

        expect(response?['result'], {
          'contents': [
            {
              'uri': 'app://tasks/A%20B',
              'mimeType': 'text/plain',
              'text': 'A B',
            },
          ],
        });
      },
    );

    test('resource templates expose shared concrete URI expansion', () {
      final template = McpResourceTemplate(
        uriTemplate: 'app://tasks/{taskId}',
        name: 'task',
      );

      expect(
        template.expandUri(const {'taskId': 'A B/✓'}),
        'app://tasks/A%20B%2F%E2%9C%93',
      );
      expect(
        McpResourceUriTemplate(template.uriTemplate).match(
          'app://tasks/A%20B%2F%E2%9C%93',
        ),
        const {'taskId': 'A B/✓'},
      );
    });

    test(
      'resource registry exposes its deterministic readable template match',
      () {
        final generic = McpResourceTemplate(
          uriTemplate: 'app://tasks/{taskId}',
          name: 'generic-task',
          read: (request, variables) => const [],
        );
        final specific = McpResourceTemplate(
          uriTemplate: 'app://tasks/prefix-{taskId}',
          name: 'prefixed-task',
          read: (request, variables) => const [],
        );
        final registry = McpResourceRegistry(templates: [generic, specific]);

        final match = registry.matchReadableTemplate(
          'app://tasks/prefix-A%20B',
        );

        expect(match, isNotNull);
        expect(match!.template, same(specific));
        expect(match.variables, const <String, String>{'taskId': 'A B'});
        expect(
          () => match.variables['taskId'] = 'changed',
          throwsUnsupportedError,
        );
      },
    );

    test('resources/read prefers an exact resource over a template', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resources: [
          McpResource(
            uri: 'app://tasks/fixed',
            name: 'fixed',
            read: (request) => [
              McpTextResourceContent(uri: request.uri, text: 'exact'),
            ],
          ),
        ],
        resourceTemplates: [
          McpResourceTemplate(
            uriTemplate: 'app://tasks/{taskId}',
            name: 'task',
            read: (request, variables) => [
              McpTextResourceContent(uri: request.uri, text: 'template'),
            ],
          ),
        ],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'exact-read',
        'method': 'resources/read',
        'params': {'uri': 'app://tasks/fixed'},
      });

      final result = response?['result'] as Map<String, Object?>;
      final contents = result['contents'] as List<Object?>;
      expect(contents.single, containsPair('text', 'exact'));
    });

    test('resource-template reads support a literal suffix', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resourceTemplates: [
          McpResourceTemplate(
            uriTemplate: 'app://tasks/{taskId}.json',
            name: 'task-json',
            read: (request, variables) => [
              McpTextResourceContent(
                uri: request.uri,
                text: variables['taskId']!,
              ),
            ],
          ),
        ],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'suffix-read',
        'method': 'resources/read',
        'params': {'uri': 'app://tasks/A.B.json'},
      });

      final result = response?['result'] as Map<String, Object?>;
      final contents = result['contents'] as List<Object?>;
      expect(contents.single, containsPair('text', 'A.B'));
    });

    test('resource templates reject ambiguous or unsupported expressions', () {
      for (final uriTemplate in [
        'app://tasks/{first}{second}',
        'app://tasks/{id:2}',
        'app://tasks/{+id}',
        'app://tasks/{first}-{second}',
        'app://tasks/{id}/{id}',
        'relative/{id}',
      ]) {
        expect(
          () => McpResourceTemplate(
            uriTemplate: uriTemplate,
            name: 'invalid',
          ),
          throwsArgumentError,
          reason: uriTemplate,
        );
      }
    });

    test(
      'resources/read does not let Level 1 variables consume a path',
      () async {
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resourceTemplates: [
            McpResourceTemplate(
              uriTemplate: 'app://tasks/{taskId}',
              name: 'task',
              read: (request, variables) => const [],
            ),
          ],
        );
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'reserved-read',
          'method': 'resources/read',
          'params': {'uri': 'app://tasks/parent/child'},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.resourceNotFound);
      },
    );

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

    test(
      'resources/read rejects malformed resource URIs before lookup',
      () async {
        final server = _server();
        await _initializeAndStart(server);

        for (final uri in ['', 'relative/context', 'app://tasks/open\n']) {
          final response = await server.handleMessage({
            'jsonrpc': '2.0',
            'id': 'resource-$uri',
            'method': 'resources/read',
            'params': {'uri': uri},
          });

          final error = response?['error'] as Map<String, Object?>;
          expect(error['code'], McpErrorCodes.invalidParams);
          expect(error['message'], contains('resources/read.params.uri'));
        }
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

    test(
      'resources/templates/list returns deterministic URI template ordering',
      () async {
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          resourceTemplates: [
            McpResourceTemplate(
              uriTemplate: 'app://templates/gamma/{id}',
              name: 'gamma',
            ),
            McpResourceTemplate(
              uriTemplate: 'app://templates/alpha/{id}',
              name: 'alpha',
            ),
            McpResourceTemplate(
              uriTemplate: 'app://templates/beta/{id}',
              name: 'beta',
            ),
          ],
        );
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 20,
          'method': 'resources/templates/list',
          'params': {},
        });

        final result = response?['result'] as Map<String, Object?>;
        expect(_resourceTemplateNames(result), ['alpha', 'beta', 'gamma']);
      },
    );

    test('resources/templates/list rejects malformed cursor strings', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        resourceTemplates: [
          McpResourceTemplate(uriTemplate: 'app://tasks/{id}', name: 'task'),
        ],
      );
      await _initializeAndStart(server);

      for (final cursor in ['', 'cursor with space', 'cursor\nnext']) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'template-cursor-$cursor',
          'method': 'resources/templates/list',
          'params': {'cursor': cursor},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.invalidParams);
        expect(error['message'], contains('cursor must be a non-empty string'));
      }
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

List<String> _resourceTemplateNames(Map<String, Object?> listResult) {
  final templates = listResult['resourceTemplates'] as List<Object?>;
  return [
    for (final template in templates)
      (template as Map<String, Object?>)['name']! as String,
  ];
}

Future<void> _initializeAndStart(McpServer server) async {
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
      'protocolVersion': mcpLatestSessionProtocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
    },
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
