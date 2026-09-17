import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpServer lifecycle', () {
    test('keeps latest and initialize-era protocol constants distinct', () {
      expect(mcpLatestProtocolVersion, '2026-07-28');
      expect(mcpLatestStatelessProtocolVersion, mcpLatestProtocolVersion);
      expect(mcpLatestSessionProtocolVersion, '2025-11-25');
      expect(mcpMissingProtocolVersionFallback, '2025-03-26');
      expect(
        mcpSupportedProtocolVersions,
        contains(mcpMissingProtocolVersionFallback),
      );
      expect(
        mcpNegotiateProtocolVersion(mcpLatestProtocolVersion),
        mcpLatestSessionProtocolVersion,
      );
    });

    test(
      'initialize negotiates the current protocol and advertises tools',
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

        expect(response?['id'], 1);
        final result = response?['result'] as Map<String, Object?>;
        expect(result['protocolVersion'], mcpLatestSessionProtocolVersion);
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

      expect(result['protocolVersion'], mcpLatestSessionProtocolVersion);
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

    final incompleteHandshakes = <String, List<Map<String, Object?>>>{
      'absent initialize': [],
      'initialize sent as a notification': [
        {
          'jsonrpc': '2.0',
          'method': 'initialize',
          'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
        },
      ],
      for (final version in [null, 7, true, <Object?>[]])
        'invalid protocol version $version': [
          {
            'jsonrpc': '2.0',
            'id': 'invalid-init',
            'method': 'initialize',
            'params': {'protocolVersion': version},
          },
        ],
    };
    for (final entry in incompleteHandshakes.entries) {
      for (final batched in [false, true]) {
        test('does not unlock ${entry.key}, batched=$batched', () async {
          var calls = 0;
          final server = McpServer(
            serverInfo: const McpServerInfo(name: 'handshake', version: '1'),
            tools: [
              McpTool(
                name: 'mark',
                handler: (_) {
                  calls++;
                  return McpToolResult.text('marked');
                },
              ),
            ],
          );
          addTearDown(server.shutdown);
          final messages = [
            ...entry.value,
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {
              'jsonrpc': '2.0',
              'id': 'call',
              'method': 'tools/call',
              'params': {'name': 'mark'},
            },
          ];
          final responses = <Map>[];
          if (batched) {
            final result = await server.handleMessage(messages);
            responses.addAll((result as List).cast<Map>());
          } else {
            for (final message in messages) {
              final result = await server.handleMessage(message);
              if (result != null) responses.add(result as Map);
            }
          }
          expect(calls, 0);
          expect(server.state, McpServerState.created);
          expect(responses.last['id'], 'call');
          expect(
            (responses.last['error'] as Map)['code'],
            McpErrorCodes.serverNotInitialized,
          );
          if (entry.key.startsWith('invalid protocol')) {
            expect(responses.first['id'], 'invalid-init');
            expect(
              (responses.first['error'] as Map)['code'],
              McpErrorCodes.invalidParams,
            );
          }

          // An early acknowledgement must not carry over to a later handshake.
          await _initialize(server);
          expect(server.state, McpServerState.created);
          await server.handleMessage({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          });
          expect(server.state, McpServerState.initialized);
          final accepted = await server.handleMessage(messages.last);
          expect(accepted?['result'], McpToolResult.text('marked').toJson());
          expect(calls, 1);
        });
      }
    }

    test('unrelated notifications never acknowledge initialization', () async {
      final server = _server();
      addTearDown(server.shutdown);
      for (final initializedRequest in [false, true]) {
        if (initializedRequest) await _initialize(server);
        expect(
          await server.handleMessage({
            'jsonrpc': '2.0',
            'method': 'notifications/cancelled',
            'params': {'requestId': 'unknown'},
          }),
          isNull,
        );
        expect(server.state, McpServerState.created);
      }
      await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      expect(server.state, McpServerState.initialized);
    });

    for (final initialized in [false, true]) {
      test(
        'notifications cannot reopen closed server, started=$initialized',
        () async {
          final server = _server();
          if (initialized) await _initializeAndStart(server);
          server.shutdown();
          for (final method in [
            'notifications/initialized',
            'notifications/cancelled',
          ]) {
            expect(
              await server.handleMessage({'jsonrpc': '2.0', 'method': method}),
              isNull,
            );
            expect(server.state, McpServerState.closed);
          }
          final response = await server.handleMessage({
            'jsonrpc': '2.0',
            'id': 'reinitialize',
            'method': 'initialize',
            'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
          });
          expect(
            (response?['error'] as Map)['code'],
            McpErrorCodes.serverClosed,
          );
          expect(server.state, McpServerState.closed);
        },
      );
    }

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

    test(
      'rejects JSON-RPC methods containing whitespace or control characters',
      () async {
        final server = _server();
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'bad-method-whitespace',
          'method': 'tools/list\n',
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(response?['id'], 'bad-method-whitespace');
        expect(error['code'], McpErrorCodes.invalidRequest);
        expect(
          error['message'],
          contains('method must not contain whitespace or control characters'),
        );
      },
    );

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
          'protocolVersion': mcpLatestSessionProtocolVersion,
          'capabilities': {},
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
        },
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], isNull);
      expect(error['code'], McpErrorCodes.invalidRequest);
      expect(error['message'], contains('string or integer'));
    });

    test('rejects fractional JSON-RPC request ids', () async {
      final server = _server();

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 1.5,
        'method': 'initialize',
        'params': {
          'protocolVersion': mcpLatestSessionProtocolVersion,
          'capabilities': {},
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
        },
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], isNull);
      expect(error['code'], McpErrorCodes.invalidRequest);
      expect(error['message'], contains('string or integer'));
    });

    test('rejects request objects with response-only members', () async {
      final server = _server();

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'response-member',
        'method': 'initialize',
        'result': <String, Object?>{},
        'params': {
          'protocolVersion': mcpLatestSessionProtocolVersion,
          'capabilities': {},
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
        },
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], 'response-member');
      expect(error['code'], McpErrorCodes.invalidRequest);
      expect(error['message'], contains('result or error'));
    });

    test('rejects explicit null JSON-RPC params before dispatch', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'null-params',
        'method': 'tools/list',
        'params': null,
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(response?['id'], 'null-params');
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('params must be an object'));
    });

    test('suppresses parser errors for JSON-RPC notifications', () async {
      final server = _server();
      await _initializeAndStart(server);

      final singleResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'tools/list',
        'params': null,
      });
      expect(singleResponse, isNull);

      final batchResponse = await server.handleMessage([
        {'jsonrpc': '2.0', 'method': 'tools/list', 'params': null},
        {
          'jsonrpc': '2.0',
          'id': 'after-invalid-notification',
          'method': 'tools/list',
        },
      ]);

      expect(batchResponse, isA<List<Object?>>());
      final responses = (batchResponse as List).cast<Map<String, Object?>>();
      expect(responses, hasLength(1));
      expect(responses.single['id'], equals('after-invalid-notification'));
      expect(responses.single['result'], isA<Map<String, Object?>>());
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

    for (final state in McpServerState.values) {
      test('notification-only batches have no response in $state', () async {
        final server = _server();
        addTearDown(server.shutdown);
        if (state != McpServerState.created) await _initializeAndStart(server);
        if (state == McpServerState.closed) server.shutdown();
        final response = await server.handleMessage([
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          {'jsonrpc': '2.0', 'method': 'notifications/unknown'},
          {'jsonrpc': '2.0', 'method': 'tools/call', 'params': null},
        ]);
        expect(response, isNull);
        expect(server.state, state);
      });
    }

    for (final invalidId in [true, false, 1.5]) {
      test(
        'duplicate invalid ID $invalidId does not reject valid batch entry',
        () async {
          final server = _server();
          addTearDown(server.shutdown);
          await _initializeAndStart(server);
          final response = await server.handleMessage([
            {'jsonrpc': '2.0', 'id': invalidId, 'method': 'ping'},
            {'jsonrpc': '2.0', 'id': invalidId, 'method': 'ping'},
            {'jsonrpc': '2.0', 'id': 'valid', 'method': 'ping'},
          ]);
          expect(response, isA<List>());
          final responses = response as List;
          expect(responses, hasLength(3));
          for (final invalid in responses.take(2).cast<Map>()) {
            expect(invalid['id'], isNull);
            expect(
              (invalid['error'] as Map)['code'],
              McpErrorCodes.invalidRequest,
            );
          }
          expect(responses.last, {
            'jsonrpc': '2.0',
            'id': 'valid',
            'result': {},
          });
        },
      );
    }

    for (final raw in [null, true, 7, 'not an object']) {
      test('rejects non-object $raw with message-shape context', () async {
        final server = _server();
        addTearDown(server.shutdown);
        final response = await server.handleMessage(raw);
        expect(response?['id'], isNull);
        expect(
          (response?['error'] as Map)['code'],
          McpErrorCodes.invalidRequest,
        );
        expect(
          (response?['error'] as Map)['message'],
          'JSON-RPC message must be an object',
        );
        expect(server.state, McpServerState.created);
      });
    }

    test(
      'rejects duplicate JSON-RPC batch request ids before dispatch',
      () async {
        var calls = 0;
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'connectanum-test',
            version: '0.1.0',
          ),
          tools: [
            McpTool(
              name: 'mark',
              description: 'Records a side effect.',
              handler: (_) {
                calls += 1;
                return McpToolResult.text('marked');
              },
            ),
          ],
        );
        await _initializeAndStart(server);

        final response = await server.handleMessage([
          {
            'jsonrpc': '2.0',
            'id': 'duplicate',
            'method': 'tools/call',
            'params': {'name': 'mark', 'arguments': <String, Object?>{}},
          },
          {'jsonrpc': '2.0', 'id': 'duplicate', 'method': 'tools/list'},
        ]);

        expect(response, isA<Map<String, Object?>>());
        final error =
            (response as Map<String, Object?>)['error'] as Map<String, Object?>;
        expect(response['id'], isNull);
        expect(error['code'], McpErrorCodes.invalidRequest);
        expect(error['message'], contains('duplicate request id duplicate'));
        expect(calls, isZero);
      },
    );

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
      'protocolVersion': mcpLatestSessionProtocolVersion,
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
