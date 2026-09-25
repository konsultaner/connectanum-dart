@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

McpOAuthTokenGrant _grant(
  Uri issuer, {
  String clientId = 'consumer',
  bool? documentSupport,
  List<String> scopes = const ['read'],
}) {
  McpOAuthTokenGrant? grant;
  expect(
    () {
      grant = McpOAuthTokenGrant.fromJson({
        'type': 'mcp_oauth_token_grant',
        'version': 1,
        'issued_at': '2020-01-01T00:00:00.000Z',
        'authorization_server': {
          'issuer': issuer.toString(),
          'authorization_endpoint': issuer.resolve('/authorize').toString(),
          'token_endpoint': issuer.resolve('/token').toString(),
          'revocation_endpoint': issuer.resolve('/revoke').toString(),
          'response_types_supported': ['code'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
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
          'client_id_metadata_document_supported': ?documentSupport,
        },
        'resource': 'https://resource.example/mcp',
        'client_id': clientId,
        'scopes': scopes,
        'tokens': {
          'access_token': 'fixture-access',
          'token_type': 'Bearer',
          'refresh_token': 'fixture-refresh',
        },
      }, now: DateTime.utc(2020));
    },
    returnsNormally,
    reason: 'The independently declared valid grant must restore.',
  );
  expect(grant!.clientId, clientId);
  expect(grant!.scopes, scopes);
  return grant!;
}

typedef _Request = ({
  String path,
  Map<String, String> form,
  String? authorization,
});

Future<void> _withEndpoint(
  Future<void> Function(Uri issuer, List<_Request> requests) action, {
  int status = 200,
  String? contentType = 'application/json',
  Map<String, Object?> response = const {
    'access_token': 'new-access',
    'token_type': 'Bearer',
  },
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <_Request>[];
  server.listen((request) async {
    requests.add((
      path: request.uri.path,
      form: Uri.splitQueryString(await utf8.decoder.bind(request).join()),
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
    ));
    request.response.statusCode = status;
    if (contentType != null) {
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    request.response.add(utf8.encode(jsonEncode(response)));
    await request.response.close();
  });
  try {
    await action(Uri.parse('http://127.0.0.1:${server.port}'), requests);
  } finally {
    await server.close(force: true);
  }
}

Future<McpOAuthTokenGrant?> _call(
  bool revoke,
  McpOAuthTokenGrant grant,
  McpOAuthClientAuthentication authentication, {
  List<String>? scopes,
  int maxResponseBytes = 65536,
}) => revoke
    ? revokeMcpOAuthToken(
        grant,
        clientAuthentication: authentication,
        timeout: const Duration(seconds: 2),
        maxResponseBytes: maxResponseBytes,
      ).then((_) => null)
    : refreshMcpOAuthToken(
        grant,
        clientAuthentication: authentication,
        scopes: scopes,
        timeout: const Duration(seconds: 2),
        maxResponseBytes: maxResponseBytes,
      );

Future<T> _successful<T>(Future<T> operation) async {
  try {
    return await operation;
  } on McpOAuthTokenException catch (error) {
    if (error.message.contains('timed out')) rethrow;
    fail(
      'A valid OAuth operation must succeed, not reject with ${error.message}',
    );
  }
}

McpOAuthClientAuthentication _registered(McpOAuthTokenGrant grant) =>
    McpOAuthClientAuthentication.registeredPublic(
      clientId: grant.clientId,
      authorizationServer: grant.authorizationServer,
    );

void main() {
  _responseBoundaries();
  final documentIds = <(String, bool)>[
    ('https://client.example/client.json', true),
    ('HTTPS://CLIENT.EXAMPLE/client.json', true),
    ('https://client.example/nested/client.json', true),
    ('https://[::1]/client.json', true),
    ('consumer', false),
    ('http://client.example/client.json', false),
    ('wss://client.example/client.json', false),
    ('https:client.json', false),
    ('https:///client.json', false),
    ('https://client.example', false),
    ('https://client.example/', false),
    ('https://user:secret@client.example/client.json', false),
    ('https://client.example/client.json?', false),
    ('https://client.example/client.json?query=yes', false),
    ('https://client.example/client.json#', false),
    ('https://client.example/client.json#fragment', false),
    ('https://client.example:invalid/client.json', false),
  ];
  for (final revoke in [false, true]) {
    for (final (clientId, allowed) in documentIds) {
      test(
        'portable identity revoke=$revoke accepts=$allowed $clientId',
        () async {
          await _withEndpoint((issuer, requests) async {
            final grant = _grant(
              issuer,
              clientId: clientId,
              documentSupport: true,
            );
            final operation = _call(
              revoke,
              grant,
              McpOAuthClientAuthentication.none(clientId),
            );
            if (allowed) {
              final result = await _successful(operation);
              expect(requests, hasLength(1));
              expect(requests.single.path, revoke ? '/revoke' : '/token');
              expect(requests.single.form['client_id'], clientId);
              expect(requests.single.authorization, isNull);
              expect(result?.accessToken, revoke ? null : 'new-access');
            } else {
              await expectLater(
                operation,
                throwsA(
                  isA<McpOAuthTokenException>()
                      .having(
                        (e) => e.message,
                        'identity rejection',
                        'OAuth client identity must be bound to the authorization server.',
                      )
                      .having(
                        (e) => e.endpoint,
                        'endpoint',
                        issuer.resolve(revoke ? '/revoke' : '/token'),
                      )
                      .having((e) => e.statusCode, 'no response', isNull),
                ),
              );
              expect(requests, isEmpty);
            }
          });
        },
      );
    }
    for (final support in [null, false, true]) {
      for (final bound in [false, true]) {
        test(
          'portable support revoke=$revoke support=$support bound=$bound',
          () async {
            await _withEndpoint((issuer, requests) async {
              final grant = _grant(
                issuer,
                clientId: 'https://client.example/client.json',
                documentSupport: support,
              );
              final operation = _call(
                revoke,
                grant,
                bound
                    ? _registered(grant)
                    : McpOAuthClientAuthentication.none(grant.clientId),
              );
              if (bound || support == true) {
                await _successful(operation);
                expect(requests, hasLength(1));
                expect(requests.single.form['client_id'], grant.clientId);
              } else {
                await expectLater(
                  operation,
                  throwsA(
                    isA<McpOAuthTokenException>().having(
                      (e) => e.message,
                      'unsupported portability',
                      'OAuth client identity must be bound to the authorization server.',
                    ),
                  ),
                );
                expect(requests, isEmpty);
              }
            });
          },
        );
      }
    }
    for (final basic in [false, true]) {
      for (final secret in [
        ' ',
        '!',
        '"',
        '[',
        '\\',
        ']',
        '~',
        '\u0080',
        '\u00e4',
        ':',
        '',
        '\u001f',
        '\u007f',
      ]) {
        final valid = !['', '\u001f', '\u007f'].contains(secret);
        test(
          'secret bytes revoke=$revoke basic=$basic bytes=${secret.codeUnits}',
          () async {
            await _withEndpoint((issuer, requests) async {
              final grant = _grant(issuer);
              final auth = basic
                  ? McpOAuthClientAuthentication.clientSecretBasic(
                      clientId: grant.clientId,
                      clientSecret: secret,
                      authorizationServer: grant.authorizationServer,
                    )
                  : McpOAuthClientAuthentication.clientSecretPost(
                      clientId: grant.clientId,
                      clientSecret: secret,
                      authorizationServer: grant.authorizationServer,
                    );
              final operation = _call(revoke, grant, auth);
              if (valid) {
                await _successful(operation);
                expect(requests, hasLength(1));
                if (basic) {
                  expect(requests.single.authorization, startsWith('Basic '));
                  final parts = utf8
                      .decode(
                        base64Decode(
                          requests.single.authorization!.substring(6),
                        ),
                      )
                      .split(':');
                  expect(parts, hasLength(2));
                  expect(Uri.decodeQueryComponent(parts[0]), 'consumer');
                  expect(Uri.decodeQueryComponent(parts[1]), secret);
                  expect(
                    requests.single.form.containsKey('client_secret'),
                    isFalse,
                  );
                } else {
                  expect(requests.single.authorization, isNull);
                  expect(requests.single.form['client_secret'], secret);
                }
              } else {
                await expectLater(
                  operation,
                  throwsA(
                    isA<McpOAuthTokenException>().having(
                      (e) => e.message,
                      'secret rejection',
                      'OAuth client secret must be non-empty and contain no controls.',
                    ),
                  ),
                );
                expect(requests, isEmpty);
              }
            });
          },
        );
      }
    }
  }

  for (final scope in [
    '!',
    '#',
    '[',
    ']',
    '~',
    '',
    ' ',
    '"',
    '\\',
    '\u001f',
    '\u007f',
    '\u0080',
  ]) {
    final valid = ['!', '#', '[', ']', '~'].contains(scope);
    test('scope endpoints ${scope.codeUnits}', () async {
      await _withEndpoint((issuer, requests) async {
        final grant = _grant(issuer, scopes: valid ? [scope] : ['read']);
        final operation = _call(
          false,
          grant,
          _registered(grant),
          scopes: [scope],
        );
        if (valid) {
          final result = await _successful(operation);
          expect(requests, hasLength(1));
          expect(requests.single.form['scope'], scope);
          expect(result!.scopes, [scope]);
        } else {
          await expectLater(
            operation,
            throwsA(
              isA<McpOAuthTokenException>().having(
                (e) => e.message,
                'scope rejection',
                'OAuth refresh scope contains an invalid token.',
              ),
            ),
          );
          expect(requests, isEmpty);
        }
      });
    });
  }

  for (final revoke in [false, true]) {
    for (final description in [
      ' ',
      '!',
      '#',
      '[',
      ']',
      '~',
      '',
      '"',
      '\\',
      '\u001f',
      '\u007f',
      '\u0080',
    ]) {
      final valid = [' ', '!', '#', '[', ']', '~'].contains(description);
      test(
        'error description revoke=$revoke bytes=${description.codeUnits}',
        () async {
          await _withEndpoint(
            (issuer, requests) async {
              final grant = _grant(issuer);
              await expectLater(
                _call(revoke, grant, _registered(grant)),
                throwsA(
                  isA<McpOAuthTokenException>()
                      .having(
                        (e) => e.message,
                        'error message',
                        valid
                            ? (revoke
                                  ? 'OAuth revocation endpoint rejected the request.'
                                  : 'OAuth token endpoint rejected the authorization grant.')
                            : 'OAuth endpoint returned an invalid error_description.',
                      )
                      .having((e) => e.statusCode, 'HTTP status', 400)
                      .having(
                        (e) => e.oauthError,
                        'OAuth error',
                        'invalid_grant',
                      )
                      .having(
                        (e) => e.errorDescription,
                        'description',
                        valid ? description : null,
                      ),
                ),
              );
              expect(requests, hasLength(1));
            },
            status: 400,
            response: {
              'error': 'invalid_grant',
              'error_description': description,
            },
          );
        },
      );
    }
    for (final (uri, valid) in <(String, bool)>[
      ('https://help.example/a', true),
      ('http://localhost/help', true),
      ('http://127.0.0.1/help', true),
      ('http://[::1]/help', true),
      ('http://127.0.0.2/help', false),
      ('http://help.example/a', false),
      ('https://user:secret@help.example/a', false),
      ('https://help.example/a#fragment', false),
      ('https:///help', false),
      ('mailto:help@example.com', false),
      ('https://[invalid/help', false),
    ]) {
      test('error URI revoke=$revoke valid=$valid $uri', () async {
        await _withEndpoint(
          (issuer, requests) async {
            final grant = _grant(issuer);
            await expectLater(
              _call(revoke, grant, _registered(grant)),
              throwsA(
                isA<McpOAuthTokenException>()
                    .having(
                      (e) => e.message,
                      'error URI outcome',
                      valid
                          ? (revoke
                                ? 'OAuth revocation endpoint rejected the request.'
                                : 'OAuth token endpoint rejected the authorization grant.')
                          : 'OAuth token endpoint returned an unsafe error_uri.',
                    )
                    .having((e) => e.statusCode, 'HTTP status', 400)
                    .having(
                      (e) => e.errorUri,
                      'error URI',
                      valid ? Uri.parse(uri) : null,
                    )
                    .having(
                      (e) => e.oauthError,
                      'OAuth error',
                      valid ? 'invalid_grant' : null,
                    ),
              ),
            );
            expect(requests, hasLength(1));
          },
          status: 400,
          response: {'error': 'invalid_grant', 'error_uri': uri},
        );
      });
    }
  }
}

void _responseBoundaries() {
  for (final revoke in [false, true]) {
    for (final contentType in [
      null,
      'text/plain',
      'application/problem+json',
    ]) {
      test('non-JSON error MIME revoke=$revoke type=$contentType', () async {
        await _withEndpoint(
          (issuer, requests) async {
            final grant = _grant(issuer);
            await expectLater(
              _call(revoke, grant, _registered(grant)),
              throwsA(
                isA<McpOAuthTokenException>()
                    .having(
                      (e) => e.message,
                      'MIME diagnostic',
                      revoke
                          ? 'OAuth revocation endpoint returned a non-JSON error response.'
                          : 'OAuth token endpoint must return application/json.',
                    )
                    .having((e) => e.statusCode, 'status', 400)
                    .having(
                      (e) => e.oauthError,
                      'untrusted error not interpreted',
                      isNull,
                    ),
              ),
            );
            expect(requests, hasLength(1));
          },
          status: 400,
          contentType: contentType,
          response: {'error': 'invalid_grant'},
        );
      });
    }

    test(
      'registered identity retains internal ASCII space revoke=$revoke',
      () async {
        await _withEndpoint((issuer, requests) async {
          final grant = _grant(issuer, clientId: 'consumer client');
          await _successful(_call(revoke, grant, _registered(grant)));
          expect(requests.single.form['client_id'], 'consumer client');
        });
      },
    );

    const response = {'access_token': 'new-access', 'token_type': 'Bearer'};
    final length = utf8.encode(jsonEncode(response)).length;
    for (final limit in [length - 1, length, length + 1]) {
      test(
        'response byte limit revoke=$revoke limit=$limit size=$length',
        () async {
          await _withEndpoint((issuer, requests) async {
            final grant = _grant(issuer);
            final operation = _call(
              revoke,
              grant,
              _registered(grant),
              maxResponseBytes: limit,
            );
            if (limit >= length) {
              final result = await _successful(operation);
              expect(result?.accessToken, revoke ? null : 'new-access');
            } else {
              await expectLater(
                operation,
                throwsA(
                  isA<McpOAuthTokenException>().having(
                    (e) => e.message,
                    'bounded response diagnostic',
                    '${revoke ? 'OAuth revocation endpoint' : 'OAuth token endpoint'} response exceeds $limit bytes.',
                  ),
                ),
              );
            }
            expect(requests, hasLength(1));
          }, response: response);
        },
      );
    }
  }

  for (final seconds in [0, 1, 60]) {
    test(
      'refresh response expires_in=$seconds remains a relative deadline',
      () async {
        await _withEndpoint(
          (issuer, requests) async {
            final grant = _grant(issuer);
            final result = await _successful(
              _call(false, grant, _registered(grant)),
            );
            expect(result!.expiresIn, Duration(seconds: seconds));
            expect(
              result.expiresAt,
              result.issuedAt.add(Duration(seconds: seconds)),
            );
            expect(result.isAccessTokenExpired(now: result.expiresAt), isTrue);
            expect(requests, hasLength(1));
          },
          response: {
            'access_token': 'new-access',
            'token_type': 'Bearer',
            'expires_in': seconds,
          },
        );
      },
    );
  }

  for (final scope in ['read', 'read admin', 'admin']) {
    test(
      'refresh response scope is restricted to requested set: $scope',
      () async {
        await _withEndpoint(
          (issuer, requests) async {
            final grant = _grant(issuer);
            final operation = _call(
              false,
              grant,
              _registered(grant),
              scopes: ['read'],
            );
            if (scope == 'read') {
              expect((await _successful(operation))!.scopes, ['read']);
            } else {
              await expectLater(
                operation,
                throwsA(
                  isA<McpOAuthTokenException>().having(
                    (e) => e.message,
                    'scope elevation diagnostic',
                    'OAuth refresh response scopes exceed the requested refresh scopes.',
                  ),
                ),
              );
            }
            expect(requests.single.form['scope'], 'read');
          },
          response: {
            'access_token': 'new-access',
            'token_type': 'Bearer',
            'scope': scope,
          },
        );
      },
    );
  }
}
