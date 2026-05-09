import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'IO entrypoint re-exports MCP primitives and direct WAMP helpers',
    () async {
      final tool = McpTool(
        name: 'app.echo',
        description: 'Echoes a request.',
        handler: (request) async => McpToolResult.text(
          'echo:${request.arguments['value']}',
          structuredContent: <String, Object?>{'ok': true},
        ),
      );

      final toolResult = await tool.handler(
        const McpToolRequest(
          name: 'app.echo',
          arguments: <String, Object?>{'value': 'ready'},
        ),
      );
      expect(tool.name, 'app.echo');
      expect(toolResult.structuredContent, {'ok': true});

      final endpoint = await _DirectWampEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final catalog = await client.listWampApi(
        id: 'io-entrypoint-api-list',
        kind: 'procedure',
        directJson: true,
      );

      expect(catalog['procedures'], hasLength(1));
      expect(client.sessionId, isNull);
      expect(endpoint.requests, hasLength(1));

      final request = endpoint.requests.single;
      expect(request.accept, 'application/json');
      expect(request.sessionId, isNull);
      expect(request.body['method'], 'connectanum.tool.call');

      final params = _jsonMapFrom(request.body['params'], label: 'tool params');
      expect(params['name'], 'connectanum.api.list');
      expect(_jsonMapFrom(params['arguments'], label: 'tool arguments'), {
        'kind': 'procedure',
      });
    },
  );

  test(
    'IO entrypoint re-exports direct Connectanum tool and meta helpers',
    () async {
      final endpoint = await _DirectWampEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final tools = await client.listConnectanumToolsDirect(
        id: 'io-direct-tools',
      );
      expect(tools.nextCursor, isNull);
      expect(
        tools.tools.map((tool) => tool['name']),
        containsAll(['app.echo', 'wamp.registration.match']),
      );

      final toolResult = await client.callConnectanumToolDirect(
        'app.echo',
        id: 'io-direct-tool-call',
        arguments: const <String, Object?>{'message': 'tool'},
      );
      expect(toolResult['isError'], isFalse);
      expect(toolResult['structuredContent'], {
        'echo': {'message': 'tool'},
      });

      final methodResult = await client.callConnectanumMethodDirect(
        'app.echo',
        id: 'io-direct-method-call',
        params: const <String, Object?>{'message': 'method'},
      );
      expect(methodResult['structuredContent'], {
        'echo': {'message': 'method'},
      });

      final rawMeta = await client.callConnectanumMethodDirect(
        'wamp.registration.match',
        id: 'io-direct-meta-method',
        params: const <String, Object?>{
          'arguments': <Object?>['app.echo'],
        },
      );
      expect(rawMeta['structuredContent'], {
        'procedure': 'wamp.registration.match',
        'arguments': [11],
      });

      final apiDescription = await client.describeWampApi(
        'app.echo',
        id: 'io-direct-api-describe',
        kind: 'procedure',
        directJson: true,
      );
      expect(apiDescription['procedure'], 'app.echo');
      expect(apiDescription['title'], 'Echo');

      final registration = await client.matchWampRegistration(
        'app.echo',
        id: 'io-direct-registration-match',
        directJson: true,
      );
      expect(registration.procedure, 'wamp.registration.match');
      expect(registration.arguments, [11]);

      expect(client.sessionId, isNull);
      expect(endpoint.requests, hasLength(6));
      for (final request in endpoint.requests) {
        expect(request.accept, 'application/json');
        expect(request.sessionId, isNull);
      }
      expect(endpoint.requests.map((request) => request.body['method']), [
        'connectanum.tools.list',
        'connectanum.tool.call',
        'app.echo',
        'wamp.registration.match',
        'connectanum.tool.call',
        'connectanum.tool.call',
      ]);

      final toolCallParams = _jsonMapFrom(
        endpoint.requests[1].body['params'],
        label: 'direct tool call params',
      );
      expect(toolCallParams['name'], 'app.echo');
      expect(
        _jsonMapFrom(
          toolCallParams['arguments'],
          label: 'direct tool call arguments',
        ),
        {'message': 'tool'},
      );

      final apiDescribeParams = _jsonMapFrom(
        endpoint.requests[4].body['params'],
        label: 'direct API describe params',
      );
      expect(apiDescribeParams['name'], 'connectanum.api.describe');
      expect(
        _jsonMapFrom(
          apiDescribeParams['arguments'],
          label: 'direct API describe arguments',
        ),
        {'uri': 'app.echo', 'kind': 'procedure'},
      );

      final metaHelperParams = _jsonMapFrom(
        endpoint.requests[5].body['params'],
        label: 'direct meta helper params',
      );
      expect(metaHelperParams['name'], 'wamp.registration.match');
      expect(
        _jsonMapFrom(
          metaHelperParams['arguments'],
          label: 'direct meta helper arguments',
        ),
        {
          'arguments': ['app.echo'],
        },
      );
    },
  );

  test(
    'IO entrypoint re-exports direct WAMP session and subscription meta helpers',
    () async {
      final endpoint = await _DirectWampEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final sessionCount = await client.countWampSessions(
        id: 'io-direct-session-count',
        directJson: true,
      );
      expect(sessionCount.procedure, 'wamp.session.count');
      expect(sessionCount.argumentsKeywords['count'], 2);

      final sessions = await client.listWampSessions(
        id: 'io-direct-session-list',
        directJson: true,
      );
      expect(sessions.argumentsKeywords['session_ids'], [101, 102]);

      final session = await client.getWampSession(
        101,
        id: 'io-direct-session-get',
        directJson: true,
      );
      expect(session.argumentsKeywords['details'], {
        'session': 101,
        'authid': 'io-user',
        'authrole': 'agent',
      });

      final subscription = await client.matchWampSubscription(
        _ioTopic,
        id: 'io-direct-subscription-match',
        directJson: true,
      );
      expect(subscription.procedure, 'wamp.subscription.match');
      expect(subscription.arguments, [17]);

      final subscriptionDetails = await client.getWampSubscription(
        17,
        id: 'io-direct-subscription-get',
        directJson: true,
      );
      expect(subscriptionDetails.argumentsKeywords['details'], {
        'id': 17,
        'topic': _ioTopic,
      });

      final subscriberCount = await client.countWampSubscriptionSubscribers(
        17,
        id: 'io-direct-subscription-subscriber-count',
        directJson: true,
      );
      expect(subscriberCount.argumentsKeywords['count'], 1);

      expect(client.sessionId, isNull);
      expect(endpoint.requests, hasLength(6));
      for (final request in endpoint.requests) {
        expect(request.accept, 'application/json');
        expect(request.sessionId, isNull);
        expect(request.body['method'], 'connectanum.tool.call');
      }

      final helperParams = [
        for (final request in endpoint.requests)
          _jsonMapFrom(request.body['params'], label: 'WAMP meta params'),
      ];
      expect(helperParams.map((params) => params['name']), [
        'wamp.session.count',
        'wamp.session.list',
        'wamp.session.get',
        'wamp.subscription.match',
        'wamp.subscription.get',
        'wamp.subscription.count_subscribers',
      ]);

      expect(
        _jsonMapFrom(
          helperParams[2]['arguments'],
          label: 'session get arguments',
        ),
        {
          'arguments': [101],
        },
      );
      expect(
        _jsonMapFrom(
          helperParams[3]['arguments'],
          label: 'subscription match arguments',
        ),
        {
          'arguments': [_ioTopic],
        },
      );
      expect(
        _jsonMapFrom(
          helperParams[5]['arguments'],
          label: 'subscription subscriber count arguments',
        ),
        {
          'arguments': [17],
        },
      );
    },
  );

  test('IO entrypoint re-exports HTTP auth helpers for MCP sessions', () async {
    final endpoint = await _AuthBackedMcpEndpoint.bind();
    addTearDown(endpoint.close);

    final authClient = ConnectanumHttpAuthClient(endpoint.authUri);
    addTearDown(() => authClient.close(force: true));

    final grant = await authClient.issueTicketToken(
      realm: _ioAuthRealm,
      authId: _ioAuthId,
      ticket: _ioTicketSecret,
    );
    expect(grant.accessToken, _ioAccessToken);
    expect(grant.refreshToken, _ioRefreshToken);
    expect(grant.realm, _ioAuthRealm);
    expect(grant.authId, _ioAuthId);
    expect(grant.authRole, _ioAuthRole);
    expect(grant.authMethod, 'ticket');

    final mcpClient = McpStreamableHttpClient.withBearerToken(
      endpoint.mcpUri,
      grant.accessToken,
    );
    addTearDown(() => mcpClient.close(force: true));

    final initialize = await mcpClient.initialize(id: 'io-auth-init');
    expect(
      _jsonMapFrom(
        initialize['result'],
        label: 'authenticated initialize result',
      )['protocolVersion'],
      mcpLatestProtocolVersion,
    );
    expect(mcpClient.sessionId, _ioAuthSessionId);

    final ping = await mcpClient.ping(id: 'io-auth-ping');
    expect(ping, isEmpty);

    final refreshed = await authClient.refreshToken(grant.refreshToken!);
    expect(refreshed.accessToken, _ioRefreshedAccessToken);
    expect(refreshed.refreshToken, _ioRefreshedRefreshToken);

    await authClient.revokeToken(
      refreshed.refreshToken!,
      tokenTypeHint: 'refresh_token',
    );

    expect(endpoint.authRequests, hasLength(4));
    expect(endpoint.authRequests[0].body, {
      'realm': _ioAuthRealm,
      'authmethod': 'ticket',
      'authid': _ioAuthId,
    });
    expect(endpoint.authRequests[1].body, {
      'state': _ioAuthState,
      'signature': _ioTicketSecret,
    });
    expect(endpoint.authRequests[2].body, {
      'grant_type': 'refresh_token',
      'refresh_token': _ioRefreshToken,
    });
    expect(endpoint.authRequests[3].body, {
      'grant_type': 'revoke',
      'token': _ioRefreshedRefreshToken,
      'token_type_hint': 'refresh_token',
    });

    expect(endpoint.mcpRequests, hasLength(2));
    expect(endpoint.mcpRequests[0].authorization, 'Bearer $_ioAccessToken');
    expect(endpoint.mcpRequests[0].sessionId, isNull);
    expect(endpoint.mcpRequests[0].body['method'], 'initialize');
    expect(endpoint.mcpRequests[1].authorization, 'Bearer $_ioAccessToken');
    expect(endpoint.mcpRequests[1].sessionId, _ioAuthSessionId);
    expect(endpoint.mcpRequests[1].body['method'], 'ping');
  });

  test(
    'IO entrypoint re-exports Streamable resource and prompt helpers',
    () async {
      final endpoint = await _StreamableMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final initialize = await client.initialize(id: 'io-streamable-init');
      expect(
        _jsonMapFrom(
          initialize['result'],
          label: 'initialize result',
        )['protocolVersion'],
        mcpLatestProtocolVersion,
      );
      expect(client.sessionId, 'io-session-1');

      final streamableContents = await client.readResource(
        _ioResourceUri,
        id: 'io-streamable-resource-read',
      );
      expect(streamableContents.single['text'], contains('IO entrypoint'));
      expect(client.lastEventId, 'io-session-1:post:1');

      final streamablePrompt = await client.getPrompt(
        _ioPromptName,
        id: 'io-streamable-prompt-get',
        arguments: const <String, String>{'taskId': 'T-streamable'},
      );
      expect(
        jsonEncode(streamablePrompt['messages']),
        contains('T-streamable'),
      );
      expect(client.lastEventId, 'io-session-1:post:2');

      final sessionId = client.sessionId;
      final lastEventId = client.lastEventId;

      final directResources = await client.listResources(
        id: 'io-direct-resources',
        directJson: true,
      );
      expect(directResources.resources.single['uri'], _ioResourceUri);

      final directPrompt = await client.getPrompt(
        _ioPromptName,
        id: 'io-direct-prompt-get',
        arguments: const <String, String>{'taskId': 'T-direct'},
        directJson: true,
      );
      expect(jsonEncode(directPrompt['messages']), contains('T-direct'));

      final directBatch = await client.postBatch(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-resource-read',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': _ioResourceUri},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-prompt-get',
            'method': 'prompts/get',
            'params': <String, Object?>{
              'name': _ioPromptName,
              'arguments': <String, Object?>{'taskId': 'T-batch'},
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-missing-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'app://io/missing'},
          },
        ],
        streamable: false,
        includeSession: false,
      );

      expect(directBatch, hasLength(3));
      expect(
        jsonEncode(
          _jsonRpcResult(
            directBatch![0],
            id: 'io-batch-resource-read',
          )['contents'],
        ),
        contains('IO entrypoint'),
      );
      expect(
        jsonEncode(_jsonRpcResult(directBatch[1], id: 'io-batch-prompt-get')),
        contains('T-batch'),
      );
      expect(
        _jsonMapFrom(
          directBatch[2]['error'],
          label: 'missing resource batch error',
        )['message'],
        contains('app://io/missing'),
      );

      expect(client.sessionId, sessionId);
      expect(client.lastEventId, lastEventId);
      expect(endpoint.requests, hasLength(6));
      expect(endpoint.requests[0].sessionId, isNull);
      expect(endpoint.requests[1].sessionId, 'io-session-1');
      expect(endpoint.requests[2].sessionId, 'io-session-1');
      expect(endpoint.requests[3].sessionId, isNull);
      expect(endpoint.requests[4].sessionId, isNull);
      expect(endpoint.requests[5].sessionId, isNull);
      expect(endpoint.requests[3].accept, 'application/json');
      expect(endpoint.requests[4].accept, 'application/json');
      expect(endpoint.requests[5].accept, 'application/json');
    },
  );

  test(
    'IO entrypoint re-exports Streamable notification polling and session deletion',
    () async {
      final endpoint = await _StreamableMcpEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.initialize(id: 'io-notification-init');
      expect(client.sessionId, 'io-session-1');

      await client.notifyInitialized();

      final firstEvents = await client.poll();
      expect(firstEvents, hasLength(1));
      expect(firstEvents.single.id, 'io-session-1:get:1');
      expect(firstEvents.single.event, 'message');
      expect(firstEvents.single.retryMs, 1000);
      final firstPayload = _jsonMapFrom(
        firstEvents.single.jsonValue,
        label: 'first notification',
      );
      expect(firstPayload['method'], 'notifications/tools/list_changed');
      expect(client.lastEventId, 'io-session-1:get:1');

      final resumedEvents = await client.poll(
        lastEventId: firstEvents.single.id,
      );
      expect(resumedEvents.single.id, 'io-session-1:get:2');
      final resumedPayload = _jsonMapFrom(
        resumedEvents.single.jsonValue,
        label: 'resumed notification',
      );
      expect(resumedPayload['method'], 'notifications/resources/list_changed');
      expect(client.lastEventId, 'io-session-1:get:2');

      await client.deleteSession();
      expect(client.sessionId, isNull);
      expect(client.lastEventId, isNull);

      expect(endpoint.requests, hasLength(5));
      expect(endpoint.requests.map((request) => request.method), [
        'POST',
        'POST',
        'GET',
        'GET',
        'DELETE',
      ]);
      expect(endpoint.requests[0].sessionId, isNull);
      expect(endpoint.requests[0].body, isA<Map<Object?, Object?>>());
      expect(endpoint.requests[1].sessionId, 'io-session-1');
      expect(endpoint.requests[1].body, isA<Map<Object?, Object?>>());
      expect(endpoint.requests[1].accept, contains('text/event-stream'));
      expect(endpoint.requests[2].accept, 'text/event-stream');
      expect(endpoint.requests[2].sessionId, 'io-session-1');
      expect(endpoint.requests[2].lastEventId, isNull);
      expect(endpoint.requests[3].accept, 'text/event-stream');
      expect(endpoint.requests[3].sessionId, 'io-session-1');
      expect(endpoint.requests[3].lastEventId, 'io-session-1:get:1');
      expect(endpoint.requests[4].accept, 'application/json');
      expect(endpoint.requests[4].sessionId, 'io-session-1');
    },
  );

  test('IO entrypoint re-exports Streamable pubsub helpers', () async {
    final endpoint = await _StreamableMcpEndpoint.bind();
    addTearDown(endpoint.close);

    final client = McpStreamableHttpClient(endpoint.uri);
    addTearDown(() => client.close(force: true));

    await client.initialize(id: 'io-pubsub-init');
    expect(client.sessionId, 'io-session-1');

    final streamableSubscription = await client.subscribeWampTopic(
      _ioTopic,
      id: 'io-streamable-subscribe',
      queueLimit: 5,
    );
    expect(streamableSubscription.handle, _ioSubscriptionHandle);
    expect(streamableSubscription.topic, _ioTopic);
    expect(streamableSubscription.subscriptionId, 17);
    expect(streamableSubscription.queueLimit, 5);
    expect(client.lastEventId, 'io-session-1:post:1');

    final streamablePublication = await client.publishWampEvent(
      _ioTopic,
      id: 'io-streamable-publish',
      argumentsKeywords: const <String, Object?>{'message': 'streamable'},
      acknowledge: true,
    );
    expect(streamablePublication.topic, _ioTopic);
    expect(streamablePublication.acknowledged, isTrue);
    expect(streamablePublication.publicationId, 42);
    expect(client.lastEventId, 'io-session-1:post:2');

    final streamableBatch = await client.pollWampEvents(
      streamableSubscription.handle,
      id: 'io-streamable-poll',
      limit: 2,
    );
    expect(streamableBatch.handle, streamableSubscription.handle);
    expect(streamableBatch.topic, _ioTopic);
    expect(streamableBatch.events.single['argumentsKeywords'], {
      'message': 'streamable',
    });
    expect(streamableBatch.dropped, 0);
    expect(streamableBatch.remaining, 0);
    expect(client.lastEventId, 'io-session-1:post:3');

    final streamableUnsubscribe = await client.unsubscribeWampTopic(
      streamableSubscription.handle,
      id: 'io-streamable-unsubscribe',
    );
    expect(streamableUnsubscribe.handle, streamableSubscription.handle);
    expect(streamableUnsubscribe.topic, _ioTopic);
    expect(streamableUnsubscribe.unsubscribed, isTrue);
    expect(client.lastEventId, 'io-session-1:post:4');

    final sessionId = client.sessionId;
    final lastEventId = client.lastEventId;

    final directSubscription = await client.subscribeWampTopic(
      _ioTopic,
      id: 'io-direct-subscribe',
      queueLimit: 3,
      directJson: true,
    );
    expect(directSubscription.handle, _ioSubscriptionHandle);

    final directPublication = await client.publishWampEvent(
      _ioTopic,
      id: 'io-direct-publish',
      argumentsKeywords: const <String, Object?>{'message': 'direct'},
      acknowledge: true,
      directJson: true,
    );
    expect(directPublication.acknowledged, isTrue);

    final directBatch = await client.pollWampEvents(
      directSubscription.handle,
      id: 'io-direct-poll',
      directJson: true,
    );
    expect(directBatch.events.single['argumentsKeywords'], {
      'message': 'streamable',
    });

    final directUnsubscribe = await client.unsubscribeWampTopic(
      directSubscription.handle,
      id: 'io-direct-unsubscribe',
      directJson: true,
    );
    expect(directUnsubscribe.unsubscribed, isTrue);

    final rawBatch = await client.postBatch(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'io-batch-subscribe',
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': 'connectanum.pubsub.subscribe',
            'arguments': <String, Object?>{'topic': _ioTopic, 'queueLimit': 2},
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'io-batch-publish',
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': 'connectanum.pubsub.publish',
            'arguments': <String, Object?>{
              'topic': _ioTopic,
              'argumentsKeywords': <String, Object?>{'message': 'batch'},
              'acknowledge': true,
            },
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'io-batch-missing-poll',
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': 'connectanum.pubsub.poll',
            'arguments': <String, Object?>{'handle': 'missing-subscription'},
          },
        },
      ],
      streamable: false,
      includeSession: false,
    );

    expect(rawBatch, hasLength(3));
    expect(
      _jsonMapFrom(
        _jsonRpcResult(
          rawBatch![0],
          id: 'io-batch-subscribe',
        )['structuredContent'],
        label: 'batch subscribe content',
      )['handle'],
      _ioSubscriptionHandle,
    );
    expect(
      _jsonMapFrom(
        _jsonRpcResult(
          rawBatch[1],
          id: 'io-batch-publish',
        )['structuredContent'],
        label: 'batch publish content',
      )['acknowledged'],
      isTrue,
    );
    final missingPoll = _jsonRpcResult(
      rawBatch[2],
      id: 'io-batch-missing-poll',
    );
    expect(missingPoll['isError'], isTrue);
    expect(
      jsonEncode(missingPoll['content']),
      contains('missing-subscription'),
    );

    expect(client.sessionId, sessionId);
    expect(client.lastEventId, lastEventId);
    expect(endpoint.requests, hasLength(10));
    expect(endpoint.requests[0].sessionId, isNull);
    for (final request in endpoint.requests.skip(1).take(4)) {
      expect(request.sessionId, 'io-session-1');
      expect(request.accept, contains('text/event-stream'));
    }
    for (final request in endpoint.requests.skip(5)) {
      expect(request.sessionId, isNull);
      expect(request.accept, 'application/json');
    }
  });
}

const String _ioResourceUri = 'app://io-entrypoint/context';
const String _ioPromptName = 'io.summarize';
const String _ioTopic = 'app.events.io';
const String _ioSubscriptionHandle = 'io-sub-1';
const String _ioAuthRealm = 'realm1';
const String _ioAuthId = 'consumer-1';
const String _ioAuthRole = 'member';
const String _ioTicketSecret = 'io-ticket-secret';
const String _ioAccessToken = 'io-access-token-1';
const String _ioRefreshToken = 'io-refresh-token-1';
const String _ioRefreshedAccessToken = 'io-access-token-2';
const String _ioRefreshedRefreshToken = 'io-refresh-token-2';
const String _ioAuthState = 'io-state-1';
const String _ioAuthSessionId = 'io-auth-session-1';

final class _DirectWampEndpoint {
  _DirectWampEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final requests = <_SeenRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_DirectWampEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _DirectWampEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final jsonBody = _jsonMapFrom(jsonDecode(body), label: 'request');
    requests.add(_SeenRequest.from(request, jsonBody));

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    switch (jsonBody['method']) {
      case 'connectanum.tools.list':
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': jsonBody['id'],
          'result': <String, Object?>{
            'tools': <Object?>[
              <String, Object?>{
                'name': 'app.echo',
                'description': 'Echoes arguments.',
                'inputSchema': <String, Object?>{'type': 'object'},
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
      case 'connectanum.tool.call':
        final params = _jsonMapFrom(jsonBody['params'], label: 'params');
        final toolName = params['name'];
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'tool arguments',
        );
        switch (toolName) {
          case 'connectanum.api.list':
            await _writeToolResult(jsonBody['id'], request, <String, Object?>{
              'procedures': <Object?>[
                <String, Object?>{'procedure': 'app.echo', 'title': 'Echo'},
              ],
            });
            return;
          case 'connectanum.api.describe':
            await _writeToolResult(jsonBody['id'], request, <String, Object?>{
              'procedure': arguments['uri'],
              'title': 'Echo',
              'kind': arguments['kind'],
            });
            return;
          case 'wamp.registration.match':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.registration.match',
              arguments: const <Object?>[11],
            );
            return;
          case 'wamp.session.count':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.session.count',
              argumentsKeywords: const <String, Object?>{'count': 2},
            );
            return;
          case 'wamp.session.list':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.session.list',
              argumentsKeywords: const <String, Object?>{
                'session_ids': <Object?>[101, 102],
              },
            );
            return;
          case 'wamp.session.get':
            final metaArgumentsValue = arguments['arguments'];
            final metaArguments = metaArgumentsValue is List
                ? List<Object?>.unmodifiable(metaArgumentsValue)
                : const <Object?>[];
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.session.get',
              argumentsKeywords: <String, Object?>{
                'details': <String, Object?>{
                  'session': metaArguments.isEmpty ? null : metaArguments.first,
                  'authid': 'io-user',
                  'authrole': 'agent',
                },
              },
            );
            return;
          case 'wamp.subscription.match':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.subscription.match',
              arguments: const <Object?>[17],
            );
            return;
          case 'wamp.subscription.get':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.subscription.get',
              argumentsKeywords: <String, Object?>{
                'details': <String, Object?>{'id': 17, 'topic': _ioTopic},
              },
            );
            return;
          case 'wamp.subscription.count_subscribers':
            await _writeWampMetaResult(
              jsonBody['id'],
              request,
              'wamp.subscription.count_subscribers',
              argumentsKeywords: const <String, Object?>{'count': 1},
            );
            return;
          case 'app.echo':
            await _writeToolResult(jsonBody['id'], request, <String, Object?>{
              'echo': arguments,
            });
            return;
        }
        break;
      case 'app.echo':
        final params = _jsonMapFrom(jsonBody['params'], label: 'echo params');
        await _writeToolResult(jsonBody['id'], request, <String, Object?>{
          'echo': params,
        });
        return;
      case 'wamp.registration.match':
        await _writeWampMetaResult(
          jsonBody['id'],
          request,
          'wamp.registration.match',
          arguments: const <Object?>[11],
        );
        return;
    }

    await _writeJson(request, <String, Object?>{
      'jsonrpc': '2.0',
      'id': jsonBody['id'],
      'error': <String, Object?>{
        'code': -32601,
        'message': 'unsupported method',
      },
    });
  }

  Future<void> _writeToolResult(
    Object? id,
    HttpRequest request,
    Map<String, Object?> structuredContent,
  ) async {
    await _writeJson(request, <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': jsonEncode(structuredContent),
          },
        ],
        'structuredContent': structuredContent,
        'isError': false,
      },
    });
  }

  Future<void> _writeWampMetaResult(
    Object? id,
    HttpRequest request,
    String procedure, {
    List<Object?> arguments = const <Object?>[],
    Map<String, Object?> argumentsKeywords = const <String, Object?>{},
  }) async {
    await _writeToolResult(id, request, <String, Object?>{
      'procedure': procedure,
      if (arguments.isNotEmpty) 'arguments': arguments,
      if (argumentsKeywords.isNotEmpty) 'argumentsKeywords': argumentsKeywords,
    });
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

final class _AuthBackedMcpEndpoint {
  _AuthBackedMcpEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final authRequests = <_SeenAuthRequest>[];
  final mcpRequests = <_SeenAuthorizedMcpRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;

  Uri get authUri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/auth',
  );

  Uri get mcpUri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_AuthBackedMcpEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _AuthBackedMcpEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    switch (request.uri.path) {
      case '/auth':
        await _handleAuth(request);
        return;
      case '/mcp':
        await _handleMcp(request);
        return;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _handleAuth(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final jsonBody = _jsonMapFrom(jsonDecode(body), label: 'auth request');
    authRequests.add(_SeenAuthRequest.from(request, jsonBody));

    switch (jsonBody['grant_type']) {
      case 'refresh_token':
        expect(jsonBody['refresh_token'], _ioRefreshToken);
        await _writeJson(request, <String, Object?>{
          'status': 'ok',
          'token_type': 'Bearer',
          'access_token': _ioRefreshedAccessToken,
          'refresh_token': _ioRefreshedRefreshToken,
          'realm': _ioAuthRealm,
          'authid': _ioAuthId,
          'authrole': _ioAuthRole,
          'authmethod': 'ticket',
        });
        return;
      case 'revoke':
        expect(jsonBody['token'], _ioRefreshedRefreshToken);
        await _writeJson(request, const <String, Object?>{'status': 'revoked'});
        return;
      case null:
        if (!jsonBody.containsKey('state')) {
          expect(jsonBody['realm'], _ioAuthRealm);
          expect(jsonBody['authmethod'], 'ticket');
          expect(jsonBody['authid'], _ioAuthId);
          await _writeJson(request, const <String, Object?>{
            'state': _ioAuthState,
            'challenge': <String, Object?>{},
          }, statusCode: HttpStatus.unauthorized);
          return;
        }
        expect(jsonBody['state'], _ioAuthState);
        expect(jsonBody['signature'], _ioTicketSecret);
        await _writeJson(request, <String, Object?>{
          'status': 'ok',
          'token_type': 'Bearer',
          'access_token': _ioAccessToken,
          'refresh_token': _ioRefreshToken,
          'realm': _ioAuthRealm,
          'authid': _ioAuthId,
          'authrole': _ioAuthRole,
          'authmethod': 'ticket',
          'authprovider': 'consumer-local',
          'expires_in': 60,
          'refresh_token_expires_in': 600,
        });
        return;
      default:
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
    }
  }

  Future<void> _handleMcp(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final jsonBody = _jsonMapFrom(jsonDecode(body), label: 'mcp request');
    mcpRequests.add(_SeenAuthorizedMcpRequest.from(request, jsonBody));

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $_ioAccessToken') {
      await _writeJson(request, const <String, Object?>{
        'error': <String, Object?>{'code': 401, 'message': 'unauthorized'},
      }, statusCode: HttpStatus.unauthorized);
      return;
    }

    switch (jsonBody['method']) {
      case 'initialize':
        request.response.headers.set('MCP-Session-Id', _ioAuthSessionId);
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': jsonBody['id'],
          'result': <String, Object?>{
            'protocolVersion': mcpLatestProtocolVersion,
            'capabilities': <String, Object?>{'tools': <String, Object?>{}},
            'serverInfo': <String, Object?>{
              'name': 'io-auth-fake',
              'version': '1.0.0',
            },
          },
        });
        return;
      case 'ping':
        expect(request.headers.value('MCP-Session-Id'), _ioAuthSessionId);
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': jsonBody['id'],
          'result': <String, Object?>{},
        });
        return;
      default:
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': jsonBody['id'],
          'error': <String, Object?>{
            'code': -32601,
            'message': 'unsupported method',
          },
        });
        return;
    }
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

final class _SeenAuthRequest {
  const _SeenAuthRequest(this.method, this.body);

  final String method;
  final Map<String, Object?> body;

  factory _SeenAuthRequest.from(
    HttpRequest request,
    Map<String, Object?> body,
  ) {
    return _SeenAuthRequest(request.method, body);
  }
}

final class _SeenAuthorizedMcpRequest {
  const _SeenAuthorizedMcpRequest({
    required this.authorization,
    required this.sessionId,
    required this.body,
  });

  final String? authorization;
  final String? sessionId;
  final Map<String, Object?> body;

  factory _SeenAuthorizedMcpRequest.from(
    HttpRequest request,
    Map<String, Object?> body,
  ) {
    return _SeenAuthorizedMcpRequest(
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      body: body,
    );
  }
}

final class _SeenRequest {
  const _SeenRequest({
    required this.accept,
    required this.sessionId,
    required this.body,
  });

  final String? accept;
  final String? sessionId;
  final Map<String, Object?> body;

  factory _SeenRequest.from(HttpRequest request, Map<String, Object?> body) {
    return _SeenRequest(
      accept: request.headers.value(HttpHeaders.acceptHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      body: body,
    );
  }
}

final class _StreamableMcpEndpoint {
  _StreamableMcpEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final requests = <_StreamableSeenRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;
  var _eventCounter = 0;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_StreamableMcpEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _StreamableMcpEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'GET') {
      requests.add(_StreamableSeenRequest.from(request, null));
      final eventId = request.headers.value('Last-Event-ID') == null
          ? 'io-session-1:get:1'
          : 'io-session-1:get:2';
      final method = eventId.endsWith(':1')
          ? 'notifications/tools/list_changed'
          : 'notifications/resources/list_changed';
      await _writeSseEvent(
        request,
        id: eventId,
        event: 'message',
        retryMs: 1000,
        data: <String, Object?>{
          'jsonrpc': '2.0',
          'method': method,
          'params': <String, Object?>{'source': 'io-entrypoint'},
        },
      );
      return;
    }

    if (request.method == 'DELETE') {
      requests.add(_StreamableSeenRequest.from(request, null));
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final message = jsonDecode(body);
    requests.add(_StreamableSeenRequest.from(request, message));

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final response = _responseFor(request, message);
    if (response == null) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }

    if (_shouldWriteSse(request, message)) {
      await _writeSse(request, _jsonMapFrom(response, label: 'SSE response'));
      return;
    }
    await _writeJsonValue(request, response);
  }

  Object? _responseFor(HttpRequest request, Object? message) {
    if (message case final List<Object?> batch) {
      return <Object?>[
        for (final item in batch)
          if (item case final Map<Object?, Object?> map)
            if (map['id'] != null)
              _responseForSingle(request, <String, Object?>{
                for (final entry in map.entries)
                  if (entry.key case final String key) key: entry.value,
              }),
      ];
    }
    if (message case final Map<Object?, Object?> map) {
      final json = <String, Object?>{
        for (final entry in map.entries)
          if (entry.key case final String key) key: entry.value,
      };
      if (json['id'] == null) {
        return null;
      }
      return _responseForSingle(request, json);
    }
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': null,
      'error': <String, Object?>{'code': -32600, 'message': 'invalid request'},
    };
  }

  Map<String, Object?> _responseForSingle(
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    final id = message['id'];
    switch (message['method']) {
      case 'initialize':
        request.response.headers.set('MCP-Session-Id', 'io-session-1');
        request.response.headers.set(
          'MCP-Protocol-Version',
          mcpLatestProtocolVersion,
        );
        return _result(id, <String, Object?>{
          'protocolVersion': mcpLatestProtocolVersion,
          'capabilities': <String, Object?>{},
          'serverInfo': <String, Object?>{
            'name': 'io-entrypoint-test',
            'version': '1.0.0',
          },
        });
      case 'resources/list':
        return _result(id, <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{
              'uri': _ioResourceUri,
              'name': 'io-context',
              'mimeType': 'text/plain',
            },
          ],
        });
      case 'resources/read':
        final params = _jsonMapFrom(
          message['params'],
          label: 'resource params',
        );
        final uri = params['uri'];
        if (uri != _ioResourceUri) {
          return _error(id, -32004, 'Resource not found: $uri');
        }
        return _result(id, <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'uri': _ioResourceUri,
              'mimeType': 'text/plain',
              'text': 'IO entrypoint resource context',
            },
          ],
        });
      case 'prompts/get':
        final params = _jsonMapFrom(message['params'], label: 'prompt params');
        if (params['name'] != _ioPromptName) {
          return _error(id, -32004, 'Prompt not found: ${params['name']}');
        }
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'prompt arguments',
        );
        return _result(id, <String, Object?>{
          'description': 'Summarize a task.',
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'Summarize ${arguments['taskId']}.',
              },
            },
          ],
        });
      case 'tools/call':
        final params = _jsonMapFrom(message['params'], label: 'tool params');
        return _responseForToolCall(
          id,
          params['name'],
          _jsonMapFrom(params['arguments'], label: 'tool arguments'),
        );
      case 'connectanum.tool.call':
        final params = _jsonMapFrom(
          message['params'],
          label: 'direct tool params',
        );
        return _responseForToolCall(
          id,
          params['name'],
          _jsonMapFrom(params['arguments'], label: 'direct tool arguments'),
        );
      default:
        return _error(id, -32601, 'unsupported method');
    }
  }

  Map<String, Object?> _responseForToolCall(
    Object? id,
    Object? toolName,
    Map<String, Object?> arguments,
  ) {
    switch (toolName) {
      case 'connectanum.pubsub.subscribe':
        return _toolResult(id, <String, Object?>{
          'handle': _ioSubscriptionHandle,
          'topic': arguments['topic'],
          'subscriptionId': 17,
          'queueLimit': arguments['queueLimit'],
        });
      case 'connectanum.pubsub.publish':
        return _toolResult(id, <String, Object?>{
          'topic': arguments['topic'],
          'acknowledged': true,
          'publicationId': 42,
        });
      case 'connectanum.pubsub.poll':
        if (arguments['handle'] != _ioSubscriptionHandle) {
          return _toolError(
            id,
            'subscription not found: ${arguments['handle']}',
          );
        }
        return _toolResult(id, <String, Object?>{
          'handle': arguments['handle'],
          'topic': _ioTopic,
          'events': <Object?>[
            <String, Object?>{
              'subscriptionId': 17,
              'publicationId': 42,
              'topic': _ioTopic,
              'argumentsKeywords': <String, Object?>{'message': 'streamable'},
            },
          ],
          'dropped': 0,
          'remaining': 0,
        });
      case 'connectanum.pubsub.unsubscribe':
        return _toolResult(id, <String, Object?>{
          'handle': arguments['handle'],
          'topic': _ioTopic,
          'unsubscribed': true,
        });
      default:
        return _error(id, -32601, 'unsupported tool: $toolName');
    }
  }

  Map<String, Object?> _toolResult(
    Object? id,
    Map<String, Object?> structuredContent,
  ) {
    return _result(id, <String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': jsonEncode(structuredContent),
        },
      ],
      'structuredContent': structuredContent,
      'isError': false,
    });
  }

  Map<String, Object?> _toolError(Object? id, String message) {
    return _result(id, <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': message},
      ],
      'isError': true,
    });
  }

  bool _shouldWriteSse(HttpRequest request, Object? message) {
    final acceptsSse =
        request.headers
            .value(HttpHeaders.acceptHeader)
            ?.contains('text/event-stream') ??
        false;
    return acceptsSse && message is Map && message['method'] != 'initialize';
  }

  Future<void> _writeJsonValue(HttpRequest request, Object? body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeSse(HttpRequest request, Map<String, Object?> body) async {
    _eventCounter += 1;
    await _writeSseEvent(
      request,
      id: 'io-session-1:post:$_eventCounter',
      data: body,
    );
  }

  Future<void> _writeSseEvent(
    HttpRequest request, {
    required String id,
    String? event,
    int? retryMs,
    required Object? data,
  }) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.writeln('id: $id');
    if (event != null) {
      request.response.writeln('event: $event');
    }
    if (retryMs != null) {
      request.response.writeln('retry: $retryMs');
    }
    request.response.writeln('data: ${jsonEncode(data)}');
    request.response.writeln();
    await request.response.close();
  }

  Map<String, Object?> _result(Object? id, Map<String, Object?> result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, Object?> _error(Object? id, int code, String message) =>
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      };
}

final class _StreamableSeenRequest {
  const _StreamableSeenRequest({
    required this.method,
    required this.accept,
    required this.sessionId,
    required this.lastEventId,
    required this.body,
  });

  final String method;
  final String? accept;
  final String? sessionId;
  final String? lastEventId;
  final Object? body;

  factory _StreamableSeenRequest.from(HttpRequest request, Object? body) {
    return _StreamableSeenRequest(
      method: request.method,
      accept: request.headers.value(HttpHeaders.acceptHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      lastEventId: request.headers.value('Last-Event-ID'),
      body: body,
    );
  }
}

Map<String, Object?> _jsonRpcResult(
  Map<String, Object?> response, {
  required Object? id,
}) {
  expect(response['id'], id);
  expect(response, isNot(contains('error')));
  return _jsonMapFrom(response['result'], label: 'JSON-RPC result');
}

Map<String, Object?> _jsonMapFrom(Object? value, {required String label}) {
  if (value case final Map<Object?, Object?> map) {
    return <String, Object?>{
      for (final entry in map.entries)
        if (entry.key case final String key) key: entry.value,
    };
  }
  throw StateError('Expected $label to be a JSON object, got $value.');
}
