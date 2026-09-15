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
          request.response.headers.contentType = ContentType.json;
          if (message.containsKey('state')) {
            expect(message['state'], 'fixture-auth-state');
            expect(message['signature'], 'fixture-ticket');
            request.response.write(
              jsonEncode({
                'access_token': 'fixture-access-token',
                'refresh_token': 'fixture-refresh-token',
                'token_type': 'Bearer',
                'realm': 'consumer.realm',
                'authmethod': 'ticket',
                'authid': 'consumer',
                'authrole': 'user',
                'authprovider': 'fixture',
                ...grantOverrides,
              }),
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
          expect(authorization, 'Bearer fixture-access-token');
        }
        final metadata = (message['params'] as Map)['_meta'] as Map;
        expect(metadata['io.modelcontextprotocol/protocolVersion'], _protocol);
        final result = _result(message);
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
  final authorizations = <String?>[];
  final failures = <(Object, StackTrace)>[];
  bool requireAuth = false;
  Map<String, Object?> grantOverrides = {};
  _Rewrite? rewrite;

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
}

Future<({List<Map<String, Object?>> lines, String err})> _run(
  _Peer peer,
  List<String> options,
) async {
  final output = _CapturedStdout();
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
    stdout: () => output,
    stderr: () => errors,
  );
  return (
    lines: const LineSplitter()
        .convert(output.text.toString())
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
