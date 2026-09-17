@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';
import 'package:test/test.dart';

const _protocol = '2026-07-28';
const _tool = {
  'name': 'echo',
  'inputSchema': {'type': 'object'},
};
const _resource = {'uri': 'app://notes/current', 'name': 'Current note'};
const _template = {'uriTemplate': 'app://notes/{id}', 'name': 'Note'};
const _prompt = {
  'name': 'inspect',
  'arguments': [
    {'name': 'locale'},
  ],
};

void main() {
  group('public router-hosted CLI over HTTP', () {
    late _Peer peer;
    setUp(() async => peer = await _Peer.start());
    tearDown(() => peer.close());

    test(
      'opaque hyphen-prefixed bearer reaches HTTP unchanged and stays out of output',
      () async {
        const token = '--valid-base64url-token_0123456789';
        final result = await _run(peer, ['--bearer-token', token]);
        expect(result.err, isEmpty);
        expect(peer.authorizations, isNotEmpty);
        expect(peer.authorizations, everyElement('Bearer $token'));
        expect(jsonEncode(result.lines), isNot(contains(token)));
      },
    );

    for (final discover in [false, true]) {
      test(
        'ticket grant ${discover ? 'discovered' : 'explicit'} stays bound to the MCP client',
        () async {
          peer.requireAuth = true;
          final result = await _run(peer, [
            '--realm',
            'consumer.realm',
            '--auth-id',
            'consumer',
            '--ticket',
            'fixture-ticket',
            if (!discover) ...[
              '--auth-url',
              'http://127.0.0.1:${peer.server.port}/auth',
            ],
          ]);
          expect(result.err, isEmpty);
          expect(peer.authRequests, [
            {
              'realm': 'consumer.realm',
              'authid': 'consumer',
              'authmethod': 'ticket',
            },
            {'state': 'fixture-auth-state', 'signature': 'fixture-ticket'},
          ]);
          expect(peer.authorizations, [
            if (discover) null,
            ...List.filled(4, 'Bearer fixture-access-token'),
          ]);
          if (discover) {
            expect(result.lines.first, {
              'auth': {
                'endpointDiscovery': true,
                'endpoint': 'http://127.0.0.1:${peer.server.port}/auth',
                'method': 'ticket',
              },
            });
          } else {
            expect(
              result.lines.any((line) => line.containsKey('auth')),
              isFalse,
            );
          }
          final transcript = jsonEncode(result.lines);
          for (final secret in [
            'fixture-ticket',
            'fixture-access-token',
            'fixture-refresh-token',
            'fixture-auth-state',
          ]) {
            expect(transcript, isNot(contains(secret)));
          }
        },
      );
    }

    for (final field in ['realm', 'authmethod', 'authid']) {
      test('a mismatched grant $field never reaches MCP', () async {
        peer.requireAuth = true;
        peer.grantOverrides = {field: 'wrong-identity'};
        await expectLater(
          _run(peer, [
            '--auth-url',
            'http://127.0.0.1:${peer.server.port}/auth',
            '--realm',
            'consumer.realm',
            '--auth-id',
            'consumer',
            '--ticket',
            'fixture-ticket',
          ]),
          throwsA(
            isA<ConnectanumHttpAuthProtocolException>().having(
              (e) => e.message,
              'message',
              'HTTP auth grant $field does not match the authentication request.',
            ),
          ),
        );
        expect(peer.authRequests.length, 2);
        expect(peer.requests, isEmpty);
      });
    }

    group('refresh and revocation lifecycle', () {
      late List<String> options;
      setUp(() {
        peer.requireAuth = true;
        options = [
          '--auth-url',
          'http://127.0.0.1:${peer.server.port}/auth',
          '--realm',
          'consumer.realm',
          '--auth-id',
          'consumer',
          '--ticket',
          'fixture-ticket',
          '--auth-lifecycle-smoke',
        ];
      });

      test('uses rotated credentials and verifies both revocations', () async {
        final result = await _run(peer, options);
        expect(result.err, isEmpty);
        expect(result.lines.last, {
          'authLifecycle': {
            'method': 'ticket',
            'issued': true,
            'refreshed': true,
            'refreshedDirectPing': true,
            'refreshedSessionless': true,
            'revokedAccessRejected': true,
            'revokedRefreshRejected': true,
          },
        });
        expect(peer.authRequests.skip(4), [
          {
            'grant_type': 'refresh_token',
            'refresh_token': 'fixture-refresh-token',
          },
          {
            'grant_type': 'revoke',
            'token': 'rotated-access-token',
            'token_type_hint': 'access_token',
          },
          {
            'grant_type': 'revoke',
            'token': 'rotated-refresh-token',
            'token_type_hint': 'refresh_token',
          },
          {
            'grant_type': 'refresh_token',
            'refresh_token': 'rotated-refresh-token',
          },
        ]);
        expect(peer.authTraces.skip(2), [
          'router-hosted-client-auth-lifecycle-issue',
          'router-hosted-client-auth-lifecycle-issue',
          'router-hosted-client-auth-lifecycle-refresh',
          'router-hosted-client-auth-lifecycle-revoke-access',
          'router-hosted-client-auth-lifecycle-revoke-refresh',
          'auth-lifecycle-refresh-revoked',
        ]);
        expect(peer.authorizations, [
          ...List.filled(4, 'Bearer fixture-access-token'),
          ...List.filled(2, 'Bearer rotated-access-token'),
        ]);
        expect(
          peer.requests.map((message) => message['id']).toList().sublist(4),
          [
            'auth-lifecycle-refreshed-direct-ping',
            'auth-lifecycle-revoked-direct-ping',
          ],
        );
        final transcript = jsonEncode(result.lines);
        for (final secret in [
          'fixture-ticket',
          'fixture-access-token',
          'fixture-refresh-token',
          'fixture-auth-state',
          'rotated-access-token',
          'rotated-refresh-token',
        ]) {
          expect(transcript, isNot(contains(secret)));
        }
      });

      for (final rotated in [false, true]) {
        for (final token in [null, '', '   ']) {
          test(
            'rejects unusable refresh token $token, rotated=$rotated',
            () async {
              if (rotated) {
                peer.refreshedGrantOverrides = {'refresh_token': token};
              } else {
                peer.lifecycleGrantOverrides = {'refresh_token': token};
              }
              final output = _CapturedStdout();
              await expectLater(
                _run(peer, options, output: output),
                throwsA(
                  isA<StateError>().having(
                    (error) => error.message,
                    'message',
                    rotated
                        ? 'Auth lifecycle smoke did not rotate a refresh token.'
                        : 'Auth lifecycle smoke did not receive a refresh token.',
                  ),
                ),
              );
              expect(peer.authRequests.length, rotated ? 5 : 4);
              expect(peer.requests.length, 4);
              expect(output.text.toString(), isNot(contains('authLifecycle')));
            },
          );
        }
      }

      for (final refresh in [false, true]) {
        for (final status in [200, 400, 403, 404, 500]) {
          test(
            'does not accept revoked ${refresh ? 'refresh' : 'access'} status $status',
            () async {
              if (refresh) {
                peer.revokedRefreshStatus = status;
              } else {
                peer.revokedAccessStatus = status;
              }
              final output = _CapturedStdout();
              await expectLater(
                _run(peer, options, output: output),
                throwsA(
                  isA<StateError>().having(
                    (error) => error.message,
                    'message',
                    status == 200
                        ? 'Auth lifecycle smoke accepted a revoked ${refresh ? 'refresh' : 'access'} token.'
                        : 'Auth lifecycle revoked ${refresh ? 'refresh' : 'access'} token returned $status, expected 401.',
                  ),
                ),
              );
              expect(peer.authRequests.length, refresh ? 8 : 6);
              expect(peer.requests.length, 6);
              expect(output.text.toString(), isNot(contains('authLifecycle')));
            },
          );
        }
      }

      for (final operation in [
        'refresh_token',
        'access_token',
        'refresh_revoke',
      ]) {
        test(
          'propagates $operation server failure before later effects',
          () async {
            if (operation == 'refresh_token') {
              peer.refreshStatus = 503;
            } else {
              peer.revokeStatuses[operation == 'access_token'
                      ? 'access_token'
                      : 'refresh_token'] =
                  503;
            }
            final output = _CapturedStdout();
            await expectLater(
              _run(peer, options, output: output),
              throwsA(
                isA<ConnectanumHttpAuthException>().having(
                  (error) => error.statusCode,
                  'status',
                  503,
                ),
              ),
            );
            expect(peer.authRequests.length, switch (operation) {
              'refresh_token' => 5,
              'access_token' => 6,
              _ => 7,
            });
            expect(peer.requests.length, switch (operation) {
              'refresh_token' => 4,
              'access_token' => 5,
              _ => 6,
            });
            expect(output.text.toString(), isNot(contains('authLifecycle')));
          },
        );
      }
    });

    for (final authenticated in [false, true]) {
      test(
        'stateless discovery and direct catalogs, bearer=$authenticated',
        () async {
          final result = await _run(peer, [
            if (authenticated) ...['--bearer-token', ' fixture-token '],
          ]);
          expect(result.err, isEmpty);
          expect(result.lines, [
            {
              'modernBatchUnsupported': {
                'protocolVersion': _protocol,
                'rejectedLocally': true,
                'sessionless': true,
              },
            },
            {'directPing': {}},
            {
              'directStandardTools': ['other'],
              'directStandardNextCursor': 'page-2',
              'directTools': ['other'],
              'nextCursor': 'page-2',
            },
            {
              'stateless': {
                'protocolVersion': _protocol,
                'sessionless': true,
                'supportedVersions': [_protocol],
                'capabilities': {'tools': {}, 'resources': {}, 'prompts': {}},
                'serverInfo': {'name': 'consumer-fixture', 'version': '1'},
                'ttlMs': 1000,
                'cacheScope': 'private',
              },
            },
          ]);
          expect(peer.requests.map((r) => r['method']), [
            'server/discover',
            'ping',
            'tools/list',
            'connectanum.tools.list',
          ]);
          expect(
            peer.authorizations,
            everyElement(authenticated ? 'Bearer fixture-token' : isNull),
          );
          expect(jsonEncode(result.lines), isNot(contains('fixture-token')));
        },
      );
    }

    test(
      'paginated tool, resource, template and prompt use advertised APIs',
      () async {
        final result = await _run(peer, [
          '--tool',
          'echo',
          '--tool-arguments',
          '{"text":"hello","values":[1,true,null]}',
          '--resource-uri',
          'app://notes/current',
          '--resource-template',
          'app://notes/{id}',
          '--resource-template-variables',
          '{"id":"a/b"}',
          '--prompt',
          'inspect',
          '--prompt-arguments',
          '{"locale":"de"}',
        ]);
        expect(result.err, isEmpty);
        final tool = result.lines.singleWhere(
          (line) => line.containsKey('directToolResult'),
        );
        for (final key in [
          'directToolResult',
          'directStandardToolResult',
          'directToolMethodResult',
        ]) {
          expect(tool[key], {
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
            'structuredContent': {
              'text': 'hello',
              'values': [1, true, null],
            },
          });
        }
        expect(tool['directStandardToolPagesRead'], 2);
        expect(tool['directToolPagesRead'], 2);
        expect(tool['directToolMethodPagesRead'], 2);
        final resource = result.lines.singleWhere(
          (line) => line.containsKey('directResourceContent'),
        );
        expect(resource['directResourcePagesRead'], 2);
        expect(resource['directResourceMethodPagesRead'], 2);
        expect(resource['directResourceContent'], [
          {'uri': 'app://notes/current', 'text': 'fixture note'},
        ]);
        final template = result.lines.singleWhere(
          (line) => line.containsKey('directResourceTemplateExpansion'),
        );
        expect(template['directResourceTemplateExpansion'], {
          'uriTemplate': 'app://notes/{id}',
          'variableNames': ['id'],
          'uri': 'app://notes/a%2Fb',
          'pagesRead': 2,
          'content': [
            {'uri': 'app://notes/a%2Fb', 'text': 'fixture note'},
          ],
        });
        final prompt = result.lines.singleWhere(
          (line) => line.containsKey('directPrompt'),
        );
        expect(prompt['directPromptPagesRead'], 2);
        expect(prompt['directPromptMethodPagesRead'], 2);
        expect(prompt['directPrompt'], {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'de'},
            },
          ],
        });
        expect(prompt['directPromptMethod'], prompt['directPrompt']);
        expect(
          peer.requests.where((r) => r['method'] == 'tools/call').length,
          1,
        );
        expect(
          peer.requests
              .where((r) => r['method'] == 'connectanum.tool.call')
              .length,
          2,
        );
        for (final request in peer.requests.where(
          (r) => ['tools/call', 'connectanum.tool.call'].contains(r['method']),
        )) {
          final params = request['params'] as Map;
          expect(params['name'], 'echo');
          expect(params['arguments'], {
            'text': 'hello',
            'values': [1, true, null],
          });
        }
        expect((result.lines.last['stateless'] as Map)['sessionless'], isTrue);
      },
    );

    test(
      'discovery cannot silently downgrade the requested protocol',
      () async {
        peer.rewrite = (request, result) =>
            request['method'] == 'server/discover'
            ? {
                ...result,
                'supportedVersions': ['2025-11-25'],
              }
            : result;
        await expectLater(
          _run(peer, []),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Stateless discovery did not advertise $_protocol.',
            ),
          ),
        );
        expect(peer.requests.map((r) => r['method']), ['server/discover']);
      },
    );

    for (final (option, value, catalogMethod, label) in [
      ('--tool', 'missing', 'tools/list', 'Direct standard tool'),
      ('--resource-uri', 'app://missing', 'resources/list', 'Direct resource'),
      (
        '--resource-template',
        'app://missing/fixed',
        'resources/templates/list',
        'Direct JSON resource template expansion',
      ),
      ('--prompt', 'missing', 'prompts/list', 'Direct prompt'),
    ]) {
      for (final cycle in [false, true]) {
        test(
          '$label rejects ${cycle ? 'cyclic' : 'exhausted'} catalogs',
          () async {
            peer.rewrite = (request, result) =>
                cycle && request['method'] == catalogMethod
                ? {...result, 'nextCursor': 'page-2'}
                : result;
            await expectLater(
              _run(peer, [option, value]),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  cycle
                      ? '$label repeated catalog cursor.'
                      : '$label did not advertise $value.',
                ),
              ),
            );
            expect(
              peer.requests.where((r) => r['method'] == catalogMethod).length,
              lessThanOrEqualTo(3),
            );
            expect(
              peer.requests.where(
                (r) => [
                  'tools/call',
                  'connectanum.tool.call',
                  'resources/read',
                  'prompts/get',
                ].contains(r['method']),
              ),
              isEmpty,
            );
          },
        );
      }
    }

    for (final (payload, message) in <(Map<String, Object?>, String)>[
      ({'tools': {}}, 'returned a non-list tools catalog.'),
      (
        {
          'tools': [null],
        },
        'returned a non-object catalog entry.',
      ),
      for (final cursor in [42, '', 'white space', 'bad\u0000cursor'])
        (
          {'tools': [], 'nextCursor': cursor},
          'returned an invalid next cursor.',
        ),
    ]) {
      test('raw method catalog rejects ${jsonEncode(payload)}', () async {
        peer.rewrite = (request, result) =>
            request['id'] == 'direct-tools-method-0' ? payload : result;
        await expectLater(
          _run(peer, ['--tool', 'echo']),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Direct tool method list $message',
            ),
          ),
        );
        expect(
          peer.requests.where((r) => r['method'] == 'connectanum.tool.call'),
          isEmpty,
        );
      });
    }

    for (final id in [
      'direct-tool-call',
      'direct-standard-tool-call',
      'direct-tool-call-method',
    ]) {
      test('tool error at $id aborts before later actions', () async {
        peer.rewrite = (request, result) => request['id'] == id
            ? {
                'isError': true,
                'content': [
                  {'type': 'text', 'text': 'fixture rejection'},
                ],
              }
            : result;
        await expectLater(
          _run(peer, [
            '--tool',
            'echo',
            '--resource-uri',
            'app://notes/current',
          ]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('returned an error:'),
            ),
          ),
        );
        expect(peer.requests.last['id'], id);
      });
    }

    group('WAMP pubsub integrity and cleanup', () {
      const event = {
        'text': 'hello',
        'values': [1, true, null],
        'nested': {'a': 2},
      };
      final options = [
        '--pubsub-topic',
        'app.events',
        '--pubsub-event',
        jsonEncode(event),
      ];

      test(
        'publishes, polls, notifies and releases its subscription',
        () async {
          final result = await _run(peer, options);
          expect(result.err, isEmpty);
          final transcript = result.lines.singleWhere(
            (line) => line.containsKey('pubsubTopic'),
          );
          expect(transcript['subscription'], {
            'handle': 'fixture-handle',
            'topic': 'app.events',
            'queueLimit': 10,
            'subscriptionId': 7,
          });
          for (final entry in {
            'events': event,
            'methodEvents': {'methodEvent': event},
            'notificationEvents': {'notificationEvent': event},
            'methodNotificationEvents': {'methodNotificationEvent': event},
          }.entries) {
            expect((transcript[entry.key] as List).single, {
              'subscriptionId': 7,
              'publicationId': 19,
              'argumentsKeywords': entry.value,
            });
          }
          expect(transcript['publication'], {
            'topic': 'app.events',
            'acknowledged': true,
            'publicationId': 19,
          });
          expect(transcript['dropped'], 0);
          expect(transcript['remaining'], 0);
          expect(
            peer.requests.where((request) => !request.containsKey('id')).length,
            2,
          );
          expect(peer.requests.last['id'], 'direct-pubsub-unsubscribe');
          expect(peer.subscriptionActive, isFalse);
        },
      );

      final faults = <(String, String, Object?, String)>[
        (
          'direct-pubsub-subscribe',
          'topic',
          'app.other',
          'returned subscription for',
        ),
        ('direct-pubsub-subscribe', 'queueLimit', 11, 'returned queue limit'),
        ('direct-pubsub-subscribe', 'queueLimit', null, 'returned queue limit'),
        (
          'direct-pubsub-publish',
          'topic',
          'app.other',
          'returned publication for',
        ),
        ('direct-pubsub-publish', 'acknowledged', false, 'did not acknowledge'),
        (
          'direct-pubsub-publish',
          'publicationId',
          null,
          'without a publication id',
        ),
        (
          'direct-pubsub-publish-method',
          'topic',
          'app.other',
          'returned topic',
        ),
        (
          'direct-pubsub-publish-method',
          'acknowledged',
          false,
          'did not acknowledge',
        ),
        (
          'direct-pubsub-publish-method',
          'publicationId',
          null,
          'without a publication id',
        ),
        for (final id in [
          'direct-pubsub-poll',
          'direct-pubsub-method-poll',
          'direct-pubsub-notification-poll',
          'direct-pubsub-method-notification-poll',
        ]) ...[
          (id, 'handle', 'wrong-handle', 'returned events for handle'),
          (id, 'topic', 'app.other', 'returned events for app.other'),
          (id, 'dropped', 1, 'dropped pub/sub events'),
          (id, 'remaining', 1, 'events queued after polling'),
          (id, 'events', [], 'Published event was not observed'),
          (
            id,
            'events',
            [
              {
                'subscriptionId': 7,
                'publicationId': 19,
                'argumentsKeywords': {'text': 'not the published event'},
              },
            ],
            'Published event was not observed',
          ),
        ],
      ];
      for (final (id, field, value, message) in faults) {
        test(
          'rejects $id $field=${jsonEncode(value)} and unsubscribes',
          () async {
            peer.rewrite = (request, result) => request['id'] == id
                ? {
                    ...result,
                    'structuredContent': {
                      ...result['structuredContent'] as Map,
                      field: value,
                    },
                  }
                : result;
            await expectLater(
              _run(peer, options),
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'diagnostic',
                  contains(message),
                ),
              ),
            );
            final faultIndex = peer.requests.indexWhere(
              (request) => request['id'] == id,
            );
            expect(faultIndex, isNonNegative);
            expect(
              peer.requests
                  .skip(faultIndex + 1)
                  .map((request) => request['id']),
              ['direct-pubsub-unsubscribe'],
              reason: 'Only cleanup may follow rejected pubsub metadata',
            );
            expect(peer.subscriptionActive, isFalse);
          },
        );
      }
    });

    group('WAMP metadata integrity', () {
      const options = [
        '--wamp-procedure',
        'app.echo',
        '--wamp-topic',
        'app.events',
      ];

      void rejects(
        String name,
        String id,
        Map<String, Object?> structuredContent,
        String message,
      ) {
        test(name, () async {
          peer.rewrite = (request, result) => request['id'] == id
              ? {...result, 'structuredContent': structuredContent}
              : result;
          await expectLater(
            _run(peer, options),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'metadata diagnostic',
                contains(message),
              ),
            ),
          );
          expect(
            peer.requests.last['id'],
            id,
            reason: 'Rejected metadata must stop subsequent network actions',
          );
        });
      }

      for (final detailField in ['id', 'session']) {
        for (final integralDouble in [false, true]) {
          test(
            'accepts $detailField and integralDouble=$integralDouble',
            () async {
              peer.rewrite = (request, result) {
                final name = (request['params'] as Map)['name'];
                if (name is! String || !name.startsWith('wamp.')) return result;
                final content = Map<String, Object?>.from(
                  result['structuredContent'] as Map,
                );
                if (name == 'wamp.session.get') {
                  content['argumentsKeywords'] = {
                    'details': {detailField: integralDouble ? 101.0 : 101},
                  };
                }
                if (integralDouble) {
                  if (name == 'wamp.session.count') {
                    content['argumentsKeywords'] = {'count': 1.0};
                  }
                  if (name == 'wamp.session.list') {
                    content['argumentsKeywords'] = {
                      'session_ids': [101.0],
                    };
                  }
                  if (content['arguments'] case final List arguments) {
                    content['arguments'] = [
                      for (final value in arguments) (value as num).toDouble(),
                    ];
                  }
                }
                return {...result, 'structuredContent': content};
              };
              final result = await _run(peer, options);
              expect(result.err, isEmpty);
              final metadata =
                  result.lines.singleWhere(
                        (line) => line.containsKey('directWampMetadata'),
                      )['directWampMetadata']
                      as Map;
              expect(
                (metadata['sessionMetadata'] as Map)['selectedSessionId'],
                101,
              );
              final registration =
                  (metadata['procedure']
                          as Map)['configuredRegistrationMetadata']
                      as Map;
              final subscription =
                  (metadata['topic'] as Map)['configuredSubscriptionMetadata']
                      as Map;
              expect(registration['registrationId'], 11);
              expect(subscription['subscriptionId'], 7);
              expect((registration['callees'] as Map)['arguments'], isEmpty);
              expect(
                (subscription['subscribers'] as Map)['arguments'],
                isEmpty,
              );
              expect((registration['calleeCount'] as Map)['arguments'], [0]);
              expect((subscription['subscriberCount'] as Map)['arguments'], [
                0,
              ]);
              expect(
                (result.lines.last['stateless'] as Map)['sessionless'],
                isTrue,
              );
            },
          );
        }
      }

      for (final count in [null, false, '1', 0, -1, 1.5]) {
        rejects(
          'rejects session count ${jsonEncode(count)}',
          'direct-wamp-session-count',
          {
            'argumentsKeywords': {'count': count},
          },
          'invalid session count',
        );
      }
      for (final ids in [null, {}, '101']) {
        rejects(
          'rejects non-list session ids ${jsonEncode(ids)}',
          'direct-wamp-session-list',
          {
            'argumentsKeywords': {'session_ids': ids},
          },
          'was not a list of integer ids',
        );
      }
      for (final id in [null, true, '101', 101.5]) {
        rejects(
          'rejects non-integer session id ${jsonEncode(id)}',
          'direct-wamp-session-list',
          {
            'argumentsKeywords': {
              'session_ids': [id],
            },
          },
          'contained a non-integer id',
        );
      }
      rejects('rejects empty session list', 'direct-wamp-session-list', {
        'argumentsKeywords': {'session_ids': []},
      }, 'returned no session ids');
      rejects(
        'rejects count smaller than session list',
        'direct-wamp-session-list',
        {
          'argumentsKeywords': {
            'session_ids': [101, 102],
          },
        },
        'was smaller than listed sessions',
      );
      for (final details in [null, [], '101']) {
        rejects(
          'rejects non-map session details ${jsonEncode(details)}',
          'direct-wamp-session-get',
          {
            'argumentsKeywords': {'details': details},
          },
          'returned no details map',
        );
      }
      for (final details in [
        {},
        {'id': 102},
        {'session': 102},
        {'id': 101.5},
        {'id': '101'},
        {'id': 102, 'session': 101},
      ]) {
        rejects(
          'rejects mismatched session details ${jsonEncode(details)}',
          'direct-wamp-session-get',
          {
            'argumentsKeywords': {'details': details},
          },
          'expected 101',
        );
      }

      for (final kind in ['registration', 'subscription']) {
        final prefix = 'direct-wamp-configured-$kind';
        final members = kind == 'registration' ? 'callees' : 'subscribers';
        final count = kind == 'registration' ? 'callee' : 'subscriber';
        rejects('$kind lookup rejects missing entity', '$prefix-lookup', {
          'arguments': [],
        }, 'returned no $kind id');
        for (final value in ['11', null, 11.5]) {
          rejects(
            '$kind lookup rejects ${jsonEncode(value)}',
            '$prefix-lookup',
            {
              'arguments': [value],
            },
            'contained a non-integer id',
          );
        }
        for (final ids in [
          [],
          [999],
        ]) {
          rejects('$kind match rejects ${jsonEncode(ids)}', '$prefix-match', {
            'arguments': ids,
          }, 'match did not include lookup id');
          rejects('$kind list rejects ${jsonEncode(ids)}', '$prefix-list', {
            'argumentsKeywords': {'exact': ids},
          }, 'list did not include lookup id');
        }
        rejects('$kind list rejects non-list exact ids', '$prefix-list', {
          'argumentsKeywords': {'exact': {}},
        }, 'was not a list of integer ids');
        rejects('$kind list rejects non-integer exact id', '$prefix-list', {
          'argumentsKeywords': {
            'exact': ['11'],
          },
        }, 'contained a non-integer id');
        for (final uri in [null, 'app.other']) {
          rejects(
            '$kind details reject uri ${jsonEncode(uri)}',
            '$prefix-get',
            {
              'argumentsKeywords': {'uri': uri},
            },
            'details returned',
          );
        }
        rejects('$kind rejects live members', '$prefix-$members', {
          'arguments': [101],
        }, 'exposed live $members');
        rejects('$kind rejects malformed members', '$prefix-$members', {
          'arguments': ['101'],
        }, 'contained a non-integer id');
        for (final values in [
          [],
          [0, 0],
        ]) {
          rejects(
            '$kind rejects count arity ${jsonEncode(values)}',
            '$prefix-$count-count',
            {'arguments': values},
            'expected one integer value',
          );
        }
        for (final value in [1, -1]) {
          rejects(
            '$kind rejects nonzero count $value',
            '$prefix-$count-count',
            {
              'arguments': [value],
            },
            'expected 0',
          );
        }
        for (final value in ['0', 0.5, null]) {
          rejects(
            '$kind rejects count ${jsonEncode(value)}',
            '$prefix-$count-count',
            {
              'arguments': [value],
            },
            'contained a non-integer id',
          );
        }
      }
    });
  });
}

typedef _Rewrite =
    Map<String, Object?> Function(Map<String, Object?>, Map<String, Object?>);

class _Peer {
  _Peer(this.server) {
    server.listen((request) async {
      try {
        expect(request.method, 'POST');
        expect(request.headers.value('Mcp-Session-Id'), isNull);
        expect(request.headers.value('Last-Event-ID'), isNull);
        final message =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, Object?>();
        if (request.uri.path == '/auth') {
          expect(requireAuth, isTrue);
          expect(request.headers.value('Authorization'), isNull);
          authRequests.add(message);
          final trace = request.headers.value('x-consumer-trace');
          authTraces.add(trace);
          request.response.headers.contentType = ContentType.json;
          if (message['grant_type'] == 'refresh_token') {
            expect(
              message['refresh_token'],
              _refreshRevoked
                  ? 'rotated-refresh-token'
                  : 'fixture-refresh-token',
            );
            request.response.statusCode = _refreshRevoked
                ? revokedRefreshStatus
                : refreshStatus;
            request.response.write(
              jsonEncode(
                request.response.statusCode == 200
                    ? _grant(refreshed: true)
                    : {'error': 'invalid_grant'},
              ),
            );
            return;
          }
          if (message['grant_type'] == 'revoke') {
            final hint = message['token_type_hint'];
            expect(hint, anyOf('access_token', 'refresh_token'));
            expect(
              message['token'],
              hint == 'access_token'
                  ? 'rotated-access-token'
                  : 'rotated-refresh-token',
            );
            request.response.statusCode = revokeStatuses[hint] ?? 200;
            if (request.response.statusCode == 200) {
              if (hint == 'access_token') {
                _accessRevoked = true;
              } else {
                _refreshRevoked = true;
              }
            }
            request.response.write(
              jsonEncode(
                request.response.statusCode == 200
                    ? <String, Object?>{}
                    : {'error': 'unavailable'},
              ),
            );
            return;
          }
          if (message.containsKey('state')) {
            expect(message['state'], 'fixture-auth-state');
            expect(message['signature'], 'fixture-ticket');
            request.response.write(
              jsonEncode(
                _grant(
                  lifecycle:
                      trace == 'router-hosted-client-auth-lifecycle-issue',
                ),
              ),
            );
          } else {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.write(
              jsonEncode({
                'realm': 'consumer.realm',
                'authmethod': 'ticket',
                'state': 'fixture-auth-state',
                'challenge': {},
              }),
            );
          }
          return;
        }
        expect(request.uri.path, '/mcp');
        final authorization = request.headers.value('Authorization');
        authorizations.add(authorization);
        requests.add(message);
        if (requireAuth && authorization == null) {
          expect(message['id'], 'http-auth-discovery');
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.set(
            'WWW-Authenticate',
            'Bearer realm="consumer.realm", auth_path="/auth"',
          );
          return;
        }
        if (requireAuth) {
          expect(
            authorization,
            anyOf('Bearer fixture-access-token', 'Bearer rotated-access-token'),
          );
          if (_accessRevoked &&
              authorization == 'Bearer rotated-access-token' &&
              revokedAccessStatus != 200) {
            request.response.statusCode = revokedAccessStatus;
            return;
          }
        }
        final metadata = (message['params'] as Map)['_meta'] as Map;
        expect(metadata['io.modelcontextprotocol/protocolVersion'], _protocol);
        final result = _result(message);
        if (!message.containsKey('id')) {
          request.response.statusCode = HttpStatus.accepted;
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': rewrite?.call(message, result) ?? result,
          }),
        );
      } catch (error, stack) {
        failures.add((error, stack));
        request.response.statusCode = 500;
      } finally {
        await request.response.close();
      }
    });
  }

  final HttpServer server;
  final requests = <Map<String, Object?>>[];
  final authRequests = <Map<String, Object?>>[];
  final authTraces = <String?>[];
  final authorizations = <String?>[];
  final failures = <(Object, StackTrace)>[];
  bool requireAuth = false;
  Map<String, Object?> grantOverrides = {};
  Map<String, Object?> lifecycleGrantOverrides = {};
  Map<String, Object?> refreshedGrantOverrides = {};
  final revokeStatuses = <Object?, int>{};
  int refreshStatus = 200;
  int revokedAccessStatus = 401;
  int revokedRefreshStatus = 401;
  bool _accessRevoked = false;
  bool _refreshRevoked = false;
  _Rewrite? rewrite;
  bool subscriptionActive = false;
  final _events = <Map<String, Object?>>[];

  Map<String, Object?> _grant({
    bool lifecycle = false,
    bool refreshed = false,
  }) => {
    'access_token': refreshed ? 'rotated-access-token' : 'fixture-access-token',
    'refresh_token': refreshed
        ? 'rotated-refresh-token'
        : 'fixture-refresh-token',
    'token_type': 'Bearer',
    'realm': 'consumer.realm',
    'authmethod': 'ticket',
    'authid': 'consumer',
    'authrole': 'user',
    'authprovider': 'fixture',
    ...grantOverrides,
    if (lifecycle) ...lifecycleGrantOverrides,
    if (refreshed) ...refreshedGrantOverrides,
  };

  static Future<_Peer> start() async =>
      _Peer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> close() async {
    await server.close(force: true);
    expect(
      failures,
      isEmpty,
      reason: 'Fixture must not hide server-side assertion failures',
    );
  }

  Map<String, Object?> _result(Map<String, Object?> request) {
    final params = request['params'] as Map;
    final toolName = params['name'];
    if (request['method'] == 'connectanum.tool.call' &&
        toolName is String &&
        toolName.startsWith('connectanum.pubsub.')) {
      return _pubsubResult(toolName, params['arguments'] as Map);
    }
    if ((request['method'] as String).startsWith('connectanum.pubsub.')) {
      return _pubsubResult(request['method'] as String, params);
    }
    if (request['method'] == 'connectanum.tool.call' &&
        toolName is String &&
        (toolName.startsWith('wamp.') ||
            toolName.startsWith('connectanum.api.'))) {
      return _metadataResult(toolName, params['arguments'] as Map);
    }
    if (request['method'] == 'connectanum.api.list' ||
        request['method'] == 'connectanum.api.describe') {
      return _metadataResult(request['method'] as String, params);
    }
    final secondPage = params['cursor'] == 'page-2';
    Map<String, Object?> catalog(
      String key,
      Map<String, Object?> entry,
      Map<String, Object?> other,
    ) => {
      key: [secondPage ? entry : other],
      if (!secondPage) 'nextCursor': 'page-2',
    };
    switch (request['method']) {
      case 'server/discover':
        return {
          'supportedVersions': [_protocol],
          'capabilities': {'tools': {}, 'resources': {}, 'prompts': {}},
          '_meta': {
            'io.modelcontextprotocol/serverInfo': {
              'name': 'consumer-fixture',
              'version': '1',
            },
          },
          'ttlMs': 1000,
          'cacheScope': 'private',
        };
      case 'ping':
        return {};
      case 'tools/list':
      case 'connectanum.tools.list':
        return catalog('tools', _tool, {
          'name': 'other',
          'inputSchema': {'type': 'object'},
        });
      case 'tools/call':
      case 'connectanum.tool.call':
        return {
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
          'structuredContent': params['arguments'],
        };
      case 'resources/list':
        return catalog('resources', _resource, {
          'uri': 'app://other',
          'name': 'Other',
        });
      case 'resources/templates/list':
        return catalog('resourceTemplates', _template, {
          'uriTemplate': 'app://other/{id}',
          'name': 'Other',
        });
      case 'resources/read':
        return {
          'contents': [
            {'uri': params['uri'], 'text': 'fixture note'},
          ],
        };
      case 'prompts/list':
        return catalog('prompts', _prompt, {'name': 'other'});
      case 'prompts/get':
        return {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': (params['arguments'] as Map)['locale'],
              },
            },
          ],
        };
      default:
        fail('Unexpected method: ${request['method']}');
    }
  }

  Map<String, Object?> _pubsubResult(String name, Map arguments) {
    final operation = name.split('.').last;
    if (operation == 'subscribe' || operation == 'publish') {
      expect(arguments['topic'], 'app.events');
    } else {
      expect(arguments['handle'], 'fixture-handle');
    }
    final content = <String, Object?>{'topic': 'app.events'};
    switch (operation) {
      case 'subscribe':
        expect(subscriptionActive, isFalse);
        expect(arguments['queueLimit'], 10);
        subscriptionActive = true;
        content.addAll({
          'handle': 'fixture-handle',
          'queueLimit': 10,
          'subscriptionId': 7,
        });
      case 'publish':
        expect(subscriptionActive, isTrue);
        _events.add({
          'subscriptionId': 7,
          'publicationId': 19,
          'argumentsKeywords': arguments['argumentsKeywords'],
        });
        content.addAll({'acknowledged': true, 'publicationId': 19});
      case 'poll':
        expect(subscriptionActive, isTrue);
        expect(arguments['limit'], 10);
        content.addAll({
          'handle': 'fixture-handle',
          'events': List.of(_events),
          'dropped': 0,
          'remaining': 0,
        });
        _events.clear();
      case 'unsubscribe':
        expect(subscriptionActive, isTrue);
        subscriptionActive = false;
        content.addAll({'handle': 'fixture-handle', 'unsubscribed': true});
      default:
        fail('Unexpected pubsub method: $name');
    }
    return {'content': <Object?>[], 'structuredContent': content};
  }

  Map<String, Object?> _metadataResult(String name, Map arguments) {
    Map<String, Object?> toolResult(Map<String, Object?> content) => {
      'content': <Object?>[],
      'structuredContent': content,
    };
    if (name.startsWith('connectanum.api.')) {
      final kind = arguments['kind'];
      expect(kind, isIn(['procedure', 'topic']));
      final uri = kind == 'procedure' ? 'app.echo' : 'app.events';
      if (name == 'connectanum.api.describe') {
        expect(arguments['uri'], uri);
        return toolResult({'uri': uri});
      }
      return toolResult({
        kind == 'procedure' ? 'procedures' : 'topics': [
          {'uri': uri},
        ],
      });
    }
    if (name == 'wamp.session.count') {
      return toolResult({
        'argumentsKeywords': {'count': 1},
      });
    }
    if (name == 'wamp.session.list') {
      return toolResult({
        'argumentsKeywords': {
          'session_ids': [101],
        },
      });
    }
    if (name == 'wamp.session.get') {
      expect(arguments['arguments'], [101]);
      return toolResult({
        'argumentsKeywords': {
          'details': {'id': 101},
        },
      });
    }
    final registration = name.startsWith('wamp.registration.');
    expect(
      name,
      startsWith(registration ? 'wamp.registration.' : 'wamp.subscription.'),
    );
    final id = registration ? 11 : 7;
    final uri = registration ? 'app.echo' : 'app.events';
    final operation = name.split('.').last;
    if (operation == 'lookup' || operation == 'match') {
      expect(arguments['arguments'], [uri]);
      if (operation == 'lookup') {
        expect(arguments['argumentsKeywords'], {'match': 'exact'});
      }
      return toolResult({
        'arguments': [id],
      });
    }
    if (operation == 'list') {
      return toolResult({
        'argumentsKeywords': {
          'exact': [id],
        },
      });
    }
    expect(arguments['arguments'], [id]);
    return toolResult(switch (operation) {
      'get' => {
        'argumentsKeywords': {'uri': uri},
      },
      'list_callees' || 'list_subscribers' => {'arguments': []},
      'count_callees' || 'count_subscribers' => {
        'arguments': [0],
      },
      _ => throw StateError('Unexpected fixture meta procedure: $name'),
    });
  }
}

Future<({List<Map<String, Object?>> lines, String err})> _run(
  _Peer peer,
  List<String> options, {
  _CapturedStdout? output,
}) async {
  final capturedOutput = output ?? _CapturedStdout();
  final errors = _CapturedStdout();
  // Only the option suite owns process-wide exitCode. HTTP tests use valid
  // arguments and assert the completed transcript or the specific exception.
  await IOOverrides.runZoned(
    () => runRouterHostedClient([
      '--endpoint',
      'http://127.0.0.1:${peer.server.port}/mcp',
      '--protocol-version',
      _protocol,
      ...options,
    ]),
    stdout: () => capturedOutput,
    stderr: () => errors,
  );
  return (
    lines: const LineSplitter()
        .convert(capturedOutput.text.toString())
        .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
        .toList(),
    err: errors.text.toString(),
  );
}

class _CapturedStdout implements Stdout {
  final text = StringBuffer();

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
