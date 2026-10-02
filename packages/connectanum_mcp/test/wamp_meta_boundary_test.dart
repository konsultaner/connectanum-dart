import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

import 'support/expect_valid.dart';

void main() {
  const metaTopics = [
    'wamp.session.on_join',
    'wamp.session.on_leave',
    'wamp.registration.on_create',
    'wamp.registration.on_register',
    'wamp.registration.on_unregister',
    'wamp.registration.on_delete',
    'wamp.subscription.on_create',
    'wamp.subscription.on_subscribe',
    'wamp.subscription.on_unsubscribe',
    'wamp.subscription.on_delete',
  ];
  for (final topic in metaTopics) {
    test('$topic is observable but cannot be forged by publishing', () async {
      var publications = 0;
      final subscribed = <String>[];
      final released = <McpWampSubscription>[];
      final api = McpWampApi(includeStandardMetaApi: true);
      expect(api.topics.map((entry) => entry.topic), metaTopics);
      final descriptor = api.topics.singleWhere(
        (entry) => entry.topic == topic,
      );
      expect(descriptor.allowPublish, isFalse);
      expect(descriptor.allowSubscribe, isTrue);
      final server = await _server(
        api,
        publish: (_) {
          publications++;
          return const McpWampPublication(publicationId: 7, acknowledged: true);
        },
        subscribe: (request, _) {
          subscribed.add(request.topic);
          return McpWampSubscription(topic: request.topic, subscriptionId: 41);
        },
        unsubscribe: released.add,
      );

      final rejected = await _call(server, 'connectanum.pubsub.publish', {
        'topic': topic,
        'arguments': [123],
      });
      expect(rejected['isError'], isTrue);
      expect(rejected, isNot(contains('structuredContent')));
      expect(publications, 0);
      expect(subscribed, isEmpty);

      final accepted = await _call(server, 'connectanum.pubsub.subscribe', {
        'topic': topic,
      });
      expect(accepted['isError'], isFalse);
      expect(accepted['structuredContent'], isA<Map>());
      final data = accepted['structuredContent'] as Map;
      expect(data, {
        'handle': 'wamp-sub-1',
        'topic': topic,
        'subscriptionId': 41,
        'queueLimit': 100,
      });
      expect(subscribed, [topic]);
      final removed = await _call(server, 'connectanum.pubsub.unsubscribe', {
        'handle': data['handle'],
      });
      expect(removed['isError'], isFalse);
      expect(released, hasLength(1));
      expect(released.single.topic, topic);
      expect(released.single.subscriptionId, 41);
      expect(publications, 0);
    });
  }

  const procedures = [
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
  ];
  for (final procedure in procedures) {
    test('$procedure advertises raw keyword extensibility', () {
      final descriptor = McpWampStandardMetaApi.procedures.singleWhere(
        (entry) => entry.procedure == procedure,
      );
      final schema = descriptor.inputSchema;
      expect(schema, containsPair('properties', isA<Map>()));
      final properties = schema['properties'] as Map;
      expect(properties['argumentsKeywords'], {
        'type': 'object',
        'additionalProperties': true,
        'description': 'Raw keyword WAMP arguments compatibility form.',
      });
      expect(schema['additionalProperties'], isFalse);
    });
    for (final form in ['positional', 'keyword', 'both']) {
      test(
        '$procedure forwards the $form raw form without reinterpretation',
        () async {
          final calls = <McpWampToolCall>[];
          final server = await _server(
            McpWampApi(includeStandardMetaApi: true),
            calls: calls,
          );
          final response = await _call(server, procedure, {
            if (form != 'keyword') 'arguments': [7, 'raw'],
            if (form != 'positional') 'argumentsKeywords': {'trace': 9},
          });
          expect(response['isError'], isFalse);
          expect(calls, hasLength(1));
          expect(calls.single.procedure, procedure);
          expect(
            calls.single.payload.arguments,
            form == 'keyword' ? null : [7, 'raw'],
          );
          expect(
            calls.single.payload.argumentsKeywords,
            form == 'positional' ? null : {'trace': 9},
          );
        },
      );
    }
    if (!procedure.endsWith('.lookup')) {
      test('$procedure rejects a match policy before dispatch', () async {
        final calls = <McpWampToolCall>[];
        final server = await _server(
          McpWampApi(includeStandardMetaApi: true),
          calls: calls,
        );
        final response = await _call(server, procedure, {
          'arguments': [],
          'match': 'prefix',
        });
        expect(response['isError'], isTrue);
        expect(
          response['content'],
          contains(
            containsPair(
              'text',
              contains('unsupported standard WAMP Meta fields: match'),
            ),
          ),
        );
        expect(calls, isEmpty);
      });
    }
  }

  for (final uri in ['app.echo', 'echo']) {
    test('describe resolves the declared procedure by $uri', () async {
      final procedure = McpWampProcedure(
        procedure: 'app.echo',
        toolName: 'echo',
        allowCall: false,
      );
      final server = await _server(McpWampApi(procedures: [procedure]));
      final response = await _call(server, 'connectanum.api.describe', {
        'uri': uri,
      });
      expect(response['isError'], isFalse);
      expect(response['structuredContent'], containsPair('uri', 'app.echo'));
      expect(response['structuredContent'], containsPair('toolName', 'echo'));
    });
  }

  test(
    'inferred event topics retain unique tags and explicit topic precedence',
    () {
      final explicit = McpWampTopic(topic: 'app.explicit', allowPublish: false);
      final api = McpWampApi(
        topics: [explicit],
        procedures: [
          McpWampProcedure(
            procedure: 'app.create',
            metadata: const McpWampApiMetadata(
              tags: ['safe', 'event', 'safe'],
              publishesEvents: ['app.created', 'app.explicit', 'app.created'],
            ),
          ),
        ],
      );
      expect(api.topics.map((topic) => topic.topic), [
        'app.explicit',
        'app.created',
      ]);
      expect(api.topics.first, same(explicit));
      expect(api.topics.last.metadata.tags, ['safe', 'event']);
      expect(
        () => api.topics.last.metadata.tags.add('changed'),
        throwsUnsupportedError,
      );
    },
  );
}

Future<McpServer> _server(
  McpWampApi api, {
  List<McpWampToolCall>? calls,
  McpWampPublishInvoker? publish,
  McpWampSubscribeInvoker? subscribe,
  McpWampUnsubscribeInvoker? unsubscribe,
}) async {
  final server = expectValid(
    () => McpServer(
      serverInfo: const McpServerInfo(name: 'meta-boundaries', version: '1'),
      tools: api.toTools(
        call: (call) {
          expect(calls, isNotNull, reason: 'Unexpected WAMP call');
          calls!.add(call);
          return (
            callRequestId: 1,
            progress: false,
            pptScheme: null,
            pptSerializer: null,
            pptCipher: null,
            pptKeyId: null,
            customDetails: null,
            arguments: [42],
            argumentsKeywords: null,
          );
        },
        publish: publish,
        subscribe: subscribe,
        unsubscribe: unsubscribe,
      ),
    ),
  );
  addTearDown(server.shutdown);
  final initialized = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
  });
  expect(initialized, containsPair('result', isA<Map>()));
  expect(
    await server.handleMessage({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }),
    isNull,
  );
  expect(server.state, McpServerState.initialized);
  return server;
}

Future<Map> _call(
  McpServer server,
  String name,
  Map<String, Object?> arguments,
) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 2,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  });
  expect(response, containsPair('id', 2));
  expect(response, containsPair('result', isA<Map>()));
  expect(response, isNot(contains('error')));
  return response!['result'] as Map;
}
