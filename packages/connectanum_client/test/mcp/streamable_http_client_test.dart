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

        final client = McpStreamableHttpClient(
          endpoint.uri,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer test-token',
          },
        );
        addTearDown(() => client.close(force: true));

        final initialize = await client.initialize(
          clientInfo: const <String, Object?>{
            'name': 'consumer-test',
            'version': '1.0.0',
          },
        );

        expect(client.sessionId, 'session-1');
        expect(
          client.protocolVersion,
          McpStreamableHttpClient.latestProtocolVersion,
        );
        expect(initialize['id'], 'initialize');

        await client.notifyInitialized();

        final tools = await client.request('tools/list', id: 'tools-sse');
        expect(tools['id'], 'tools-sse');
        expect(client.lastEventId, 'session-1:post:2');

        final pollEvents = await client.poll();
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
        );
        expect(jsonTools['id'], 'tools-json');

        final ping = await client.ping(id: 'ping-json', streamable: false);
        expect(ping, isEmpty);

        final streamableBatch = await client.postBatch([
          {'jsonrpc': '2.0', 'id': 'batch-sse', 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ]);
        expect(streamableBatch, hasLength(1));
        expect(streamableBatch?.single['id'], 'batch-sse');
        expect(client.lastEventId, 'session-1:post-batch:1');

        final jsonBatch = await client.postBatch([
          {'jsonrpc': '2.0', 'id': 'batch-json', 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ], streamable: false);
        expect(jsonBatch, hasLength(1));
        expect(jsonBatch?.single['id'], 'batch-json');

        await client.deleteSession();
        expect(client.sessionId, isNull);
        expect(client.lastEventId, isNull);

        expect(endpoint.requests, hasLength(9));
        expect(endpoint.requests[0].authorization, 'Bearer test-token');
        expect(endpoint.requests[0].accept, contains('text/event-stream'));
        expect(endpoint.requests[0].contentLength, greaterThan(0));
        expect(endpoint.requests[0].transferEncoding, isNull);
        expect(endpoint.requests[1].sessionId, 'session-1');
        expect(endpoint.requests[2].sessionId, 'session-1');
        expect(endpoint.requests[3].lastEventId, 'session-1:post:2');
        expect(endpoint.requests[4].accept, 'application/json');
        expect(endpoint.requests[5].accept, 'application/json');
        expect(endpoint.requests[5].body, containsPair('method', 'ping'));
        expect(endpoint.requests[6].accept, contains('text/event-stream'));
        expect(endpoint.requests[7].accept, 'application/json');
        expect(endpoint.requests[8].method, 'DELETE');
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
      );
      expect(page.nextCursor, isNull);
      expect(page.tools, hasLength(1));
      expect(page.tools.single['name'], 'app.echo');

      final result = await client.callTool(
        'app.echo',
        id: 'call-helper',
        arguments: {'message': 'hello'},
        streamable: false,
      );
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {
        'echo': {'message': 'hello'},
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
    });

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
      );
      expect(resources.nextCursor, isNull);
      expect(resources.resources, hasLength(1));
      expect(resources.resources.single['uri'], 'wamp://app/readme');

      final contents = await client.readResource(
        'wamp://app/readme',
        id: 'resource-read',
        streamable: false,
      );
      expect(contents, hasLength(1));
      expect(contents.single['text'], 'hello resource');

      final templates = await client.listResourceTemplates(
        id: 'resource-templates-helper',
        streamable: false,
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
      );
      expect(prompts.nextCursor, isNull);
      expect(prompts.prompts, hasLength(1));
      expect(prompts.prompts.single['name'], 'summarize');

      final prompt = await client.getPrompt(
        'summarize',
        id: 'prompt-get',
        arguments: {'topic': 'mcp'},
        streamable: false,
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
    });

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
      );
      expect(topic['topic'], 'app.events.audit');

      final subscription = await client.subscribeWampTopic(
        'app.events.audit',
        id: 'wamp-subscribe',
        queueLimit: 3,
        options: const <String, Object?>{'match': 'exact'},
        streamable: false,
      );
      expect(subscription.handle, 'wamp-sub-1');
      expect(subscription.topic, 'app.events.audit');
      expect(subscription.subscriptionId, 7);
      expect(subscription.queueLimit, 3);

      final publication = await client.publishWampEvent(
        'app.events.audit',
        id: 'wamp-publish',
        argumentsKeywords: const <String, Object?>{'message': 'hello'},
        acknowledge: true,
        streamable: false,
      );
      expect(publication.topic, 'app.events.audit');
      expect(publication.publicationId, 42);
      expect(publication.acknowledged, isTrue);

      final batch = await client.pollWampEvents(
        subscription.handle,
        id: 'wamp-poll',
        limit: 2,
        streamable: false,
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
      );
      expect(unsubscribe.handle, subscription.handle);
      expect(unsubscribe.topic, 'app.events.audit');
      expect(unsubscribe.unsubscribed, isTrue);

      await expectLater(
        client.subscribeWampTopic(
          'app.secure.audit',
          id: 'wamp-denied',
          streamable: false,
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
    });

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
      );
      expect(registrations.procedure, 'wamp.registration.list');
      expect(registrations.arguments, isEmpty);
      expect(registrations.argumentsKeywords['exact'], [11]);

      final registrationMatch = await client.callWampMetaProcedure(
        'wamp.registration.match',
        id: 'wamp-registration-match',
        arguments: const <Object?>['app.echo'],
        streamable: false,
      );
      expect(registrationMatch.arguments, [11]);
      expect(registrationMatch.argumentsKeywords, isEmpty);

      final registrationDetails = await client.callWampMetaProcedure(
        'wamp.registration.get',
        id: 'wamp-registration-get',
        argumentsKeywords: const <String, Object?>{'id': 11},
        streamable: false,
      );
      expect(registrationDetails.argumentsKeywords['uri'], 'app.echo');
      expect(registrationDetails.argumentsKeywords['match'], 'exact');

      final subscriptions = await client.callWampMetaProcedure(
        'wamp.subscription.lookup',
        id: 'wamp-subscription-lookup',
        argumentsKeywords: const <String, Object?>{'topic': 'app.events.audit'},
        streamable: false,
      );
      expect(subscriptions.arguments, [7]);

      final subscribers = await client.callWampMetaProcedure(
        'wamp.subscription.count_subscribers',
        id: 'wamp-subscription-count',
        arguments: const <Object?>[7],
        streamable: false,
      );
      expect(subscribers.arguments, [1]);

      expect(endpoint.requests.last.sessionId, 'session-1');
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
      );
      expect(sessionCount.procedure, 'wamp.session.count');
      expect(sessionCount.argumentsKeywords['count'], 2);

      final sessions = await client.listWampSessions(
        id: 'session-list',
        streamable: false,
      );
      expect(sessions.argumentsKeywords['session_ids'], [101, 102]);

      final session = await client.getWampSession(
        101,
        id: 'session-get',
        streamable: false,
      );
      expect(session.argumentsKeywords['details'], {
        'session': 101,
        'authid': 'anonymous',
      });

      final registrations = await client.listWampRegistrations(
        id: 'registration-list',
        streamable: false,
      );
      expect(registrations.argumentsKeywords['exact'], [11]);

      final lookup = await client.lookupWampRegistration(
        'app.echo',
        id: 'registration-lookup',
        match: 'exact',
        streamable: false,
      );
      expect(lookup.arguments, [11]);

      final match = await client.matchWampRegistration(
        'app.echo',
        id: 'registration-match-helper',
        streamable: false,
      );
      expect(match.arguments, [11]);

      final registration = await client.getWampRegistration(
        11,
        id: 'registration-get-helper',
        streamable: false,
      );
      expect(registration.argumentsKeywords['uri'], 'app.echo');

      final callees = await client.listWampRegistrationCallees(
        11,
        id: 'registration-callees',
        streamable: false,
      );
      expect(callees.arguments, [101]);

      final calleeCount = await client.countWampRegistrationCallees(
        11,
        id: 'registration-callee-count',
        streamable: false,
      );
      expect(calleeCount.arguments, [1]);

      final subscriptions = await client.listWampSubscriptions(
        id: 'subscription-list',
        streamable: false,
      );
      expect(subscriptions.argumentsKeywords['exact'], [7]);

      final lookupSubscription = await client.lookupWampSubscription(
        'app.events.audit',
        id: 'subscription-lookup-helper',
        match: 'exact',
        streamable: false,
      );
      expect(lookupSubscription.arguments, [7]);

      final matchingSubscriptions = await client.matchWampSubscription(
        'app.events.audit.created',
        id: 'subscription-match',
        streamable: false,
      );
      expect(matchingSubscriptions.arguments, [7]);

      final subscription = await client.getWampSubscription(
        7,
        id: 'subscription-get',
        streamable: false,
      );
      expect(subscription.argumentsKeywords['uri'], 'app.events.audit');

      final subscribers = await client.listWampSubscriptionSubscribers(
        7,
        id: 'subscription-subscribers',
        streamable: false,
      );
      expect(subscribers.arguments, [102]);

      final subscriberCount = await client.countWampSubscriptionSubscribers(
        7,
        id: 'subscription-subscriber-count',
        streamable: false,
      );
      expect(subscriberCount.arguments, [1]);

      expect(endpoint.requests.last.sessionId, 'session-1');
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

    switch (request.method) {
      case 'POST':
        await _handlePost(request, jsonBody);
        return;
      case 'GET':
        _writeSse(
          request,
          'id: session-1:get:1\n'
          'data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}\n\n',
        );
        return;
      case 'DELETE':
        request.response.statusCode = HttpStatus.accepted;
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
      if ((request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
        'text/event-stream',
      )) {
        _writeSse(
          request,
          'id: session-1:post-batch:1\n'
          'data: ${jsonEncode(responses)}\n\n',
        );
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
      _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestBody['id'],
        'result': <String, Object?>{
          'protocolVersion': McpStreamableHttpClient.latestProtocolVersion,
          'capabilities': <String, Object?>{},
          'serverInfo': <String, Object?>{
            'name': 'fake-router',
            'version': '1.0.0',
          },
        },
      }, sessionId: 'session-1');
      return;
    }

    if (method == 'notifications/initialized') {
      request.response.statusCode = HttpStatus.accepted;
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
            'inputSchema': <String, Object?>{'type': 'object'},
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

  void _writeJson(HttpRequest request, McpJsonMap body, {String? sessionId}) {
    _writeJsonValue(request, body, sessionId: sessionId);
  }

  void _writeJsonValue(HttpRequest request, Object? body, {String? sessionId}) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(
      _headerProtocolVersion,
      McpStreamableHttpClient.latestProtocolVersion,
    );
    if (sessionId != null) {
      request.response.headers.set(_headerSessionId, sessionId);
    }
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
      McpStreamableHttpClient.latestProtocolVersion,
    );
    request.response.headers.set(_headerSessionId, 'session-1');
    request.response.write(body);
    unawaited(request.response.close());
  }
}

const _headerProtocolVersion = 'MCP-Protocol-Version';
const _headerSessionId = 'MCP-Session-Id';

final class _SeenRequest {
  const _SeenRequest({
    required this.method,
    required this.accept,
    required this.authorization,
    required this.sessionId,
    required this.lastEventId,
    required this.contentLength,
    required this.transferEncoding,
    required this.body,
  });

  final String method;
  final String? accept;
  final String? authorization;
  final String? sessionId;
  final String? lastEventId;
  final int contentLength;
  final String? transferEncoding;
  final Object? body;

  factory _SeenRequest.from(HttpRequest request, Object? body) {
    return _SeenRequest(
      method: request.method,
      accept: request.headers.value(HttpHeaders.acceptHeader),
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      sessionId: request.headers.value(_headerSessionId),
      lastEventId: request.headers.value('Last-Event-ID'),
      contentLength: request.headers.contentLength,
      transferEncoding: request.headers.value(
        HttpHeaders.transferEncodingHeader,
      ),
      body: body,
    );
  }
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
