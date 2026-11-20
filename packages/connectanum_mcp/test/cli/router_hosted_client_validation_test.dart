@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_mcp/src/cli/router_hosted_client_validation.dart'
    as validation;
import 'package:test/test.dart';

Matcher diagnostic(String text) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'CLI diagnostic',
    contains(text),
  ),
);

// Accepted inputs must produce assertion failures if their defensive guard rejects.
T accepted<T>(T Function() body) {
  try {
    return body();
  } on StateError catch (error) {
    fail('Valid CLI contract was rejected: $error');
  }
}

void main() {
  group('CLI batch contracts', () {
    test(
      'IDs retain response order and require the complete requested set',
      () {
        expect(
          accepted(
            () => validation.expectBatchResponseIds(
              [
                {'id': 'b'},
                {'id': 'a'},
              ],
              ['a', 'b'],
              label: 'Probe',
            ),
          ),
          ['b', 'a'],
        );
        for (final (responses, message) in <(List<McpJsonMap>?, String)>[
          (null, 'no responses'),
          ([], '0 responses for 2 requests'),
          (
            [
              {'id': 1},
              {'id': 'b'},
            ],
            'non-string id',
          ),
          (
            [
              {'id': 'a'},
              {'id': 'a'},
            ],
            'missed responses for [b]',
          ),
        ]) {
          expect(
            () => validation.expectBatchResponseIds(responses, [
              'a',
              'b',
            ], label: 'Probe'),
            diagnostic(message),
          );
        }
      },
    );
    test('a batch rejects every error envelope after checking its IDs', () {
      expect(
        accepted(
          () => validation.expectBatchResponses(
            [
              {'id': 'a', 'result': {}},
            ],
            ['a'],
            label: 'Probe',
          ),
        ),
        ['a'],
      );
      for (final error in <Object?>[
        null,
        {'code': -32601},
      ]) {
        expect(
          () => validation.expectBatchResponses(
            [
              {'id': 'a', 'error': error},
            ],
            ['a'],
            label: 'Probe',
          ),
          diagnostic('response a errored'),
        );
      }
    });
    test('results are selected by ID rather than position', () {
      expect(
        accepted(
          () => validation.batchResult(
            [
              {
                'id': 'other',
                'result': {'wrong': true},
              },
              {
                'id': 'wanted',
                'result': {'value': 42},
              },
            ],
            'wanted',
            label: 'Probe',
          ),
        ),
        {'value': 42},
      );
      for (final (responses, message) in <(List<McpJsonMap>?, String)>[
        (null, 'no responses'),
        (
          [
            {'id': 'other', 'result': {}},
          ],
          'missed response wanted',
        ),
        (
          [
            {'id': 'wanted', 'result': []},
          ],
          'non-object result',
        ),
      ]) {
        expect(
          () => validation.batchResult(responses, 'wanted', label: 'Probe'),
          diagnostic(message),
        );
      }
    });
    test(
      'error results distinguish wrong IDs, success and malformed errors',
      () {
        expect(
          accepted(
            () => validation.batchError(
              [
                {
                  'id': 'other',
                  'error': {'code': 0},
                },
                {
                  'id': 'wanted',
                  'error': {'code': -32601},
                },
              ],
              'wanted',
              label: 'Probe',
            ),
          ),
          {'code': -32601},
        );
        for (final (responses, message) in <(List<McpJsonMap>?, String)>[
          (null, 'no responses'),
          (
            [
              {'id': 'other', 'error': {}},
            ],
            'missed response wanted',
          ),
          (
            [
              {'id': 'wanted', 'result': {}},
            ],
            'succeeded unexpectedly',
          ),
          (
            [
              {'id': 'wanted', 'error': []},
            ],
            'non-object error',
          ),
        ]) {
          expect(
            () => validation.batchError(responses, 'wanted', label: 'Probe'),
            diagnostic(message),
          );
        }
      },
    );
    test(
      'single responses preserve explicit peer errors and reject bad shape',
      () {
        expect(
          accepted(
            () => validation.responseResult(
              {
                'id': 'wanted',
                'result': {'value': 42},
              },
              'wanted',
              label: 'Probe',
            ),
          ),
          {'value': 42},
        );
        for (final (response, message) in <(McpJsonMap?, String)>[
          (null, 'no response'),
          ({'id': 'other', 'result': {}}, 'id other instead of wanted'),
          (
            {
              'id': 'wanted',
              'error': {'code': -32601},
            },
            'returned error {"code":-32601}',
          ),
          ({'id': 'wanted', 'result': []}, 'non-object result'),
        ]) {
          expect(
            () => validation.responseResult(response, 'wanted', label: 'Probe'),
            diagnostic(message),
          );
        }
      },
    );
  });

  group('CLI WAMP result contracts', () {
    test('catalog membership requires a matching map in an iterable', () {
      for (final catalog in <Object?>[
        null,
        3,
        {'uri': 'app://target'},
        [],
        [
          null,
          'app://target',
          {'uri': 'app://other'},
        ],
      ]) {
        expect(
          validation.catalogContainsValue(
            catalog: catalog,
            field: 'uri',
            value: 'app://target',
          ),
          isFalse,
        );
        expect(
          validation.wampCatalogContainsUri(catalog, 'app://target'),
          isFalse,
        );
        expect(
          () => validation.expectWampCatalogContains(
            catalog: catalog,
            uri: 'app://target',
            label: 'Probe',
          ),
          diagnostic('did not include app://target'),
        );
      }
      final catalog = [
        null,
        {'uri': 'app://other'},
        {'uri': 'app://target'},
      ];
      expect(
        validation.catalogContainsValue(
          catalog: catalog,
          field: 'uri',
          value: 'app://target',
        ),
        isTrue,
      );
      expect(
        validation.wampCatalogContainsUri(catalog, 'app://target'),
        isTrue,
      );
      accepted(
        () => validation.expectWampCatalogContains(
          catalog: catalog,
          uri: 'app://target',
          label: 'Probe',
        ),
      );
    });
    test('metadata belongs to the requested procedure', () {
      McpStreamableWampMetaCallResult result(String procedure) =>
          McpStreamableWampMetaCallResult(
            procedure: procedure,
            arguments: const [],
            argumentsKeywords: const {},
            structuredContent: const {},
          );
      accepted(
        () => validation.expectWampMetaProcedure(
          result('wamp.session.count'),
          'wamp.session.count',
          label: 'Probe',
        ),
      );
      expect(
        () => validation.expectWampMetaProcedure(
          result('wamp.session.list'),
          'wamp.session.count',
          label: 'Probe',
        ),
        diagnostic('returned wamp.session.list, expected wamp.session.count'),
      );
    });
    test(
      'subscriptions preserve topic, a nonempty handle and queue bounds',
      () {
        McpStreamableWampSubscriptionResult subscription(
          String topic,
          String handle,
          int limit,
        ) => McpStreamableWampSubscriptionResult(
          topic: topic,
          handle: handle,
          queueLimit: limit,
          structuredContent: const {},
        );
        accepted(
          () => validation.expectWampSubscription(
            subscription('app.events', 'handle', 100),
            topic: 'app.events',
            queueLimit: 100,
            label: 'Probe',
          ),
        );
        for (final (result, message) in [
          (
            subscription('other.events', 'handle', 100),
            'subscription for other.events',
          ),
          (subscription('app.events', '', 100), 'empty subscription handle'),
          (
            subscription('app.events', 'handle', 99),
            'queue limit 99, expected 100',
          ),
        ]) {
          expect(
            () => validation.expectWampSubscription(
              result,
              topic: 'app.events',
              queueLimit: 100,
              label: 'Probe',
            ),
            diagnostic(message),
          );
        }
      },
    );
  });

  test(
    'session snapshot checks compare both independent state fields',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final message =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('MCP-Session-Id', 'fixture-session');
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': {
              'protocolVersion':
                  McpStreamableHttpClient.latestSessionProtocolVersion,
              'serverInfo': {'name': 'fixture', 'version': '1'},
              'capabilities': {},
            },
          }),
        );
        await request.response.close();
      });
      final client = McpStreamableHttpClient(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      );
      try {
        for (final initialized in [false, true]) {
          if (initialized) await client.initialize(id: 'snapshot');
          final id = initialized ? 'fixture-session' : null;
          expect(client.sessionId, id);
          accepted(
            () => validation.expectStreamableStateUnchanged(
              client,
              sessionId: id,
              lastEventId: null,
              label: 'Probe',
            ),
          );
          accepted(
            () => validation.expectSessionIdUnchanged(
              client,
              sessionId: id,
              diagnostic: 'session changed',
            ),
          );
          expect(
            () => validation.expectSessionIdUnchanged(
              client,
              sessionId: 'wrong',
              diagnostic: 'session changed',
            ),
            diagnostic('session changed'),
          );
          for (final (expectedId, cursor) in [
            (id, 'wrong-cursor'),
            ('wrong', null),
            ('wrong', 'wrong-cursor'),
          ]) {
            expect(
              () => validation.expectStreamableStateUnchanged(
                client,
                sessionId: expectedId,
                lastEventId: cursor,
                label: 'Probe',
              ),
              diagnostic('Probe changed Streamable state.'),
            );
            expect(
              () => validation.expectStreamableStateUnchanged(
                client,
                sessionId: expectedId,
                lastEventId: cursor,
                label: 'Probe',
                diagnostic: 'original diagnostic',
              ),
              diagnostic('original diagnostic'),
            );
          }
        }
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
