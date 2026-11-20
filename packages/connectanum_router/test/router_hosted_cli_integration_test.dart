@TestOn('vm')
@Timeout(Duration(seconds: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';
import 'package:test/test.dart';

import '../../connectanum_mcp/test/cli/owned_http_client_test_support.dart';

import 'support/router_example.dart';

const _task = {'taskId': 'T-cli-regression', 'status': 'open'};
const _topic = 'example.events.task';
const _procedure = 'example.task.configured.lookup';
const _resource = 'app://example/context/live';

void main() {
  test(
    'proxy preserves discovery paths and maps only its endpoint prefix',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        request.response.write('${request.uri.path}?${request.uri.query}');
        await request.response.close();
      });
      final proxy = await _ResponseFaultProxy.start(
        Uri.parse('http://127.0.0.1:${upstream.port}/actual/mcp'),
        'unused-json-target',
        null,
      );
      final client = HttpClient();
      try {
        for (final (path, expected) in [
          ('/mcp?first=1', '/actual/mcp?first=1'),
          ('/.well-known/mcp.json?x=1', '/.well-known/mcp.json?x=1'),
          ('/mcp/discovery?y=2', '/actual/mcp/discovery?y=2'),
          ('/mcp-other', '/mcp-other?'),
        ]) {
          final request = await client.getUrl(proxy.endpoint.resolve(path));
          final response = await request.close();
          expect(await utf8.decoder.bind(response).join(), expected);
        }
      } finally {
        client.close(force: true);
        await proxy.close();
        await upstream.close(force: true);
      }
    },
  );

  for (final rejectFollowing in [false, true]) {
    test(
      'proxy checks the next request before forwarding: $rejectFollowing',
      () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var forwarded = 0;
        upstream.listen((request) async {
          forwarded++;
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'probe',
              'result': {},
            }),
          );
          await request.response.close();
        });
        final proxy = await _ResponseFaultProxy.start(
          Uri.parse('http://127.0.0.1:${upstream.port}/mcp'),
          'probe',
          null,
          rewrite: (response) => response,
          rejectFollowingRequests: rejectFollowing,
        );
        final client = HttpClient();
        try {
          final request = await client.postUrl(proxy.endpoint);
          request.write(
            jsonEncode({'jsonrpc': '2.0', 'id': 'probe', 'method': 'probe'}),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();
          final next = await client.getUrl(proxy.endpoint);
          final nextResponse = await next.close();
          expect(
            nextResponse.statusCode,
            rejectFollowing ? HttpStatus.internalServerError : HttpStatus.ok,
          );
          await nextResponse.drain<void>();
          expect(proxy.changedResponses, 1);
          expect(proxy.requests, hasLength(2));
          expect(forwarded, rejectFollowing ? 1 : 2);
        } finally {
          client.close(force: true);
          await upstream.close(force: true);
          if (rejectFollowing) {
            expect(proxy.failures, [isA<TestFailure>()]);
            await expectLater(proxy.close(), throwsA(isA<TestFailure>()));
          } else {
            await proxy.close();
          }
        }
      },
    );
  }

  group('CLI against the public router example', () {
    late RouterExample router;
    RouterExample? started;
    RouterExampleSmokeFailure? smokeFailure;
    void routerTest(String name, Future<void> Function() body) {
      test(name, () async {
        expect(
          smokeFailure,
          isNull,
          reason: 'The public example must pass its MCP smoke before CLI use.',
        );
        await body();
      });
    }

    setUpAll(() async {
      try {
        router = await RouterExample.start();
        started = router;
      } on RouterExampleSmokeFailure catch (error) {
        // A deliberate product smoke rejection belongs to the behavior oracle.
        // Missing native assets, compiler errors and deadlines still fail setup.
        smokeFailure = error;
      }
    });
    tearDownAll(() => started?.close());

    routerTest(
      'compatibility template expansion keeps its live session',
      () async {
        final transcript = await _runSuccessfully(router, '/mcp', [
          '--protocol-version',
          '2025-06-18',
          '--resource-template',
          'app://example/tasks/{taskId}',
          '--resource-template-variables',
          '{"taskId":"T-cli-template"}',
        ]);
        final direct = transcript['directResourceTemplateExpansion'] as Map;
        final session = transcript['streamable'] as Map;
        final streamed = session['resourceTemplateExpansion'] as Map;
        for (final expansion in [direct, streamed]) {
          expect(expansion['uriTemplate'], 'app://example/tasks/{taskId}');
          expect(expansion['variableNames'], ['taskId']);
          expect(expansion['uri'], 'app://example/tasks/T-cli-template');
          expect(expansion['pagesRead'], greaterThanOrEqualTo(1));
          expect(expansion['content'], isA<List>());
          final contents = expansion['content'] as List;
          expect(contents, hasLength(1));
          expect(
            (contents.single as Map)['uri'],
            'app://example/tasks/T-cli-template',
          );
        }
        expect(streamed['sessionUnchanged'], isTrue);
      },
    );
    routerTest(
      'compatibility session omits every unrequested WAMP capability',
      () async {
        final transcript = await _runSuccessfully(router, '/mcp', [
          '--protocol-version',
          '2025-06-18',
        ]);
        expect(transcript['directBatch'], {
          'responseIds': ['direct-batch-standard-tools', 'direct-batch-tools'],
        });
        final session = transcript['streamable'] as Map;
        expect(session, isNot(contains('wampMetadata')));
        expect(session, isNot(contains('pubsub')));
        expect(session['batch'], {
          'responseIds': ['streamable-batch-tools'],
        });
      },
    );

    for (final scenario in [
      (version: '2025-03-26', route: '/mcp', ticket: false),
      (version: '2025-06-18', route: '/mcp', ticket: false),
      (version: '2025-06-18', route: '/mcp/secure', ticket: true),
      (version: '2025-06-18', route: '/mcp/secure-json-post', ticket: true),
    ]) {
      routerTest(
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
          final transcript = await _runSuccessfully(router, scenario.route, [
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

    for (final auth in ['none', 'bearer', 'ticket']) {
      routerTest(
        'minimal compatibility session supports $auth authentication',
        () async {
          String? bearer;
          if (auth == 'bearer') {
            final client = ConnectanumHttpAuthClient(router.endpoint('/auth'));
            try {
              bearer = (await client.issueTicketToken(
                realm: 'example.realm',
                authId: 'mcp-user',
                ticket: 'mcp-demo-ticket',
              )).accessToken;
            } finally {
              client.close(force: true);
            }
          }
          final transcript = await _runSuccessfully(
            router,
            auth == 'none' ? '/mcp' : '/mcp/secure',
            [
              '--protocol-version',
              '2025-06-18',
              if (bearer != null) ...['--bearer-token', bearer],
              if (auth == 'ticket') ...[
                ..._credentials('--ticket', 'mcp-demo-ticket'),
                '--auth-lifecycle-smoke',
              ],
            ],
          );
          expect(transcript, containsPair('directPing', <String, Object?>{}));
          expect(transcript, isNot(contains('directPubSub')));
          expect(transcript, isNot(contains('directWampMetadata')));
          expect(transcript['directBatch'], {
            'responseIds': [
              'direct-batch-standard-tools',
              'direct-batch-tools',
            ],
          });
          final session = transcript['streamable'] as Map;
          expect(session, isNot(contains('wampMetadata')));
          expect(session['activeDirectJson'], isA<Map>());
          expect(
            session['activeDirectJson'] as Map,
            isNot(contains('wampMetadata')),
          );
          expect(session['protocolVersion'], '2025-06-18');
          expect(session['sessionId'], isNotEmpty);
          if (auth == 'ticket') {
            expect(transcript['authLifecycle'], {
              'method': 'ticket',
              'issued': true,
              'refreshed': true,
              'refreshedDirectPing': true,
              'refreshedStreamableSession': true,
              'revokedAccessRejected': true,
              'revokedRefreshRejected': true,
            });
          }
        },
      );
    }

    for (final procedureOnly in [true, false]) {
      routerTest(
        'one WAMP selector preserves ${procedureOnly ? 'procedure' : 'topic'} metadata',
        () async {
          final transcript = await _runSuccessfully(router, '/mcp', [
            '--protocol-version',
            '2025-06-18',
            if (procedureOnly) ...[
              '--wamp-procedure',
              _procedure,
            ] else ...[
              '--wamp-topic',
              _topic,
            ],
          ]);
          final selected = procedureOnly ? 'procedure' : 'topic';
          final absent = procedureOnly ? 'topic' : 'procedure';
          for (final (value, sessionKey) in [
            (transcript['directWampMetadata'], 'sessionMetadata'),
            ((transcript['streamable'] as Map)['wampMetadata'], 'sessionCount'),
            (
              ((transcript['streamable'] as Map)['activeDirectJson']
                  as Map)['wampMetadata'],
              'sessionMetadata',
            ),
          ]) {
            expect(value, isA<Map>());
            expect(value as Map, contains(selected));
            expect(value, isNot(contains(absent)));
            expect(value, contains(sessionKey));
          }
          final batch = transcript['directBatch'];
          expect(batch, isA<Map>());
          expect(batch as Map, contains('wampSessionMetadata'));
          expect(
            batch,
            contains(
              procedureOnly
                  ? 'configuredRegistrationMetadata'
                  : 'configuredSubscriptionMetadata',
            ),
          );
          expect(
            batch,
            isNot(
              contains(
                procedureOnly
                    ? 'configuredSubscriptionMetadata'
                    : 'configuredRegistrationMetadata',
              ),
            ),
          );
        },
      );
    }

    group('adversarial HTTP rejection diagnostics', () {
      final probes = <(String, String)>[
        for (final method in ['post', 'get', 'delete']) ...[
          ('malformed-session-id-$method', 'malformed MCP-Session-Id'),
          ('unsupported-protocol-version-$method', 'unsupported MCP protocol'),
          ('rejected-origin-${method.toUpperCase()}', 'rejected-Origin'),
        ],
        for (final label in [
          'compatibility-method',
          'stateless-method',
          'compatibility-get-accept',
          'compatibility-post-accept',
          'stateless-post-accept',
          'compatibility-post-content-type',
        ])
          ('negotiation-$label', '$label negotiation'),
      ];
      for (final (probe, diagnostic) in probes) {
        for (final fault in ['status', 'session header', 'body']) {
          routerTest('$probe rejects a wrong $fault', () async {
            final proxy = await _ResponseFaultProxy.start(
              router.endpoint('/mcp'),
              'unused-json-target',
              null,
              targetTrace: 'router-hosted-client-streamable-$probe',
              rewriteHttp: (request, response, text) {
                switch (fault) {
                  case 'status':
                    request.response.statusCode = HttpStatus.badGateway;
                  case 'session header':
                    request.response.headers.set(
                      'MCP-Session-Id',
                      'wrong-session',
                    );
                  case 'body':
                    return 'A different rejection';
                }
                return text;
              },
            );
            try {
              await expectLater(
                IOOverrides.runZoned(
                  () => runRouterHostedClient([
                    '--endpoint',
                    proxy.endpoint.toString(),
                    '--protocol-version',
                    '2025-06-18',
                    '--rejected-origin',
                    'https://rejected.example',
                  ]),
                  stdout: _Output.new,
                  stderr: _Output.new,
                ),
                throwsA(
                  isA<StateError>().having(
                    (error) => error.message,
                    'HTTP rejection diagnostic',
                    contains(diagnostic),
                  ),
                ),
              );
              expect(proxy.changedResponses, 1);
              expect(proxy.faultRequestIndex, isNotNull);
              expect(
                proxy.requests.skip(proxy.faultRequestIndex! + 1),
                everyElement(('DELETE', null)),
                reason: 'Only session cleanup may follow a rejected probe',
              );
            } finally {
              await proxy.close();
            }
          });
        }
      }
    });

    routerTest(
      'resource update consumes its matching notification before another poll',
      () async {
        final proxy = await _ResponseFaultProxy.start(
          router.endpoint('/mcp'),
          'unused-json-target',
          null,
          targetTrace: 'router-hosted-client-resource-update-poll',
          rewriteHttp: (request, response, text) {
            expect(response.statusCode, HttpStatus.ok);
            return text;
          },
          maximumTraceResponses: 1,
        );
        try {
          final output = _Output();
          await expectLater(
            IOOverrides.runZoned(
              () => runRouterHostedClient([
                '--endpoint',
                proxy.endpoint.toString(),
                '--protocol-version',
                '2025-06-18',
                '--resource-uri',
                _resource,
                '--resource-update-topic',
                'example.events.context.updated',
              ]),
              stdout: () => output,
              stderr: _Output.new,
            ),
            completes,
          );
          expect(proxy.changedResponses, 1);
          final transcript = <String, dynamic>{};
          for (final line in const LineSplitter().convert(
            output.text.toString(),
          )) {
            transcript.addAll(jsonDecode(line) as Map<String, dynamic>);
          }
          final resource =
              (transcript['streamable'] as Map)['resourceSubscription'] as Map;
          final event = resource['notification'] as Map;
          expect(event['method'], 'notifications/resources/updated');
          expect(event['params'], containsPair('uri', _resource));
          expect(resource['unsubscribed'], isTrue);
        } finally {
          await proxy.close();
        }
      },
    );

    group('adversarial direct batch metadata', () {
      final faults = <(String, Map<String, Object?>, String)>[
        for (final (suffix, key) in [
          ('standard-tools', 'tools'),
          ('tools', 'tools'),
          ('resources', 'resources'),
          ('prompts', 'prompts'),
          ('wamp-procedure-api-list', 'procedures'),
          ('wamp-topic-api-list', 'topics'),
        ])
          (suffix, {key: [], 'nextCursor': null}, 'did not advertise'),
        for (final operation in ['count', 'list', 'get'])
          (
            'wamp-session-$operation',
            {'procedure': 'wamp.other'},
            'returned procedure wamp.other',
          ),
        (
          'wamp-session-count',
          {'argumentsKeywords': null},
          'returned no argumentsKeywords map',
        ),
        (
          'wamp-session-count',
          {'structuredContent': null, 'procedure': null},
          'returned no structured content',
        ),
        for (final count in [0, -1, null, 1.25, '1'])
          (
            'wamp-session-count',
            {
              'argumentsKeywords': {'count': count},
            },
            'batch returned invalid session count',
          ),
        (
          'wamp-session-list',
          {
            'argumentsKeywords': {'session_ids': []},
          },
          'batch returned no session ids',
        ),
        (
          'wamp-session-list',
          {
            'argumentsKeywords': {
              'session_ids': List.generate(100, (index) => index + 1),
            },
          },
          'was smaller than listed sessions',
        ),
        (
          'wamp-session-get',
          {
            'argumentsKeywords': {'details': null},
          },
          'batch session get returned no details map',
        ),
        (
          'wamp-session-get',
          {
            'argumentsKeywords': {
              'details': {'id': -1},
            },
          },
          'batch session get returned session',
        ),
        for (final kind in ['registration', 'subscription']) ...[
          (
            'wamp-configured-$kind-lookup',
            {'arguments': null},
            'returned no arguments list',
          ),
          (
            'wamp-configured-$kind-lookup',
            {'arguments': []},
            'lookup returned no $kind id',
          ),
          (
            'wamp-configured-$kind-match',
            {'arguments': []},
            'match did not include lookup id',
          ),
          (
            'wamp-configured-$kind-list',
            {
              'argumentsKeywords': {'exact': []},
            },
            'list did not include lookup id',
          ),
          (
            'wamp-configured-$kind-get',
            {
              'argumentsKeywords': {'uri': 'other.uri'},
            },
            'details returned other.uri',
          ),
          for (final operation in ['lookup', 'match', 'list', 'get'])
            (
              'wamp-configured-$kind-$operation',
              {'procedure': 'wamp.other'},
              'returned procedure wamp.other',
            ),
        ],
        (
          'wamp-configured-registration-callees',
          {
            'arguments': [42],
          },
          'exposed live callees',
        ),
        (
          'wamp-configured-subscription-subscribers',
          {
            'arguments': [42],
          },
          'exposed live subscribers',
        ),
        for (final values in [
          <int>[],
          [1],
        ]) ...[
          (
            'wamp-configured-registration-callee-count',
            {'arguments': values},
            'configured registration callee count was',
          ),
          (
            'wamp-configured-subscription-subscriber-count',
            {'arguments': values},
            'configured subscription subscriber count was',
          ),
        ],
        (
          'wamp-session-count',
          {'isError': true, 'content': []},
          'returned an error',
        ),
      ];
      for (final (suffix, patch, diagnostic) in faults) {
        routerTest(
          '$suffix ${jsonEncode(patch)} rejects before further requests',
          () async {
            final proxy = await _ResponseFaultProxy.start(
              router.endpoint('/mcp'),
              'direct-batch-$suffix',
              null,
              rejectFollowingRequests: true,
              rewrite: (envelope) {
                final result = envelope['result'] as Map;
                final content = result['structuredContent'];
                return {
                  ...envelope,
                  'result': {
                    ...result,
                    if (content is Map &&
                        !patch.containsKey('structuredContent') &&
                        !patch.containsKey('isError'))
                      'structuredContent': {...content, ...patch}
                    else
                      ...patch,
                  },
                };
              },
            );
            try {
              await expectLater(
                IOOverrides.runZoned(
                  () => runRouterHostedClient([
                    '--endpoint',
                    proxy.endpoint.toString(),
                    '--protocol-version',
                    '2025-06-18',
                    ..._selectors,
                  ]),
                  stdout: _Output.new,
                  stderr: _Output.new,
                ),
                throwsA(
                  isA<StateError>().having(
                    (error) => error.message,
                    'batch diagnostic',
                    contains(diagnostic),
                  ),
                ),
              );
              expect(proxy.changedResponses, 1);
              expect(proxy.faultRequestIndex, isNotNull);
              expect(
                proxy.requests.skip(proxy.faultRequestIndex! + 1),
                isEmpty,
                reason: 'No further request may follow a rejected batch',
              );
            } finally {
              await proxy.close();
            }
          },
        );
      }

      // Each shape performs the complete native exchange once. All ten named
      // cases independently inspect their operation in that immutable transcript.
      // Captures are lazy and sequential: sessions must not share live topics.
      final shapeTranscripts = <String, Future<Map<String, dynamic>>>{};
      Future<Map<String, dynamic>> captureShape(String shape) async {
        final proxy = await _ResponseFaultProxy.start(
          router.endpoint('/mcp'),
          'direct-batch-wamp-session-get',
          null,
          additionalTargetIds: shape == 'wrapped'
              ? const {}
              : const {
                  'direct-batch-wamp-session-count',
                  'direct-batch-wamp-session-list',
                },
          rewrite: (envelope) {
            if (shape == 'wrapped') return envelope;
            final operation = (envelope['id'] as String).split('-').last;
            final result = envelope['result'] as Map;
            final content = {...result['structuredContent'] as Map};
            if (shape == 'without procedure') {
              content.remove('procedure');
            } else {
              content['procedure'] = 'wamp.session.$operation';
            }
            return {
              ...envelope,
              'result': shape == 'flat'
                  ? content
                  : {...result, 'structuredContent': content},
            };
          },
        );
        final output = _Output();
        try {
          try {
            await IOOverrides.runZoned(
              () => expectOwnedHttpClientsClosed(
                () => runRouterHostedClient([
                  '--endpoint',
                  proxy.endpoint.toString(),
                  '--protocol-version',
                  '2025-06-18',
                  ..._selectors,
                ]),
              ),
              stdout: () => output,
              stderr: _Output.new,
            );
          } on StateError catch (error) {
            fail('Valid $shape metadata exchange was rejected: $error');
          }
          final transcript = <String, dynamic>{
            for (final line in const LineSplitter().convert(
              output.text.toString(),
            ))
              ...(jsonDecode(line) as Map).cast<String, dynamic>(),
          };
          _expectDirect(transcript);
          expect(transcript['directBatch'], isA<Map>());
          expect(transcript['streamable'], isA<Map>());
          expect(proxy.changedResponses, shape == 'wrapped' ? 1 : 3);
          expect(proxy.requests.last, ('DELETE', null));
          return Map.unmodifiable(transcript);
        } finally {
          await proxy.close();
        }
      }

      for (final (operation, shape) in [
        ('get', 'wrapped'),
        for (final operation in ['count', 'list', 'get']) ...[
          (operation, 'without procedure'),
          (operation, 'with procedure'),
          (operation, 'flat'),
        ],
      ]) {
        routerTest(
          '$shape $operation batch passes the proxy and reaches session cleanup',
          () async {
            final transcript = await shapeTranscripts.putIfAbsent(
              shape,
              () => captureShape(shape),
            );
            final metadata =
                (transcript['directBatch'] as Map)['wampSessionMetadata']
                    as Map;
            final selected =
                metadata[operation == 'get' ? 'selectedSession' : operation]
                    as Map;
            expect(
              selected['procedure'],
              shape == 'without procedure' || shape == 'wrapped'
                  ? isNull
                  : 'wamp.session.$operation',
            );
          },
        );
      }
    });

    for (final auth in [
      (flag: '--ticket', secret: 'mcp-demo-ticket', method: 'ticket'),
      (flag: '--wampcra-secret', secret: 'mcp-demo-secret', method: 'wampcra'),
      (flag: '--scram-secret', secret: 'mcp-demo-secret', method: 'scram'),
    ]) {
      routerTest(
        'modern ${auth.method} refresh and revocation remain sessionless',
        () async {
          final transcript = await _runSuccessfully(router, '/mcp/secure', [
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

    routerTest(
      'wrong realm and unprotected auth discovery fail closed',
      () async {
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
      },
    );

    for (final prefix in [
      'direct-pubsub',
      'streamable-active-direct-pubsub',
      'streamable-pubsub',
    ]) {
      for (final field in ['topic', 'queueLimit']) {
        routerTest(
          '$prefix releases subscription after rejected $field',
          () async {
            final proxy = await _ResponseFaultProxy.start(
              router.endpoint('/mcp'),
              '$prefix-subscribe',
              field,
            );
            try {
              await expectLater(
                IOOverrides.runZoned(
                  () => runRouterHostedClient([
                    '--endpoint',
                    proxy.endpoint.toString(),
                    '--protocol-version',
                    '2025-06-18',
                    '--pubsub-topic',
                    _topic,
                  ]),
                  stdout: _Output.new,
                  stderr: _Output.new,
                ),
                throwsA(
                  isA<StateError>().having(
                    (error) => error.message,
                    'subscription diagnostic',
                    contains(
                      field == 'topic'
                          ? 'returned subscription for'
                          : 'returned queue limit',
                    ),
                  ),
                ),
              );
              expect(proxy.changedResponses, 1);
              expect(proxy.subscriptionHandle, isNotEmpty);
              expect(proxy.cleanedHandles, contains(proxy.subscriptionHandle));
              final afterFault = proxy.requests
                  .skipWhile(
                    (request) => request.$2 != '$prefix-subscribe',
                  )
                  .skip(1);
              expect(afterFault, [
                ('POST', '$prefix-unsubscribe'),
                if (prefix != 'direct-pubsub') ('DELETE', null),
              ], reason: 'Only cleanup may follow the rejected subscription');
            } finally {
              await proxy.close();
            }
          },
        );
      }
    }
  });
}

// Corrupt one real router response while retaining its wire shape and siblings.
// Subscription cleanup evidence comes from the router's acknowledgement.
class _ResponseFaultProxy {
  _ResponseFaultProxy(
    this.server,
    this.upstream,
    this.targetId,
    this.field, {
    this.rewrite,
    this.targetTrace,
    this.rewriteHttp,
    this.maximumTraceResponses,
    this.additionalTargetIds = const {},
    this.rejectFollowingRequests = false,
  }) {
    server.listen((request) {
      late Future<void> pending;
      pending = _handle(request).whenComplete(() => _pending.remove(pending));
      _pending.add(pending);
    });
  }

  final HttpServer server;
  final Uri upstream;
  final String targetId;
  final Set<String> additionalTargetIds;
  final bool rejectFollowingRequests;

  bool _targetsId(Object? id) =>
      id == targetId || additionalTargetIds.contains(id);
  final String? field;
  final Map<String, Object?> Function(Map<String, Object?>)? rewrite;
  final String? targetTrace;
  final String Function(HttpRequest, HttpClientResponse, String)? rewriteHttp;
  final int? maximumTraceResponses;
  final client = HttpClient();
  final requests = <(String, Object?)>[];
  final cleanedHandles = <String>[];
  final failures = <Object>[];
  final _deliveredResourceUpdates = <String>{};
  final _pending = <Future<void>>{};
  String? subscriptionHandle;
  int changedResponses = 0;
  int? faultRequestIndex;
  bool _closing = false;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${server.port}/mcp');

  static Future<_ResponseFaultProxy> start(
    Uri upstream,
    String id,
    String? field, {
    Map<String, Object?> Function(Map<String, Object?>)? rewrite,
    String? targetTrace,
    String Function(HttpRequest, HttpClientResponse, String)? rewriteHttp,
    int? maximumTraceResponses,
    Set<String> additionalTargetIds = const {},
    bool rejectFollowingRequests = false,
  }) async => _ResponseFaultProxy(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    upstream,
    id,
    field,
    rewrite: rewrite,
    targetTrace: targetTrace,
    rewriteHttp: rewriteHttp,
    maximumTraceResponses: maximumTraceResponses,
    additionalTargetIds: additionalTargetIds,
    rejectFollowingRequests: rejectFollowingRequests,
  );

  Future<void> close() async {
    _closing = true;
    client.close(force: true);
    await server.close(force: true);
    await Future.wait(List.of(_pending));
    expect(
      failures,
      isEmpty,
      reason: 'Proxy failures must not masquerade as CLI rejections',
    );
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await request.fold<List<int>>(
        [],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final message = body.isEmpty ? null : jsonDecode(utf8.decode(body));
      // These proxy cases negotiate the compatibility protocol. A stateless
      // discovery cannot replace initialization or enter an unrelated SSE wait.
      expect(
        message is Map ? message['method'] : null,
        isNot('server/discover'),
        reason: 'The compatibility CLI must initialize its negotiated session',
      );
      final id = message is Map ? message['id'] : null;
      final session = request.headers.value('MCP-Session-Id') ?? '';
      final resourcePoll =
          request.headers.value('x-consumer-trace') ==
          'router-hosted-client-resource-update-poll';
      if (message is Map && message['method'] == 'resources/subscribe') {
        expect(
          session,
          isNotEmpty,
          reason:
              'The compatibility subscription must use its negotiated session',
        );
        _deliveredResourceUpdates.remove(session);
      }
      if (resourcePoll) {
        expect(
          session,
          isNotEmpty,
          reason: 'The compatibility poll must carry its negotiated session',
        );
        expect(
          _deliveredResourceUpdates,
          isNot(contains(session)),
          reason: 'The CLI must consume the matching update already delivered',
        );
      }
      final requestIndex = requests.length;
      requests.add((request.method, id));
      if (rejectFollowingRequests) {
        // Enforce the existing no-follow-up oracle before executing another
        // native exchange after the deliberately rejected metadata response.
        expect(
          faultRequestIndex,
          isNull,
          reason: 'No request may follow the rejected metadata batch',
        );
      }
      if (targetTrace != null &&
          request.headers.value('x-consumer-trace') == targetTrace &&
          maximumTraceResponses != null) {
        // Reject an extra poll before forwarding it: an empty upstream SSE
        // poll can otherwise wait past the unchanged test deadline.
        expect(
          changedResponses,
          lessThan(maximumTraceResponses!),
          reason:
              'The matching notification must be consumed before another poll',
        );
      }
      final outgoing = await client.openUrl(
        request.method,
        upstream.replace(
          path: request.uri.path == endpoint.path
              ? upstream.path
              : request.uri.path.startsWith('${endpoint.path}/')
              ? '${upstream.path}${request.uri.path.substring(endpoint.path.length)}'
              : request.uri.path,
          query: request.uri.query,
        ),
      );
      request.headers.forEach((name, values) {
        if (![
          'host',
          'content-length',
          'transfer-encoding',
          'connection',
        ].contains(name)) {
          outgoing.headers.set(name, values);
        }
      });
      outgoing.contentLength = body.length;
      outgoing.add(body);
      final response = await outgoing.close();
      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, values) {
        if (![
          'content-length',
          'transfer-encoding',
          'connection',
        ].contains(name)) {
          request.response.headers.set(name, values);
        }
      });
      final targetsBatch =
          message is List &&
          message.any((item) => item is Map && _targetsId(item['id']));
      if (targetTrace != null &&
          request.headers.value('x-consumer-trace') == targetTrace) {
        final text = await utf8.decoder.bind(response).join();
        changedResponses++;
        faultRequestIndex = requestIndex;
        if (maximumTraceResponses != null) {
          expect(changedResponses, lessThanOrEqualTo(maximumTraceResponses!));
        }
        request.response.write(rewriteHttp!(request, response, text));
      } else if (_targetsId(id) ||
          targetsBatch ||
          (id is String && id.endsWith('-pubsub-unsubscribe'))) {
        final text = await utf8.decoder.bind(response).join();
        Map<String, Object?> inspect(Map<String, Object?> envelope) {
          final responseId = envelope['id'];
          if (_targetsId(responseId)) {
            changedResponses++;
            faultRequestIndex = requestIndex;
            if (rewrite != null) return rewrite!(envelope);
          } else if (responseId is! String ||
              !responseId.endsWith('-pubsub-unsubscribe')) {
            return envelope;
          }
          final result = envelope['result'] as Map;
          final content = result['structuredContent'] as Map;
          if (_targetsId(responseId)) {
            subscriptionHandle = content['handle'] as String;
            return {
              ...envelope,
              'result': {
                ...result,
                'structuredContent': {
                  ...content,
                  field!: field == 'topic' ? 'unexpected.topic' : 11,
                },
              },
            };
          }
          expect(content['unsubscribed'], isTrue);
          cleanedHandles.add(content['handle'] as String);
          return envelope;
        }

        Object inspectBody(Object? body) => body is List
            ? [
                for (final envelope in body)
                  inspect((envelope as Map).cast<String, Object?>()),
              ]
            : inspect((body as Map).cast<String, Object?>());

        if (response.headers.contentType?.mimeType == 'text/event-stream') {
          request.response.write(
            text
                .split('\n')
                .map((line) {
                  if (!line.startsWith('data:')) return line;
                  final data = line.substring(5).trim();
                  if (data.isEmpty) return line;
                  return 'data: ${jsonEncode(inspectBody(jsonDecode(data)))}';
                })
                .join('\n'),
          );
        } else {
          request.response.write(
            jsonEncode(
              inspectBody(jsonDecode(text)),
            ),
          );
        }
      } else if (resourcePoll) {
        final text = await utf8.decoder.bind(response).join();
        for (final event in parseMcpSseEvents(text)) {
          final data = event.jsonData;
          final params = data?['params'];
          if (event.id?.isNotEmpty == true &&
              data?['method'] == 'notifications/resources/updated' &&
              params is Map &&
              params['uri'] == _resource) {
            _deliveredResourceUpdates.add(session);
          }
        }
        request.response.write(text);
      } else {
        await request.response.addStream(response);
      }
      await request.response.close();
    } catch (error) {
      if (!_closing || error is! IOException) failures.add(error);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on IOException catch (closeError) {
        if (!_closing) failures.add(closeError);
      }
    }
  }
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

Future<Map<String, dynamic>> _runSuccessfully(
  RouterExample router,
  String route,
  List<String> args,
) async {
  late Map<String, dynamic> result;
  try {
    result = await _run(router, route, args);
  } on McpStreamableProtocolException catch (error) {
    fail('The valid CLI protocol was rejected: $error');
  } on FormatException catch (error) {
    fail('The valid CLI response was rejected: $error');
  } on StateError catch (error) {
    fail('The valid CLI exchange was rejected: $error');
  }
  return result;
}

Future<Map<String, dynamic>> _run(
  RouterExample router,
  String route,
  List<String> args,
) async {
  final output = _Output();
  final errors = _Output();
  // The compatibility resource flow must consume a delivered update; auth-only
  // and stateless modern flows keep their original direct endpoint.
  final proxy =
      args.contains('--resource-update-topic') && !args.contains('2026-07-28')
      ? await _ResponseFaultProxy.start(
          router.endpoint(route),
          'unused-json-target',
          null,
        )
      : null;
  try {
    await IOOverrides.runZoned(
      () => expectOwnedHttpClientsClosed(
        () => runRouterHostedClient([
          '--endpoint',
          (proxy?.endpoint ?? router.endpoint(route)).toString(),
          ...args,
        ]),
      ),
      stdout: () => output,
      stderr: () => errors,
    );
  } finally {
    await proxy?.close();
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
