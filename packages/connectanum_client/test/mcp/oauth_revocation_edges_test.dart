@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _access = 'fixture-access';
const _refresh = 'fixture-refresh';
const _secret = 'fixture-client-secret';

McpOAuthTokenGrant _grant(
  Uri issuer, {
  bool endpoint = true,
  bool refresh = true,
  String clientId = 'consumer',
  List<String> grants = const ['authorization_code', 'refresh_token'],
}) => McpOAuthTokenGrant.fromJson({
  'type': 'mcp_oauth_token_grant',
  'version': 1,
  'issued_at': '2020-01-01T00:00:00.000Z',
  'authorization_server': {
    'issuer': issuer.toString(),
    'authorization_endpoint': issuer.resolve('/authorize').toString(),
    'token_endpoint': issuer.resolve('/token').toString(),
    if (endpoint) 'revocation_endpoint': issuer.resolve('/revoke').toString(),
    'response_types_supported': ['code'],
    'grant_types_supported': grants,
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': [
      'none',
      'client_secret_basic',
      'client_secret_post',
    ],
    'revocation_endpoint_auth_methods_supported': [
      'none',
      'client_secret_basic',
      'client_secret_post',
    ],
  },
  'resource': 'https://resource.example/mcp',
  'client_id': clientId,
  'scopes': ['read'],
  'tokens': {
    'access_token': _access,
    'token_type': 'Bearer',
    if (refresh) 'refresh_token': _refresh,
  },
}, now: DateTime.utc(2020));

McpOAuthClientAuthentication _authentication(
  McpOAuthTokenGrant grant,
  String method,
) => switch (method) {
  'client_secret_basic' => McpOAuthClientAuthentication.clientSecretBasic(
    clientId: 'consumer',
    clientSecret: _secret,
    authorizationServer: grant.authorizationServer,
  ),
  'client_secret_post' => McpOAuthClientAuthentication.clientSecretPost(
    clientId: 'consumer',
    clientSecret: _secret,
    authorizationServer: grant.authorizationServer,
  ),
  _ => McpOAuthClientAuthentication.registeredPublic(
    clientId: 'consumer',
    authorizationServer: grant.authorizationServer,
  ),
};

Future<void> _withServer(
  Future<void> Function(HttpRequest request) respond,
  Future<void> Function(Uri issuer, List<String> paths) action,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final issuer = Uri.parse('http://127.0.0.1:${server.port}');
  final paths = <String>[];
  server.listen((request) async {
    paths.add(request.uri.path);
    await respond(request);
    await request.response.close();
  });
  try {
    await action(issuer, paths);
  } finally {
    await server.close(force: true);
  }
}

Future<void> _revocationCompletes(Future<void> operation) async {
  McpOAuthTokenException? rejection;
  try {
    await operation;
  } on McpOAuthTokenException catch (error) {
    if (error.message.contains('request timed out')) rethrow;
    rejection = error;
  }
  expect(
    rejection == null,
    isTrue,
    reason: 'A successful revocation must be accepted.',
  );
}

void main() {
  test('restoration uses the supplied clock before accepting issued_at', () {
    final state = _grant(Uri.parse('https://issuer.example')).toJson();
    expect(
      () => McpOAuthTokenGrant.fromJson(state, now: DateTime.utc(2019)),
      throwsA(
        isA<McpOAuthTokenGrantStateException>().having(
          (error) => error.message,
          'future grant rejection',
          'Persisted OAuth token grant is not yet valid.',
        ),
      ),
    );
  });
  for (final (expiry, message) in <(Map<String, Object?>, String)>[
    (
      {'expires_at': '2020-01-01T00:01:00.000Z'},
      'Persisted OAuth token grant expiry is inconsistent.',
    ),
    (
      {'expires_in': 60},
      'Persisted OAuth token grant expiry is incomplete.',
    ),
    (
      {'expires_in': 60, 'expires_at': '2020-01-01T00:01:01.000Z'},
      'Persisted OAuth token grant expiry is inconsistent.',
    ),
  ]) {
    test('restoration rejects inconsistent expiry $expiry', () {
      final state = <String, Object?>{
        ..._grant(Uri.parse('https://issuer.example')).toJson(),
        ...expiry,
      };
      expect(
        () => McpOAuthTokenGrant.fromJson(state, now: DateTime.utc(2020)),
        throwsA(
          isA<McpOAuthTokenGrantStateException>().having(
            (error) => error.message,
            'expiry validation',
            message,
          ),
        ),
      );
    });
  }
  for (final refreshable in [false, true]) {
    test(
      'grant diagnostics report refreshable=$refreshable without secrets',
      () {
        final grant = _grant(
          Uri.parse('https://issuer.example'),
          refresh: refreshable,
        );
        expect(
          grant.toString(),
          'McpOAuthTokenGrant(Bearer, scopes: 1, refreshable: $refreshable)',
        );
      },
    );
  }
  for (final includeError in [false, true]) {
    for (final includeStatus in [false, true]) {
      for (final includeEndpoint in [false, true]) {
        test(
          'error diagnostics select fields $includeError/$includeStatus/'
          '$includeEndpoint without descriptions or credentials',
          () {
            final error = McpOAuthTokenException(
              'Request rejected.',
              oauthError: includeError ? 'invalid_client' : null,
              statusCode: includeStatus ? 401 : null,
              endpoint: includeEndpoint
                  ? Uri.parse('https://issuer.example/token')
                  : null,
              errorDescription: _secret,
              errorUri: Uri.parse('https://issuer.example/help'),
            );
            expect(
              error.toString,
              returnsNormally,
              reason: 'Diagnostics must render with absent optional fields.',
            );
            expect(
              error.toString(),
              'McpOAuthTokenException: Request rejected.'
              '${includeError ? ' (error: invalid_client)' : ''}'
              '${includeStatus ? ' (status: 401)' : ''}'
              '${includeEndpoint ? ' (https://issuer.example/token)' : ''}',
            );
          },
        );
      }
    }
  }
  for (final problem in [
    'client-id',
    'secret',
    'timeout',
    'limit',
    'header',
    'empty-scopes',
    'invalid-scope',
    'missing-refresh',
  ]) {
    test('request validation rejects $problem before network I/O', () async {
      final expectedMessage = switch (problem) {
        'client-id' => 'OAuth client ID must be non-empty printable text.',
        'secret' =>
          'OAuth client secret must be non-empty and contain no controls.',
        'timeout' => 'OAuth token endpoint timeout must be positive.',
        'limit' => 'OAuth token endpoint response byte limit must be positive.',
        'header' => 'Header "x-custom" contains control characters.',
        'empty-scopes' =>
          'OAuth refresh scopes must not be empty when provided.',
        'invalid-scope' => 'OAuth refresh scope contains an invalid token.',
        _ => 'OAuth grant does not contain a usable refresh token.',
      };
      var opened = 0;
      await _withServer((request) => request.drain<void>(), (
        issuer,
        paths,
      ) async {
        final grant = _grant(
          issuer,
          clientId: problem == 'client-id' ? 'consumer\n' : 'consumer',
          refresh: problem != 'missing-refresh',
        );
        final authentication = problem == 'secret'
            ? McpOAuthClientAuthentication.clientSecretPost(
                clientId: grant.clientId,
                clientSecret: '',
                authorizationServer: grant.authorizationServer,
              )
            : McpOAuthClientAuthentication.registeredPublic(
                clientId: grant.clientId,
                authorizationServer: grant.authorizationServer,
              );
        await expectLater(
          refreshMcpOAuthToken(
            grant,
            clientAuthentication: authentication,
            scopes: problem == 'empty-scopes'
                ? []
                : problem == 'invalid-scope'
                ? ['read\t']
                : null,
            timeout: problem == 'timeout'
                ? Duration.zero
                : const Duration(seconds: 2),
            maxResponseBytes: problem == 'limit' ? 0 : 4096,
            headers: problem == 'header' ? {'x-custom': 'bad\r\nvalue'} : {},
            onRequestOpened: (_) => opened++,
          ),
          throwsA(
            isA<McpOAuthTokenException>()
                .having(
                  (error) => error.message,
                  'preflight rejection',
                  expectedMessage,
                )
                .having(
                  (error) => error.endpoint,
                  'endpoint',
                  issuer.resolve('/token'),
                )
                .having(
                  (error) => error.statusCode,
                  'no HTTP response',
                  isNull,
                ),
          ),
        );
        expect(
          opened,
          0,
          reason: 'Validation precedes the request owner callback.',
        );
        expect(paths, isEmpty);
      });
    });
  }
  for (final invalid in <Map<String, Object?>>[
    {'refresh_token': 1},
    {'refresh_token': ''},
    {'scope': 1},
    {'scope': ''},
    {'expires_in': 8640000000001},
  ]) {
    test('refresh rejects invalid response fields $invalid', () async {
      await _withServer(
        (request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'access_token': 'renewed',
              'token_type': 'Bearer',
              ...invalid,
            }),
          );
        },
        (issuer, paths) async {
          final grant = _grant(issuer);
          await expectLater(
            refreshMcpOAuthToken(
              grant,
              clientAuthentication: _authentication(grant, 'none'),
            ),
            throwsA(
              isA<McpOAuthTokenException>().having(
                (error) => error.statusCode,
                'HTTP status',
                200,
              ),
            ),
          );
          expect(paths, ['/token']);
        },
      );
    });
  }
  for (final invalid in <Map<String, Object?>>[
    {'error_description': true},
    {'error_description': 'bad\ntext'},
    {'error_uri': 1},
  ]) {
    test('revocation rejects malformed error metadata $invalid', () async {
      await _withServer(
        (request) async {
          await request.drain<void>();
          request.response.statusCode = 400;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'error': 'invalid_client', ...invalid}),
          );
        },
        (issuer, paths) async {
          final grant = _grant(issuer);
          await expectLater(
            revokeMcpOAuthToken(
              grant,
              clientAuthentication: _authentication(grant, 'none'),
            ),
            throwsA(
              isA<McpOAuthTokenException>().having(
                (error) => error.statusCode,
                'HTTP status',
                400,
              ),
            ),
          );
          expect(paths, ['/revoke']);
        },
      );
    });
  }
  test(
    'refresh client_secret_post sends credentials and requested scopes exactly',
    () async {
      Map<String, String>? form;
      String? clientHeader;
      var opened = 0;
      await _withServer(
        (request) async {
          clientHeader = request.headers.value('x-consumer');
          form = Uri.splitQueryString(await utf8.decoder.bind(request).join());
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"access_token":"renewed","token_type":"Bearer"}',
          );
        },
        (issuer, paths) async {
          final grant = _grant(issuer);
          McpOAuthTokenGrant? updated;
          await _revocationCompletes(
            refreshMcpOAuthToken(
              grant,
              clientAuthentication: _authentication(
                grant,
                'client_secret_post',
              ),
              scopes: ['read'],
              headers: {'x-consumer': 'consumer agent'},
              onRequestOpened: (_) => opened++,
            ).then((value) {
              updated = value;
            }),
          );
          expect(paths, ['/token']);
          expect(opened, 1);
          expect(clientHeader, 'consumer agent');
          expect(form, {
            'grant_type': 'refresh_token',
            'refresh_token': _refresh,
            'client_id': 'consumer',
            'client_secret': _secret,
            'resource': 'https://resource.example/mcp',
            'scope': 'read',
          });
          expect(updated!.accessToken, 'renewed');
          expect(updated!.refreshToken, _refresh);
          expect(updated!.scopes, ['read']);
          expect(grant.accessToken, _access);
        },
      );
    },
  );
  test(
    'revocation exposes a safe loopback error URI without credential text',
    () async {
      await _withServer(
        (request) async {
          await request.drain<void>();
          request.response.statusCode = 400;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"error":"invalid_client","error_uri":"http://localhost/help"}',
          );
        },
        (issuer, paths) async {
          final grant = _grant(issuer);
          await expectLater(
            revokeMcpOAuthToken(
              grant,
              clientAuthentication: _authentication(grant, 'none'),
            ),
            throwsA(
              isA<McpOAuthTokenException>().having(
                (error) => error.errorUri,
                'safe error URI',
                Uri.parse('http://localhost/help'),
              ),
            ),
          );
          expect(paths, ['/revoke']);
        },
      );
    },
  );
  test(
    'success observer preserves transport, deadline and unrelated errors',
    () async {
      for (final error in <Object>[
        TimeoutException('deadline'),
        const McpOAuthTokenException(
          'OAuth revocation endpoint request timed out.',
        ),
        const SocketException('transport failed'),
        StateError('unrelated error'),
      ]) {
        await expectLater(
          _revocationCompletes(Future<void>.error(error)),
          throwsA(same(error)),
        );
      }
    },
  );
  test(
    'success observer asserts typed rejections but permits successful void results',
    () async {
      await _revocationCompletes(Future<void>.value());
      await expectLater(
        _revocationCompletes(
          Future<void>.error(
            const McpOAuthTokenException('unexpected rejection'),
          ),
        ),
        throwsA(isA<TestFailure>()),
      );
    },
  );
  for (final method in ['none', 'client_secret_basic', 'client_secret_post']) {
    for (final kind in McpOAuthTokenKind.values) {
      test(
        '$method revokes $kind with an exact form and preserves the grant',
        () async {
          Map<String, String>? form;
          String? authorization;
          await _withServer(
            (request) async {
              form = Uri.splitQueryString(
                await utf8.decoder.bind(request).join(),
              );
              authorization = request.headers.value(
                HttpHeaders.authorizationHeader,
              );
              expect(request.method, 'POST');
              expect(
                request.headers.contentType?.mimeType,
                'application/x-www-form-urlencoded',
              );
              request.response.statusCode = 200;
              request.response.add([
                255,
              ]); // RFC7009 success bodies are ignored.
            },
            (issuer, paths) async {
              final grant = _grant(issuer);
              final before = grant.toJson();
              await _revocationCompletes(
                revokeMcpOAuthToken(
                  grant,
                  clientAuthentication: _authentication(grant, method),
                  tokenKind: kind,
                ),
              );
              expect(paths, ['/revoke']);
              expect(form, {
                'token': kind == McpOAuthTokenKind.accessToken
                    ? _access
                    : _refresh,
                'token_type_hint': kind == McpOAuthTokenKind.accessToken
                    ? 'access_token'
                    : 'refresh_token',
                if (method != 'client_secret_basic') 'client_id': 'consumer',
                if (method == 'client_secret_post') 'client_secret': _secret,
              });
              expect(
                authorization,
                method == 'client_secret_basic'
                    ? 'Basic ${base64Encode(utf8.encode('consumer:$_secret'))}'
                    : null,
              );
              expect(grant.toJson(), before);
            },
          );
        },
      );
    }
  }
  final errors = <(int, String, List<int>, String?)>[
    (503, 'text/plain', utf8.encode('not-json'), null),
    (400, 'application/json', [255], null),
    (400, 'application/json', utf8.encode('{broken'), null),
    (400, 'application/json', utf8.encode('[]'), null),
    (400, 'application/json', utf8.encode('{}'), null),
    (
      401,
      'application/json',
      utf8.encode(
        jsonEncode({
          'error': 'invalid_client',
          'error_description': _secret,
          'error_uri': 'https://auth.example/help',
        }),
      ),
      'invalid_client',
    ),
  ];
  for (final (status, mime, bytes, oauthError) in errors) {
    test(
      'revocation reports typed HTTP $status $mime ${bytes.length}-byte error',
      () async {
        await _withServer(
          (request) async {
            await request.drain<void>();
            request.response.statusCode = status;
            request.response.headers.set(HttpHeaders.contentTypeHeader, mime);
            request.response.add(bytes);
          },
          (issuer, paths) async {
            final grant = _grant(issuer);
            await expectLater(
              revokeMcpOAuthToken(
                grant,
                clientAuthentication: _authentication(grant, 'none'),
              ),
              throwsA(
                isA<McpOAuthTokenException>()
                    .having((error) => error.statusCode, 'HTTP status', status)
                    .having(
                      (error) => error.oauthError,
                      'OAuth error',
                      oauthError,
                    )
                    .having(
                      (error) => error.endpoint,
                      'endpoint',
                      issuer.resolve('/revoke'),
                    )
                    .having(
                      (error) => error.toString(),
                      'redaction',
                      isNot(contains(_secret)),
                    ),
              ),
            );
            expect(paths, ['/revoke']);
          },
        );
      },
    );
  }
  for (final missing in ['endpoint', 'refresh', 'refresh-grant']) {
    test('missing $missing fails before a network request', () async {
      await _withServer((request) => request.drain<void>(), (
        issuer,
        paths,
      ) async {
        final grant = _grant(
          issuer,
          endpoint: missing != 'endpoint',
          refresh: missing != 'refresh',
          grants: missing == 'refresh-grant'
              ? ['authorization_code']
              : ['authorization_code', 'refresh_token'],
        );
        final authentication = _authentication(grant, 'none');
        await expectLater(
          missing == 'refresh-grant'
              ? refreshMcpOAuthToken(
                  grant,
                  clientAuthentication: authentication,
                )
              : revokeMcpOAuthToken(
                  grant,
                  clientAuthentication: authentication,
                ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        expect(paths, isEmpty);
      });
    });
  }
}
