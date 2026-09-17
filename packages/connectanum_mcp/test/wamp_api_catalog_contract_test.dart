import 'dart:async';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart' show ResultPayload;
import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('public built-in tool discovery', () {
    final contracts = <String, (List<bool>, Map<String, Object?>)>{
      'connectanum.api.list': (
        [true, false, true, false],
        _schema({
          'kind': {
            'type': 'string',
            'enum': ['procedure', 'topic'],
          },
          'tag': {'type': 'string'},
          'cursor': {'type': 'string'},
        }),
      ),
      'connectanum.api.describe': (
        [true, false, true, false],
        _schema(
          {
            'kind': {
              'type': 'string',
              'enum': ['procedure', 'topic'],
            },
            'uri': {'type': 'string'},
          },
          required: ['uri'],
        ),
      ),
      'connectanum.pubsub.publish': (
        [false, false, false, false],
        _schema(
          {
            'topic': {'type': 'string'},
            'arguments': {'type': 'array'},
            'argumentsKeywords': {
              'type': 'object',
              'additionalProperties': true,
            },
            'acknowledge': {'type': 'boolean'},
            'options': {'type': 'object', 'additionalProperties': true},
          },
          required: ['topic'],
        ),
      ),
      'connectanum.pubsub.subscribe': (
        [false, false, false, false],
        _schema(
          {
            'topic': {'type': 'string'},
            'queueLimit': {'type': 'integer', 'minimum': 1},
            'options': {'type': 'object', 'additionalProperties': true},
          },
          required: ['topic'],
        ),
      ),
      'connectanum.pubsub.poll': (
        [true, false, false, false],
        _schema(
          {
            'handle': {'type': 'string'},
            'limit': {'type': 'integer', 'minimum': 1},
          },
          required: ['handle'],
        ),
      ),
      'connectanum.pubsub.unsubscribe': (
        [false, false, true, false],
        _schema(
          {
            'handle': {'type': 'string'},
          },
          required: ['handle'],
        ),
      ),
    };
    for (final entry in contracts.entries) {
      test('${entry.key} advertises exact hints and schema', () async {
        final server = await _server(McpWampApi().toTools());
        final response = await _rpc(server, 'tools/list', {});
        final tools = (response['tools'] as List).cast<Map>();
        expect(
          tools.map((tool) => tool['name']),
          unorderedEquals(contracts.keys),
        );
        final tool = tools.singleWhere((tool) => tool['name'] == entry.key);
        final (hints, schema) = entry.value;
        expect(tool['annotations'], {
          'readOnlyHint': hints[0],
          'destructiveHint': hints[1],
          'idempotentHint': hints[2],
          'openWorldHint': hints[3],
        });
        expect(tool['inputSchema'], schema);
      });
    }

    for (final meta in [false, true]) {
      for (final pubsub in [false, true]) {
        test('selects meta=$meta and pubsub=$pubsub independently', () async {
          final server = await _server(
            McpWampApi().toTools(
              includeApiMetaTools: meta,
              includePubSubTools: pubsub,
            ),
          );
          final response = await _rpc(server, 'tools/list', {});
          expect(
            (response['tools'] as List).map((tool) => (tool as Map)['name']),
            [
              if (meta) ...['connectanum.api.describe', 'connectanum.api.list'],
              if (pubsub) ...[
                'connectanum.pubsub.poll',
                'connectanum.pubsub.publish',
                'connectanum.pubsub.subscribe',
                'connectanum.pubsub.unsubscribe',
              ],
            ],
          );
        });
      }
    }
  });

  group('direct catalog metadata', () {
    test(
      'empty metadata remains absent rather than inventing safety hints',
      () {
        const metadata = McpWampApiMetadata();
        expect(metadata.isEmpty, isTrue);
        expect(metadata.toJson(), isEmpty);
        expect(metadata.toToolAnnotations(), isNull);
        expect(McpWampProcedure(procedure: 'app.call').toJson(), {
          'kind': 'procedure',
          'uri': 'app.call',
          'procedure': 'app.call',
          'toolName': 'app.call',
          'allowCall': true,
          'inputSchema': {'type': 'object', 'additionalProperties': true},
        });
        expect(McpWampTopic(topic: 'app.events').toJson(), {
          'kind': 'topic',
          'uri': 'app.events',
          'topic': 'app.events',
          'eventSchema': {'type': 'object', 'additionalProperties': true},
          'allowPublish': true,
          'allowSubscribe': true,
        });
      },
    );

    final cases = <(String, McpWampApiMetadata, Map<String, Object?>)>[
      (
        'short description',
        const McpWampApiMetadata(shortDescription: ''),
        {'short_description': ''},
      ),
      (
        'description',
        const McpWampApiMetadata(description: 'Details'),
        {'description': 'Details'},
      ),
      ('domain', const McpWampApiMetadata(domain: ''), {'domain': ''}),
      (
        'entity',
        const McpWampApiMetadata(entity: 'record'),
        {'entity': 'record'},
      ),
      (
        'verbs',
        const McpWampApiMetadata(verbs: ['create']),
        {
          'verbs': ['create'],
        },
      ),
      (
        'tags',
        const McpWampApiMetadata(tags: ['safe']),
        {
          'tags': ['safe'],
        },
      ),
      (
        'synonyms',
        const McpWampApiMetadata(synonyms: ['alias']),
        {
          'synonyms': ['alias'],
        },
      ),
      (
        'events',
        const McpWampApiMetadata(publishesEvents: ['app.changed']),
        {
          'publishes_events': ['app.changed'],
        },
      ),
      (
        'input schema',
        const McpWampApiMetadata(inputJsonSchema: {}),
        {'input_json_schema': {}},
      ),
      (
        'output schema',
        const McpWampApiMetadata(outputJsonSchema: {}),
        {'output_json_schema': {}},
      ),
      ('danger', const McpWampApiMetadata(danger: true), {'danger': true}),
      for (final flag in [false, true]) ...[
        (
          'read only $flag',
          McpWampApiMetadata(readOnlyHint: flag),
          {'read_only_hint': flag},
        ),
        (
          'destructive $flag',
          McpWampApiMetadata(destructiveHint: flag),
          {'destructive_hint': flag},
        ),
        (
          'idempotent $flag',
          McpWampApiMetadata(idempotentHint: flag),
          {'idempotent_hint': flag},
        ),
        (
          'open world $flag',
          McpWampApiMetadata(openWorldHint: flag),
          {'open_world_hint': flag},
        ),
      ],
    ];
    for (final (name, metadata, expected) in cases) {
      test('$name alone is retained in both entry kinds', () {
        expect(metadata.isEmpty, isFalse);
        expect(metadata.toJson(), expected);
        expect(
          McpWampProcedure(
            procedure: 'app.call',
            metadata: metadata,
          ).toJson()['metadata'],
          expected,
        );
        expect(
          McpWampTopic(
            topic: 'app.events',
            metadata: metadata,
          ).toJson()['metadata'],
          expected,
        );
      });
    }

    test('danger supplies only unspecified risk annotations', () {
      expect(
        const McpWampApiMetadata(danger: true).toToolAnnotations()!.toJson(),
        {
          'readOnlyHint': false,
          'destructiveHint': true,
        },
      );
      for (final danger in [false, true]) {
        for (final flag in [false, true]) {
          final annotations = McpWampApiMetadata(
            danger: danger,
            readOnlyHint: flag,
            destructiveHint: flag,
            idempotentHint: flag,
            openWorldHint: flag,
          ).toToolAnnotations(title: 'Action');
          expect(annotations!.toJson(), {
            'title': 'Action',
            'readOnlyHint': flag,
            'destructiveHint': flag,
            'idempotentHint': flag,
            'openWorldHint': flag,
          });
        }
      }
    });

    for (final title in ['', 'Action']) {
      test('title-only annotations preserve "$title"', () {
        expect(
          const McpWampApiMetadata().toToolAnnotations(title: title)!.toJson(),
          {'title': title},
        );
      });
    }

    final listCases = <String, McpWampApiMetadata Function(List<String>)>{
      'verbs': (values) => McpWampApiMetadata(verbs: values),
      'tags': (values) => McpWampApiMetadata(tags: values),
      'synonyms': (values) => McpWampApiMetadata(synonyms: values),
      'publishes_events': (values) =>
          McpWampApiMetadata(publishesEvents: values),
    };
    for (final entry in listCases.entries) {
      test('${entry.key} serialization owns an immutable list snapshot', () {
        final input = ['first'];
        final metadata = entry.value(input);
        final snapshot = metadata.toJson();
        input.add('second');
        expect(snapshot, {
          entry.key: ['first'],
        });
        expect(
          () => (snapshot[entry.key] as List).add('other'),
          throwsUnsupportedError,
        );
        expect(metadata.toJson(), {
          entry.key: ['first', 'second'],
        });
      });
    }

    test(
      'explicit entry schemas, empty labels and denied capabilities survive serialization',
      () {
        expect(
          McpWampProcedure(
            procedure: 'app.call',
            toolName: 'call',
            title: '',
            description: '',
            inputSchema: const {'type': 'string'},
            outputSchema: const {'type': 'boolean'},
            allowCall: false,
          ).toJson(),
          {
            'kind': 'procedure',
            'uri': 'app.call',
            'procedure': 'app.call',
            'toolName': 'call',
            'title': '',
            'description': '',
            'allowCall': false,
            'inputSchema': {'type': 'string'},
            'outputSchema': {'type': 'boolean'},
          },
        );
        expect(
          McpWampTopic(
            topic: 'app.events',
            title: '',
            description: '',
            eventSchema: const {'type': 'integer'},
            allowPublish: false,
            allowSubscribe: false,
          ).toJson(),
          {
            'kind': 'topic',
            'uri': 'app.events',
            'topic': 'app.events',
            'title': '',
            'description': '',
            'eventSchema': {'type': 'integer'},
            'allowPublish': false,
            'allowSubscribe': false,
          },
        );
      },
    );
  });

  group('catalog lookup contracts', () {
    for (final (uri, kind, expectedKind) in <(String, String?, String?)>[
      ('app.shared', null, 'procedure'),
      ('app.shared', 'procedure', 'procedure'),
      ('app.shared', 'topic', 'topic'),
      ('app.topic', null, 'topic'),
      ('app.topic', 'procedure', null),
      ('app.procedure', 'topic', null),
    ]) {
      test('describe $uri as $kind does not cross entry kinds', () async {
        final server = await _server(
          McpWampApi(
            procedures: [
              McpWampProcedure(procedure: 'app.shared', allowCall: false),
              McpWampProcedure(procedure: 'app.procedure', allowCall: false),
            ],
            topics: [
              McpWampTopic(topic: 'app.shared'),
              McpWampTopic(topic: 'app.topic'),
            ],
          ).toTools(),
        );
        final result = await _call(server, 'connectanum.api.describe', {
          'uri': uri,
          if (kind != null) 'kind': kind,
        });
        if (expectedKind == null) {
          expect(result['isError'], isTrue);
          expect(result['content'], [
            {'type': 'text', 'text': 'Unknown declared WAMP API entry: $uri'},
          ]);
        } else {
          expect(result['isError'], isFalse);
          final entry = result['structuredContent'] as Map;
          expect(entry['kind'], expectedKind);
          expect(entry['uri'], uri);
          expect(
            entry,
            isNot(
              contains(expectedKind == 'procedure' ? 'topic' : 'procedure'),
            ),
          );
          expect(
            jsonDecode(
              ((result['content'] as List).single as Map)['text'] as String,
            ),
            entry,
          );
        }
      });
    }

    for (final named in [false, true]) {
      test('empty list preserves optional root fields, named=$named', () async {
        final server = await _server(
          McpWampApi(
            name: named ? '' : null,
            metadata: named
                ? {
                    'nested': {2: double.infinity},
                  }
                : const {},
          ).toTools(),
        );
        final result = await _call(server, 'connectanum.api.list', {});
        final expected = {
          if (named) 'name': '',
          if (named)
            'metadata': {
              'nested': {'2': 'Infinity'},
            },
          'procedures': [],
          'topics': [],
        };
        expect(result['isError'], isFalse);
        expect(result['structuredContent'], expected);
        expect(
          jsonDecode(
            ((result['content'] as List).single as Map)['text'] as String,
          ),
          expected,
        );
      });
    }
  });

  group('pubsub capacity and capability boundaries', () {
    test('default publication does not imply acknowledgement', () {
      expect(const McpWampPublication().toJson(), {'acknowledged': false});
    });

    for (final byteBound in [false, true]) {
      test(
        'event exactly fits ${byteBound ? 'byte' : 'count'} capacity',
        () async {
          late void Function(McpWampEvent) emit;
          const event = McpWampEvent(
            subscriptionId: 9,
            publicationId: 7,
            arguments: ['data'],
          );
          final eventBytes = utf8.encode(jsonEncode(event.toJson())).length;
          var releases = 0;
          final server = await _server(
            McpWampApi(
              topics: [McpWampTopic(topic: 'app.events', allowPublish: false)],
            ).toTools(
              subscribe: (_, handler) {
                emit = handler;
                return const McpWampSubscription(
                  topic: 'app.events',
                  subscriptionId: 9,
                );
              },
              unsubscribe: (subscription) {
                expect(subscription.subscriptionId, 9);
                releases++;
              },
              maxBufferedEventBytes: byteBound ? eventBytes : null,
            ),
          );
          final subscribed = await _call(
            server,
            'connectanum.pubsub.subscribe',
            {
              'topic': 'app.events',
              'queueLimit': 1,
            },
          );
          expect(subscribed['isError'], isFalse);
          final handle = (subscribed['structuredContent'] as Map)['handle'];
          emit(event);
          final first = await _call(server, 'connectanum.pubsub.poll', {
            'handle': handle,
          });
          final batch = first['structuredContent'] as Map;
          expect(batch['events'], [event.toJson()]);
          expect(batch['dropped'], 0);
          expect(batch['remaining'], 0);
          expect(batch['remainingBytes'], 0);

          emit(event);
          emit(
            const McpWampEvent(
              subscriptionId: 9,
              publicationId: 8,
              arguments: ['data'],
            ),
          );
          final second = await _call(server, 'connectanum.pubsub.poll', {
            'handle': handle,
          });
          final overflow = second['structuredContent'] as Map;
          expect((overflow['events'] as List).single, {
            'subscriptionId': 9,
            'publicationId': 8,
            'arguments': ['data'],
          });
          expect(overflow['dropped'], 1);
          expect(overflow['remaining'], 0);
          expect(overflow['remainingBytes'], 0);
          final released = await _call(
            server,
            'connectanum.pubsub.unsubscribe',
            {'handle': handle},
          );
          expect(released['isError'], isFalse);
          expect(releases, 1);
        },
      );
    }

    test('publish-only topic does not require subscribe permission', () async {
      McpWampPublishRequest? published;
      final server = await _server(
        McpWampApi(
          topics: [McpWampTopic(topic: 'app.events', allowSubscribe: false)],
        ).toTools(
          publish: (request) {
            published = request;
            return const McpWampPublication();
          },
        ),
      );
      final result = await _call(server, 'connectanum.pubsub.publish', {
        'topic': 'app.events',
      });
      expect(result['isError'], isFalse);
      expect(published!.topic, 'app.events');
      expect(published!.arguments, isNull);
      expect(published!.argumentsKeywords, isNull);
      expect(published!.options?.custom, isEmpty);
      expect(result['structuredContent'], containsPair('acknowledged', false));
    });
  });

  group('procedure invocation overrides', () {
    test(
      'uses the declared mapper rather than the default lossless envelope',
      () async {
        final payload = _payload();
        McpWampToolCall? mappedCall;
        ResultPayload? mappedPayload;
        final server = await _server(
          McpWampApi(
            procedures: [
              McpWampProcedure(
                procedure: 'app.call',
                toolName: 'call',
                resultMapper: (call, result) {
                  mappedCall = call;
                  mappedPayload = result;
                  return McpToolResult.text('consumer projection');
                },
              ),
            ],
          ).toTools(call: (_) => payload),
        );
        final result = await _call(server, 'call', {'value': 7});
        expect(result, {
          'content': [
            {'type': 'text', 'text': 'consumer projection'},
          ],
          'isError': false,
        });
        expect(mappedPayload, payload);
        expect(mappedPayload!.arguments, same(payload.arguments));
        expect(
          mappedPayload!.argumentsKeywords,
          same(payload.argumentsKeywords),
        );
        expect(mappedCall!.procedure, 'app.call');
        expect(mappedCall!.payload.argumentsKeywords, {'value': 7});
      },
    );

    const short = Duration(milliseconds: 5);
    const long = Duration(minutes: 1);
    for (final (name, local, shared, timesOut)
        in <(String, Duration?, Duration?, bool)>[
          ('local deadline overrides shared', short, long, true),
          ('local allowance overrides shared', long, short, false),
          ('inherits shared deadline', null, short, true),
          ('no deadline is invented', null, null, false),
        ]) {
      test(name, () async {
        final pending = Completer<ResultPayload>();
        final tool =
            McpWampApi(
                  procedures: [
                    McpWampProcedure(
                      procedure: 'app.call',
                      timeout: local,
                    ),
                  ],
                )
                .toTools(
                  call: (_) => pending.future,
                  timeout: shared,
                  includeApiMetaTools: false,
                  includePubSubTools: false,
                )
                .single;
        var completed = false;
        Object? failure;
        McpToolResult? result;
        final observed =
            Future<McpToolResult>.value(
              tool.handler(
                McpToolRequest(name: 'app.call', arguments: const {}),
              ),
            ).then<void>(
              (value) {
                result = value;
                completed = true;
              },
              onError: (Object error, StackTrace stack) {
                failure = error;
                completed = true;
              },
            );
        try {
          // Keep the provider pending so a wrong deadline fails an assertion,
          // not the mutation runner's test timeout.
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(completed, timesOut);
          expect(failure, timesOut ? isA<TimeoutException>() : isNull);
        } finally {
          pending.complete(_payload());
          await observed;
        }
        if (!timesOut) {
          expect(result!.isError, isFalse);
          expect(result!.structuredContent, {
            'arguments': [42],
            'argumentsKeywords': {'ok': true},
          });
        }
      });
    }
  });
}

ResultPayload _payload() => (
  callRequestId: 1,
  progress: false,
  pptScheme: null,
  pptSerializer: null,
  pptCipher: null,
  pptKeyId: null,
  customDetails: null,
  arguments: [42],
  argumentsKeywords: {'ok': true},
);

Map<String, Object?> _schema(
  Map<String, Object?> properties, {
  List<String>? required,
}) => {
  'type': 'object',
  'properties': properties,
  if (required != null) 'required': required,
  'additionalProperties': false,
};

Future<McpServer> _server(List<McpTool> tools) async {
  final server = McpServer(
    serverInfo: const McpServerInfo(name: 'consumer-catalog', version: '1'),
    tools: tools,
  );
  addTearDown(server.shutdown);
  await _rpc(server, 'initialize', {
    'protocolVersion': mcpLatestSessionProtocolVersion,
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
  return server;
}

Future<Map<String, Object?>> _rpc(
  McpServer server,
  String method,
  Map<String, Object?> params,
) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': method,
    'params': params,
  });
  expect(response, containsPair('id', 1));
  expect(response, isNot(contains('error')));
  return response!['result'] as Map<String, Object?>;
}

Future<Map<String, Object?>> _call(
  McpServer server,
  String name,
  Map<String, Object?> arguments,
) => _rpc(server, 'tools/call', {'name': name, 'arguments': arguments});
