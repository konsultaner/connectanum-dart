import 'dart:async';
import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpWampApi', () {
    test('generates procedure tools and API metadata tools', () async {
      late McpWampToolCall capturedCall;
      final api = McpWampApi(
        name: 'demo',
        procedures: [
          McpWampProcedure(
            procedure: 'app.echo',
            toolName: 'echo',
            title: 'Echo',
            description: 'Echoes a message through WAMP.',
            inputSchema: const {
              'type': 'object',
              'properties': {
                'text': {'type': 'string'},
              },
              'required': ['text'],
            },
            metadata: const McpWampApiMetadata(
              domain: 'demo',
              entity: 'message',
              verbs: ['echo'],
              tags: ['safe'],
            ),
          ),
        ],
      );
      final server = _server(
        api.toTools(
          call: (call) {
            capturedCall = call;
            return (
              callRequestId: 1,
              progress: false,
              pptScheme: null,
              pptSerializer: null,
              pptCipher: null,
              pptKeyId: null,
              customDetails: null,
              arguments: null,
              argumentsKeywords: {'echo': call.payload.argumentsKeywords},
            );
          },
          includePubSubTools: false,
        ),
      );
      await _initializeAndStart(server);

      final listResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 10,
        'method': 'tools/list',
        'params': {},
      });
      final tools = (listResponse?['result'] as Map)['tools'] as List;
      expect(tools.map((tool) => tool['name']), containsAll(['echo']));
      expect(
        tools.map((tool) => tool['name']),
        containsAll(['connectanum.api.list', 'connectanum.api.describe']),
      );

      final callResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 11,
        'method': 'tools/call',
        'params': {
          'name': 'echo',
          'arguments': {'text': 'hello'},
        },
      });
      expect(capturedCall.procedure, 'app.echo');
      expect(capturedCall.payload.argumentsKeywords, {'text': 'hello'});
      final callResult = callResponse?['result'] as Map<String, Object?>;
      expect(callResult['isError'], isFalse);

      final metaResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 12,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.list',
          'arguments': {'kind': 'procedure', 'tag': 'safe'},
        },
      });
      final metaResult = metaResponse?['result'] as Map<String, Object?>;
      final metadata = metaResult['structuredContent'] as Map<String, Object?>;
      final procedures = metadata['procedures'] as List;
      expect(procedures.single['uri'], 'app.echo');
      expect(procedures.single['metadata'], containsPair('domain', 'demo'));
    });

    test('connectanum.api.list returns deterministic URI ordering', () async {
      final api = McpWampApi(
        procedures: [
          McpWampProcedure(procedure: 'app.gamma', allowCall: false),
          McpWampProcedure(procedure: 'app.alpha', allowCall: false),
          McpWampProcedure(procedure: 'app.beta', allowCall: false),
        ],
        topics: [
          McpWampTopic(topic: 'app.topic.gamma'),
          McpWampTopic(topic: 'app.topic.alpha'),
          McpWampTopic(topic: 'app.topic.beta'),
        ],
      );
      final server = _server(api.toTools(includePubSubTools: false));
      await _initializeAndStart(server);

      final metaResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 13,
        'method': 'tools/call',
        'params': {'name': 'connectanum.api.list', 'arguments': {}},
      });

      final metaResult = metaResponse?['result'] as Map<String, Object?>;
      final metadata = metaResult['structuredContent'] as Map<String, Object?>;
      expect(_catalogUris(metadata['procedures']), [
        'app.alpha',
        'app.beta',
        'app.gamma',
      ]);
      expect(_catalogUris(metadata['topics']), [
        'app.topic.alpha',
        'app.topic.beta',
        'app.topic.gamma',
      ]);
    });

    test(
      'connectanum.api.list paginates deterministic filtered catalogs',
      () async {
        expect(
          () => McpWampApi(listPageSize: 0),
          throwsArgumentError,
        );

        final api = McpWampApi(
          listPageSize: 2,
          procedures: [
            McpWampProcedure(procedure: 'app.gamma', allowCall: false),
            McpWampProcedure(procedure: 'app.alpha', allowCall: false),
            McpWampProcedure(procedure: 'app.beta', allowCall: false),
          ],
          topics: [
            McpWampTopic(topic: 'app.topic.beta'),
            McpWampTopic(topic: 'app.topic.alpha'),
          ],
        );
        final server = _server(api.toTools(includePubSubTools: false));
        await _initializeAndStart(server);

        Future<Map<String, Object?>> listPage({
          required int id,
          String? kind,
          String? cursor,
        }) async {
          final response = await server.handleMessage({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'tools/call',
            'params': {
              'name': 'connectanum.api.list',
              'arguments': {
                'kind': ?kind,
                'cursor': ?cursor,
              },
            },
          });
          final result = response?['result'] as Map<String, Object?>;
          return result['structuredContent'] as Map<String, Object?>;
        }

        final first = await listPage(id: 14, kind: 'procedure');
        expect(_catalogUris(first['procedures']), ['app.alpha', 'app.beta']);
        expect(first['nextCursor'], isA<String>());

        final procedureCursor = first['nextCursor']! as String;
        final second = await listPage(
          id: 15,
          kind: 'procedure',
          cursor: procedureCursor,
        );
        expect(_catalogUris(second['procedures']), ['app.gamma']);
        expect(second, isNot(contains('nextCursor')));

        final combinedFirst = await listPage(id: 16);
        expect(_catalogUris(combinedFirst['procedures']), [
          'app.alpha',
          'app.beta',
        ]);
        expect(_catalogUris(combinedFirst['topics']), isEmpty);

        final combinedSecond = await listPage(
          id: 17,
          cursor: combinedFirst['nextCursor']! as String,
        );
        expect(_catalogUris(combinedSecond['procedures']), ['app.gamma']);
        expect(_catalogUris(combinedSecond['topics']), ['app.topic.alpha']);

        final mismatchedQuery = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 18,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'topic', 'cursor': procedureCursor},
          },
        });
        expect(
          mismatchedQuery?['error'],
          containsPair('code', McpErrorCodes.invalidParams),
        );

        final refreshedServer = _server(
          McpWampApi(
            listPageSize: 2,
            procedures: [
              McpWampProcedure(procedure: 'app.alpha', allowCall: false),
              McpWampProcedure(procedure: 'app.beta', allowCall: false),
              McpWampProcedure(procedure: 'app.gamma', allowCall: false),
            ],
          ).toTools(includePubSubTools: false),
        );
        await _initializeAndStart(refreshedServer);
        final staleCatalog = await refreshedServer.handleMessage({
          'jsonrpc': '2.0',
          'id': 19,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {
              'kind': 'procedure',
              'cursor': procedureCursor,
            },
          },
        });
        expect(
          staleCatalog?['error'],
          containsPair('code', McpErrorCodes.invalidParams),
        );
      },
    );

    test('maps WAMP safety metadata to MCP tool annotations', () async {
      final api = McpWampApi(
        procedures: [
          McpWampProcedure(
            procedure: 'app.safe.lookup',
            metadata: const McpWampApiMetadata(
              tags: ['safe'],
              readOnlyHint: true,
              destructiveHint: false,
              idempotentHint: true,
              openWorldHint: false,
            ),
          ),
          McpWampProcedure(
            procedure: 'app.unsafe.delete',
            metadata: const McpWampApiMetadata(
              tags: ['unsafe'],
              danger: true,
              openWorldHint: false,
            ),
          ),
          McpWampProcedure(
            procedure: 'app.documented.only',
            allowCall: false,
            metadata: const McpWampApiMetadata(tags: ['documented']),
          ),
        ],
      );
      final server = _server(
        api.toTools(
          call: (_) => (
            callRequestId: 1,
            progress: false,
            pptScheme: null,
            pptSerializer: null,
            pptCipher: null,
            pptKeyId: null,
            customDetails: null,
            arguments: null,
            argumentsKeywords: const <String, dynamic>{},
          ),
          includePubSubTools: false,
        ),
      );
      await _initializeAndStart(server);

      final listResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 15,
        'method': 'tools/list',
        'params': {},
      });
      final tools = (listResponse?['result'] as Map)['tools'] as List;
      final byName = {
        for (final tool in tools.cast<Map>())
          tool['name'] as String: tool.cast<String, Object?>(),
      };
      expect(byName, contains('app.safe.lookup'));
      expect(byName, contains('app.unsafe.delete'));
      expect(byName, isNot(contains('app.documented.only')));
      expect(
        byName['app.safe.lookup']?['annotations'],
        containsPair('readOnlyHint', true),
      );
      expect(
        byName['app.safe.lookup']?['annotations'],
        containsPair('destructiveHint', false),
      );
      expect(
        byName['app.unsafe.delete']?['annotations'],
        containsPair('destructiveHint', true),
      );

      final metaResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 16,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.describe',
          'arguments': {'uri': 'app.documented.only'},
        },
      });
      final meta =
          (metaResponse?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(meta['allowCall'], isFalse);
    });

    test('advertises named standard WAMP meta inputs and outputs', () async {
      final api = McpWampApi(includeStandardMetaApi: true);
      final server = _server(
        api.toTools(
          call: (_) => throw StateError('catalog test must not invoke WAMP'),
          includePubSubTools: false,
        ),
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 19,
        'method': 'tools/list',
        'params': {},
      });
      final tools = (response?['result'] as Map)['tools'] as List;
      final byName = <String, Map>{
        for (final tool in tools.cast<Map>()) tool['name'] as String: tool,
      };
      final expectedNamedInputs = <String, String?>{
        'wamp.session.count': null,
        'wamp.session.list': null,
        'wamp.session.get': 'sessionId',
        'wamp.registration.list': null,
        'wamp.registration.lookup': 'procedure',
        'wamp.registration.match': 'procedure',
        'wamp.registration.get': 'registrationId',
        'wamp.registration.list_callees': 'registrationId',
        'wamp.registration.count_callees': 'registrationId',
        'wamp.subscription.list': null,
        'wamp.subscription.lookup': 'topic',
        'wamp.subscription.match': 'topic',
        'wamp.subscription.get': 'subscriptionId',
        'wamp.subscription.list_subscribers': 'subscriptionId',
        'wamp.subscription.count_subscribers': 'subscriptionId',
      };

      for (final entry in expectedNamedInputs.entries) {
        final tool = byName[entry.key]!;
        final inputSchema = tool['inputSchema'] as Map;
        final properties = inputSchema['properties'] as Map;
        expect(
          properties,
          containsPair('arguments', isA<Map>()),
          reason: entry.key,
        );
        expect(
          properties,
          containsPair('argumentsKeywords', isA<Map>()),
          reason: entry.key,
        );
        expect(inputSchema['additionalProperties'], isFalse, reason: entry.key);
        if (entry.value != null) {
          expect(properties, contains(entry.value), reason: entry.key);
          expect(
            (inputSchema['anyOf'] as List).map(
              (alternative) => (alternative as Map)['required'],
            ),
            contains(equals(<String>[entry.value!])),
            reason: entry.key,
          );
        }
        expect(
          tool['outputSchema'],
          {
            'type': 'object',
            'properties': {
              'arguments': {'type': 'array'},
              'argumentsKeywords': {
                'type': 'object',
                'additionalProperties': true,
              },
              'details': {
                'type': 'object',
                'additionalProperties': true,
              },
            },
            'additionalProperties': false,
          },
          reason: entry.key,
        );
      }
      expect(
        (byName['wamp.registration.lookup']!['inputSchema']
            as Map)['properties'],
        containsPair(
          'match',
          containsPair('enum', ['exact', 'prefix', 'wildcard']),
        ),
      );
      expect(
        (byName['wamp.subscription.lookup']!['inputSchema']
            as Map)['properties'],
        containsPair(
          'match',
          containsPair('enum', ['exact', 'prefix', 'wildcard']),
        ),
      );
      expect(
        (byName['wamp.session.get']!['inputSchema'] as Map)['properties'],
        allOf(contains('id'), contains('session')),
      );
      expect(
        (byName['wamp.registration.lookup']!['inputSchema']
            as Map)['properties'],
        contains('uri'),
      );
      expect(
        (byName['wamp.registration.get']!['inputSchema'] as Map)['properties'],
        allOf(contains('id'), contains('registration')),
      );
      expect(
        (byName['wamp.subscription.get']!['inputSchema'] as Map)['properties'],
        allOf(contains('id'), contains('subscription')),
      );
    });

    test('maps named standard WAMP meta inputs to standard payloads', () async {
      final capturedCalls = <McpWampToolCall>[];
      final api = McpWampApi(includeStandardMetaApi: true);
      final server = _server(
        api.toTools(
          call: (call) {
            capturedCalls.add(call);
            return (
              callRequestId: 2,
              progress: false,
              pptScheme: null,
              pptSerializer: null,
              pptCipher: null,
              pptKeyId: null,
              customDetails: null,
              arguments: const [
                {'id': 123, 'uri': 'app.echo'},
              ],
              argumentsKeywords: null,
            );
          },
          includePubSubTools: false,
        ),
      );
      await _initializeAndStart(server);

      final cases = <(String, Map<String, Object?>, List<Object?>, JsonMap?)>[
        ('wamp.session.get', {'sessionId': 123}, [123], null),
        (
          'wamp.registration.lookup',
          {'procedure': 'app.echo', 'match': 'prefix'},
          ['app.echo'],
          {'match': 'prefix'},
        ),
        (
          'wamp.registration.match',
          {'procedure': 'app.echo'},
          ['app.echo'],
          null,
        ),
        ('wamp.registration.get', {'registrationId': 123}, [123], null),
        (
          'wamp.registration.list_callees',
          {'registrationId': 123},
          [123],
          null,
        ),
        (
          'wamp.registration.count_callees',
          {'registrationId': 123},
          [123],
          null,
        ),
        (
          'wamp.subscription.lookup',
          {'topic': 'app.events', 'match': 'wildcard'},
          ['app.events'],
          {'match': 'wildcard'},
        ),
        (
          'wamp.subscription.match',
          {'topic': 'app.events'},
          ['app.events'],
          null,
        ),
        ('wamp.subscription.get', {'subscriptionId': 456}, [456], null),
        (
          'wamp.subscription.list_subscribers',
          {'subscriptionId': 456},
          [456],
          null,
        ),
        (
          'wamp.subscription.count_subscribers',
          {'subscriptionId': 456},
          [456],
          null,
        ),
      ];

      for (final (index, testCase) in cases.indexed) {
        final (procedure, arguments, _, _) = testCase;
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 20 + index,
          'method': 'tools/call',
          'params': {'name': procedure, 'arguments': arguments},
        });
        expect(response?['result'], isA<Map<String, Object?>>());
      }

      for (final (index, capturedCall) in capturedCalls.indexed) {
        final (procedure, _, positional, keywords) = cases[index];
        expect(capturedCall.procedure, procedure);
        expect(capturedCall.payload.arguments, positional, reason: procedure);
        expect(
          capturedCall.payload.argumentsKeywords,
          keywords,
          reason: procedure,
        );
      }
    });

    test('preserves raw standard WAMP meta payload compatibility', () async {
      final capturedCalls = <McpWampToolCall>[];
      final api = McpWampApi(includeStandardMetaApi: true);
      final server = _server(
        api.toTools(
          call: (call) {
            capturedCalls.add(call);
            return (
              callRequestId: 3,
              progress: false,
              pptScheme: null,
              pptSerializer: null,
              pptCipher: null,
              pptKeyId: null,
              customDetails: null,
              arguments: const <Object?>[],
              argumentsKeywords: null,
            );
          },
          includePubSubTools: false,
        ),
      );
      await _initializeAndStart(server);

      final rawResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 31,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.registration.lookup',
          'arguments': {
            'arguments': ['app.echo'],
            'argumentsKeywords': {'match': 'exact'},
          },
        },
      });
      expect((rawResponse?['result'] as Map)['isError'], isFalse);
      expect(capturedCalls.single.payload.arguments, ['app.echo']);
      expect(capturedCalls.single.payload.argumentsKeywords, {
        'match': 'exact',
      });

      final aliasResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 32,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.registration.get',
          'arguments': {'id': 789},
        },
      });
      expect((aliasResponse?['result'] as Map)['isError'], isFalse);
      expect(capturedCalls.last.payload.arguments, [789]);

      final mixedResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 33,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.registration.get',
          'arguments': {
            'registrationId': 123,
            'arguments': [456],
          },
        },
      });
      final mixedResult = mixedResponse?['result'] as Map<String, Object?>;
      expect(mixedResult['isError'], isTrue);
      expect(
        mixedResult['content'],
        contains(
          containsPair(
            'text',
            contains('cannot combine named and raw WAMP arguments'),
          ),
        ),
      );
      final invalidCases = <(String, JsonMap, String)>[
        (
          'wamp.registration.get',
          {'registrationId': 0},
          'must be a positive integer',
        ),
        (
          'wamp.registration.get',
          {'registrationId': 123, 'id': 123},
          'cannot combine standard WAMP Meta parameter aliases',
        ),
        (
          'wamp.registration.lookup',
          {'procedure': 'app.echo', 'match': 'glob'},
          'must be exact, prefix, or wildcard',
        ),
        (
          'wamp.session.count',
          {'unexpected': true},
          'unsupported standard WAMP Meta fields',
        ),
      ];
      for (final (index, invalidCase) in invalidCases.indexed) {
        final (toolName, arguments, message) = invalidCase;
        final invalidResponse = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 34 + index,
          'method': 'tools/call',
          'params': {'name': toolName, 'arguments': arguments},
        });
        final invalidResult =
            invalidResponse?['result'] as Map<String, Object?>;
        expect(invalidResult['isError'], isTrue, reason: toolName);
        expect(
          invalidResult['content'],
          contains(containsPair('text', contains(message))),
          reason: toolName,
        );
      }
      expect(capturedCalls, hasLength(2));
    });

    test('publishes and polls declared WAMP topics through MCP', () async {
      late McpWampPublishRequest published;
      late McpWampSubscribeRequest subscribed;
      late void Function(McpWampEvent event) onEvent;
      late McpWampSubscription unsubscribed;
      final api = McpWampApi(
        topics: [
          McpWampTopic(
            topic: 'app.events',
            description: 'Application events.',
            eventSchema: const {
              'type': 'object',
              'properties': {
                'message': {'type': 'string'},
              },
            },
          ),
        ],
      );
      final server = _server(
        api.toTools(
          publish: (request) {
            published = request;
            return const McpWampPublication(
              publicationId: 99,
              acknowledged: true,
            );
          },
          subscribe: (request, handler) {
            subscribed = request;
            onEvent = handler;
            return const McpWampSubscription(
              topic: 'app.events',
              subscriptionId: 7,
            );
          },
          unsubscribe: (subscription) {
            unsubscribed = subscription;
          },
        ),
      );
      await _initializeAndStart(server);

      final publishResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 30,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': 'app.events',
            'argumentsKeywords': {'message': 'hello'},
            'acknowledge': true,
            'options': {
              'acknowledge': false,
              'exclude': [123],
              'exclude_authid': ['blocked-user'],
              'exclude_authrole': ['blocked-role'],
              'eligible': [456],
              'eligibleAuthId': ['allowed-user'],
              'eligibleAuthRole': ['allowed-role'],
              'exclude_me': false,
              'discloseMe': true,
              'retain': true,
              'ppt_scheme': 'wamp',
              'pptSerializer': 'cbor',
              'ppt_cipher': 'xsalsa20poly1305',
              'pptKeyId': 'task-key',
              'x_app_trace': 'custom-publish',
            },
          },
        },
      });
      expect(published.topic, 'app.events');
      expect(published.argumentsKeywords, {'message': 'hello'});
      expect(published.options?.acknowledge, isTrue);
      expect(published.options?.exclude, [123]);
      expect(published.options?.excludeAuthId, ['blocked-user']);
      expect(published.options?.excludeAuthRole, ['blocked-role']);
      expect(published.options?.eligible, [456]);
      expect(published.options?.eligibleAuthId, ['allowed-user']);
      expect(published.options?.eligibleAuthRole, ['allowed-role']);
      expect(published.options?.excludeMe, isFalse);
      expect(published.options?.discloseMe, isTrue);
      expect(published.options?.retain, isTrue);
      expect(published.options?.pptScheme, 'wamp');
      expect(published.options?.pptSerializer, 'cbor');
      expect(published.options?.pptCipher, 'xsalsa20poly1305');
      expect(published.options?.pptKeyId, 'task-key');
      expect(published.options?.custom, {'x_app_trace': 'custom-publish'});
      final publishResult = publishResponse?['result'] as Map<String, Object?>;
      expect(
        publishResult['structuredContent'],
        containsPair('publicationId', 99),
      );

      final subscribeResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 31,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {
            'topic': 'app.events',
            'queueLimit': 1,
            'options': {
              'match': 'prefix',
              'metaTopic': 'app.events.meta',
              'get_retained': true,
              'x_app_subscription': 'custom-subscribe',
            },
          },
        },
      });
      final handle =
          (subscribeResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(handle['subscriptionId'], 7);
      expect(subscribed.topic, 'app.events');
      expect(subscribed.queueLimit, 1);
      expect(subscribed.options?.match, 'prefix');
      expect(subscribed.options?.metaTopic, 'app.events.meta');
      expect(subscribed.options?.getRetained, isTrue);
      expect(subscribed.options?.custom, {
        'x_app_subscription': 'custom-subscribe',
      });

      onEvent(
        const McpWampEvent(
          subscriptionId: 7,
          publicationId: 100,
          topic: 'app.events',
          argumentsKeywords: {'message': 'hello'},
        ),
      );
      final pollResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 32,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': handle['handle']},
        },
      });
      final pollResult =
          (pollResponse?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(jsonEncode(pollResult['events']), contains('hello'));

      await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 33,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': handle['handle']},
        },
      });
      expect(unsubscribed.subscriptionId, 7);
    });

    test('reuses pubsub state across refreshed WAMP API catalogs', () async {
      late void Function(McpWampEvent event) onEvent;
      late McpWampSubscription unsubscribed;
      final state = McpWampPubSubState();

      McpWampSubscription subscribe(
        McpWampSubscribeRequest request,
        void Function(McpWampEvent event) handler,
      ) {
        onEvent = handler;
        return McpWampSubscription(topic: request.topic, subscriptionId: 7);
      }

      void unsubscribe(McpWampSubscription subscription) {
        unsubscribed = subscription;
      }

      final api = McpWampApi(topics: [McpWampTopic(topic: 'app.events')]);
      final server = _server(
        api.toTools(
          subscribe: subscribe,
          unsubscribe: unsubscribe,
          pubSubState: state,
        ),
      );
      await _initializeAndStart(server);

      final subscribeResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 40,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.events'},
        },
      });
      final subscription =
          (subscribeResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      final handle = subscription['handle'] as String;

      final refreshedApi = McpWampApi(
        topics: [
          McpWampTopic(topic: 'app.events'),
          McpWampTopic(topic: 'app.events.refreshed'),
        ],
      );
      server.tools.replaceAll(
        refreshedApi.toTools(
          subscribe: subscribe,
          unsubscribe: unsubscribe,
          pubSubState: state,
        ),
      );

      final catalogResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 41,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.list',
          'arguments': {'kind': 'topic'},
        },
      });
      expect(jsonEncode(catalogResponse), contains('app.events.refreshed'));

      onEvent(
        const McpWampEvent(
          subscriptionId: 7,
          publicationId: 101,
          topic: 'app.events',
          argumentsKeywords: {'message': 'after-refresh'},
        ),
      );
      final pollResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': handle},
        },
      });
      expect(jsonEncode(pollResponse), contains('after-refresh'));

      await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 43,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': handle},
        },
      });
      expect(unsubscribed.subscriptionId, 7);
    });

    test(
      'reconciles retained pubsub handles by subscribable topic with retry',
      () async {
        final handlers = <String, void Function(McpWampEvent event)>{};
        final explicitlyUnsubscribed = <McpWampSubscription>[];
        final released = <McpWampSubscription>[];
        var releaseAttempts = 0;
        final state = McpWampPubSubState();
        final api = McpWampApi(
          topics: [
            McpWampTopic(topic: 'app.events.revoked'),
            McpWampTopic(topic: 'app.events.retained'),
          ],
        );
        final server = _server(
          api.toTools(
            subscribe: (request, handler) {
              handlers[request.topic] = handler;
              return McpWampSubscription(
                topic: request.topic,
                subscriptionId: request.topic.endsWith('revoked') ? 7 : 8,
              );
            },
            unsubscribe: explicitlyUnsubscribed.add,
            pubSubState: state,
          ),
        );
        await _initializeAndStart(server);

        Future<String> subscribe(String topic, int id) async {
          final response = await server.handleMessage({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'tools/call',
            'params': {
              'name': 'connectanum.pubsub.subscribe',
              'arguments': {'topic': topic},
            },
          });
          final result =
              (response?['result'] as Map<String, Object?>)['structuredContent']
                  as Map<String, Object?>;
          return result['handle'] as String;
        }

        final revokedHandle = await subscribe('app.events.revoked', 48);
        final retainedHandle = await subscribe('app.events.retained', 49);

        await expectLater(
          state.reconcileSubscribedTopics(
            const <String>{'app.events.retained'},
            release: (subscription) {
              releaseAttempts++;
              if (releaseAttempts == 1) {
                throw StateError('temporary reconciliation failure');
              }
              released.add(subscription);
            },
          ),
          throwsA(isA<StateError>()),
        );
        handlers['app.events.revoked']!(
          const McpWampEvent(
            subscriptionId: 7,
            publicationId: 103,
            topic: 'app.events.revoked',
            argumentsKeywords: {'message': 'after-failed-reconciliation'},
          ),
        );
        final retainedAfterFailure = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 50,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': revokedHandle},
          },
        });
        expect(
          jsonEncode(retainedAfterFailure),
          contains('after-failed-reconciliation'),
        );

        await state.reconcileSubscribedTopics(
          const <String>{'app.events.retained'},
          release: (subscription) {
            releaseAttempts++;
            released.add(subscription);
          },
        );
        expect(releaseAttempts, 2);
        expect(released.single.topic, 'app.events.revoked');
        expect(explicitlyUnsubscribed, isEmpty);

        final revokedPoll = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 51,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': revokedHandle},
          },
        });
        expect(
          jsonEncode(revokedPoll),
          contains('Unknown WAMP subscription handle'),
        );

        handlers['app.events.retained']!(
          const McpWampEvent(
            subscriptionId: 8,
            publicationId: 104,
            topic: 'app.events.retained',
            argumentsKeywords: {'message': 'still-authorized'},
          ),
        );
        final retainedPoll = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 52,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': retainedHandle},
          },
        });
        expect(jsonEncode(retainedPoll), contains('still-authorized'));

        await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 53,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.unsubscribe',
            'arguments': {'handle': retainedHandle},
          },
        });
        expect(explicitlyUnsubscribed.single.topic, 'app.events.retained');
      },
    );

    test(
      'revokes a pending pubsub subscribe before exposing its handle',
      () async {
        final subscribeStarted = Completer<void>();
        final subscriptionReady = Completer<McpWampSubscription>();
        final released = <McpWampSubscription>[];
        final explicitlyUnsubscribed = <McpWampSubscription>[];
        late void Function(McpWampEvent event) onEvent;
        final state = McpWampPubSubState();
        final api = McpWampApi(
          topics: [McpWampTopic(topic: 'app.events.revoked')],
        );
        final server = _server(
          api.toTools(
            subscribe: (request, handler) {
              onEvent = handler;
              subscribeStarted.complete();
              return subscriptionReady.future;
            },
            unsubscribe: explicitlyUnsubscribed.add,
            pubSubState: state,
          ),
        );
        await _initializeAndStart(server);

        final responseFuture = server.handleMessage({
          'jsonrpc': '2.0',
          'id': 54,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': 'app.events.revoked'},
          },
        });
        await subscribeStarted.future;

        await state.reconcileSubscribedTopics(
          const <String>{},
          release: released.add,
        );
        onEvent(
          const McpWampEvent(
            subscriptionId: 9,
            publicationId: 105,
            topic: 'app.events.revoked',
            argumentsKeywords: {'message': 'must-not-be-retained'},
          ),
        );
        subscriptionReady.complete(
          const McpWampSubscription(
            topic: 'app.events.revoked',
            subscriptionId: 9,
          ),
        );

        final response = await responseFuture;
        expect(
          jsonEncode(response),
          contains('no longer subscribable while its subscription was pending'),
        );
        expect(jsonEncode(response), isNot(contains('wamp-sub-')));
        expect(released.single.subscriptionId, 9);
        expect(explicitlyUnsubscribed, isEmpty);
      },
    );

    test(
      'retries revoked pending pubsub cleanup without reviving its handle',
      () async {
        final subscribeStarted = Completer<void>();
        final subscriptionReady = Completer<McpWampSubscription>();
        final handlers = <void Function(McpWampEvent event)>[];
        final released = <McpWampSubscription>[];
        final explicitlyUnsubscribed = <McpWampSubscription>[];
        var subscribeCalls = 0;
        var releaseAttempts = 0;
        final state = McpWampPubSubState();
        final api = McpWampApi(
          topics: [McpWampTopic(topic: 'app.events.revoked')],
        );

        FutureOr<McpWampSubscription> subscribe(
          McpWampSubscribeRequest request,
          void Function(McpWampEvent event) handler,
        ) {
          handlers.add(handler);
          subscribeCalls++;
          if (subscribeCalls == 1) {
            subscribeStarted.complete();
            return subscriptionReady.future;
          }
          return McpWampSubscription(topic: request.topic, subscriptionId: 10);
        }

        final server = _server(
          api.toTools(
            subscribe: subscribe,
            unsubscribe: explicitlyUnsubscribed.add,
            pubSubState: state,
          ),
        );
        await _initializeAndStart(server);

        final responseFuture = server.handleMessage({
          'jsonrpc': '2.0',
          'id': 55,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': 'app.events.revoked'},
          },
        });
        await subscribeStarted.future;
        await state.reconcileSubscribedTopics(
          const <String>{},
          release: (subscription) {
            releaseAttempts++;
            if (releaseAttempts == 1) {
              throw StateError('temporary mandatory release failure');
            }
            released.add(subscription);
          },
        );
        handlers.single(
          const McpWampEvent(
            subscriptionId: 9,
            publicationId: 106,
            topic: 'app.events.revoked',
            argumentsKeywords: {'message': 'discarded-before-completion'},
          ),
        );
        subscriptionReady.complete(
          const McpWampSubscription(
            topic: 'app.events.revoked',
            subscriptionId: 9,
          ),
        );

        final failedResponse = await responseFuture;
        expect(
          jsonEncode(failedResponse),
          contains('temporary mandatory release failure'),
        );
        expect(jsonEncode(failedResponse), isNot(contains('wamp-sub-')));
        expect(releaseAttempts, 1);
        expect(released, isEmpty);

        await state.reconcileSubscribedTopics(
          const <String>{},
          release: (subscription) {
            releaseAttempts++;
            released.add(subscription);
          },
        );
        expect(releaseAttempts, 2);
        expect(released.single.subscriptionId, 9);

        server.tools.replaceAll(
          api.toTools(
            subscribe: subscribe,
            unsubscribe: explicitlyUnsubscribed.add,
            pubSubState: state,
          ),
        );
        await state.reconcileSubscribedTopics(const <String>{
          'app.events.revoked',
        }, release: released.add);
        final replacementResponse = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 56,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': 'app.events.revoked'},
          },
        });
        final replacement =
            (replacementResponse?['result']
                    as Map<String, Object?>)['structuredContent']
                as Map<String, Object?>;
        final replacementHandle = replacement['handle'] as String;
        expect(replacement['subscriptionId'], 10);

        handlers.first(
          const McpWampEvent(
            subscriptionId: 9,
            publicationId: 107,
            topic: 'app.events.revoked',
            argumentsKeywords: {'message': 'discarded-after-restoration'},
          ),
        );
        handlers.last(
          const McpWampEvent(
            subscriptionId: 10,
            publicationId: 108,
            topic: 'app.events.revoked',
            argumentsKeywords: {'message': 'replacement-event'},
          ),
        );
        final pollResponse = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 57,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': replacementHandle},
          },
        });
        expect(jsonEncode(pollResponse), contains('replacement-event'));
        expect(
          jsonEncode(pollResponse),
          isNot(contains('discarded-after-restoration')),
        );

        await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 58,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.unsubscribe',
            'arguments': {'handle': replacementHandle},
          },
        });
        expect(explicitlyUnsubscribed.single.subscriptionId, 10);
      },
    );

    test('keeps pubsub handles usable when unsubscribe fails', () async {
      late void Function(McpWampEvent event) onEvent;
      var unsubscribeAttempts = 0;
      final api = McpWampApi(topics: [McpWampTopic(topic: 'app.events')]);
      final server = _server(
        api.toTools(
          subscribe: (request, handler) {
            onEvent = handler;
            return McpWampSubscription(topic: request.topic, subscriptionId: 7);
          },
          unsubscribe: (_) async {
            unsubscribeAttempts++;
            if (unsubscribeAttempts == 1) {
              throw StateError('temporary unsubscribe failure');
            }
          },
        ),
      );
      await _initializeAndStart(server);

      final subscribeResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 44,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.events'},
        },
      });
      final subscription =
          (subscribeResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      final handle = subscription['handle'] as String;

      final firstUnsubscribeResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 45,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': handle},
        },
      });
      expect(
        jsonEncode(firstUnsubscribeResponse),
        contains('temporary unsubscribe failure'),
      );
      expect(unsubscribeAttempts, 1);

      onEvent(
        const McpWampEvent(
          subscriptionId: 7,
          publicationId: 102,
          topic: 'app.events',
          argumentsKeywords: {'message': 'after-failed-unsubscribe'},
        ),
      );
      final pollResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 46,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': handle},
        },
      });
      expect(jsonEncode(pollResponse), contains('after-failed-unsubscribe'));

      final retryResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 47,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': handle},
        },
      });
      final retryResult =
          (retryResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(retryResult['unsubscribed'], isTrue);
      expect(unsubscribeAttempts, 2);
    });

    test('bounds buffered WAMP events by their UTF-8 JSON size', () async {
      late void Function(McpWampEvent event) onEvent;
      final api = McpWampApi(topics: [McpWampTopic(topic: 'app.events')]);
      const first = McpWampEvent(
        subscriptionId: 7,
        publicationId: 100,
        topic: 'app.events',
        argumentsKeywords: {'sequence': 1, 'message': 'événement'},
      );
      const second = McpWampEvent(
        subscriptionId: 7,
        publicationId: 101,
        topic: 'app.events',
        argumentsKeywords: {'sequence': 2, 'message': 'événement'},
      );
      const third = McpWampEvent(
        subscriptionId: 7,
        publicationId: 102,
        topic: 'app.events',
        argumentsKeywords: {'sequence': 3, 'message': 'événement'},
      );
      final eventByteLength = utf8.encode(jsonEncode(first.toJson())).length;
      expect(
        [
          second,
          third,
        ].map((event) => utf8.encode(jsonEncode(event.toJson())).length),
        everyElement(eventByteLength),
      );
      final queueByteLimit = eventByteLength * 2;
      final server = _server(
        api.toTools(
          subscribe: (request, handler) {
            onEvent = handler;
            return const McpWampSubscription(
              topic: 'app.events',
              subscriptionId: 7,
            );
          },
          unsubscribe: (_) {},
          maxBufferedEventBytes: queueByteLimit,
        ),
      );
      await _initializeAndStart(server);

      final subscribeResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 40,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': 'app.events', 'queueLimit': 10},
        },
      });
      final subscription =
          (subscribeResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(subscription['queueByteLimit'], queueByteLimit);

      onEvent(first);
      onEvent(second);
      onEvent(third);
      final pollResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 41,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': subscription['handle'], 'limit': 1},
        },
      });
      final batch =
          (pollResponse?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      final events = batch['events'] as List<Object?>;
      expect(events, hasLength(1));
      expect(
        events.single,
        containsPair('argumentsKeywords', {
          'sequence': 2,
          'message': 'événement',
        }),
      );
      expect(batch['dropped'], 1);
      expect(batch['remaining'], 1);
      expect(batch['remainingBytes'], eventByteLength);

      final remainingResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': subscription['handle']},
        },
      });
      final remaining =
          (remainingResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(remaining['events'], hasLength(1));
      expect(jsonEncode(remaining['events']), contains('"sequence":3'));
      expect(remaining['remaining'], 0);
      expect(remaining['remainingBytes'], 0);

      onEvent(
        McpWampEvent(
          subscriptionId: 7,
          publicationId: 103,
          topic: 'app.events',
          argumentsKeywords: {
            'message': List<String>.filled(queueByteLimit, 'x').join(),
          },
        ),
      );
      onEvent(
        const McpWampEvent(
          subscriptionId: 7,
          publicationId: 104,
          topic: 'app.events',
          argumentsKeywords: {'message': 'recovered'},
        ),
      );
      final recoveryResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 43,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.poll',
          'arguments': {'handle': subscription['handle']},
        },
      });
      final recovered =
          (recoveryResponse?['result']
                  as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(recovered['events'], hasLength(1));
      expect(jsonEncode(recovered['events']), contains('recovered'));
      expect(recovered['dropped'], 2);
      expect(recovered['remainingBytes'], 0);

      expect(() => api.toTools(maxBufferedEventBytes: 0), throwsArgumentError);
    });

    test('derives pubsub topics from procedure metadata', () async {
      final api = McpWampApi(
        procedures: [
          McpWampProcedure(
            procedure: 'app.task.create',
            metadata: const McpWampApiMetadata(
              domain: 'app',
              entity: 'task',
              tags: ['task'],
              publishesEvents: ['app.task.changed'],
            ),
          ),
        ],
      );

      final topics = api.topics.map((topic) => topic.topic);
      expect(topics, contains('app.task.changed'));

      final server = _server(
        api.toTools(
          call: (_) => (
            callRequestId: 1,
            progress: false,
            pptScheme: null,
            pptSerializer: null,
            pptCipher: null,
            pptKeyId: null,
            customDetails: null,
            arguments: null,
            argumentsKeywords: const <String, dynamic>{},
          ),
          publish: (request) => McpWampPublication(
            publicationId: request.topic.hashCode,
            acknowledged: true,
          ),
        ),
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 40,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.describe',
          'arguments': {'kind': 'topic', 'uri': 'app.task.changed'},
        },
      });
      final result =
          (response?['result'] as Map<String, Object?>)['structuredContent']
              as Map<String, Object?>;
      expect(result['topic'], 'app.task.changed');
      expect(result['metadata'], containsPair('domain', 'app'));
    });

    test('can disable derived pubsub topics from procedure metadata', () {
      final api = McpWampApi(
        includePublishedEventTopics: false,
        procedures: [
          McpWampProcedure(
            procedure: 'app.task.create',
            metadata: const McpWampApiMetadata(
              publishesEvents: ['app.task.changed'],
            ),
          ),
        ],
      );

      expect(
        api.topics.map((topic) => topic.topic),
        isNot(contains('app.task.changed')),
      );
    });
  });
}

McpServer _server(List<McpTool> tools) => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-wamp-api', version: '0.1'),
  tools: tools,
);

List<String> _catalogUris(Object? catalog) {
  final entries = catalog as List<Object?>;
  return [
    for (final entry in entries)
      (entry as Map<String, Object?>)['uri']! as String,
  ];
}

Future<void> _initializeAndStart(McpServer server) async {
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
