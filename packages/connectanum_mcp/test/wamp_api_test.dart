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

    test('exposes standard WAMP meta procedures when requested', () async {
      late McpWampToolCall capturedCall;
      final api = McpWampApi(includeStandardMetaApi: true);
      final server = _server(
        api.toTools(
          call: (call) {
            capturedCall = call;
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

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 20,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.registration.get',
          'arguments': {
            'arguments': [123],
          },
        },
      });

      expect(capturedCall.procedure, 'wamp.registration.get');
      expect(capturedCall.payload.arguments, [123]);
      expect(response?['result'], isA<Map<String, Object?>>());
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
    'params': {'protocolVersion': mcpLatestProtocolVersion},
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
