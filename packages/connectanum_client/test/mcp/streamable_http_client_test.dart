import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpStreamableHttpClient', () {
    test(
      'tracks Streamable HTTP sessions, SSE responses, polling, and auth headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient.withBearerToken(
          endpoint.uri,
          ' test-token ',
        );
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(
          clientInfo: const <String, Object?>{
            'name': 'consumer-test',
            'version': '1.0.0',
          },
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-initialize-token',
            'x-consumer-trace': 'streamable-initialize',
          },
        );

        expect(client.sessionId, 'session-1');
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(initialize['id'], 'initialize');

        await client.notifyInitialized(
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-initialized-token',
            'x-consumer-trace': 'streamable-initialized',
          },
        );

        final tools = await client.request(
          'tools/list',
          id: 'tools-sse',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-tools-sse-token',
          },
        );
        expect(tools['id'], 'tools-sse');
        expect(client.lastEventId, 'session-1:post:2');

        final pollEvents = await client.poll(
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-poll-token',
            'x-consumer-trace': 'streamable-poll',
          },
        );
        expect(pollEvents, hasLength(1));
        expect(pollEvents.single.id, 'session-1:get:1');
        expect(
          pollEvents.single.jsonData?['method'],
          'notifications/tools/list_changed',
        );
        expect(client.lastEventId, 'session-1:get:1');

        final jsonTools = await client.request(
          'tools/list',
          id: 'tools-json',
          streamable: false,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-tools-json-token',
          },
        );
        expect(jsonTools['id'], 'tools-json');

        final ping = await client.pingDirect(
          id: 'ping-json',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-ping-json-token',
            'x-consumer-trace': 'ping-json-helper',
          },
        );
        expect(ping, isEmpty);

        final streamableBatch = await client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 'batch-sse', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          ],
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-batch-sse-token',
          },
        );
        expect(streamableBatch, hasLength(1));
        expect(streamableBatch?.single['id'], 'batch-sse');
        expect(client.lastEventId, 'session-1:post-batch:1');

        final jsonBatch = await client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 'batch-json', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          ],
          streamable: false,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-batch-json-token',
          },
        );
        expect(jsonBatch, hasLength(1));
        expect(jsonBatch?.single['id'], 'batch-json');

        await client.deleteSession(
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-delete-token',
            'x-consumer-trace': 'streamable-delete',
          },
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        expect(endpoint.requests, hasLength(9));
        expect(
          endpoint.requests.map((request) => request.authorization),
          everyElement('Bearer test-token'),
        );
        expect(endpoint.requests[0].accept, contains('text/event-stream'));
        expect(endpoint.requests[0].mcpMethod, 'initialize');
        expect(endpoint.requests[0].mcpName, isNull);
        expect(endpoint.requests[0].consumerTrace, 'streamable-initialize');
        expect(endpoint.requests[0].contentLength, greaterThan(0));
        expect(endpoint.requests[0].transferEncoding, isNull);
        expect(endpoint.requests[1].sessionId, 'session-1');
        expect(endpoint.requests[1].mcpMethod, 'notifications/initialized');
        expect(endpoint.requests[1].consumerTrace, 'streamable-initialized');
        expect(endpoint.requests[2].sessionId, 'session-1');
        expect(endpoint.requests[2].mcpMethod, 'tools/list');
        expect(endpoint.requests[3].lastEventId, 'session-1:post:2');
        expect(endpoint.requests[3].consumerTrace, 'streamable-poll');
        expect(endpoint.requests[4].accept, 'application/json');
        expect(endpoint.requests[4].mcpMethod, 'tools/list');
        expect(endpoint.requests[5].accept, 'application/json');
        expect(endpoint.requests[5].body, containsPair('method', 'ping'));
        expect(endpoint.requests[5].mcpMethod, 'ping');
        expect(endpoint.requests[5].sessionId, isNull);
        expect(endpoint.requests[5].lastEventId, isNull);
        expect(endpoint.requests[5].consumerTrace, 'ping-json-helper');
        expect(endpoint.requests[6].accept, contains('text/event-stream'));
        expect(endpoint.requests[6].mcpMethod, isNull);
        expect(endpoint.requests[7].accept, 'application/json');
        expect(endpoint.requests[7].mcpMethod, isNull);
        expect(endpoint.requests[8].method, 'DELETE');
        expect(endpoint.requests[8].consumerTrace, 'streamable-delete');
      },
    );

    test('keeps supported initialize protocol versions', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(
        endpoint.uri,
        defaultProtocolVersion: '2025-06-18',
      );
      addTearDown(() => client.close(force: true));

      final initialize = await client.initialize(id: 'older-protocol-init');

      final result = (initialize['result'] as Map).cast<String, Object?>();
      expect(result['protocolVersion'], '2025-06-18');
      expect(client.protocolVersion, '2025-06-18');
      expect(endpoint.requests.single.protocolVersion, '2025-06-18');

      await client.notifyInitialized();
      expect(endpoint.requests.last.protocolVersion, '2025-06-18');
    });

    test('rejects unsupported default protocol versions locally', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      expect(
        () => McpStreamableHttpClient(
          endpoint.uri,
          defaultProtocolVersion: '2099-01-01',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'defaultProtocolVersion',
          ),
        ),
      );
      expect(endpoint.requests, isEmpty);
    });

    test(
      'rejects unsupported explicit protocol versions before requests',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.initialize(
            id: 'unsupported-request-protocol',
            protocolVersion: '2099-01-01',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'protocolVersion',
            ),
          ),
        );
        expect(endpoint.requests, isEmpty);
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
      },
    );

    test('rejects unsupported protocol assignments locally', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      expect(
        () => client.protocolVersion = '2099-01-01',
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'protocolVersion',
          ),
        ),
      );
      expect(endpoint.requests, isEmpty);
      expect(
        client.protocolVersion,
        McpStreamableHttpClient.latestProtocolVersion,
      );
    });

    test(
      'rejects unsupported response protocol headers without poisoning state',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.initialize(
            id: 'unsupported-response-protocol-header',
            headers: const <String, String>{
              'x-test-response-protocol-version': '2099-01-01',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.message,
              'message',
              contains('Unsupported MCP-Protocol-Version response header'),
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
      },
    );

    test('rejects unsupported initialize result protocol versions', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.initialize(
          id: 'unsupported-result-protocol-version',
          headers: const <String, String>{
            'x-test-result-protocol-version': '2099-01-01',
          },
        ),
        throwsA(
          isA<McpStreamableProtocolException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported initialize protocolVersion'),
          ),
        ),
      );
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
      expect(
        client.protocolVersion,
        McpStreamableHttpClient.latestProtocolVersion,
      );
    });

    test(
      'uses explicit initialize protocol version in request headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(
          id: 'explicit-protocol-init',
          protocolVersion: '2025-06-18',
        );

        final result = (initialize['result'] as Map).cast<String, Object?>();
        expect(result['protocolVersion'], '2025-06-18');
        expect(client.protocolVersion, '2025-06-18');
        expect(endpoint.requests.single.protocolVersion, '2025-06-18');
        final initializeBody = (endpoint.requests.single.body as Map)
            .cast<String, Object?>();
        final initializeParams = (initializeBody['params'] as Map)
            .cast<String, Object?>();
        expect(initializeParams['protocolVersion'], '2025-06-18');
      },
    );

    test(
      'keeps negotiated protocol after streamable helper overrides',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize(id: 'streamable-protocol-override-init');
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        final sessionId = client.sessionId;
        expect(sessionId, isNotNull);

        final ping = await client.ping(
          id: 'streamable-protocol-override-ping',
          protocolVersion: '2025-03-26',
        );

        expect(ping, isEmpty);
        expect(endpoint.requests.last.protocolVersion, '2025-03-26');
        expect(endpoint.requests.last.sessionId, sessionId);
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(client.sessionId, sessionId);
      },
    );

    test('lets direct JSON helpers override protocol headers', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.postDirect(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'ping',
        'method': 'ping',
      }, protocolVersion: '2025-03-26');
      await client.postBatchDirect(<McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'batch-tools',
          'method': 'tools/list',
        },
      ], protocolVersion: '2025-06-18');
      await client.requestDirect(
        'tools/list',
        id: 'direct-tools',
        protocolVersion: '2025-03-26',
      );
      await client.notificationDirect(
        'connectanum.event',
        protocolVersion: '2025-06-18',
      );
      await client.listToolsDirect(
        id: 'typed-tools',
        protocolVersion: '2025-03-26',
      );
      await client.callToolDirect(
        'app.echo',
        id: 'typed-tool-call',
        arguments: const <String, Object?>{'message': 'typed'},
        protocolVersion: '2025-06-18',
      );
      await client.listConnectanumToolsDirect(
        id: 'typed-connectanum-tools',
        protocolVersion: '2025-03-26',
      );
      await client.notifyConnectanumToolDirect(
        'app.echo',
        arguments: const <String, Object?>{'message': 'typed-notify'},
        protocolVersion: '2025-06-18',
      );
      await client.listResourcesDirect(
        id: 'typed-resources',
        protocolVersion: '2025-03-26',
      );
      await client.getPromptDirect(
        'summarize',
        id: 'typed-prompt',
        protocolVersion: '2025-06-18',
      );
      await client.listWampApiDirect(
        id: 'typed-wamp-api',
        protocolVersion: '2025-03-26',
      );
      await client.publishWampEventDirect(
        'app.events.audit',
        id: 'typed-pubsub',
        argumentsKeywords: const <String, Object?>{'message': 'typed'},
        protocolVersion: '2025-06-18',
      );

      expect(endpoint.requests.map((request) => request.protocolVersion), [
        '2025-03-26',
        '2025-06-18',
        '2025-03-26',
        '2025-06-18',
        '2025-03-26',
        '2025-06-18',
        '2025-03-26',
        '2025-06-18',
        '2025-03-26',
        '2025-06-18',
        '2025-03-26',
        '2025-06-18',
      ]);
      expect(
        client.protocolVersion,
        McpStreamableHttpClient.latestProtocolVersion,
      );
    });

    test('treats delete without an active session as local cleanup', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      client.lastEventId = 'orphan-event';
      await client.deleteSession(
        headers: const <String, String>{
          'x-consumer-trace': 'delete-without-session',
        },
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
      expect(endpoint.requests, isEmpty);
    });

    test(
      'selects matching JSON-RPC responses from Streamable HTTP SSE events',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        final response = await client.request(
          'tools/list',
          id: 'tools-after-notification',
          headers: const <String, String>{
            'x-test-sse-prefix-notification': '1',
          },
        );

        expect(response['id'], 'tools-after-notification');
        expect(response['result'], containsPair('tools', isEmpty));
        expect(client.lastEventId, 'session-1:post:3');
      },
    );

    test('rejects unexpected JSON-RPC single response ids from JSON', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.post(
          {'jsonrpc': '2.0', 'id': 'tools-request', 'method': 'tools/list'},
          streamable: false,
          headers: const <String, String>{
            'x-test-json-response-id': 'other-response',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unexpected response id other-response'),
          ),
        ),
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test('rejects invalid JSON-RPC single response ids from JSON', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.post(
          {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
          streamable: false,
          headers: const <String, String>{
            'x-test-json-response-id-shape': 'fractional',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('id must be a string or integer'),
          ),
        ),
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test(
      'rejects invalid JSON-RPC single response discriminants from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        for (final shape in const <String, String>{
          'missing-discriminant': 'exactly one of result or error',
          'both-result-error': 'exactly one of result or error',
          'invalid-error': 'error must be a JSON object',
        }.entries) {
          await expectLater(
            client.post(
              {
                'jsonrpc': '2.0',
                'id': 'tools-${shape.key}',
                'method': 'tools/list',
              },
              streamable: false,
              headers: <String, String>{
                'x-test-json-response-shape': shape.key,
              },
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains(shape.value),
              ),
            ),
          );
        }

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC single response error objects from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        for (final shape in const <String, String>{
          'missing-error-code': 'error code must be an integer',
          'invalid-error-code': 'error code must be an integer',
          'missing-error-message': 'error message must be a string',
          'invalid-error-message': 'error message must be a string',
        }.entries) {
          await expectLater(
            client.post(
              {
                'jsonrpc': '2.0',
                'id': 'tools-${shape.key}',
                'method': 'tools/list',
              },
              streamable: false,
              headers: <String, String>{
                'x-test-json-response-shape': shape.key,
              },
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains(shape.value),
              ),
            ),
          );
        }

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC single response versions from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        for (final shape in const <String>[
          'missing-jsonrpc',
          'invalid-jsonrpc',
          'non-string-jsonrpc',
        ]) {
          await expectLater(
            client.post(
              {'jsonrpc': '2.0', 'id': 'tools-$shape', 'method': 'tools/list'},
              streamable: false,
              headers: <String, String>{'x-test-json-response-shape': shape},
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains('jsonrpc must be 2.0'),
              ),
            ),
          );
        }

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects unexpected JSON-RPC single response ids from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        await expectLater(
          client.request(
            'tools/list',
            id: 'tools-after-extra-response',
            headers: const <String, String>{'x-test-sse-extra-response': '1'},
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('unexpected response id other-response'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC single response ids from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-response-id';
        await expectLater(
          client.request(
            'tools/list',
            id: 1,
            headers: const <String, String>{
              'x-test-sse-response-id-shape': 'fractional',
              'x-test-response-session-id': 'post-sse-id-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('id must be a string or integer'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-response-id');
      },
    );

    test(
      'rejects invalid JSON-RPC single response discriminants from SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-shape';
        await expectLater(
          client.request(
            'tools/list',
            id: 'tools-invalid-shape',
            headers: const <String, String>{
              'x-test-sse-response-shape': 'both-result-error',
              'x-test-response-session-id': 'post-sse-shape-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('exactly one of result or error'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-shape');
      },
    );

    test(
      'rejects invalid JSON-RPC single response error objects from SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-error';
        await expectLater(
          client.request(
            'tools/list',
            id: 'tools-invalid-error',
            headers: const <String, String>{
              'x-test-sse-response-shape': 'missing-error-code',
              'x-test-response-session-id': 'post-sse-error-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('error code must be an integer'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-error');
      },
    );

    test(
      'rejects invalid JSON-RPC single response versions from SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-jsonrpc';
        await expectLater(
          client.request(
            'tools/list',
            id: 'tools-invalid-jsonrpc',
            headers: const <String, String>{
              'x-test-sse-response-shape': 'missing-jsonrpc',
              'x-test-response-session-id': 'post-sse-jsonrpc-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('jsonrpc must be 2.0'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-jsonrpc');
      },
    );

    test(
      'keeps Streamable HTTP SSE server requests before matching responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        final response = await client.request(
          'tools/list',
          id: 'tools-after-server-request',
          headers: const <String, String>{
            'x-test-sse-server-request-before-response': '1',
          },
        );

        expect(response['id'], 'tools-after-server-request');
        expect(response['result'], containsPair('tools', isEmpty));
        expect(client.lastEventId, 'session-1:post:3');
      },
    );

    test(
      'rejects malformed Streamable HTTP SSE messages before matching responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-sse-message';
        await expectLater(
          client.request(
            'tools/list',
            id: 'tools-after-invalid-sse-message',
            headers: const <String, String>{
              'x-test-sse-invalid-interim-message': '1',
              'x-test-response-session-id': 'post-sse-interim-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('JSON-RPC SSE event data must be an object or array'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-sse-message');
      },
    );

    test('clears the resume cursor when SSE sends an empty id', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final response = await client.request(
        'tools/list',
        id: 'tools-after-reset',
        headers: const <String, String>{'x-test-sse-reset-event-id': '1'},
      );

      expect(response['id'], 'tools-after-reset');
      expect(client.lastEventId, isNull);

      await client.poll();
      expect(endpoint.requests.last.method, 'GET');
      expect(endpoint.requests.last.lastEventId, isNull);
    });

    test('collects batch responses from Streamable HTTP SSE events', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final responses = await client.postBatch(
        [
          {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
        ],
        headers: const <String, String>{
          'x-test-sse-split-batch-with-notification': '1',
        },
      );

      expect(responses, hasLength(2));
      expect(responses?.map((response) => response['id']), [
        'batch-one',
        'batch-two',
      ]);
      expect(client.lastEventId, 'session-1:post-batch:3');
    });

    test(
      'keeps Streamable HTTP SSE server requests before batch responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        final responses = await client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
          ],
          headers: const <String, String>{
            'x-test-sse-batch-server-request-before-response': '1',
          },
        );

        expect(responses, hasLength(2));
        expect(responses?.map((response) => response['id']), [
          'batch-one',
          'batch-two',
        ]);
        expect(client.lastEventId, 'session-1:post-batch:3');
      },
    );

    test(
      'rejects malformed Streamable HTTP SSE messages before batch responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-batch-sse-message';
        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-sse-batch-invalid-interim-message': '1',
              'x-test-response-session-id': 'post-sse-batch-interim-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('JSON-RPC SSE event data must be an object or array'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(
          client.lastEventId,
          'session-1:get:kept-invalid-batch-sse-message',
        );
      },
    );

    test('rejects invalid JSON-RPC request ids before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final invalidId in <Object?>[null, 1.5]) {
        await expectLater(
          client.post({
            'jsonrpc': '2.0',
            'id': invalidId,
            'method': 'tools/list',
          }, streamable: false),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('invalid request id ${invalidId ?? 'null'}'),
            ),
          ),
        );
      }

      expect(endpoint.requests, isEmpty);
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test('rejects invalid JSON-RPC request versions before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final message in <McpJsonMap>[
        {'id': 'missing-jsonrpc', 'method': 'tools/list'},
        {'jsonrpc': '1.0', 'id': 'invalid-jsonrpc', 'method': 'tools/list'},
        {'jsonrpc': 2.0, 'id': 'numeric-jsonrpc', 'method': 'tools/list'},
      ]) {
        await expectLater(
          client.post(message, streamable: false),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('jsonrpc must be 2.0'),
            ),
          ),
        );
      }

      await expectLater(
        client.postBatch([
          {'jsonrpc': '2.0', 'id': 'valid', 'method': 'ping'},
          {'jsonrpc': '1.0', 'id': 'invalid-batch', 'method': 'tools/list'},
        ], streamable: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('jsonrpc must be 2.0'),
          ),
        ),
      );

      expect(endpoint.requests, isEmpty);
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test('rejects invalid JSON-RPC request objects before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final message in <McpJsonMap>[
        {'jsonrpc': '2.0', 'id': 'missing-method'},
        {'jsonrpc': '2.0', 'id': 'numeric-method', 'method': 7},
        {'jsonrpc': '2.0', 'id': 'empty-method', 'method': ''},
        {'jsonrpc': '2.0', 'id': 'blank-method', 'method': '  '},
        {'jsonrpc': '2.0', 'id': 'control-method', 'method': 'tools\nlist'},
        {
          'jsonrpc': '2.0',
          'id': 'unicode-space-method',
          'method': 'tools\u00a0list',
        },
        {
          'jsonrpc': '2.0',
          'id': 'response-shaped-request',
          'method': 'tools/list',
          'result': <String, Object?>{},
        },
        {
          'jsonrpc': '2.0',
          'id': 'invalid-params',
          'method': 'tools/list',
          'params': 'not-structured',
        },
        {
          'jsonrpc': '2.0',
          'id': 'array-params',
          'method': 'tools/list',
          'params': <Object?>[],
        },
        {
          'jsonrpc': '2.0',
          'id': 'non-string-param-key',
          'method': 'tools/list',
          'params': <Object?, Object?>{1: 'invalid'},
        },
      ]) {
        await expectLater(
          client.post(message, streamable: false),
          throwsA(isA<FormatException>()),
        );
      }

      await expectLater(
        client.postBatch([
          {'jsonrpc': '2.0', 'id': 'valid', 'method': 'ping'},
          {'jsonrpc': '2.0', 'id': 'invalid-batch'},
        ], streamable: false),
        throwsA(isA<FormatException>()),
      );

      expect(endpoint.requests, isEmpty);
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test('rejects empty JSON-RPC batches before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.postBatch(const <McpJsonMap>[], streamable: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('batch must not be empty'),
          ),
        ),
      );

      await expectLater(
        client.postBatchDirect(const <McpJsonMap>[]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('batch must not be empty'),
          ),
        ),
      );

      expect(endpoint.requests, isEmpty);
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test(
      'rejects duplicate JSON-RPC batch request ids before sending',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.postBatch([
            {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'ping'},
          ], streamable: false),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('duplicate request id batch-one'),
            ),
          ),
        );

        expect(endpoint.requests, isEmpty);
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test('rejects invalid JSON-RPC batch request ids before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final invalidId in <Object?>[null, 1.5]) {
        await expectLater(
          client.postBatch([
            {'jsonrpc': '2.0', 'id': invalidId, 'method': 'tools/list'},
          ], streamable: false),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('invalid request id ${invalidId ?? 'null'}'),
            ),
          ),
        );
      }

      expect(endpoint.requests, isEmpty);
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test(
      'rejects invalid JSON-RPC batch response discriminants from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            streamable: false,
            headers: const <String, String>{
              'x-test-batch-response-shape': 'missing-discriminant',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('exactly one of result or error'),
            ),
          ),
        );

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC batch response error objects from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            streamable: false,
            headers: const <String, String>{
              'x-test-batch-response-shape': 'invalid-error-message',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('error message must be a string'),
            ),
          ),
        );

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC batch response versions from JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            streamable: false,
            headers: const <String, String>{
              'x-test-batch-response-shape': 'invalid-jsonrpc',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('jsonrpc must be 2.0'),
            ),
          ),
        );

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC batch response versions from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-batch-response-shape': 'missing-jsonrpc',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('jsonrpc must be 2.0'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC batch response errors from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-batch-response-shape': 'invalid-error-code',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('error code must be an integer'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects incomplete JSON-RPC batch responses from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-batch-missing-response': '1',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('missing response for id batch-two'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
      },
    );

    test('rejects incomplete JSON-RPC batch responses from JSON', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
          ],
          streamable: false,
          headers: const <String, String>{'x-test-batch-missing-response': '1'},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missing response for id batch-two'),
          ),
        ),
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test('rejects invalid JSON-RPC batch response ids from JSON', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
          ],
          streamable: false,
          headers: const <String, String>{
            'x-test-batch-response-id-shape': 'fractional',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('id must be a string or integer'),
          ),
        ),
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test(
      'rejects unexpected JSON-RPC batch response ids from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-batch-unexpected-response': '1',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('unexpected response id batch-extra'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'rejects invalid JSON-RPC batch response ids from Streamable HTTP SSE',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();

        client.lastEventId = 'session-1:get:kept-invalid-batch-id';
        await expectLater(
          client.postBatch(
            [
              {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
              {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
              {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
            ],
            headers: const <String, String>{
              'x-test-batch-response-id-shape': 'fractional',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('id must be a string or integer'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-batch-id');
      },
    );

    test('rejects duplicate JSON-RPC batch response ids from JSON', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.postBatch(
          [
            {'jsonrpc': '2.0', 'id': 'batch-one', 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 'batch-two', 'method': 'ping'},
          ],
          streamable: false,
          headers: const <String, String>{
            'x-test-batch-duplicate-response': '1',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate response for id batch-one'),
          ),
        ),
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
    });

    test(
      'owns MCP protocol and session headers despite caller headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(
          endpoint.uri,
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'text/plain',
            _headerProtocolVersion: '2099-01-01',
            _headerSessionId: 'default-stale-session',
            'Last-Event-ID': 'default-stale-event',
            _headerMethod: 'default-stale-method',
            _headerName: 'default-stale-name',
            'x-consumer-default': 'kept',
          },
        );
        addTearDown(() => client.close(force: true));

        await client.initialize(
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'text/plain',
            _headerProtocolVersion: '2099-02-01',
            _headerSessionId: 'initialize-stale-session',
            'Last-Event-ID': 'initialize-stale-event',
            _headerMethod: 'initialize-stale-method',
            _headerName: 'initialize-stale-name',
            'x-consumer-trace': 'controlled-initialize',
          },
        );
        expect(client.sessionId, 'session-1');
        expect(endpoint.requests.last.accept, contains('text/event-stream'));
        expect(
          endpoint.requests.last.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(endpoint.requests.last.sessionId, isNull);
        expect(endpoint.requests.last.lastEventId, isNull);
        expect(endpoint.requests.last.mcpMethod, 'initialize');
        expect(endpoint.requests.last.mcpName, isNull);

        await client.notifyInitialized();
        final sessionId = client.sessionId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        final direct = await client.callConnectanumMethodDirect(
          'app.direct.controlled-headers',
          id: 'controlled-direct',
          params: const <String, Object?>{'message': 'direct'},
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'text/plain',
            _headerProtocolVersion: '2099-03-01',
            _headerSessionId: 'direct-stale-session',
            'Last-Event-ID': 'direct-stale-event',
            _headerMethod: 'direct-stale-method',
            _headerName: 'direct-stale-name',
            'x-consumer-trace': 'controlled-direct',
          },
        );
        expect(direct['isError'], isFalse);
        expect(endpoint.requests.last.accept, 'application/json');
        expect(
          endpoint.requests.last.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(endpoint.requests.last.sessionId, isNull);
        expect(endpoint.requests.last.lastEventId, isNull);
        expect(
          endpoint.requests.last.mcpMethod,
          'app.direct.controlled-headers',
        );
        expect(endpoint.requests.last.mcpName, isNull);
        expect(endpoint.requests.last.consumerTrace, 'controlled-direct');

        final streamable = await client.ping(
          id: 'controlled-streamable',
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'text/plain',
            _headerProtocolVersion: '2099-04-01',
            _headerSessionId: 'streamable-stale-session',
            'Last-Event-ID': 'streamable-stale-event',
            _headerMethod: 'streamable-stale-method',
            _headerName: 'streamable-stale-name',
            'x-consumer-trace': 'controlled-streamable',
          },
        );
        expect(streamable, isEmpty);
        expect(endpoint.requests.last.accept, contains('text/event-stream'));
        expect(
          endpoint.requests.last.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(endpoint.requests.last.sessionId, sessionId);
        expect(endpoint.requests.last.lastEventId, isNull);
        expect(endpoint.requests.last.mcpMethod, 'ping');
        expect(endpoint.requests.last.mcpName, isNull);

        final events = await client.poll(
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'application/json',
            _headerSessionId: 'poll-stale-session',
            'Last-Event-ID': 'poll-stale-event',
            _headerMethod: 'poll-stale-method',
            _headerName: 'poll-stale-name',
            'x-consumer-trace': 'controlled-poll',
          },
        );
        expect(events, hasLength(1));
        expect(endpoint.requests.last.accept, 'text/event-stream');
        expect(endpoint.requests.last.sessionId, sessionId);
        expect(endpoint.requests.last.lastEventId, isNull);
        expect(endpoint.requests.last.mcpMethod, isNull);
        expect(endpoint.requests.last.mcpName, isNull);
        expect(endpoint.requests.last.consumerTrace, 'controlled-poll');

        final batch = await client.postBatch(
          [
            {
              'jsonrpc': '2.0',
              'id': 'controlled-batch-tools',
              'method': 'tools/list',
            },
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          ],
          headers: const <String, String>{
            _headerMethod: 'batch-stale-method',
            _headerName: 'batch-stale-name',
            'x-consumer-trace': 'controlled-batch',
          },
        );
        expect(batch, hasLength(1));
        expect(endpoint.requests.last.mcpMethod, isNull);
        expect(endpoint.requests.last.mcpName, isNull);
        expect(endpoint.requests.last.consumerTrace, 'controlled-batch');
      },
    );

    test(
      'clears stale Streamable HTTP session state after session failures',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        Future<void> expectSessionFailureClearsState({
          required String staleSessionId,
          required int statusCode,
          required String label,
        }) async {
          client.sessionId = staleSessionId;
          client.lastEventId = '$staleSessionId:get:1';
          await expectLater(
            client.listTools(id: '$label-stale-tools'),
            throwsA(
              isA<McpStreamableHttpException>().having(
                (error) => error.statusCode,
                'statusCode',
                statusCode,
              ),
            ),
          );
          expect(client.sessionId, isNull);
          expect(client.lastEventId, isNull);
          expect(endpoint.requests.last.sessionId, staleSessionId);

          client.sessionId = staleSessionId;
          client.lastEventId = '$staleSessionId:get:2';
          await expectLater(
            client.poll(),
            throwsA(
              isA<McpStreamableHttpException>().having(
                (error) => error.statusCode,
                'statusCode',
                statusCode,
              ),
            ),
          );
          expect(client.sessionId, isNull);
          expect(client.lastEventId, isNull);
          expect(endpoint.requests.last.method, 'GET');
          expect(endpoint.requests.last.lastEventId, '$staleSessionId:get:2');

          client.sessionId = staleSessionId;
          client.lastEventId = '$staleSessionId:get:3';
          await expectLater(
            client.deleteSession(),
            throwsA(
              isA<McpStreamableHttpException>().having(
                (error) => error.statusCode,
                'statusCode',
                statusCode,
              ),
            ),
          );
          expect(client.sessionId, isNull);
          expect(client.lastEventId, isNull);
          expect(endpoint.requests.last.method, 'DELETE');
        }

        client.sessionId = 'stale-before-initialize';
        client.lastEventId = 'stale-before-initialize:get:1';
        final initialize = await client.initialize(id: 'fresh-initialize');
        expect(initialize['id'], 'fresh-initialize');
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
        expect(endpoint.requests.single.sessionId, isNull);

        await expectSessionFailureClearsState(
          staleSessionId: 'expired-session',
          statusCode: HttpStatus.notFound,
          label: 'not-found',
        );
        await expectSessionFailureClearsState(
          staleSessionId: 'unauthorized-session',
          statusCode: HttpStatus.unauthorized,
          label: 'unauthorized',
        );
        await expectSessionFailureClearsState(
          staleSessionId: 'forbidden-session',
          statusCode: HttpStatus.forbidden,
          label: 'forbidden',
        );
      },
    );

    test(
      'keeps Streamable HTTP session state after rate-limit failures',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'rate-limit-init');
        expect(initialize['id'], 'rate-limit-init');
        final sessionId = client.sessionId;
        expect(sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept';
        await expectLater(
          client.listTools(
            id: 'rate-limited-tools',
            headers: <String, String>{
              'x-test-force-status': '${HttpStatus.tooManyRequests}',
              'x-test-response-session-id': sessionId!,
            },
          ),
          throwsA(
            isA<McpStreamableHttpException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.tooManyRequests,
            ),
          ),
        );
        expect(client.sessionId, sessionId);
        expect(client.lastEventId, 'session-1:get:kept');
        expect(endpoint.requests.last.sessionId, sessionId);
        expect(endpoint.requests.last.method, 'POST');

        await client.deleteSession(
          headers: const <String, String>{
            'x-consumer-trace': 'rate-limit-cleanup',
          },
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(endpoint.requests.last.method, 'DELETE');
        expect(endpoint.requests.last.sessionId, sessionId);
        expect(endpoint.requests.last.consumerTrace, 'rate-limit-cleanup');
      },
    );

    test(
      'keeps Streamable HTTP session state after non-SSE poll responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'poll-session-init');
        expect(initialize['id'], 'poll-session-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept';
        await expectLater(
          client.poll(
            headers: const <String, String>{
              'x-test-poll-json-response': '1',
              'x-test-response-session-id': 'poll-json-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Expected text/event-stream'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept');
        expect(endpoint.requests.last.method, 'GET');
        expect(endpoint.requests.last.sessionId, 'session-1');
        expect(endpoint.requests.last.lastEventId, 'session-1:get:kept');

        final events = await client.poll();
        expect(events, hasLength(1));
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:1');
      },
    );

    test(
      'rejects malformed Streamable HTTP poll messages before state capture',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'poll-invalid-init');
        expect(initialize['id'], 'poll-invalid-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-invalid-poll-message';
        await expectLater(
          client.poll(
            headers: const <String, String>{
              'x-test-poll-invalid-message': '1',
              'x-test-response-session-id': 'poll-invalid-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('JSON-RPC SSE event data must be an object or array'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-poll-message');
        expect(endpoint.requests.last.method, 'GET');
        expect(endpoint.requests.last.sessionId, 'session-1');
        expect(
          endpoint.requests.last.lastEventId,
          'session-1:get:kept-invalid-poll-message',
        );
      },
    );

    test(
      'rejects invalid Streamable HTTP poll event ids before state capture',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'poll-invalid-id-init');
        expect(initialize['id'], 'poll-invalid-id-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-invalid-poll-id';
        await expectLater(
          client.poll(
            headers: const <String, String>{
              'x-test-poll-invalid-event-id': '1',
              'x-test-response-session-id': 'poll-invalid-id-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('SSE event id cannot be used as Last-Event-ID'),
            ),
          ),
        );

        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-poll-id');
        expect(endpoint.requests.last.method, 'GET');
        expect(endpoint.requests.last.sessionId, 'session-1');
        expect(
          endpoint.requests.last.lastEventId,
          'session-1:get:kept-invalid-poll-id',
        );
      },
    );

    test('rejects invalid outgoing Last-Event-ID poll values', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final initialize = await client.initialize(id: 'poll-invalid-outgoing');
      expect(initialize['id'], 'poll-invalid-outgoing');
      expect(client.sessionId, 'session-1');

      client.lastEventId = 'session-1:get:kept-outgoing-invalid-id';
      await expectLater(
        client.poll(lastEventId: 'bad\u0000id'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Last-Event-ID header value contains invalid characters'),
          ),
        ),
      );

      expect(client.sessionId, 'session-1');
      expect(client.lastEventId, 'session-1:get:kept-outgoing-invalid-id');
      expect(endpoint.requests, hasLength(1));
      expect(endpoint.requests.last.method, 'POST');

      client.lastEventId = 'bad\u0000stored-id';
      await expectLater(
        client.poll(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Last-Event-ID header value contains invalid characters'),
          ),
        ),
      );

      expect(client.sessionId, 'session-1');
      expect(client.lastEventId, 'bad\u0000stored-id');
      expect(endpoint.requests, hasLength(1));
    });

    test('rejects invalid outgoing MCP-Session-Id values', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final initialize = await client.initialize(id: 'invalid-session-init');
      expect(initialize['id'], 'invalid-session-init');
      expect(client.sessionId, 'session-1');

      client.sessionId = 'bad session';
      await expectLater(
        client.listTools(id: 'invalid-session-tools'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('MCP-Session-Id header value contains invalid characters'),
          ),
        ),
      );

      expect(client.sessionId, 'bad session');
      expect(endpoint.requests, hasLength(1));
      expect(endpoint.requests.last.method, 'POST');
    });

    test(
      'rejects malformed response session headers without poisoning state',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await expectLater(
          client.initialize(
            id: 'malformed-response-session',
            headers: const <String, String>{
              'x-test-response-session-id': 'malformed session',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(endpoint.requests.single.sessionId, isNull);

        await expectLater(
          client.initialize(
            id: 'empty-response-session',
            headers: const <String, String>{
              'x-test-empty-response-session-id': '1',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(endpoint.requests.last.sessionId, isNull);

        final initialize = await client.initialize(id: 'fresh-after-malformed');
        expect(initialize['id'], 'fresh-after-malformed');
        expect(client.sessionId, 'session-1');
        expect(endpoint.requests.last.sessionId, isNull);
      },
    );

    test(
      'keeps active session state after malformed response session headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'active-malformed-init');
        expect(initialize['id'], 'active-malformed-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-malformed-header';
        await expectLater(
          client.listTools(
            id: 'active-malformed-response-session',
            streamable: false,
            headers: const <String, String>{
              'x-test-response-session-id': 'malformed session',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-malformed-header');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        final page = await client.listTools(
          id: 'active-malformed-response-session-recovery',
          streamable: false,
        );
        expect(page.tools.map((tool) => tool['name']), contains('app.echo'));
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-malformed-header');
      },
    );

    test('clears stale session state when initialize is sessionless', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      client.sessionId = 'stale-session-before-sessionless-init';
      client.lastEventId = 'stale-session-before-sessionless-init:get:1';

      final initialize = await client.initialize(
        id: 'sessionless-initialize',
        headers: const <String, String>{'x-test-no-response-session-id': '1'},
      );

      expect(initialize['id'], 'sessionless-initialize');
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
      expect(endpoint.requests.single.method, 'POST');
      expect(endpoint.requests.single.sessionId, isNull);

      await client.notifyInitialized();
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);
    });

    test(
      'clears stale resume cursor when initialize returns current session id',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        client.sessionId = 'session-1';
        client.lastEventId = 'session-1:get:stale';

        final initialize = await client.initialize(
          id: 'same-session-initialize',
        );

        expect(initialize['id'], 'same-session-initialize');
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, isNull);
        expect(endpoint.requests.single.method, 'POST');
        expect(endpoint.requests.single.sessionId, isNull);

        final events = await client.poll();
        expect(events, hasLength(1));
        expect(endpoint.requests.last.method, 'GET');
        expect(endpoint.requests.last.lastEventId, isNull);
      },
    );

    test(
      'validates DELETE response session headers before local cleanup',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'delete-header-init');
        expect(initialize['id'], 'delete-header-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-delete';
        await expectLater(
          client.deleteSession(
            headers: const <String, String>{
              'x-test-response-session-id': 'malformed session',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-delete');
        expect(endpoint.requests.last.method, 'DELETE');
        expect(endpoint.requests.last.sessionId, 'session-1');

        await expectLater(
          client.deleteSession(
            headers: const <String, String>{
              'x-test-empty-response-session-id': '1',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-delete');

        await expectLater(
          client.deleteSession(
            headers: const <String, String>{
              'x-test-response-session-id': 'other-session',
            },
          ),
          throwsA(
            isA<McpStreamableProtocolException>().having(
              (error) => error.toString(),
              'message',
              contains('MCP-Session-Id'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-delete');

        await client.deleteSession(
          headers: const <String, String>{
            'x-test-response-session-id': 'session-1',
          },
        );
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'keeps Streamable HTTP session state after malformed POST responses',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(id: 'malformed-post-init');
        expect(initialize['id'], 'malformed-post-init');
        expect(client.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-json';
        await expectLater(
          client.listTools(
            id: 'malformed-json-tools',
            streamable: false,
            headers: const <String, String>{
              'x-test-malformed-json-response': '1',
              'x-test-response-session-id': 'post-json-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-json');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-shape';
        await expectLater(
          client.listTools(
            id: 'wrong-json-shape-tools',
            streamable: false,
            headers: const <String, String>{
              'x-test-json-array-response': '1',
              'x-test-response-session-id': 'post-json-shape-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-shape');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-sse';
        await expectLater(
          client.listTools(
            id: 'malformed-sse-tools',
            headers: const <String, String>{
              'x-test-malformed-sse-response': '1',
              'x-test-response-session-id': 'post-sse-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-sse');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-invalid-sse-id';
        await expectLater(
          client.listTools(
            id: 'invalid-sse-id-tools',
            headers: const <String, String>{
              'x-test-sse-invalid-event-id': '1',
              'x-test-response-session-id': 'post-sse-invalid-id-session',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('SSE event id cannot be used as Last-Event-ID'),
            ),
          ),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-invalid-sse-id');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-missing-sse';
        await expectLater(
          client.listTools(
            id: 'missing-sse-tools',
            headers: const <String, String>{
              'x-test-sse-notification-only-response': '1',
              'x-test-response-session-id': 'post-sse-missing-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-missing-sse');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        await expectLater(
          client.postBatch(
            const <McpJsonMap>[
              {'jsonrpc': '2.0', 'id': 'batch-shape', 'method': 'tools/list'},
            ],
            streamable: false,
            headers: const <String, String>{
              'x-test-batch-json-object-response': '1',
              'x-test-response-session-id': 'post-batch-shape-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-missing-sse');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-notification-json';
        await expectLater(
          client.notification(
            'notifications/progress',
            params: const <String, Object?>{
              'progressToken': 'malformed-notification-json',
              'progress': 1,
            },
            headers: const <String, String>{
              'x-test-json-notification-response': '1',
              'x-test-response-session-id': 'post-notification-json-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-notification-json');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-notification-sse';
        await expectLater(
          client.notification(
            'notifications/tools/list_changed',
            params: const <String, Object?>{},
            headers: const <String, String>{
              'x-test-sse-notification-only-response': '1',
              'x-test-response-session-id': 'post-notification-sse-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-notification-sse');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-notification-batch-json';
        await expectLater(
          client.postBatch(
            const <McpJsonMap>[
              {
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': <String, Object?>{
                  'progressToken': 'malformed-notification-batch-json',
                  'progress': 1,
                },
              },
            ],
            headers: const <String, String>{
              'x-test-json-notification-response': '1',
              'x-test-response-session-id':
                  'post-notification-batch-json-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(
          client.lastEventId,
          'session-1:get:kept-notification-batch-json',
        );
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        client.lastEventId = 'session-1:get:kept-notification-batch-sse';
        await expectLater(
          client.postBatch(
            const <McpJsonMap>[
              {
                'jsonrpc': '2.0',
                'method': 'notifications/tools/list_changed',
                'params': <String, Object?>{},
              },
            ],
            headers: const <String, String>{
              'x-test-sse-notification-only-response': '1',
              'x-test-response-session-id':
                  'post-notification-batch-sse-session',
            },
          ),
          throwsA(isA<FormatException>()),
        );
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-notification-batch-sse');
        expect(endpoint.requests.last.method, 'POST');
        expect(endpoint.requests.last.sessionId, 'session-1');

        final page = await client.listTools(
          id: 'fresh-after-malformed-post',
          streamable: false,
        );
        expect(page.tools.map((tool) => tool['name']), contains('app.echo'));
        expect(client.sessionId, 'session-1');
        expect(client.lastEventId, 'session-1:get:kept-notification-batch-sse');
      },
    );

    test('rejects empty bearer tokens', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      expect(
        () => McpStreamableHttpClient.withBearerToken(endpoint.uri, '  '),
        throwsArgumentError,
      );
    });

    test(
      'rejects bearer tokens with whitespace or control characters',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        for (final token in <String>[
          'bad token',
          'bad\ttoken',
          'bad\ntoken',
          'bad\u0000token',
          'bad\u0085token',
          'bad\u00a0token',
        ]) {
          expect(
            () => McpStreamableHttpClient.withBearerToken(endpoint.uri, token),
            throwsArgumentError,
          );
        }
        expect(
          () => McpStreamableHttpClient.withAuthGrant(
            endpoint.uri,
            const ConnectanumHttpAuthGrant(
              accessToken: 'grant token',
              tokenType: 'Bearer',
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test('creates bearer clients from HTTP auth grants', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient.withAuthGrant(
        endpoint.uri,
        const ConnectanumHttpAuthGrant(
          accessToken: ' grant-token ',
          tokenType: 'bearer',
        ),
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer stale-token',
          'x-consumer-trace': 'grant-session',
        },
      );
      addTearDown(() => client.close(force: true));

      await client.initialize(
        id: 'grant-initialize',
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
        },
      );
      await client.listTools(
        id: 'grant-list-tools',
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
          'x-consumer-trace': 'grant-list-tools',
        },
      );
      await client.poll(
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
          'x-consumer-trace': 'grant-poll',
        },
      );
      await client.deleteSession(
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
          'x-consumer-trace': 'grant-delete',
        },
      );

      expect(
        endpoint.requests.map((request) => request.authorization),
        everyElement('Bearer grant-token'),
      );
      expect(endpoint.requests[0].consumerTrace, 'grant-session');
      expect(endpoint.requests[1].consumerTrace, 'grant-list-tools');
      expect(endpoint.requests[1].sessionId, 'session-1');
      expect(endpoint.requests[2].consumerTrace, 'grant-poll');
      expect(endpoint.requests[2].sessionId, 'session-1');
      expect(endpoint.requests[3].consumerTrace, 'grant-delete');
      expect(endpoint.requests[3].sessionId, 'session-1');
      expect(client.sessionId, isNull);
    });

    test(
      'uses HTTP auth grants for direct JSON helpers without lifecycle',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient.withAuthGrant(
          endpoint.uri,
          const ConnectanumHttpAuthGrant(
            accessToken: ' grant-direct-token ',
            tokenType: 'bearer',
          ),
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer stale-direct-token',
            'x-consumer-trace': 'grant-direct-client',
          },
        );
        addTearDown(() => client.close(force: true));

        final ping = await client.pingDirect(
          id: 'grant-direct-ping',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-ping',
          },
        );
        expect(ping, isEmpty);

        final page = await client.listToolsDirect(
          id: 'grant-direct-tools',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-tools',
          },
        );
        expect(page.tools.map((tool) => tool['name']), contains('app.echo'));

        final meta = await client.callConnectanumToolDirect(
          'connectanum.api.list',
          id: 'grant-direct-api-list',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-api-list',
          },
        );
        expect(
          jsonEncode(meta['structuredContent']),
          contains('app.events.audit'),
        );

        final sessionCount = await client.countWampSessionsDirect(
          id: 'grant-direct-session-count',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-session-count',
          },
        );
        expect(sessionCount.argumentsKeywords['count'], 2);

        final sessions = await client.listWampSessionsDirect(
          id: 'grant-direct-session-list',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-session-list',
          },
        );
        expect(sessions.argumentsKeywords['session_ids'], [101, 102]);

        final session = await client.getWampSessionDirect(
          101,
          id: 'grant-direct-session-get',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-session-get',
          },
        );
        expect(
          session.argumentsKeywords['details'],
          containsPair('session', 101),
        );

        final registrations = await client.listWampRegistrationsDirect(
          id: 'grant-direct-registration-list',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-list',
          },
        );
        expect(registrations.argumentsKeywords['exact'], [11]);

        final lookupRegistration = await client.lookupWampRegistrationDirect(
          'app.echo',
          match: 'exact',
          id: 'grant-direct-registration-lookup',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-lookup',
          },
        );
        expect(lookupRegistration.arguments, [11]);

        final registration = await client.matchWampRegistrationDirect(
          'app.echo',
          id: 'grant-direct-registration-match',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-match',
          },
        );
        expect(registration.arguments, [11]);

        final registrationDetails = await client.getWampRegistrationDirect(
          11,
          id: 'grant-direct-registration-get',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-get',
          },
        );
        expect(registrationDetails.argumentsKeywords['uri'], 'app.echo');

        final callees = await client.listWampRegistrationCalleesDirect(
          11,
          id: 'grant-direct-registration-callees',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-callees',
          },
        );
        expect(callees.arguments, [101]);

        final calleeCount = await client.countWampRegistrationCalleesDirect(
          11,
          id: 'grant-direct-registration-callee-count',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-registration-callee-count',
          },
        );
        expect(calleeCount.arguments, [1]);

        final subscriptions = await client.listWampSubscriptionsDirect(
          id: 'grant-direct-subscription-list',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscription-list',
          },
        );
        expect(subscriptions.argumentsKeywords['exact'], [7]);

        final lookupSubscription = await client.lookupWampSubscriptionDirect(
          'app.events.audit',
          match: 'exact',
          id: 'grant-direct-subscription-lookup',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscription-lookup',
          },
        );
        expect(lookupSubscription.arguments, [7]);

        final matchingSubscription = await client.matchWampSubscriptionDirect(
          'app.events.audit.created',
          id: 'grant-direct-subscription-match',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscription-match',
          },
        );
        expect(matchingSubscription.arguments, [7]);

        final subscriptionDetails = await client.getWampSubscriptionDirect(
          7,
          id: 'grant-direct-subscription-get',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscription-get',
          },
        );
        expect(
          subscriptionDetails.argumentsKeywords['uri'],
          'app.events.audit',
        );

        final subscribers = await client.listWampSubscriptionSubscribersDirect(
          7,
          id: 'grant-direct-subscription-subscribers',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscription-subscribers',
          },
        );
        expect(subscribers.arguments, [102]);

        final subscriberCount = await client
            .countWampSubscriptionSubscribersDirect(
              7,
              id: 'grant-direct-subscription-subscriber-count',
              headers: const <String, String>{
                HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
                'x-consumer-trace':
                    'grant-direct-subscription-subscriber-count',
              },
            );
        expect(subscriberCount.arguments, [1]);

        final resources = await client.listResourcesDirect(
          id: 'grant-direct-resources',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-resources',
          },
        );
        expect(resources.resources.single['uri'], 'wamp://app/readme');

        final resourceContents = await client.readResourceDirect(
          'wamp://app/readme',
          id: 'grant-direct-resource-read',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-resource-read',
          },
        );
        expect(resourceContents.single['text'], 'hello resource');

        final resourceTemplates = await client.listResourceTemplatesDirect(
          id: 'grant-direct-resource-templates',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-resource-templates',
          },
        );
        expect(
          resourceTemplates.resourceTemplates.single['uriTemplate'],
          'wamp://app/{name}',
        );

        final prompts = await client.listPromptsDirect(
          id: 'grant-direct-prompts',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-prompts',
          },
        );
        expect(prompts.prompts.single['name'], 'summarize');

        final prompt = await client.getPromptDirect(
          'summarize',
          id: 'grant-direct-prompt-get',
          arguments: const <String, String>{'topic': 'audit'},
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-prompt-get',
          },
        );
        expect(jsonEncode(prompt['messages']), contains('Summarize audit'));

        final subscription = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'grant-direct-subscribe',
          queueLimit: 2,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-subscribe',
          },
        );
        expect(subscription.handle, 'wamp-sub-1');
        expect(subscription.topic, 'app.events.audit');

        final publication = await client.publishWampEventDirect(
          'app.events.audit',
          id: 'grant-direct-publish',
          argumentsKeywords: const <String, Object?>{'message': 'hello'},
          acknowledge: true,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-publish',
          },
        );
        expect(publication.acknowledged, isTrue);
        expect(publication.publicationId, 42);

        final events = await client.pollWampEventsDirect(
          subscription.handle,
          id: 'grant-direct-poll',
          limit: 1,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-poll',
          },
        );
        expect(events.events.single['argumentsKeywords'], {'message': 'hello'});

        final unsubscribe = await client.unsubscribeWampTopicDirect(
          subscription.handle,
          id: 'grant-direct-unsubscribe',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-unsubscribe',
          },
        );
        expect(unsubscribe.unsubscribed, isTrue);

        await client.notifyToolDirect(
          'app.echo',
          arguments: const <String, Object?>{'message': 'tool notification'},
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-tool-notification',
          },
        );

        await client.notifyConnectanumToolDirect(
          'connectanum.pubsub.publish',
          arguments: const <String, Object?>{
            'topic': 'app.events.audit',
            'argumentsKeywords': <String, Object?>{
              'message': 'tool pubsub notification',
            },
          },
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-tool-pubsub-notification',
          },
        );

        await client.notifyConnectanumMethodDirect(
          'connectanum.pubsub.publish',
          params: const <String, Object?>{
            'topic': 'app.events.audit',
            'argumentsKeywords': <String, Object?>{
              'message': 'method pubsub notification',
            },
          },
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-method-pubsub-notification',
          },
        );

        await client.notifyWampEventDirect(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{
            'message': 'typed pubsub notification',
          },
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-wamp-pubsub-notification',
          },
        );

        final batch = await client.postBatchDirect(
          const <McpJsonMap>[
            {'jsonrpc': '2.0', 'id': 'grant-direct-batch', 'method': 'ping'},
          ],
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer per-call-stale-token',
            'x-consumer-trace': 'grant-direct-batch',
          },
        );
        expect(batch, hasLength(1));
        expect(batch?.single['id'], 'grant-direct-batch');

        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);
        expect(
          endpoint.requests.map((request) => request.authorization),
          everyElement('Bearer grant-direct-token'),
        );
        expect(
          endpoint.requests.map((request) => request.accept),
          everyElement('application/json'),
        );
        expect(
          endpoint.requests.map((request) => request.sessionId),
          everyElement(isNull),
        );
        expect(
          endpoint.requests.map((request) => request.lastEventId),
          everyElement(isNull),
        );
        final notificationRequests = endpoint.requests
            .where(
              (request) => const <String>{
                'grant-direct-tool-notification',
                'grant-direct-tool-pubsub-notification',
                'grant-direct-method-pubsub-notification',
                'grant-direct-wamp-pubsub-notification',
              }.contains(request.consumerTrace),
            )
            .toList();
        expect(notificationRequests, hasLength(4));
        expect(
          notificationRequests.map((request) {
            final body = _jsonMapFrom(
              request.body,
              label: 'notification request body',
            );
            return body.containsKey('id');
          }),
          everyElement(isFalse),
        );
        expect(notificationRequests.map((request) => request.mcpMethod), [
          'tools/call',
          'connectanum.tool.call',
          'connectanum.pubsub.publish',
          'connectanum.pubsub.publish',
        ]);
        expect(endpoint.requests[0].consumerTrace, 'grant-direct-ping');
        expect(endpoint.requests[1].consumerTrace, 'grant-direct-tools');
        expect(endpoint.requests[2].consumerTrace, 'grant-direct-api-list');
        expect(
          endpoint.requests
              .map((request) => request.consumerTrace)
              .skip(3)
              .take(29),
          [
            'grant-direct-session-count',
            'grant-direct-session-list',
            'grant-direct-session-get',
            'grant-direct-registration-list',
            'grant-direct-registration-lookup',
            'grant-direct-registration-match',
            'grant-direct-registration-get',
            'grant-direct-registration-callees',
            'grant-direct-registration-callee-count',
            'grant-direct-subscription-list',
            'grant-direct-subscription-lookup',
            'grant-direct-subscription-match',
            'grant-direct-subscription-get',
            'grant-direct-subscription-subscribers',
            'grant-direct-subscription-subscriber-count',
            'grant-direct-resources',
            'grant-direct-resource-read',
            'grant-direct-resource-templates',
            'grant-direct-prompts',
            'grant-direct-prompt-get',
            'grant-direct-subscribe',
            'grant-direct-publish',
            'grant-direct-poll',
            'grant-direct-unsubscribe',
            'grant-direct-tool-notification',
            'grant-direct-tool-pubsub-notification',
            'grant-direct-method-pubsub-notification',
            'grant-direct-wamp-pubsub-notification',
            'grant-direct-batch',
          ],
        );
        expect(
          endpoint.requests
              .map((request) => request.mcpName)
              .whereType<String>(),
          [
            'connectanum.api.list',
            'wamp.session.count',
            'wamp.session.list',
            'wamp.session.get',
            'wamp.registration.list',
            'wamp.registration.lookup',
            'wamp.registration.match',
            'wamp.registration.get',
            'wamp.registration.list_callees',
            'wamp.registration.count_callees',
            'wamp.subscription.list',
            'wamp.subscription.lookup',
            'wamp.subscription.match',
            'wamp.subscription.get',
            'wamp.subscription.list_subscribers',
            'wamp.subscription.count_subscribers',
            'wamp://app/readme',
            'summarize',
            'connectanum.pubsub.subscribe',
            'connectanum.pubsub.publish',
            'connectanum.pubsub.poll',
            'connectanum.pubsub.unsubscribe',
            'app.echo',
            'connectanum.pubsub.publish',
          ],
        );
      },
    );

    test(
      'allows plain clients to send per-call authorization headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize(
          id: 'plain-auth-initialize',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer plain-per-call-token',
          },
        );

        expect(
          endpoint.requests.single.authorization,
          'Bearer plain-per-call-token',
        );
      },
    );

    test('rejects non-bearer HTTP auth grants', () {
      expect(
        () => McpStreamableHttpClient.withAuthGrant(
          Uri.parse('http://127.0.0.1/mcp'),
          const ConnectanumHttpAuthGrant(
            accessToken: 'grant-token',
            tokenType: 'mac',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid MCP tool names before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final name in const [
        '',
        'bad tool',
        'bad/tool',
        'bad:tool',
        'bad\u00a0tool',
      ]) {
        await expectLater(
          client.callTool(name, id: 'invalid-tool-name'),
          throwsArgumentError,
        );
        expect(() => client.notifyTool(name), throwsArgumentError);
        await expectLater(
          client.callToolDirect(name, id: 'invalid-tool-name-direct'),
          throwsArgumentError,
        );
        expect(() => client.notifyToolDirect(name), throwsArgumentError);
        await expectLater(
          client.callConnectanumToolDirect(
            name,
            id: 'invalid-connectanum-tool-name-direct',
          ),
          throwsArgumentError,
        );
        expect(
          () => client.notifyConnectanumToolDirect(name),
          throwsArgumentError,
        );
      }

      expect(endpoint.requests, isEmpty);
    });

    test(
      'rejects invalid resource URIs and prompt names before sending',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        for (final uri in const [
          '',
          'readme',
          '/relative/readme',
          'app://bad resource',
          'app://bad\nresource',
        ]) {
          await expectLater(
            client.readResource(uri, id: 'invalid-resource-uri'),
            throwsArgumentError,
          );
          await expectLater(
            client.readResourceDirect(uri, id: 'invalid-resource-uri-direct'),
            throwsArgumentError,
          );
        }

        for (final promptName in const ['', 'bad prompt', 'bad\nprompt']) {
          await expectLater(
            client.getPrompt(promptName, id: 'invalid-prompt-name'),
            throwsArgumentError,
          );
          await expectLater(
            client.getPromptDirect(
              promptName,
              id: 'invalid-prompt-name-direct',
            ),
            throwsArgumentError,
          );
        }

        expect(endpoint.requests, isEmpty);
      },
    );

    test('lists and calls tools through typed helpers', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final page = await client.listTools(
        id: 'tools-helper',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'typed-tools-list'},
      );
      expect(page.nextCursor, isNull);
      expect(page.tools, hasLength(1));
      expect(page.tools.single['name'], 'app.echo');

      final result = await client.callTool(
        'app.echo',
        id: 'call-helper',
        arguments: {
          'message': 'hello',
          'attempt': 2,
          'dryRun': true,
          'note': ' padded ',
          'wrapper': '=?base64?Zm9v?=',
        },
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'typed-tool-call'},
      );
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {
        'echo': {
          'message': 'hello',
          'attempt': 2,
          'dryRun': true,
          'note': ' padded ',
          'wrapper': '=?base64?Zm9v?=',
        },
      });

      await expectLater(
        client.callTool('app.fail', id: 'call-failure', streamable: false),
        throwsA(
          isA<McpJsonRpcException>()
              .having((error) => error.id, 'id', 'call-failure')
              .having((error) => error.method, 'method', 'tools/call')
              .having(
                (error) => error.error['message'],
                'message',
                'tool failed',
              ),
        ),
      );

      final lastEventIdBeforeNotification = client.lastEventId;
      await client.notifyTool(
        'app.echo',
        arguments: const <String, Object?>{'message': 'notify'},
        headers: const <String, String>{
          'x-consumer-trace': 'typed-tool-notify',
          'Mcp-Param-Message': 'wrong',
        },
      );
      expect(client.lastEventId, lastEventIdBeforeNotification);

      expect(endpoint.requests[2].mcpMethod, 'tools/list');
      expect(endpoint.requests[2].mcpName, isNull);
      expect(endpoint.requests[2].consumerTrace, 'typed-tools-list');
      expect(endpoint.requests[3].mcpMethod, 'tools/call');
      expect(endpoint.requests[3].mcpName, 'app.echo');
      expect(endpoint.requests[3].consumerTrace, 'typed-tool-call');
      expect(endpoint.requests[3].mcpParameterHeaders, {
        'mcp-param-message': 'hello',
        'mcp-param-attempt': '2',
        'mcp-param-dryrun': 'true',
        'mcp-param-note': '=?base64?${base64Encode(utf8.encode(' padded '))}?=',
        'mcp-param-wrapper':
            '=?base64?${base64Encode(utf8.encode('=?base64?Zm9v?='))}?=',
      });
      expect(endpoint.requests[4].mcpMethod, 'tools/call');
      expect(endpoint.requests[4].mcpName, 'app.fail');
      expect(endpoint.requests[4].mcpParameterHeaders, isEmpty);
      expect(endpoint.requests[5].mcpMethod, 'tools/call');
      expect(endpoint.requests[5].mcpName, 'app.echo');
      expect(endpoint.requests[5].sessionId, 'session-1');
      expect(endpoint.requests[5].accept, contains('text/event-stream'));
      expect(endpoint.requests[5].consumerTrace, 'typed-tool-notify');
      expect(endpoint.requests[5].mcpParameterHeaders, {
        'mcp-param-message': 'notify',
      });
      expect(endpoint.requests[5].body, {
        'jsonrpc': '2.0',
        'method': 'tools/call',
        'params': {
          'name': 'app.echo',
          'arguments': {'message': 'notify'},
        },
      });
    });

    test('uses standard direct JSON helpers without MCP lifecycle', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final ping = await client.pingDirect(
        id: 'direct-ping',
        headers: const <String, String>{'x-consumer-trace': 'direct-ping'},
      );
      expect(ping, isEmpty);

      final page = await client.listToolsDirect(
        id: 'direct-tools',
        headers: const <String, String>{
          'x-consumer-trace': 'direct-tools-list',
        },
      );
      expect(page.nextCursor, isNull);
      expect(page.tools.map((tool) => tool['name']), contains('app.echo'));

      final result = await client.callToolDirect(
        'app.echo',
        id: 'direct-call',
        arguments: const <String, Object?>{'message': 'direct'},
        headers: const <String, String>{'x-consumer-trace': 'direct-tool-call'},
      );
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {
        'echo': {'message': 'direct'},
      });

      await client.notifyToolDirect(
        'app.echo',
        arguments: const <String, Object?>{'message': 'direct-notify'},
        headers: const <String, String>{
          'x-consumer-trace': 'direct-tool-notify',
          'Mcp-Param-Message': 'wrong',
        },
      );

      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);
      expect(endpoint.requests, hasLength(4));
      for (final request in endpoint.requests) {
        expect(request.accept, 'application/json');
        expect(request.sessionId, isNull);
      }
      expect(endpoint.requests[0].mcpMethod, 'ping');
      expect(endpoint.requests[0].consumerTrace, 'direct-ping');
      expect(endpoint.requests[1].mcpMethod, 'tools/list');
      expect(endpoint.requests[1].consumerTrace, 'direct-tools-list');
      expect(endpoint.requests[2].mcpMethod, 'tools/call');
      expect(endpoint.requests[2].mcpName, 'app.echo');
      expect(endpoint.requests[2].consumerTrace, 'direct-tool-call');
      expect(endpoint.requests[2].mcpParameterHeaders, {
        'mcp-param-message': 'direct',
      });
      expect(endpoint.requests[3].mcpMethod, 'tools/call');
      expect(endpoint.requests[3].mcpName, 'app.echo');
      expect(endpoint.requests[3].consumerTrace, 'direct-tool-notify');
      expect(endpoint.requests[3].mcpParameterHeaders, {
        'mcp-param-message': 'direct-notify',
      });
      expect(endpoint.requests[3].body, {
        'jsonrpc': '2.0',
        'method': 'tools/call',
        'params': {
          'name': 'app.echo',
          'arguments': {'message': 'direct-notify'},
        },
      });
    });

    test(
      'uses Connectanum direct JSON helpers without MCP lifecycle',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final page = await client.listConnectanumToolsDirect(
          id: 'direct-tools',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-tools-list',
          },
        );
        expect(page.nextCursor, isNull);
        expect(page.tools.map((tool) => tool['name']), contains('app.echo'));

        final rawResponse = await client.requestDirect(
          'connectanum.tools.list',
          id: 'direct-request-tools',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-request-tools',
          },
        );
        final rawResult = _jsonMapFrom(
          rawResponse['result'],
          label: 'direct request result',
        );
        expect(jsonEncode(rawResult['tools']), contains('app.echo'));

        final rawPostResponse = await client.postDirect(
          {
            'jsonrpc': '2.0',
            'id': 'direct-post-tools',
            'method': 'connectanum.tools.list',
          },
          headers: const <String, String>{
            'x-consumer-trace': 'direct-post-tools',
          },
        );
        final rawPostResult = _jsonMapFrom(
          rawPostResponse?['result'],
          label: 'direct post result',
        );
        expect(jsonEncode(rawPostResult['tools']), contains('app.echo'));

        const directToolArguments = <String, Object?>{
          'message': 'direct',
          'attempt': 3,
          'dryRun': false,
          'note': ' spaced ',
          'wrapper': '=?base64?Zm9v?=',
        };

        final toolResult = await client.callConnectanumToolDirect(
          'app.echo',
          id: 'direct-call',
          arguments: directToolArguments,
          headers: const <String, String>{
            'x-consumer-trace': 'direct-tool-call',
          },
        );
        expect(toolResult['isError'], isFalse);
        expect(toolResult['structuredContent'], {'echo': directToolArguments});
        await client.notifyConnectanumToolDirect(
          'app.echo',
          arguments: directToolArguments,
          headers: const <String, String>{
            'x-consumer-trace': 'direct-tool-notify',
          },
        );

        final aliasResult = await client.callConnectanumMethodDirect(
          'connectanum.tools.call',
          id: 'direct-alias',
          params: const <String, Object?>{
            'name': 'app.echo',
            'arguments': <String, Object?>{'message': 'alias'},
          },
          headers: const <String, String>{
            'x-consumer-trace': 'direct-alias-method',
            'Mcp-Param-Message': 'wrong',
          },
        );
        expect(aliasResult['isError'], isFalse);
        expect(aliasResult['structuredContent'], {
          'echo': {'message': 'alias'},
        });

        final methodResult = await client.callConnectanumMethodDirect(
          'app.echo',
          id: 'direct-dotted',
          params: {'message': 'dotted'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-dotted-method',
            'Mcp-Param-Message': 'wrong',
          },
        );
        expect(methodResult['isError'], isFalse);
        expect(methodResult['structuredContent'], {
          'echo': {'message': 'dotted'},
        });

        final metaResult = await client.callConnectanumMethodDirect(
          'wamp.registration.match',
          id: 'direct-meta',
          params: {
            'arguments': ['app.echo'],
          },
          headers: const <String, String>{
            'x-consumer-trace': 'direct-meta-method',
          },
        );
        expect(metaResult['structuredContent'], {
          'arguments': [11],
        });

        expect(client.sessionId, isNull);
        expect(endpoint.requests, hasLength(8));
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.sessionId, isNull);
          expect(request.mcpMethod, isNotEmpty);
        }
        final expectedDirectToolHeaders = <String, String>{
          'mcp-param-message': 'direct',
          'mcp-param-attempt': '3',
          'mcp-param-dryrun': 'false',
          'mcp-param-note':
              '=?base64?${base64Encode(utf8.encode(' spaced '))}?=',
          'mcp-param-wrapper':
              '=?base64?${base64Encode(utf8.encode('=?base64?Zm9v?='))}?=',
        };
        expect(endpoint.requests[0].mcpMethod, 'connectanum.tools.list');
        expect(endpoint.requests[0].consumerTrace, 'direct-tools-list');
        expect(endpoint.requests[1].mcpMethod, 'connectanum.tools.list');
        expect(endpoint.requests[1].consumerTrace, 'direct-request-tools');
        expect(endpoint.requests[2].mcpMethod, 'connectanum.tools.list');
        expect(endpoint.requests[2].consumerTrace, 'direct-post-tools');
        expect(endpoint.requests[3].mcpMethod, 'connectanum.tool.call');
        expect(endpoint.requests[3].mcpName, 'app.echo');
        expect(endpoint.requests[3].consumerTrace, 'direct-tool-call');
        expect(
          endpoint.requests[3].mcpParameterHeaders,
          expectedDirectToolHeaders,
        );
        expect(endpoint.requests[4].mcpMethod, 'connectanum.tool.call');
        expect(endpoint.requests[4].mcpName, 'app.echo');
        expect(endpoint.requests[4].consumerTrace, 'direct-tool-notify');
        expect(
          endpoint.requests[4].mcpParameterHeaders,
          expectedDirectToolHeaders,
        );
        expect(endpoint.requests[5].mcpMethod, 'connectanum.tools.call');
        expect(endpoint.requests[5].mcpName, 'app.echo');
        expect(endpoint.requests[5].consumerTrace, 'direct-alias-method');
        expect(endpoint.requests[5].mcpParameterHeaders, {
          'mcp-param-message': 'alias',
        });
        expect(endpoint.requests[6].mcpMethod, 'app.echo');
        expect(endpoint.requests[6].consumerTrace, 'direct-dotted-method');
        expect(endpoint.requests[6].mcpParameterHeaders, {
          'mcp-param-message': 'dotted',
        });
        expect(endpoint.requests[7].consumerTrace, 'direct-meta-method');
        expect(
          endpoint.requests.first.body,
          containsPair('method', 'connectanum.tools.list'),
        );
        expect(endpoint.requests[4].body, {
          'jsonrpc': '2.0',
          'method': 'connectanum.tool.call',
          'params': {'name': 'app.echo', 'arguments': directToolArguments},
        });
        expect(endpoint.requests.last.body, {
          'jsonrpc': '2.0',
          'id': 'direct-meta',
          'method': 'wamp.registration.match',
          'params': {
            'arguments': ['app.echo'],
          },
        });
      },
    );

    test('uses Connectanum method helper on Streamable sessions', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.listConnectanumToolsDirect(id: 'streamable-method-catalog');
      await client.initialize();
      await client.notifyInitialized();
      endpoint.requests.clear();

      final result = await client.callConnectanumMethod(
        'app.echo',
        id: 'streamable-method-call',
        params: const <String, Object?>{'message': 'streamable'},
        headers: const <String, String>{
          'Mcp-Param-Message': 'wrong',
          'x-consumer-trace': 'streamable-method-call',
        },
      );

      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {
        'echo': {'message': 'streamable'},
      });
      expect(client.sessionId, 'session-1');
      expect(endpoint.requests, hasLength(1));
      expect(endpoint.requests.single.accept, contains('text/event-stream'));
      expect(endpoint.requests.single.sessionId, 'session-1');
      expect(endpoint.requests.single.mcpMethod, 'app.echo');
      expect(endpoint.requests.single.consumerTrace, 'streamable-method-call');
      expect(endpoint.requests.single.mcpParameterHeaders, {
        'mcp-param-message': 'streamable',
      });

      final eventIdBeforeNotification = client.lastEventId;
      await client.notifyConnectanumMethod(
        'app.echo',
        params: const <String, Object?>{'message': 'streamable-notify'},
        headers: const <String, String>{
          'Mcp-Param-Message': 'wrong',
          'x-consumer-trace': 'streamable-method-notify',
        },
      );

      expect(client.sessionId, 'session-1');
      expect(client.lastEventId, eventIdBeforeNotification);
      expect(endpoint.requests, hasLength(2));
      expect(endpoint.requests.last.accept, contains('text/event-stream'));
      expect(endpoint.requests.last.sessionId, 'session-1');
      expect(endpoint.requests.last.mcpMethod, 'app.echo');
      expect(endpoint.requests.last.consumerTrace, 'streamable-method-notify');
      expect(endpoint.requests.last.mcpParameterHeaders, {
        'mcp-param-message': 'streamable-notify',
      });
      expect(endpoint.requests.last.body, {
        'jsonrpc': '2.0',
        'method': 'app.echo',
        'params': {'message': 'streamable-notify'},
      });
    });

    test(
      'reuses direct JSON tool catalog for later Streamable custom headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final page = await client.listToolsDirect(id: 'direct-catalog');
        expect(page.tools.map((tool) => tool['name']), contains('app.echo'));

        await client.initialize();
        await client.notifyInitialized();

        final result = await client.callTool(
          'app.echo',
          id: 'streamable-after-direct-catalog',
          arguments: {
            'message': 'from-direct-catalog',
            'attempt': 3,
            'dryRun': false,
            'note': ' spaced ',
            'wrapper': '=?base64?Zm9v?=',
          },
        );
        expect(result['isError'], isFalse);
        expect(result['structuredContent'], {
          'echo': {
            'message': 'from-direct-catalog',
            'attempt': 3,
            'dryRun': false,
            'note': ' spaced ',
            'wrapper': '=?base64?Zm9v?=',
          },
        });

        expect(endpoint.requests[0].mcpMethod, 'tools/list');
        expect(endpoint.requests[0].accept, 'application/json');
        expect(endpoint.requests[1].mcpMethod, 'initialize');
        expect(endpoint.requests[2].mcpMethod, 'notifications/initialized');
        expect(endpoint.requests[3].mcpMethod, 'tools/call');
        expect(endpoint.requests[3].mcpName, 'app.echo');
        expect(endpoint.requests[3].mcpParameterHeaders, {
          'mcp-param-message': 'from-direct-catalog',
          'mcp-param-attempt': '3',
          'mcp-param-dryrun': 'false',
          'mcp-param-note':
              '=?base64?${base64Encode(utf8.encode(' spaced '))}?=',
          'mcp-param-wrapper':
              '=?base64?${base64Encode(utf8.encode('=?base64?Zm9v?='))}?=',
        });
      },
    );

    test('uses typed helpers for resources and prompts', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final resources = await client.listResources(
        id: 'resources-helper',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'resources-list-helper',
        },
      );
      expect(resources.nextCursor, isNull);
      expect(resources.resources, hasLength(1));
      expect(resources.resources.single['uri'], 'wamp://app/readme');

      final contents = await client.readResource(
        'wamp://app/readme',
        id: 'resource-read',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'resource-read-helper',
        },
      );
      expect(contents, hasLength(1));
      expect(contents.single['text'], 'hello resource');

      final templates = await client.listResourceTemplates(
        id: 'resource-templates-helper',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'resource-templates-helper',
        },
      );
      expect(templates.nextCursor, isNull);
      expect(templates.resourceTemplates, hasLength(1));
      expect(
        templates.resourceTemplates.single['uriTemplate'],
        'wamp://app/{name}',
      );

      final prompts = await client.listPrompts(
        id: 'prompts-helper',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'prompts-list-helper',
        },
      );
      expect(prompts.nextCursor, isNull);
      expect(prompts.prompts, hasLength(1));
      expect(prompts.prompts.single['name'], 'summarize');

      final prompt = await client.getPrompt(
        'summarize',
        id: 'prompt-get',
        arguments: {'topic': 'mcp'},
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'prompt-get-helper',
        },
      );
      expect(prompt['description'], 'Summarizes a topic.');
      expect(prompt['messages'], hasLength(1));

      await expectLater(
        client.getPrompt('missing', id: 'prompt-missing', streamable: false),
        throwsA(
          isA<McpJsonRpcException>()
              .having((error) => error.id, 'id', 'prompt-missing')
              .having((error) => error.method, 'method', 'prompts/get')
              .having(
                (error) => error.error['message'],
                'message',
                'prompt not found',
              ),
        ),
      );

      expect(endpoint.requests[3].mcpMethod, 'resources/read');
      expect(endpoint.requests[3].mcpName, 'wamp://app/readme');
      expect(endpoint.requests[2].consumerTrace, 'resources-list-helper');
      expect(endpoint.requests[3].consumerTrace, 'resource-read-helper');
      expect(endpoint.requests[4].consumerTrace, 'resource-templates-helper');
      expect(endpoint.requests[5].consumerTrace, 'prompts-list-helper');
      expect(endpoint.requests[6].mcpMethod, 'prompts/get');
      expect(endpoint.requests[6].mcpName, 'summarize');
      expect(endpoint.requests[6].consumerTrace, 'prompt-get-helper');
      expect(endpoint.requests[7].mcpMethod, 'prompts/get');
      expect(endpoint.requests[7].mcpName, 'missing');
    });

    test(
      'uses typed resource and prompt helpers through direct JSON without session headers',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        expect(client.sessionId, 'session-1');
        endpoint.requests.clear();

        final resources = await client.listResourcesDirect(
          id: 'direct-resources-helper',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-resources-list-helper',
          },
        );
        expect(resources.resources.single['uri'], 'wamp://app/readme');

        final contents = await client.readResourceDirect(
          'wamp://app/readme',
          id: 'direct-resource-read',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-resource-read-helper',
          },
        );
        expect(contents.single['text'], 'hello resource');

        final templates = await client.listResourceTemplatesDirect(
          id: 'direct-resource-templates-helper',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-resource-templates-helper',
          },
        );
        expect(
          templates.resourceTemplates.single['uriTemplate'],
          'wamp://app/{name}',
        );

        final prompts = await client.listPromptsDirect(
          id: 'direct-prompts-helper',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-prompts-list-helper',
          },
        );
        expect(prompts.prompts.single['name'], 'summarize');

        final prompt = await client.getPromptDirect(
          'summarize',
          id: 'direct-prompt-get',
          arguments: {'topic': 'mcp'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-prompt-get-helper',
          },
        );
        expect(prompt['messages'], hasLength(1));

        expect(client.sessionId, 'session-1');
        expect(endpoint.requests, hasLength(5));
        expect(
          endpoint.requests.map((request) => (request.body as Map)['method']),
          [
            'resources/list',
            'resources/read',
            'resources/templates/list',
            'prompts/list',
            'prompts/get',
          ],
        );
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.sessionId, isNull);
          expect(request.mcpMethod, isNotEmpty);
        }
        expect(endpoint.requests[1].mcpMethod, 'resources/read');
        expect(endpoint.requests[1].mcpName, 'wamp://app/readme');
        expect(
          endpoint.requests[0].consumerTrace,
          'direct-resources-list-helper',
        );
        expect(
          endpoint.requests[1].consumerTrace,
          'direct-resource-read-helper',
        );
        expect(
          endpoint.requests[2].consumerTrace,
          'direct-resource-templates-helper',
        );
        expect(
          endpoint.requests[3].consumerTrace,
          'direct-prompts-list-helper',
        );
        expect(endpoint.requests[4].mcpMethod, 'prompts/get');
        expect(endpoint.requests[4].mcpName, 'summarize');
        expect(endpoint.requests[4].consumerTrace, 'direct-prompt-get-helper');
      },
    );

    test('uses Connectanum WAMP tool helpers for API and pubsub', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final catalog = await client.listWampApi(
        id: 'wamp-api-list',
        kind: 'topic',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'wamp-api-list'},
      );
      expect(catalog['topics'], hasLength(1));
      expect(
        (catalog['topics'] as List).single,
        containsPair('topic', 'app.events.audit'),
      );

      final topic = await client.describeWampApi(
        'app.events.audit',
        id: 'wamp-api-describe',
        kind: 'topic',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-api-describe',
        },
      );
      expect(topic['topic'], 'app.events.audit');

      final subscription = await client.subscribeWampTopic(
        'app.events.audit',
        id: 'wamp-subscribe',
        queueLimit: 3,
        options: mcpWampSubscribeOptions(
          match: 'exact',
          metaTopic: 'app.events.audit.meta',
          getRetained: true,
          custom: const <String, Object?>{
            'x_consumer_subscription': 'custom-subscribe',
            'match': 'custom-match',
          },
        ),
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'wamp-subscribe'},
      );
      expect(subscription.handle, 'wamp-sub-1');
      expect(subscription.topic, 'app.events.audit');
      expect(subscription.subscriptionId, 7);
      expect(subscription.queueLimit, 3);

      final publication = await client.publishWampEvent(
        'app.events.audit',
        id: 'wamp-publish',
        argumentsKeywords: const <String, Object?>{'message': 'hello'},
        options: mcpWampPublishOptions(
          acknowledge: true,
          excludeMe: false,
          discloseMe: true,
          pptScheme: 'wamp',
          custom: const <String, Object?>{
            'x_consumer_trace': 'custom-publish',
            'acknowledge': false,
          },
        ),
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'wamp-publish'},
      );
      expect(publication.topic, 'app.events.audit');
      expect(publication.publicationId, 42);
      expect(publication.acknowledged, isTrue);

      await client.notifyWampEvent(
        'app.events.audit',
        argumentsKeywords: const <String, Object?>{'message': 'notify'},
        headers: const <String, String>{
          'Mcp-Param-Topic': 'wrong',
          'x-consumer-trace': 'wamp-notify',
        },
      );

      final batch = await client.pollWampEvents(
        subscription.handle,
        id: 'wamp-poll',
        limit: 2,
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'wamp-poll'},
      );
      expect(batch.handle, subscription.handle);
      expect(batch.topic, 'app.events.audit');
      expect(batch.dropped, 0);
      expect(batch.remaining, 0);
      expect(batch.events, hasLength(1));
      expect(batch.events.single['argumentsKeywords'], {'message': 'hello'});

      final unsubscribe = await client.unsubscribeWampTopic(
        subscription.handle,
        id: 'wamp-unsubscribe',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'wamp-unsubscribe'},
      );
      expect(unsubscribe.handle, subscription.handle);
      expect(unsubscribe.topic, 'app.events.audit');
      expect(unsubscribe.unsubscribed, isTrue);

      await expectLater(
        client.subscribeWampTopic(
          'app.secure.audit',
          id: 'wamp-denied',
          streamable: false,
          headers: const <String, String>{'x-consumer-trace': 'wamp-denied'},
        ),
        throwsA(
          isA<McpStreamableWampToolException>()
              .having(
                (error) => error.toolName,
                'toolName',
                'connectanum.pubsub.subscribe',
              )
              .having(
                (error) => error.message,
                'message',
                'not authorized for topic',
              ),
        ),
      );
      expect(
        endpoint.requests.skip(2).map((request) => request.consumerTrace),
        [
          'wamp-api-list',
          'wamp-api-describe',
          'wamp-subscribe',
          'wamp-publish',
          'wamp-notify',
          'wamp-poll',
          'wamp-unsubscribe',
          'wamp-denied',
        ],
      );
      final subscribeBody = _jsonMapFrom(
        endpoint.requests[4].body,
        label: 'WAMP subscribe request body',
      );
      final subscribeParams = _jsonMapFrom(
        subscribeBody['params'],
        label: 'WAMP subscribe params',
      );
      final subscribeArguments = _jsonMapFrom(
        subscribeParams['arguments'],
        label: 'WAMP subscribe arguments',
      );
      expect(subscribeArguments['options'], {
        'x_consumer_subscription': 'custom-subscribe',
        'match': 'exact',
        'meta_topic': 'app.events.audit.meta',
        'get_retained': true,
      });
      final publishBody = _jsonMapFrom(
        endpoint.requests[5].body,
        label: 'WAMP publish request body',
      );
      final publishParams = _jsonMapFrom(
        publishBody['params'],
        label: 'WAMP publish params',
      );
      final publishArguments = _jsonMapFrom(
        publishParams['arguments'],
        label: 'WAMP publish arguments',
      );
      expect(publishArguments['options'], {
        'x_consumer_trace': 'custom-publish',
        'acknowledge': true,
        'exclude_me': false,
        'disclose_me': true,
        'ppt_scheme': 'wamp',
      });
      expect(endpoint.requests[6].accept, contains('text/event-stream'));
      expect(endpoint.requests[6].sessionId, 'session-1');
      expect(endpoint.requests[6].mcpParameterHeaders, isEmpty);
      expect(
        _jsonMapFrom(endpoint.requests[6].body, label: 'notification body'),
        {
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': 'app.events.audit',
            'argumentsKeywords': {'message': 'notify'},
          },
        },
      );
    });

    test(
      'uses typed WAMP helpers through direct JSON without lifecycle',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        final catalog = await client.listWampApiDirect(
          id: 'direct-helper-api-list',
          kind: 'topic',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-api-list',
          },
        );
        expect(catalog['topics'], hasLength(1));

        final subscription = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'direct-helper-subscribe',
          queueLimit: 3,
          options: mcpWampSubscribeOptions(
            match: 'exact',
            custom: const <String, Object?>{
              'x_consumer_subscription': 'direct-custom-subscribe',
            },
          ),
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-subscribe',
          },
        );
        expect(subscription.handle, 'wamp-sub-1');

        final publication = await client.publishWampEventDirect(
          'app.events.audit',
          id: 'direct-helper-publish',
          argumentsKeywords: const <String, Object?>{'message': 'hello'},
          options: mcpWampPublishOptions(
            acknowledge: true,
            excludeMe: false,
            custom: const <String, Object?>{
              'x_consumer_trace': 'direct-custom-publish',
            },
          ),
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-publish',
          },
        );
        expect(publication.acknowledged, isTrue);

        final batch = await client.pollWampEventsDirect(
          subscription.handle,
          id: 'direct-helper-poll',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-poll',
          },
        );
        expect(batch.events.single['argumentsKeywords'], {'message': 'hello'});

        final registration = await client.matchWampRegistrationDirect(
          'app.echo',
          id: 'direct-helper-registration-match',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-registration-match',
          },
        );
        expect(registration.arguments, [11]);

        final unsubscribe = await client.unsubscribeWampTopicDirect(
          subscription.handle,
          id: 'direct-helper-unsubscribe',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-helper-unsubscribe',
          },
        );
        expect(unsubscribe.unsubscribed, isTrue);

        expect(client.sessionId, isNull);
        expect(endpoint.requests, hasLength(6));
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.sessionId, isNull);
          expect(request.body, containsPair('method', 'connectanum.tool.call'));
        }
        expect(endpoint.requests.map((request) => request.consumerTrace), [
          'direct-helper-api-list',
          'direct-helper-subscribe',
          'direct-helper-publish',
          'direct-helper-poll',
          'direct-helper-registration-match',
          'direct-helper-unsubscribe',
        ]);
        final firstParams = _jsonMapFrom(
          (endpoint.requests.first.body as Map)['params'],
          label: 'direct helper first params',
        );
        expect(
          _jsonMapFrom(
            firstParams['arguments'],
            label: 'direct API list arguments',
          ),
          {'kind': 'topic'},
        );
        expect(firstParams['name'], 'connectanum.api.list');
        final subscribeParams = _jsonMapFrom(
          (endpoint.requests[1].body as Map)['params'],
          label: 'direct helper subscribe params',
        );
        final subscribeArguments = _jsonMapFrom(
          subscribeParams['arguments'],
          label: 'direct helper subscribe arguments',
        );
        expect(subscribeArguments['options'], {
          'x_consumer_subscription': 'direct-custom-subscribe',
          'match': 'exact',
        });
        final publishParams = _jsonMapFrom(
          (endpoint.requests[2].body as Map)['params'],
          label: 'direct helper publish params',
        );
        final publishArguments = _jsonMapFrom(
          publishParams['arguments'],
          label: 'direct helper publish arguments',
        );
        expect(publishArguments['options'], {
          'x_consumer_trace': 'direct-custom-publish',
          'acknowledge': true,
          'exclude_me': false,
        });
      },
    );

    test('rejects invalid WAMP helper arguments before sending', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      Future<void> expectLocalArgumentError(
        FutureOr<Object?> Function() action,
      ) async {
        await expectLater(Future<Object?>.sync(action), throwsArgumentError);
        expect(endpoint.requests, isEmpty);
      }

      await expectLocalArgumentError(
        () => client.describeWampApi('bad topic', streamable: false),
      );
      await expectLocalArgumentError(
        () => client.callWampMetaProcedure('wamp.', streamable: false),
      );
      await expectLocalArgumentError(
        () => client.lookupWampRegistrationDirect('bad procedure'),
      );
      await expectLocalArgumentError(
        () => client.matchWampSubscription('bad\ntopic', streamable: false),
      );
      await expectLocalArgumentError(
        () => client.getWampSession(0, streamable: false),
      );
      await expectLocalArgumentError(
        () => client.getWampRegistrationDirect(-1),
      );
      await expectLocalArgumentError(
        () => client.listWampRegistrationCallees(0, streamable: false),
      );
      await expectLocalArgumentError(
        () => client.countWampRegistrationCalleesDirect(-1),
      );
      await expectLocalArgumentError(
        () => client.getWampSubscription(0, streamable: false),
      );
      await expectLocalArgumentError(
        () => client.listWampSubscriptionSubscribersDirect(-1),
      );
      await expectLocalArgumentError(
        () => client.countWampSubscriptionSubscribers(0, streamable: false),
      );
      await expectLocalArgumentError(
        () => client.publishWampEvent('', streamable: false),
      );
      await expectLocalArgumentError(
        () => client.notifyWampEvent('bad topic', streamable: false),
      );
      await expectLocalArgumentError(
        () =>
            client.subscribeWampTopicDirect('app.events.audit', queueLimit: 0),
      );
      await expectLocalArgumentError(
        () => client.subscribeWampTopic(
          'app.events.audit',
          queueLimit: -1,
          streamable: false,
        ),
      );
      await expectLocalArgumentError(
        () => client.pollWampEventsDirect('', limit: 1),
      );
      await expectLocalArgumentError(
        () => client.pollWampEvents('wamp-sub-1', limit: 0, streamable: false),
      );
      await expectLocalArgumentError(
        () => client.unsubscribeWampTopicDirect('bad handle'),
      );
    });

    test(
      'keeps direct WAMP helpers lifecycle-free with an active Streamable session',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        final catalog = await client.listWampApiDirect(
          id: 'direct-active-api-list',
          kind: 'topic',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-api-list',
          },
        );
        expect(catalog['topics'], hasLength(1));

        final topic = await client.describeWampApiDirect(
          'app.events.audit',
          id: 'direct-active-api-describe',
          kind: 'topic',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-api-describe',
          },
        );
        expect(topic['topic'], 'app.events.audit');

        final subscription = await client.subscribeWampTopicDirect(
          'app.events.audit',
          id: 'direct-active-subscribe',
          queueLimit: 3,
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-subscribe',
          },
        );
        expect(subscription.handle, 'wamp-sub-1');

        final publication = await client.publishWampEventDirect(
          'app.events.audit',
          id: 'direct-active-publish',
          argumentsKeywords: const <String, Object?>{'message': 'hello'},
          acknowledge: true,
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-publish',
          },
        );
        expect(publication.acknowledged, isTrue);

        final batch = await client.pollWampEventsDirect(
          subscription.handle,
          id: 'direct-active-poll',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-poll',
          },
        );
        expect(batch.events.single['argumentsKeywords'], {'message': 'hello'});

        final registration = await client.matchWampRegistrationDirect(
          'app.echo',
          id: 'direct-active-registration-match',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-registration-match',
          },
        );
        expect(registration.arguments, [11]);

        final unsubscribe = await client.unsubscribeWampTopicDirect(
          subscription.handle,
          id: 'direct-active-unsubscribe',
          headers: const <String, String>{
            'x-consumer-trace': 'direct-active-unsubscribe',
          },
        );
        expect(unsubscribe.unsubscribed, isTrue);

        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests, hasLength(7));
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.sessionId, isNull);
          expect(request.lastEventId, isNull);
          expect(request.mcpMethod, 'connectanum.tool.call');
          expect(request.body, containsPair('method', 'connectanum.tool.call'));
        }
        expect(endpoint.requests.map((request) => request.consumerTrace), [
          'direct-active-api-list',
          'direct-active-api-describe',
          'direct-active-subscribe',
          'direct-active-publish',
          'direct-active-poll',
          'direct-active-registration-match',
          'direct-active-unsubscribe',
        ]);
        expect(
          endpoint.requests.map(
            (request) => _jsonMapFrom(
              _jsonMapFrom(
                (request.body as Map)['params'],
                label: 'direct active params',
              )['arguments'],
              label: 'direct active arguments',
            ),
          ),
          [
            {'kind': 'topic'},
            {'uri': 'app.events.audit', 'kind': 'topic'},
            {'topic': 'app.events.audit', 'queueLimit': 3},
            {
              'topic': 'app.events.audit',
              'argumentsKeywords': {'message': 'hello'},
              'acknowledge': true,
            },
            {'handle': 'wamp-sub-1'},
            {
              'arguments': ['app.echo'],
            },
            {'handle': 'wamp-sub-1'},
          ],
        );
      },
    );

    test(
      'keeps direct Connectanum notifications lifecycle-free with active session',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        await client.notifyConnectanumToolDirect(
          'app.echo',
          arguments: const <String, Object?>{'message': 'uncached-notify'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notify-uncached-tool',
            'Mcp-Param-Message': 'wrong',
          },
        );
        expect(
          endpoint.requests.single.consumerTrace,
          'direct-notify-uncached-tool',
        );
        expect(endpoint.requests.single.mcpParameterHeaders, isEmpty);
        endpoint.requests.clear();

        await client.listConnectanumToolsDirect(id: 'direct-notify-catalog');
        endpoint.requests.clear();

        await client.notifyConnectanumToolDirect(
          'app.echo',
          arguments: const <String, Object?>{'message': 'tool-notify'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notify-tool',
            'Mcp-Param-Message': 'wrong',
          },
        );
        await client.notifyConnectanumMethodDirect(
          'app.echo',
          params: const <String, Object?>{'message': 'method-notify'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notify-method',
            'Mcp-Param-Message': 'wrong',
          },
        );
        await client.notifyConnectanumMethodDirect(
          'connectanum.tools.call',
          params: const <String, Object?>{
            'name': 'app.echo',
            'arguments': {'message': 'alias-notify'},
          },
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notify-alias-method',
            'Mcp-Param-Message': 'wrong',
          },
        );
        await client.notifyWampEventDirect(
          'app.events.audit',
          argumentsKeywords: const <String, Object?>{
            'message': 'pubsub-notify',
          },
          options: const <String, Object?>{'exclude_me': false},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notify-pubsub',
            'Mcp-Param-Topic': 'wrong',
          },
        );

        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests, hasLength(4));
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.sessionId, isNull);
          expect(request.lastEventId, isNull);
          expect(
            _jsonMapFrom(
              request.body,
              label: 'direct notification body',
            ).containsKey('id'),
            isFalse,
          );
        }
        expect(endpoint.requests.map((request) => request.consumerTrace), [
          'direct-notify-tool',
          'direct-notify-method',
          'direct-notify-alias-method',
          'direct-notify-pubsub',
        ]);
        expect(endpoint.requests[0].body, {
          'jsonrpc': '2.0',
          'method': 'connectanum.tool.call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'tool-notify'},
          },
        });
        expect(endpoint.requests[0].mcpName, 'app.echo');
        expect(endpoint.requests[0].mcpParameterHeaders, {
          'mcp-param-message': 'tool-notify',
        });
        expect(endpoint.requests[1].body, {
          'jsonrpc': '2.0',
          'method': 'app.echo',
          'params': {'message': 'method-notify'},
        });
        expect(endpoint.requests[1].mcpParameterHeaders, {
          'mcp-param-message': 'method-notify',
        });
        expect(endpoint.requests[2].body, {
          'jsonrpc': '2.0',
          'method': 'connectanum.tools.call',
          'params': {
            'name': 'app.echo',
            'arguments': {'message': 'alias-notify'},
          },
        });
        expect(endpoint.requests[2].mcpName, 'app.echo');
        expect(endpoint.requests[2].mcpParameterHeaders, {
          'mcp-param-message': 'alias-notify',
        });
        expect(endpoint.requests[3].body, {
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': 'app.events.audit',
            'argumentsKeywords': {'message': 'pubsub-notify'},
            'options': {'exclude_me': false},
          },
        });
        expect(endpoint.requests[3].mcpParameterHeaders, isEmpty);
      },
    );

    test(
      'keeps direct JSON batches lifecycle-free with an active Streamable session',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        final batch = await client.postBatchDirect(
          [
            {
              'jsonrpc': '2.0',
              'id': 'direct-batch-tools',
              'method': 'tools/list',
            },
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          ],
          headers: const <String, String>{
            'x-consumer-trace': 'direct-batch-smoke',
          },
        );

        expect(batch, hasLength(1));
        expect(batch?.single['id'], 'direct-batch-tools');
        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests, hasLength(1));
        expect(endpoint.requests.single.accept, 'application/json');
        expect(endpoint.requests.single.sessionId, isNull);
        expect(endpoint.requests.single.lastEventId, isNull);
        expect(endpoint.requests.single.consumerTrace, 'direct-batch-smoke');
        expect(endpoint.requests.single.mcpMethod, isNull);
        expect(endpoint.requests.single.body, isA<List>());
      },
    );

    test(
      'keeps active Streamable session state after direct JSON HTTP failures',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        for (final statusCode in const <int>[
          HttpStatus.unauthorized,
          HttpStatus.forbidden,
          HttpStatus.notFound,
        ]) {
          await expectLater(
            client.callConnectanumMethodDirect(
              'app.direct.error',
              id: 'direct-error-$statusCode',
              params: <String, Object?>{'statusCode': statusCode},
              headers: <String, String>{
                'x-consumer-trace': 'direct-error-$statusCode',
                'x-test-force-status': '$statusCode',
              },
            ),
            throwsA(
              isA<McpStreamableHttpException>().having(
                (error) => error.statusCode,
                'statusCode',
                statusCode,
              ),
            ),
          );
          expect(client.sessionId, sessionId);
          expect(client.lastEventId, eventId);
          expect(endpoint.requests.last.sessionId, isNull);
          expect(endpoint.requests.last.lastEventId, isNull);
          expect(
            endpoint.requests.last.consumerTrace,
            'direct-error-$statusCode',
          );
        }

        final ping = await client.ping(id: 'session-still-usable');
        expect(ping, isEmpty);
        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests.last.sessionId, sessionId);
      },
    );

    test('keeps direct JSON response session headers lifecycle-free', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();
      final sessionId = client.sessionId;
      final eventId = client.lastEventId;
      expect(sessionId, 'session-1');
      endpoint.requests.clear();

      final result = await client.callConnectanumMethodDirect(
        'app.direct.response-session',
        id: 'direct-response-session-success',
        params: const <String, Object?>{'message': 'success'},
        headers: const <String, String>{
          'x-consumer-trace': 'direct-response-session-success',
          'x-test-response-session-id': 'direct-session-ignored',
        },
      );
      expect(result['isError'], isFalse);
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      final post = await client.postDirect(
        {
          'jsonrpc': '2.0',
          'id': 'direct-response-session-post',
          'method': 'connectanum.tools.list',
        },
        headers: const <String, String>{
          'x-consumer-trace': 'direct-response-session-post',
          'x-test-response-session-id': 'direct-post-session-ignored',
        },
      );
      expect(post?['id'], 'direct-response-session-post');
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.accept, 'application/json');
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      await expectLater(
        client.callConnectanumMethodDirect(
          'app.direct.response-session-error',
          id: 'direct-response-session-error',
          params: const <String, Object?>{'message': 'error'},
          headers: const <String, String>{
            'x-consumer-trace': 'direct-response-session-error',
            'x-test-force-status': '${HttpStatus.unauthorized}',
            'x-test-response-session-id': 'direct-error-session-ignored',
          },
        ),
        throwsA(
          isA<McpStreamableHttpException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.unauthorized,
          ),
        ),
      );
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      final batch = await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'id': 'direct-response-session-batch',
            'method': 'connectanum.tools.list',
          },
          {
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': <String, Object?>{
              'progressToken': 'direct-response-session-batch',
              'progress': 1,
            },
          },
        ],
        headers: const <String, String>{
          'x-consumer-trace': 'direct-response-session-batch',
          'x-test-response-session-id': 'direct-batch-session-ignored',
        },
      );
      expect(batch, hasLength(1));
      expect(batch?.single['id'], 'direct-response-session-batch');
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      await client.notificationDirect(
        'notifications/progress',
        params: const <String, Object?>{
          'progressToken': 'direct-response-session-notification',
          'progress': 1,
        },
        headers: const <String, String>{
          'x-consumer-trace': 'direct-response-session-notification',
          'x-test-response-session-id': 'direct-notification-session-ignored',
        },
      );
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      final notificationBatch = await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': <String, Object?>{
              'progressToken': 'direct-response-session-notification-batch',
              'progress': 1,
            },
          },
        ],
        headers: const <String, String>{
          'x-consumer-trace': 'direct-response-session-notification-batch',
          'x-test-response-session-id':
              'direct-notification-batch-session-ignored',
        },
      );
      expect(notificationBatch, isNull);
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      await expectLater(
        client.notificationDirect(
          'notifications/progress',
          params: const <String, Object?>{
            'progressToken': 'direct-notification-body',
            'progress': 1,
          },
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notification-body',
            'x-test-json-notification-response': '1',
            'x-test-response-session-id': 'direct-notification-body-ignored',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('notification response must not include a body'),
          ),
        ),
      );
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      await expectLater(
        client.postBatchDirect(
          [
            {
              'jsonrpc': '2.0',
              'method': 'notifications/progress',
              'params': <String, Object?>{
                'progressToken': 'direct-notification-batch-body',
                'progress': 1,
              },
            },
          ],
          headers: const <String, String>{
            'x-consumer-trace': 'direct-notification-batch-body',
            'x-test-json-notification-response': '1',
            'x-test-response-session-id':
                'direct-notification-batch-body-ignored',
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(
              'notification-only batch response must not include a body',
            ),
          ),
        ),
      );
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, isNull);
      expect(endpoint.requests.last.lastEventId, isNull);

      final ping = await client.ping(id: 'session-header-still-usable');
      expect(ping, isEmpty);
      expect(client.sessionId, sessionId);
      expect(client.lastEventId, eventId);
      expect(endpoint.requests.last.sessionId, sessionId);
    });

    test(
      'treats notification-only batches as accepted without lifecycle changes',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        final directBatch = await client.postBatchDirect([
          {
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
          {
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': <String, Object?>{
              'progressToken': 'direct-notification-batch',
              'progress': 1,
            },
          },
        ]);
        final streamableBatch = await client.postBatch([
          {
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
          {
            'jsonrpc': '2.0',
            'method': 'notifications/tools/list_changed',
            'params': <String, Object?>{},
          },
        ]);

        expect(directBatch, isNull);
        expect(streamableBatch, isNull);
        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests, hasLength(2));
        expect(endpoint.requests[0].accept, 'application/json');
        expect(endpoint.requests[0].sessionId, isNull);
        expect(endpoint.requests[0].lastEventId, isNull);
        expect(endpoint.requests[0].body, isA<List>());
        expect(endpoint.requests[1].accept, contains('text/event-stream'));
        expect(endpoint.requests[1].sessionId, sessionId);
        expect(endpoint.requests[1].lastEventId, eventId);
        expect(endpoint.requests[1].body, isA<List>());
      },
    );

    test(
      'keeps single notifications lifecycle-free when sent through direct JSON',
      () async {
        final endpoint = await _FakeMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = McpStreamableHttpClient(endpoint.uri);
        addTearDown(() => client.close(force: true));

        await client.initialize();
        await client.notifyInitialized();
        final sessionId = client.sessionId;
        final eventId = client.lastEventId;
        expect(sessionId, 'session-1');
        endpoint.requests.clear();

        await client.notificationDirect(
          'notifications/progress',
          params: <String, Object?>{
            'progressToken': 'direct-single-notification',
            'progress': 1,
          },
        );
        await client.notification(
          'notifications/tools/list_changed',
          params: <String, Object?>{},
        );

        expect(client.sessionId, sessionId);
        expect(client.lastEventId, eventId);
        expect(endpoint.requests, hasLength(2));
        expect(endpoint.requests[0].accept, 'application/json');
        expect(endpoint.requests[0].sessionId, isNull);
        expect(endpoint.requests[0].lastEventId, isNull);
        expect(endpoint.requests[0].mcpMethod, 'notifications/progress');
        expect(endpoint.requests[0].body, isA<Map<String, Object?>>());
        expect(
          endpoint.requests[0].body,
          containsPair('method', 'notifications/progress'),
        );
        expect(endpoint.requests[1].accept, contains('text/event-stream'));
        expect(endpoint.requests[1].sessionId, sessionId);
        expect(endpoint.requests[1].lastEventId, eventId);
        expect(
          endpoint.requests[1].mcpMethod,
          'notifications/tools/list_changed',
        );
      },
    );

    test('uses Connectanum WAMP meta procedure helpers', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final registrations = await client.callWampMetaProcedure(
        'wamp.registration.list',
        id: 'wamp-registration-list',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-registration-list',
        },
      );
      expect(registrations.procedure, 'wamp.registration.list');
      expect(registrations.arguments, isEmpty);
      expect(registrations.argumentsKeywords['exact'], [11]);

      final registrationMatch = await client.callWampMetaProcedure(
        'wamp.registration.match',
        id: 'wamp-registration-match',
        arguments: const <Object?>['app.echo'],
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-registration-match',
        },
      );
      expect(registrationMatch.arguments, [11]);
      expect(registrationMatch.argumentsKeywords, isEmpty);

      final registrationDetails = await client.callWampMetaProcedure(
        'wamp.registration.get',
        id: 'wamp-registration-get',
        argumentsKeywords: const <String, Object?>{'id': 11},
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-registration-get',
        },
      );
      expect(registrationDetails.argumentsKeywords['uri'], 'app.echo');
      expect(registrationDetails.argumentsKeywords['match'], 'exact');

      final subscriptions = await client.callWampMetaProcedure(
        'wamp.subscription.lookup',
        id: 'wamp-subscription-lookup',
        argumentsKeywords: const <String, Object?>{'topic': 'app.events.audit'},
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-subscription-lookup',
        },
      );
      expect(subscriptions.arguments, [7]);

      final subscribers = await client.callWampMetaProcedure(
        'wamp.subscription.count_subscribers',
        id: 'wamp-subscription-count',
        arguments: const <Object?>[7],
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'wamp-subscription-count',
        },
      );
      expect(subscribers.arguments, [1]);

      expect(endpoint.requests.last.sessionId, 'session-1');
      expect(
        endpoint.requests.skip(2).map((request) => request.consumerTrace),
        [
          'wamp-registration-list',
          'wamp-registration-match',
          'wamp-registration-get',
          'wamp-subscription-lookup',
          'wamp-subscription-count',
        ],
      );
      expect(endpoint.requests.last.body, {
        'jsonrpc': '2.0',
        'id': 'wamp-subscription-count',
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.count_subscribers',
          'arguments': {
            'arguments': [7],
          },
        },
      });
    });

    test('uses standard WAMP meta convenience helpers', () async {
      final endpoint = await _FakeMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize();
      await client.notifyInitialized();

      final sessionCount = await client.countWampSessions(
        id: 'session-count',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'session-count'},
      );
      expect(sessionCount.procedure, 'wamp.session.count');
      expect(sessionCount.argumentsKeywords['count'], 2);

      final sessions = await client.listWampSessions(
        id: 'session-list',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'session-list'},
      );
      expect(sessions.argumentsKeywords['session_ids'], [101, 102]);

      final session = await client.getWampSession(
        101,
        id: 'session-get',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'session-get'},
      );
      expect(session.argumentsKeywords['details'], {
        'session': 101,
        'authid': 'anonymous',
      });

      final registrations = await client.listWampRegistrations(
        id: 'registration-list',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-list',
        },
      );
      expect(registrations.argumentsKeywords['exact'], [11]);

      final lookup = await client.lookupWampRegistration(
        'app.echo',
        id: 'registration-lookup',
        match: 'exact',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-lookup',
        },
      );
      expect(lookup.arguments, [11]);

      final match = await client.matchWampRegistration(
        'app.echo',
        id: 'registration-match-helper',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-match-helper',
        },
      );
      expect(match.arguments, [11]);

      final registration = await client.getWampRegistration(
        11,
        id: 'registration-get-helper',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-get-helper',
        },
      );
      expect(registration.argumentsKeywords['uri'], 'app.echo');

      final callees = await client.listWampRegistrationCallees(
        11,
        id: 'registration-callees',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-callees',
        },
      );
      expect(callees.arguments, [101]);

      final calleeCount = await client.countWampRegistrationCallees(
        11,
        id: 'registration-callee-count',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'registration-callee-count',
        },
      );
      expect(calleeCount.arguments, [1]);

      final subscriptions = await client.listWampSubscriptions(
        id: 'subscription-list',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'subscription-list',
        },
      );
      expect(subscriptions.argumentsKeywords['exact'], [7]);

      final lookupSubscription = await client.lookupWampSubscription(
        'app.events.audit',
        id: 'subscription-lookup-helper',
        match: 'exact',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'subscription-lookup-helper',
        },
      );
      expect(lookupSubscription.arguments, [7]);

      final matchingSubscriptions = await client.matchWampSubscription(
        'app.events.audit.created',
        id: 'subscription-match',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'subscription-match',
        },
      );
      expect(matchingSubscriptions.arguments, [7]);

      final subscription = await client.getWampSubscription(
        7,
        id: 'subscription-get',
        streamable: false,
        headers: const <String, String>{'x-consumer-trace': 'subscription-get'},
      );
      expect(subscription.argumentsKeywords['uri'], 'app.events.audit');

      final subscribers = await client.listWampSubscriptionSubscribers(
        7,
        id: 'subscription-subscribers',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'subscription-subscribers',
        },
      );
      expect(subscribers.arguments, [102]);

      final subscriberCount = await client.countWampSubscriptionSubscribers(
        7,
        id: 'subscription-subscriber-count',
        streamable: false,
        headers: const <String, String>{
          'x-consumer-trace': 'subscription-subscriber-count',
        },
      );
      expect(subscriberCount.arguments, [1]);

      expect(endpoint.requests.last.sessionId, 'session-1');
      expect(
        endpoint.requests.skip(2).map((request) => request.consumerTrace),
        [
          'session-count',
          'session-list',
          'session-get',
          'registration-list',
          'registration-lookup',
          'registration-match-helper',
          'registration-get-helper',
          'registration-callees',
          'registration-callee-count',
          'subscription-list',
          'subscription-lookup-helper',
          'subscription-match',
          'subscription-get',
          'subscription-subscribers',
          'subscription-subscriber-count',
        ],
      );
      expect(endpoint.requests.last.body, {
        'jsonrpc': '2.0',
        'id': 'subscription-subscriber-count',
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.count_subscribers',
          'arguments': {
            'arguments': [7],
          },
        },
      });
    });

    test(
      'parses SSE event ids, retry hints, event names, and multi-line data',
      () {
        final events = parseMcpSseEvents(
          ': ignored comment\n'
          'id: one\n'
          'retry: 2500\n'
          'event: message\n'
          'data: {"jsonrpc":"2.0",\n'
          'data: "id":"a"}\n\n'
          'id: two\n'
          'data:\n\n',
        );

        expect(events, hasLength(2));
        expect(events.first.id, 'one');
        expect(events.first.retryMs, 2500);
        expect(events.first.event, 'message');
        expect(events.first.jsonData?['id'], 'a');
        expect(events.last.id, 'two');
        expect(events.last.jsonData, isNull);
      },
    );

    test('throws typed HTTP exceptions for non-success responses', () async {
      final endpoint = await _FakeMcpEndpoint.bind(failInitialize: true);
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final call = client.initialize();
      await expectLater(
        call,
        throwsA(
          isA<McpStreamableHttpException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.unauthorized,
              )
              .having(
                (error) => error.error?['error'],
                'error',
                'missing token',
              ),
        ),
      );
    });
  });
}

final class _FakeMcpEndpoint {
  _FakeMcpEndpoint._(this._server, this._failInitialize) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final bool _failInitialize;
  final requests = <_SeenRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_FakeMcpEndpoint> bind({bool failInitialize = false}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeMcpEndpoint._(server, failInitialize);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final jsonBody = body.isEmpty ? null : jsonDecode(body);
    requests.add(_SeenRequest.from(request, jsonBody));

    final requestSessionId = request.headers.value(_headerSessionId);
    if (requestSessionId == 'expired-session' ||
        requestSessionId == 'unauthorized-session' ||
        requestSessionId == 'forbidden-session') {
      var statusCode = HttpStatus.notFound;
      var message = 'Unknown MCP HTTP session';
      if (requestSessionId == 'unauthorized-session') {
        statusCode = HttpStatus.unauthorized;
        message = 'Missing or invalid bearer token';
      } else if (requestSessionId == 'forbidden-session') {
        statusCode = HttpStatus.forbidden;
        message = 'MCP session is forbidden';
      }
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(_headerSessionId, requestSessionId!);
      request.response.write(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'message': message},
        }),
      );
      await request.response.close();
      return;
    }

    final forcedStatus = request.headers.value('x-test-force-status');
    if (forcedStatus != null) {
      final statusCode = int.tryParse(forcedStatus);
      request.response.statusCode =
          statusCode ?? HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      _applyTestResponseHeaders(request);
      request.response.write(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'message': 'forced test HTTP status',
            'statusCode': request.response.statusCode,
          },
        }),
      );
      await request.response.close();
      return;
    }

    switch (request.method) {
      case 'POST':
        await _handlePost(request, jsonBody);
        return;
      case 'GET':
        if (request.headers.value('x-test-poll-json-response') == '1') {
          _writeJson(request, <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'poll-json',
            'result': <String, Object?>{},
          });
          return;
        }
        if (request.headers.value('x-test-poll-invalid-message') == '1') {
          _writeSse(
            request,
            'id: session-1:get:invalid-poll-message\n'
            'data: 42\n\n',
          );
          return;
        }
        if (request.headers.value('x-test-poll-invalid-event-id') == '1') {
          _writeSse(
            request,
            'id: session-1:get:invalid\u0000id\n'
            'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n',
          );
          return;
        }
        _writeSse(
          request,
          'id: session-1:get:1\n'
          'data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}\n\n',
        );
        return;
      case 'DELETE':
        request.response.statusCode = HttpStatus.accepted;
        _applyTestResponseHeaders(request);
        await request.response.close();
        return;
      default:
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
    }
  }

  Future<void> _handlePost(HttpRequest request, Object? jsonBody) async {
    if (jsonBody is List) {
      final responses = <McpJsonMap>[
        for (final item in jsonBody)
          if (_jsonMapFrom(item, label: 'batch request').containsKey('id'))
            {
              'jsonrpc': '2.0',
              'id': _jsonMapFrom(item, label: 'batch request')['id'],
              'result': <String, Object?>{'tools': <Object?>[]},
            },
      ];
      if (responses.isEmpty) {
        if (request.headers.value('x-test-json-notification-response') == '1') {
          _writeJson(request, <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': <String, Object?>{
              'progressToken': 'server-response-to-notification-batch',
              'progress': 1,
            },
          });
          return;
        }
        if ((request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
              'text/event-stream',
            ) &&
            request.headers.value('x-test-sse-notification-only-response') ==
                '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:notification\n'
            'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n',
          );
          return;
        }
        request.response.statusCode = HttpStatus.accepted;
        _applyTestResponseHeaders(request);
        await request.response.close();
        return;
      }
      if (request.headers.value('x-test-batch-json-object-response') == '1') {
        _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': responses.first['id'],
          'result': <String, Object?>{'tools': <Object?>[]},
        });
        return;
      }
      if ((request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
        'text/event-stream',
      )) {
        if (request.headers.value(
              'x-test-sse-batch-server-request-before-response',
            ) ==
            '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: {"jsonrpc":"2.0","id":"server-request","method":"sampling/createMessage","params":{"messages":[]}}\n\n'
            'id: session-1:post-batch:2\n'
            'data: ${jsonEncode(responses[0])}\n\n'
            'id: session-1:post-batch:3\n'
            'data: ${jsonEncode(responses[1])}\n\n',
          );
          return;
        }
        if (request.headers.value('x-test-sse-batch-invalid-interim-message') ==
            '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: 42\n\n'
            'id: session-1:post-batch:2\n'
            'data: ${jsonEncode(responses[0])}\n\n'
            'id: session-1:post-batch:3\n'
            'data: ${jsonEncode(responses[1])}\n\n',
          );
          return;
        }
        if (request.headers.value('x-test-batch-missing-response') == '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: ${jsonEncode(responses.first)}\n\n',
          );
          return;
        }
        if (request.headers.value('x-test-batch-unexpected-response') == '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: ${jsonEncode(responses[0])}\n\n'
            'id: session-1:post-batch:2\n'
            'data: {"jsonrpc":"2.0","id":"batch-extra","result":{"tools":[]}}\n\n'
            'id: session-1:post-batch:3\n'
            'data: ${jsonEncode(responses[1])}\n\n',
          );
          return;
        }
        final testBatchResponseIdShape = request.headers.value(
          'x-test-batch-response-id-shape',
        );
        if (testBatchResponseIdShape != null) {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: ${jsonEncode(_testJsonRpcBatchResponsesWithIdShape(responses, testBatchResponseIdShape))}\n\n',
          );
          return;
        }
        if (request.headers.value('x-test-sse-split-batch-with-notification') ==
            '1') {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n'
            'id: session-1:post-batch:2\n'
            'data: ${jsonEncode(responses[0])}\n\n'
            'id: session-1:post-batch:3\n'
            'data: ${jsonEncode(responses[1])}\n\n',
          );
          return;
        }
        final testBatchResponseShape = request.headers.value(
          'x-test-batch-response-shape',
        );
        if (testBatchResponseShape != null) {
          _writeSse(
            request,
            'id: session-1:post-batch:1\n'
            'data: ${jsonEncode([_testJsonRpcResponseWithShape(responses.first['id'], testBatchResponseShape), ...responses.skip(1)])}\n\n',
          );
          return;
        }
        _writeSse(
          request,
          'id: session-1:post-batch:1\n'
          'data: ${jsonEncode(responses)}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-batch-missing-response') == '1') {
        _writeJsonValue(request, responses.take(1).toList());
        return;
      }
      if (request.headers.value('x-test-batch-duplicate-response') == '1') {
        _writeJsonValue(request, [
          responses.first,
          responses.first,
          ...responses.skip(1),
        ]);
        return;
      }
      final testBatchResponseIdShape = request.headers.value(
        'x-test-batch-response-id-shape',
      );
      if (testBatchResponseIdShape != null) {
        _writeJsonValue(
          request,
          _testJsonRpcBatchResponsesWithIdShape(
            responses,
            testBatchResponseIdShape,
          ),
        );
        return;
      }
      final testBatchResponseShape = request.headers.value(
        'x-test-batch-response-shape',
      );
      if (testBatchResponseShape != null) {
        _writeJsonValue(request, [
          _testJsonRpcResponseWithShape(
            responses.first['id'],
            testBatchResponseShape,
          ),
          ...responses.skip(1),
        ]);
        return;
      }
      _writeJsonValue(request, responses);
      return;
    }

    final requestBody = _jsonMapFrom(jsonBody, label: 'request');
    final method = requestBody['method'];
    if (method == 'initialize') {
      if (_failInitialize) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{'error': 'missing token'}),
        );
        await request.response.close();
        return;
      }
      final params = _jsonMapFrom(
        requestBody['params'],
        label: 'initialize params',
      );
      final requestedProtocolVersion = params['protocolVersion'];
      final responseSessionId =
          request.headers.value('x-test-no-response-session-id') == '1'
          ? null
          : request.headers.value('x-test-response-session-id') ?? 'session-1';
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'protocolVersion':
              request.headers.value('x-test-result-protocol-version') ??
              (requestedProtocolVersion is String
                  ? requestedProtocolVersion
                  : McpStreamableHttpClient.latestProtocolVersion),
          'capabilities': <String, Object?>{},
          'serverInfo': <String, Object?>{
            'name': 'fake-router',
            'version': '1.0.0',
          },
        },
      }, sessionId: responseSessionId);
      return;
    }

    if (method is String && method.startsWith('notifications/')) {
      if (request.headers.value('x-test-json-notification-response') == '1') {
        _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': <String, Object?>{
            'progressToken': 'server-response-to-notification',
            'progress': 1,
          },
        });
        return;
      }
      if ((request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
            'text/event-stream',
          ) &&
          request.headers.value('x-test-sse-notification-only-response') ==
              '1') {
        _writeSse(
          request,
          'id: session-1:post:notification\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n',
        );
        return;
      }
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
      return;
    }

    if (!requestBody.containsKey('id') &&
        method is String &&
        (method == 'tools/call' ||
            method == 'connectanum.tool.call' ||
            method == 'connectanum.tools.call' ||
            method.contains('.'))) {
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
      return;
    }

    if (method == 'ping') {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{},
      });
      return;
    }

    if (request.headers.value('x-test-malformed-json-response') == '1') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      _applyTestResponseHeaders(request);
      request.response.write('{');
      await request.response.close();
      return;
    }
    if (request.headers.value('x-test-json-array-response') == '1') {
      _writeJsonValue(request, const <Object?>[]);
      return;
    }
    final testJsonResponseId = request.headers.value('x-test-json-response-id');
    if (testJsonResponseId != null) {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': testJsonResponseId,
        'result': <String, Object?>{'tools': <Object?>[]},
      });
      return;
    }
    final testJsonResponseIdShape = request.headers.value(
      'x-test-json-response-id-shape',
    );
    if (testJsonResponseIdShape != null) {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': _testJsonRpcResponseIdWithShape(
          requestBody['id'],
          testJsonResponseIdShape,
        ),
        'result': <String, Object?>{'tools': <Object?>[]},
      });
      return;
    }
    final testJsonResponseShape = request.headers.value(
      'x-test-json-response-shape',
    );
    if (testJsonResponseShape != null) {
      _writeJson(
        request,
        _testJsonRpcResponseWithShape(requestBody['id'], testJsonResponseShape),
      );
      return;
    }

    if (method == 'connectanum.tools.list') {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'tools': <Object?>[
            <String, Object?>{
              'name': 'app.echo',
              'description': 'Echoes arguments.',
              'inputSchema': _toolInputSchemaWithHeaders(),
            },
            <String, Object?>{
              'name': 'wamp.registration.match',
              'description': 'Matches a visible WAMP registration.',
              'inputSchema': <String, Object?>{'type': 'object'},
            },
          ],
        },
      });
      return;
    }

    if (method == 'connectanum.tool.call' ||
        method == 'connectanum.tools.call') {
      final params = _jsonMapFrom(
        requestBody['params'],
        label: 'connectanum.tool.call',
      );
      final name = params['name'];
      final arguments = _jsonMapFrom(
        params['arguments'],
        label: 'connectanum.tool.call arguments',
      );
      if (name is String && name.startsWith('wamp.')) {
        _writeWampMetaToolResult(request, requestBody['id'], name, arguments);
        return;
      }
      if (name == 'connectanum.api.list') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topics': <Object?>[
            <String, Object?>{
              'topic': 'app.events.audit',
              'title': 'Audit Events',
            },
          ],
        });
        return;
      }
      if (name == 'connectanum.api.describe') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topic': 'app.events.audit',
          'title': 'Audit Events',
        });
        return;
      }
      if (name == 'connectanum.pubsub.subscribe') {
        if (arguments['topic'] == 'app.secure.audit') {
          _writeJson(request, <String, Object?>{
            'jsonrpc': '2.0',
            'id': requestBody['id'],
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'not authorized for topic',
                },
              ],
              'isError': true,
            },
          });
          return;
        }
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': 'wamp-sub-1',
          'topic': arguments['topic'],
          'subscriptionId': 7,
          'queueLimit': arguments['queueLimit'],
        });
        return;
      }
      if (name == 'connectanum.pubsub.publish') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topic': arguments['topic'],
          'acknowledged': true,
          'publicationId': 42,
        });
        return;
      }
      if (name == 'connectanum.pubsub.poll') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': arguments['handle'],
          'topic': 'app.events.audit',
          'events': <Object?>[
            <String, Object?>{
              'subscriptionId': 7,
              'publicationId': 42,
              'topic': 'app.events.audit',
              'argumentsKeywords': <String, Object?>{'message': 'hello'},
            },
          ],
          'dropped': 0,
          'remaining': 0,
        });
        return;
      }
      if (name == 'connectanum.pubsub.unsubscribe') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': arguments['handle'],
          'topic': 'app.events.audit',
          'unsubscribed': true,
        });
        return;
      }
      _writeToolResult(request, requestBody['id'], <String, Object?>{
        'echo': arguments,
      });
      return;
    }

    if (method is String && method.contains('.')) {
      final params = _jsonMapFrom(
        requestBody['params'],
        label: 'connectanum direct method params',
      );
      if (method.startsWith('wamp.')) {
        _writeWampMetaToolResult(request, requestBody['id'], method, params);
        return;
      }
      _writeToolResult(request, requestBody['id'], <String, Object?>{
        'echo': params,
      });
      return;
    }

    if (method == 'tools/call') {
      final params = _jsonMapFrom(requestBody['params'], label: 'tools/call');
      if (params['name'] == 'app.fail') {
        _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': requestBody['id'],
          'error': <String, Object?>{'code': -32000, 'message': 'tool failed'},
        });
        return;
      }
      if (params['name'] is String &&
          (params['name'] as String).startsWith('wamp.')) {
        _writeWampMetaToolResult(
          request,
          requestBody['id'],
          params['name'] as String,
          _jsonMapFrom(params['arguments'], label: 'wamp meta arguments'),
        );
        return;
      }
      if (params['name'] == 'connectanum.api.list') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topics': <Object?>[
            <String, Object?>{
              'topic': 'app.events.audit',
              'title': 'Audit Events',
            },
          ],
        });
        return;
      }
      if (params['name'] == 'connectanum.api.describe') {
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topic': 'app.events.audit',
          'title': 'Audit Events',
        });
        return;
      }
      if (params['name'] == 'connectanum.pubsub.subscribe') {
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'pubsub subscribe arguments',
        );
        if (arguments['topic'] == 'app.secure.audit') {
          _writeJson(request, <String, Object?>{
            'jsonrpc': '2.0',
            'id': requestBody['id'],
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'not authorized for topic',
                },
              ],
              'isError': true,
            },
          });
          return;
        }
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': 'wamp-sub-1',
          'topic': arguments['topic'],
          'subscriptionId': 7,
          'queueLimit': arguments['queueLimit'],
        });
        return;
      }
      if (params['name'] == 'connectanum.pubsub.publish') {
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'pubsub publish arguments',
        );
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'topic': arguments['topic'],
          'acknowledged': true,
          'publicationId': 42,
        });
        return;
      }
      if (params['name'] == 'connectanum.pubsub.poll') {
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'pubsub poll arguments',
        );
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': arguments['handle'],
          'topic': 'app.events.audit',
          'events': <Object?>[
            <String, Object?>{
              'subscriptionId': 7,
              'publicationId': 42,
              'topic': 'app.events.audit',
              'argumentsKeywords': <String, Object?>{'message': 'hello'},
            },
          ],
          'dropped': 0,
          'remaining': 0,
        });
        return;
      }
      if (params['name'] == 'connectanum.pubsub.unsubscribe') {
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'pubsub unsubscribe arguments',
        );
        _writeToolResult(request, requestBody['id'], <String, Object?>{
          'handle': arguments['handle'],
          'topic': 'app.events.audit',
          'unsubscribed': true,
        });
        return;
      }
      final arguments = _jsonMapFrom(
        params['arguments'],
        label: 'tools/call arguments',
      );
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'content': <Object?>[],
          'structuredContent': <String, Object?>{'echo': arguments},
          'isError': false,
        },
      });
      return;
    }

    if (method == 'resources/list') {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{
              'uri': 'wamp://app/readme',
              'name': 'readme',
              'mimeType': 'text/plain',
            },
          ],
        },
      });
      return;
    }

    if (method == 'resources/read') {
      final params = _jsonMapFrom(
        requestBody['params'],
        label: 'resources/read',
      );
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'uri': params['uri'],
              'mimeType': 'text/plain',
              'text': 'hello resource',
            },
          ],
        },
      });
      return;
    }

    if (method == 'resources/templates/list') {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'resourceTemplates': <Object?>[
            <String, Object?>{
              'uriTemplate': 'wamp://app/{name}',
              'name': 'app-resource',
            },
          ],
        },
      });
      return;
    }

    if (method == 'prompts/list') {
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'name': 'summarize',
              'description': 'Summarizes a topic.',
              'arguments': <Object?>[
                <String, Object?>{'name': 'topic', 'required': true},
              ],
            },
          ],
        },
      });
      return;
    }

    if (method == 'prompts/get') {
      final params = _jsonMapFrom(requestBody['params'], label: 'prompts/get');
      if (params['name'] == 'missing') {
        _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': requestBody['id'],
          'error': <String, Object?>{
            'code': -32602,
            'message': 'prompt not found',
          },
        });
        return;
      }
      final arguments = _jsonMapFrom(
        params['arguments'],
        label: 'prompts/get arguments',
      );
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'description': 'Summarizes a topic.',
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'Summarize ${arguments['topic']}',
              },
            },
          ],
        },
      });
      return;
    }

    if (method == 'tools/list' &&
        (request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
          'text/event-stream',
        )) {
      if (request.headers.value('x-test-malformed-sse-response') == '1') {
        _writeSse(
          request,
          'id: session-1:post:malformed\n'
          'data: {\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-invalid-event-id') == '1') {
        _writeSse(
          request,
          'id: session-1:post:invalid\u0000id\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-reset-event-id') == '1') {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n'
          'id:\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-extra-response') == '1') {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: {"jsonrpc":"2.0","id":"other-response","result":{"tools":[]}}\n\n'
          'id: session-1:post:2\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n'
          'id: session-1:post:3\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-server-request-before-response') ==
          '1') {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: {"jsonrpc":"2.0","id":"server-request","method":"sampling/createMessage","params":{"messages":[]}}\n\n'
          'id: session-1:post:2\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n'
          'id: session-1:post:3\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-invalid-interim-message') == '1') {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: 42\n\n'
          'id: session-1:post:2\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      final testSseResponseIdShape = request.headers.value(
        'x-test-sse-response-id-shape',
      );
      if (testSseResponseIdShape != null) {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: ${jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': _testJsonRpcResponseIdWithShape(requestBody['id'], testSseResponseIdShape),
            'result': <String, Object?>{'tools': <Object?>[]},
          })}\n\n',
        );
        return;
      }
      final testSseResponseShape = request.headers.value(
        'x-test-sse-response-shape',
      );
      if (testSseResponseShape != null) {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'data: ${jsonEncode(_testJsonRpcResponseWithShape(requestBody['id'], testSseResponseShape))}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-prefix-notification') == '1') {
        _writeSse(
          request,
          'id: session-1:post:1\n'
          'retry: 1000\n'
          'data:\n\n'
          'id: session-1:post:2\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n'
          'id: session-1:post:3\n'
          'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
        );
        return;
      }
      if (request.headers.value('x-test-sse-notification-only-response') ==
          '1') {
        _writeSse(
          request,
          'id: session-1:post:missing\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n',
        );
        return;
      }
      _writeSse(
        request,
        'id: session-1:post:1\n'
        'retry: 1000\n'
        'data:\n\n'
        'id: session-1:post:2\n'
        'data: {"jsonrpc":"2.0","id":"${requestBody['id']}","result":{"tools":[]}}\n\n',
      );
      return;
    }

    _writeJson(request, <String, Object?>{
      'jsonrpc': '2.0',
      'id': requestBody['id'],
      'result': <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{
            'name': 'app.echo',
            'description': 'Echoes arguments.',
            'inputSchema': _toolInputSchemaWithHeaders(),
          },
          <String, Object?>{
            'name': 'app.invalid-header',
            'description': 'Uses an invalid MCP header annotation.',
            'inputSchema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'payload': <String, Object?>{
                  'type': 'object',
                  'x-mcp-header': 'Payload',
                },
              },
            },
          },
        ],
      },
    });
  }

  void _writeWampMetaToolResult(
    HttpRequest request,
    Object? id,
    String procedure,
    McpJsonMap toolArguments,
  ) {
    final arguments = switch (toolArguments['arguments']) {
      final List value => List<Object?>.unmodifiable(value),
      null => const <Object?>[],
      _ => throw StateError('wamp meta arguments must be an array'),
    };
    final argumentsKeywords = switch (toolArguments['argumentsKeywords']) {
      final Map value => _jsonMapFrom(value, label: 'wamp meta kwargs'),
      null => const <String, Object?>{},
      _ => throw StateError('wamp meta argumentsKeywords must be an object'),
    };
    final firstArgument = arguments.firstOrNull;

    final structuredContent = switch (procedure) {
      'wamp.session.count' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{'count': 2},
      },
      'wamp.session.list' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'session_ids': <Object?>[101, 102],
        },
      },
      'wamp.session.get' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'details': <String, Object?>{
            'session': argumentsKeywords['id'] ?? firstArgument,
            'authid': 'anonymous',
          },
        },
      },
      'wamp.registration.list' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'exact': <Object?>[11],
          'prefix': <Object?>[],
          'wildcard': <Object?>[],
        },
      },
      'wamp.registration.lookup' => <String, Object?>{
        'arguments': <Object?>[
          if ((firstArgument == 'app.echo' ||
                  argumentsKeywords['procedure'] == 'app.echo') &&
              argumentsKeywords['match'] == 'exact')
            11,
        ],
      },
      'wamp.registration.match' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 'app.echo' ||
              argumentsKeywords['procedure'] == 'app.echo')
            11,
        ],
      },
      'wamp.registration.get' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'id': argumentsKeywords['id'] ?? firstArgument,
          'uri': 'app.echo',
          'match': 'exact',
        },
      },
      'wamp.registration.list_callees' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 11 || argumentsKeywords['id'] == 11) 101,
        ],
      },
      'wamp.registration.count_callees' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 11 || argumentsKeywords['id'] == 11) 1 else 0,
        ],
      },
      'wamp.subscription.list' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'exact': <Object?>[7],
          'prefix': <Object?>[],
          'wildcard': <Object?>[],
        },
      },
      'wamp.subscription.lookup' => <String, Object?>{
        'arguments': <Object?>[
          if ((firstArgument == 'app.events.audit' ||
                  argumentsKeywords['topic'] == 'app.events.audit') &&
              (argumentsKeywords['match'] == null ||
                  argumentsKeywords['match'] == 'exact'))
            7,
        ],
      },
      'wamp.subscription.match' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 'app.events.audit.created' ||
              argumentsKeywords['topic'] == 'app.events.audit.created')
            7,
        ],
      },
      'wamp.subscription.get' => <String, Object?>{
        'argumentsKeywords': <String, Object?>{
          'id': argumentsKeywords['id'] ?? firstArgument,
          'uri': 'app.events.audit',
          'match': 'exact',
        },
      },
      'wamp.subscription.list_subscribers' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 7 || argumentsKeywords['id'] == 7) 102,
        ],
      },
      'wamp.subscription.count_subscribers' => <String, Object?>{
        'arguments': <Object?>[
          if (firstArgument == 7 || argumentsKeywords['id'] == 7) 1 else 0,
        ],
      },
      _ => <String, Object?>{
        'arguments': <Object?>[],
        'argumentsKeywords': <String, Object?>{},
      },
    };

    _writeToolResult(request, id, structuredContent);
  }

  void _writeToolResult(
    HttpRequest request,
    Object? id,
    McpJsonMap structuredContent,
  ) {
    _writeJson(request, <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'content': <Object?>[],
        'structuredContent': structuredContent,
        'isError': false,
      },
    });
  }

  void _applyTestResponseHeaders(HttpRequest request, {String? sessionId}) {
    request.response.headers.set(
      _headerProtocolVersion,
      request.headers.value('x-test-response-protocol-version') ??
          request.headers.value(_headerProtocolVersion) ??
          McpStreamableHttpClient.latestProtocolVersion,
    );
    final responseSessionId =
        request.headers.value('x-test-empty-response-session-id') != null
        ? ''
        : sessionId ?? request.headers.value('x-test-response-session-id');
    if (responseSessionId != null) {
      request.response.headers.set(_headerSessionId, responseSessionId);
    }
  }

  void _writeJson(HttpRequest request, McpJsonMap body, {String? sessionId}) {
    _writeJsonValue(request, body, sessionId: sessionId);
  }

  void _writeJsonValue(HttpRequest request, Object? body, {String? sessionId}) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    _applyTestResponseHeaders(request, sessionId: sessionId);
    request.response.write(jsonEncode(body));
    unawaited(request.response.close());
  }

  void _writeSse(HttpRequest request, String body) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream; charset=utf-8',
    );
    request.response.headers.set(
      _headerProtocolVersion,
      request.headers.value(_headerProtocolVersion) ??
          McpStreamableHttpClient.latestProtocolVersion,
    );
    request.response.headers.set(
      _headerSessionId,
      request.headers.value('x-test-response-session-id') ?? 'session-1',
    );
    request.response.write(body);
    unawaited(request.response.close());
  }
}

const _headerProtocolVersion = 'MCP-Protocol-Version';
const _headerSessionId = 'MCP-Session-Id';
const _headerMethod = 'Mcp-Method';
const _headerName = 'Mcp-Name';

McpJsonMap _toolInputSchemaWithHeaders() {
  return <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'message': <String, Object?>{'type': 'string', 'x-mcp-header': 'Message'},
      'attempt': <String, Object?>{
        'type': 'integer',
        'x-mcp-header': 'Attempt',
      },
      'dryRun': <String, Object?>{'type': 'boolean', 'x-mcp-header': 'DryRun'},
      'note': <String, Object?>{'type': 'string', 'x-mcp-header': 'Note'},
      'wrapper': <String, Object?>{'type': 'string', 'x-mcp-header': 'Wrapper'},
    },
  };
}

final class _SeenRequest {
  const _SeenRequest({
    required this.method,
    required this.accept,
    required this.protocolVersion,
    required this.authorization,
    required this.sessionId,
    required this.lastEventId,
    required this.mcpMethod,
    required this.mcpName,
    required this.consumerTrace,
    required this.mcpParameterHeaders,
    required this.contentLength,
    required this.transferEncoding,
    required this.body,
  });

  final String method;
  final String? accept;
  final String? protocolVersion;
  final String? authorization;
  final String? sessionId;
  final String? lastEventId;
  final String? mcpMethod;
  final String? mcpName;
  final String? consumerTrace;
  final Map<String, String> mcpParameterHeaders;
  final int contentLength;
  final String? transferEncoding;
  final Object? body;

  factory _SeenRequest.from(HttpRequest request, Object? body) {
    return _SeenRequest(
      method: request.method,
      accept: request.headers.value(HttpHeaders.acceptHeader),
      protocolVersion: request.headers.value(_headerProtocolVersion),
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      sessionId: request.headers.value(_headerSessionId),
      lastEventId: request.headers.value('Last-Event-ID'),
      mcpMethod: request.headers.value(_headerMethod),
      mcpName: request.headers.value(_headerName),
      consumerTrace: request.headers.value('x-consumer-trace'),
      mcpParameterHeaders: _mcpParameterHeadersFrom(request),
      contentLength: request.headers.contentLength,
      transferEncoding: request.headers.value(
        HttpHeaders.transferEncodingHeader,
      ),
      body: body,
    );
  }
}

McpJsonMap _testJsonRpcResponseWithShape(Object? id, String shape) {
  final response = <String, Object?>{'jsonrpc': '2.0', 'id': id};
  switch (shape) {
    case 'missing-jsonrpc':
      response.remove('jsonrpc');
      response['result'] = <String, Object?>{'tools': <Object?>[]};
      break;
    case 'invalid-jsonrpc':
      response['jsonrpc'] = '1.0';
      response['result'] = <String, Object?>{'tools': <Object?>[]};
      break;
    case 'non-string-jsonrpc':
      response['jsonrpc'] = 2.0;
      response['result'] = <String, Object?>{'tools': <Object?>[]};
      break;
    case 'missing-discriminant':
      break;
    case 'both-result-error':
      response['result'] = <String, Object?>{'tools': <Object?>[]};
      response['error'] = <String, Object?>{
        'code': -32000,
        'message': 'unexpected error',
      };
      break;
    case 'invalid-error':
      response['error'] = 'not an error object';
      break;
    case 'missing-error-code':
      response['error'] = <String, Object?>{'message': 'unexpected error'};
      break;
    case 'invalid-error-code':
      response['error'] = <String, Object?>{
        'code': -32000.5,
        'message': 'unexpected error',
      };
      break;
    case 'missing-error-message':
      response['error'] = <String, Object?>{'code': -32000};
      break;
    case 'invalid-error-message':
      response['error'] = <String, Object?>{
        'code': -32000,
        'message': <String, Object?>{'text': 'unexpected error'},
      };
      break;
    default:
      throw StateError('unknown JSON-RPC response shape $shape');
  }
  return response;
}

Object? _testJsonRpcResponseIdWithShape(Object? id, String shape) {
  switch (shape) {
    case 'fractional':
      return id is int ? id.toDouble() : 1.0;
    default:
      throw StateError('unknown JSON-RPC response id shape $shape');
  }
}

List<McpJsonMap> _testJsonRpcBatchResponsesWithIdShape(
  List<McpJsonMap> responses,
  String shape,
) {
  return <McpJsonMap>[
    <String, Object?>{
      ...responses.first,
      'id': _testJsonRpcResponseIdWithShape(responses.first['id'], shape),
    },
    ...responses.skip(1),
  ];
}

Map<String, String> _mcpParameterHeadersFrom(HttpRequest request) {
  final headers = <String, String>{};
  request.headers.forEach((name, values) {
    final lowerName = name.toLowerCase();
    if (lowerName.startsWith('mcp-param-')) {
      headers[lowerName] = values.join(', ');
    }
  });
  return headers;
}

McpJsonMap _jsonMapFrom(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label must contain only string keys');
    }
    result[key] = entry.value;
  }
  return result;
}
