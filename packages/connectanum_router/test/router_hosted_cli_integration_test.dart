@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';
import 'package:test/test.dart';

import 'support/router_example.dart';

const _task = {'taskId': 'T-cli-regression', 'status': 'open'};
const _topic = 'example.events.task';
const _procedure = 'example.task.configured.lookup';
const _resource = 'app://example/context/live';

void main() {
  group('CLI against the public router example', () {
    late RouterExample router;
    RouterExample? started;
    setUpAll(() async {
      router = await RouterExample.start();
      started = router;
    });
    tearDownAll(() => started?.close());

    for (final scenario in [
      (version: '2025-03-26', route: '/mcp', ticket: false),
      (version: '2025-06-18', route: '/mcp', ticket: false),
      (version: '2025-06-18', route: '/mcp/secure', ticket: true),
      (version: '2025-06-18', route: '/mcp/secure-json-post', ticket: true),
    ]) {
      test(
        '${scenario.version} ${scenario.route} complete CLI session',
        () async {
          String? bearer;
          if (scenario.ticket) {
            final auth = ConnectanumHttpAuthClient(router.endpoint('/auth'));
            try {
              bearer = (await auth.issueTicketToken(
                realm: 'example.realm',
                authId: 'mcp-user',
                ticket: 'mcp-demo-ticket',
              )).accessToken;
            } finally {
              auth.close(force: true);
            }
          }
          final transcript = await _run(router, scenario.route, [
            '--protocol-version',
            scenario.version,
            '--rejected-origin',
            'https://rejected.example',
            if (bearer != null) ...['--bearer-token', bearer],
            ..._selectors,
          ]);
          _expectDirect(transcript);
          final stream = transcript['streamable'] as Map;
          expect(stream['protocolVersion'], scenario.version);
          expect(
            (stream['initialize'] as Map)['protocolVersion'],
            scenario.version,
          );
          expect(
            stream['sessionId'],
            isA<String>().having((s) => s.length, 'length', greaterThan(10)),
          );
          expect(stream['initializedNotification'], {'accepted': true});
          expect(stream['ping'], isEmpty);
          _expectTool(stream['toolResult']);
          _expectTool(stream['toolMethodResult']);
          _expectMetadata(stream['wampMetadata'] as Map);
          _expectPubSub(stream['pubsub'] as Map);
          for (final key in ['invalidLastEventId', 'malformedSessionId']) {
            expect(stream[key], {'rejected': true, 'sessionUnchanged': true});
          }
          expect(stream['emptyLastEventId'], {
            'accepted': true,
            'sessionUnchanged': true,
          });
          expect(stream['directJsonStaleSessionId'], {
            'ignored': true,
            'sessionUnchanged': true,
          });
          expect(stream['requestNegotiation'], {
            'rejected': true,
            'sessionUnchanged': true,
            'statuses': [405, 406, 415],
          });
          expect(stream['unsupportedProtocolVersion'], {
            'rejected': true,
            'sessionUnchanged': true,
            'methods': ['POST', 'GET', 'DELETE'],
          });
          expect(stream['originRejection'], {
            'origin': 'https://rejected.example',
            'rejected': true,
            'sessionUnchanged': true,
            'methods': ['POST', 'GET', 'DELETE'],
          });
          final resource = stream['resourceSubscription'] as Map;
          expect(resource, containsPair('uri', _resource));
          expect(
            resource,
            containsPair('updateTopic', 'example.events.context.updated'),
          );
          for (final key in [
            'contentChanged',
            'unsubscribed',
            'sessionUnchanged',
          ]) {
            expect(resource[key], isTrue, reason: key);
          }
          final active = stream['activeDirectJson'] as Map;
          expect(active['sessionUnchanged'], isTrue);
          expect(active['malformedSessionId'], {
            'rejected': true,
            'sessionUnchanged': true,
          });
          expect(active['directJsonStaleSessionId'], {
            'ignored': true,
            'sessionUnchanged': true,
          });
          expect(active['notificationOnlyBatch'], {
            'accepted': true,
            'sessionUnchanged': true,
          });
          expect(active['batchErrorIsolation'], {
            'responseIds': [
              'streamable-active-direct-batch-error-tools',
              'streamable-active-direct-batch-error-missing',
              'streamable-active-direct-batch-error-ping',
            ],
            'errorCode': -32601,
            'sessionUnchanged': true,
          });
          final activePubsub =
              (stream['pubsub'] as Map)['activeDirectJson'] as Map;
          for (final key in ['notificationBatch', 'toolNotificationBatch']) {
            final batch = activePubsub[key] as Map;
            expect(batch['accepted'], isTrue);
            expect(batch['sessionUnchanged'], isTrue);
            final events = batch['events'] as List;
            expect(events, hasLength(2));
            expect(
              events.map((e) => (e as Map)['topic']),
              everyElement(_topic),
            );
            expect(
              events.map((e) => (e as Map)['publicationId']).toSet(),
              hasLength(2),
            );
          }

          // The CLI must delete its own session, not merely print a success summary.
          final client = HttpClient();
          try {
            final response = await client.deleteUrl(
              router.endpoint(scenario.route),
            );
            response.headers.set(
              'Mcp-Session-Id',
              stream['sessionId'] as String,
            );
            response.headers.set('MCP-Protocol-Version', scenario.version);
            if (bearer != null) {
              response.headers.set('Authorization', 'Bearer $bearer');
            }
            final deleted = await response.close();
            await deleted.drain<void>();
            expect(deleted.statusCode, 404);
          } finally {
            client.close(force: true);
          }
        },
      );
    }

    for (final auth in [
      (flag: '--ticket', secret: 'mcp-demo-ticket', method: 'ticket'),
      (flag: '--wampcra-secret', secret: 'mcp-demo-secret', method: 'wampcra'),
      (flag: '--scram-secret', secret: 'mcp-demo-secret', method: 'scram'),
    ]) {
      test(
        'modern ${auth.method} refresh and revocation remain sessionless',
        () async {
          final transcript = await _run(router, '/mcp/secure', [
            '--protocol-version',
            '2026-07-28',
            ..._credentials(auth.flag, auth.secret),
            '--auth-lifecycle-smoke',
            ..._selectors,
          ]);
          _expectDirect(transcript, modern: true);
          expect(transcript, isNot(contains('streamable')));
          final lifecycle = transcript['authLifecycle'] as Map;
          expect(lifecycle, {
            'method': auth.method,
            'issued': true,
            'refreshed': true,
            'refreshedDirectPing': true,
            'refreshedSessionless': true,
            'refreshedRequestScopedResourceSubscription': isA<Map>(),
            'revokedAccessRejected': true,
            'revokedRefreshRejected': true,
          });
          final resource =
              lifecycle['refreshedRequestScopedResourceSubscription'] as Map;
          expect(resource['uri'], _resource);
          expect(resource['updateTopic'], 'example.events.context.updated');
          expect(resource['updateEvent'], {
            'source': 'router-hosted-client-resource-update',
          });
          for (final flag in [
            'acknowledged',
            'notificationReceived',
            'closedLocally',
            'sessionless',
          ]) {
            expect(resource[flag], isTrue, reason: flag);
          }
          expect(resource['notification'], {
            'jsonrpc': '2.0',
            'method': 'notifications/resources/updated',
            'params': {
              'uri': _resource,
              '_meta': {
                'io.modelcontextprotocol/subscriptionId':
                    'stateless-resource-listen',
              },
            },
          });
          final contents = resource['refreshedContent'] as List;
          expect(contents, hasLength(1));
          expect((contents.single as Map)['uri'], _resource);
          final stateless = transcript['stateless'] as Map;
          expect(stateless['protocolVersion'], '2026-07-28');
          expect(stateless['sessionless'], isTrue);
          expect(stateless['cacheScope'], 'private');
          expect(stateless['ttlMs'], 0);
        },
      );
    }

    test('wrong realm and unprotected auth discovery fail closed', () async {
      for (final scenario in [
        (route: '/mcp/secure', realm: 'wrong.realm'),
        (route: '/mcp', realm: 'example.realm'),
      ]) {
        await expectLater(
          _run(router, scenario.route, [
            '--realm',
            scenario.realm,
            '--auth-id',
            'mcp-user',
            '--ticket',
            'mcp-demo-ticket',
            '--protocol-version',
            '2026-07-28',
          ]),
          throwsA(isA<ConnectanumHttpAuthProtocolException>()),
        );
      }
    });
  });
}

List<String> _credentials(String flag, String secret) => [
  '--realm',
  'example.realm',
  '--auth-id',
  'mcp-user',
  flag,
  secret,
];

final _selectors = [
  '--tool',
  'example.task.lookup',
  '--tool-arguments',
  '{"taskId":"T-cli-regression"}',
  '--resource-uri',
  _resource,
  '--resource-update-topic',
  'example.events.context.updated',
  '--prompt',
  'summarize-task',
  '--prompt-arguments',
  '{"taskId":"T-cli-regression"}',
  '--wamp-procedure',
  _procedure,
  '--wamp-topic',
  _topic,
  '--pubsub-topic',
  _topic,
  '--pubsub-event',
  jsonEncode(_task),
];

void _expectDirect(Map<String, dynamic> transcript, {bool modern = false}) {
  if (modern) {
    final ping = transcript['directPing'] as Map;
    expect(ping['resultType'], 'complete');
    expect(
      (ping['_meta'] as Map)['io.modelcontextprotocol/serverInfo'],
      containsPair('name', 'connectanum-router'),
    );
  } else {
    expect(transcript['directPing'], isEmpty);
  }
  expect(transcript['directStandardTools'], contains('example.task.lookup'));
  expect(
    transcript['directTools'],
    containsAll([
      'wamp.session.list',
      'wamp.subscription.list',
      'wamp.registration.list',
    ]),
  );
  for (final name in [
    'directToolResult',
    'directStandardToolResult',
    'directToolMethodResult',
  ]) {
    _expectTool(transcript[name]);
  }
  _expectMetadata(transcript['directWampMetadata'] as Map);
  _expectPubSub(transcript);
  expect(transcript['directResources'], contains(_resource));
  expect(transcript['directPrompts'], contains('summarize-task'));
}

void _expectTool(dynamic value) {
  final result = value as Map;
  expect(result['isError'], isFalse);
  expect(result['structuredContent'], {
    'argumentsKeywords': {..._task, 'source': 'router-hosted-mcp-example'},
  });
  final content = result['content'] as List;
  expect(content, hasLength(1));
  expect(
    jsonDecode((content.single as Map)['text'] as String),
    result['structuredContent'],
  );
}

void _expectMetadata(Map value) {
  final procedure = value['procedure'] as Map;
  expect(procedure['name'], _procedure);
  final registration = procedure['configuredRegistrationMetadata'] as Map;
  final registrationId = registration['registrationId'];
  expect(registrationId, isA<int>().having((id) => id, 'id', greaterThan(0)));
  expect(
    (registration['details'] as Map)['argumentsKeywords'],
    containsPair('uri', _procedure),
  );
  for (final operation in ['lookup', 'match']) {
    expect((registration[operation] as Map)['arguments'], [registrationId]);
  }
  expect((registration['calleeCount'] as Map)['arguments'], [0]);
  final topic = value['topic'] as Map;
  expect(topic['name'], _topic);
  final subscription = topic['configuredSubscriptionMetadata'] as Map;
  final subscriptionId = subscription['subscriptionId'];
  expect(subscriptionId, isA<int>().having((id) => id, 'id', greaterThan(0)));
  expect(
    (subscription['details'] as Map)['argumentsKeywords'],
    containsPair('uri', _topic),
  );
  for (final operation in ['lookup', 'match']) {
    expect((subscription[operation] as Map)['arguments'], [subscriptionId]);
  }
  expect((subscription['subscriberCount'] as Map)['arguments'], [0]);
}

void _expectPubSub(Map value) {
  expect(value['dropped'], 0);
  expect(value['remaining'], 0);
  final subscription = value['subscription'] as Map;
  expect(subscription['topic'], _topic);
  final publication = value['publication'] as Map;
  expect(publication['acknowledged'], isTrue);
  final events = value['events'] as List;
  expect(events, hasLength(1));
  final event = events.single as Map;
  expect(event['topic'], _topic);
  expect(event['subscriptionId'], subscription['subscriptionId']);
  expect(event['publicationId'], publication['publicationId']);
  expect(event['argumentsKeywords'], _task);
}

Future<Map<String, dynamic>> _run(
  RouterExample router,
  String route,
  List<String> args,
) async {
  final output = _Output();
  final errors = _Output();
  try {
    await IOOverrides.runZoned(
      () => runRouterHostedClient([
        '--endpoint',
        router.endpoint(route).toString(),
        ...args,
      ]),
      stdout: () => output,
      stderr: () => errors,
    );
  } finally {
    final secrets = <String>['mcp-demo-ticket', 'mcp-demo-secret'];
    for (var index = 0; index + 1 < args.length; index++) {
      if ([
        '--bearer-token',
        '--ticket',
        '--wampcra-secret',
        '--scram-secret',
      ].contains(args[index])) {
        secrets.add(args[index + 1]);
      }
    }
    for (final secret in secrets) {
      expect(output.text.toString(), isNot(contains(secret)));
      expect(errors.text.toString(), isNot(contains(secret)));
    }
  }
  expect(errors.text.toString(), isEmpty);
  final transcript = <String, dynamic>{};
  for (final line in const LineSplitter().convert(output.text.toString())) {
    final record = jsonDecode(line) as Map<String, dynamic>;
    expect(
      record.keys.where(transcript.containsKey),
      isEmpty,
      reason: 'Duplicate summary keys',
    );
    transcript.addAll(record);
  }
  return transcript;
}

class _Output implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? object = '']) => text.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
