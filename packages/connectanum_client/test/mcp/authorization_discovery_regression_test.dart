import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

Map<String, Object?> _metadata() => {
  'issuer': 'https://auth.example/tenant',
  'authorization_endpoint': 'https://auth.example/authorize',
  'token_endpoint': 'https://auth.example/token',
  'response_types_supported': ['code'],
  'code_challenge_methods_supported': ['S256'],
};

Matcher _discoveryError(String field, [String? detail]) => throwsA(
  isA<McpAuthorizationDiscoveryException>()
      .having((error) => error.message, 'field', contains(field))
      .having((error) => error.message, 'detail', contains(detail ?? 'must')),
);

Future<void> _withMetadataServer(
  Future<void> Function(Uri endpoint, List<String> paths) check, {
  void Function(HttpResponse response, Uri endpoint)? writeMetadata,
  void Function(HttpRequest request, Uri endpoint)? writeResponse,
  String endpointPath = '/mcp',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final endpoint = Uri.parse('http://127.0.0.1:${server.port}$endpointPath');
  final paths = <String>[];
  server.listen((request) async {
    paths.add(request.uri.path);
    await request.drain<void>();
    if (writeResponse != null) {
      writeResponse(request, endpoint);
    } else if (request.uri.path == '/mcp') {
      request.response.statusCode = 401;
      request.response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer resource_metadata="${endpoint.resolve('/metadata')}"',
      );
    } else {
      request.response.headers.contentType = ContentType.json;
      if (writeMetadata != null) {
        writeMetadata(request.response, endpoint);
      } else {
        request.response.write(jsonEncode(_resourceMetadata(endpoint)));
      }
    }
    await request.response.close();
  });
  try {
    await check(endpoint, paths);
  } finally {
    await server.close(force: true);
  }
}

Map<String, Object?> _resourceMetadata(Uri endpoint) => {
  'resource': endpoint.toString(),
  'authorization_servers': ['https://auth.example/tenant'],
  'resource_name': 'caf\u00e9',
};

void main() {
  group('MCP authorization metadata boundary matrix', () {
    for (final field in [
      'authorization_endpoint',
      'token_endpoint',
      'revocation_endpoint',
      'registration_endpoint',
      'jwks_uri',
    ]) {
      test('$field rejects an unparseable absolute URI', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..[field] = 'http://[broken',
          ),
          _discoveryError(field, 'absolute URL'),
        );
      });
      for (final value in <Object>[
        '',
        42,
        false,
        <String>[],
        <String, Object?>{},
      ]) {
        test('$field rejects non-string or empty value $value', () {
          expect(
            () => McpAuthorizationServerMetadata.fromJson(
              _metadata()..[field] = value,
            ),
            _discoveryError(field, 'non-empty string'),
          );
        });
      }
      for (final uri in [
        'http://auth.example/insecure',
        '/relative',
        'https://user:secret@auth.example/path',
        'https://auth.example/path#fragment',
        'file:///tmp/metadata',
        'https:/missing-host',
      ]) {
        test('$field rejects unsafe URI $uri', () {
          expect(
            () => McpAuthorizationServerMetadata.fromJson(
              _metadata()..[field] = uri,
            ),
            _discoveryError(field, 'HTTPS'),
          );
        });
      }
    }

    for (final field in ['authorization_endpoint', 'token_endpoint']) {
      test('$field is required', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..remove(field),
          ),
          _discoveryError(field, 'non-empty string'),
        );
      });
    }

    for (final value in <Object?>[null, 42, false, <String>[], '']) {
      test('issuer rejects missing or invalid value $value', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..['issuer'] = value,
          ),
          _discoveryError('issuer'),
        );
      });
    }
    test('issuer query is rejected instead of changing resource identity', () {
      expect(
        () => McpAuthorizationServerMetadata.fromJson(
          _metadata()..['issuer'] = 'https://auth.example/tenant?other=1',
        ),
        _discoveryError('issuer', 'must not include a query'),
      );
    });

    for (final field in [
      'scopes_supported',
      'response_types_supported',
      'grant_types_supported',
      'code_challenge_methods_supported',
      'token_endpoint_auth_methods_supported',
      'revocation_endpoint_auth_methods_supported',
    ]) {
      for (final value in <Object>[
        'code',
        42,
        <String>[],
        <Object>['code', 42],
        [''],
      ]) {
        test('$field rejects malformed array $value', () {
          expect(
            () => McpAuthorizationServerMetadata.fromJson(
              _metadata()..[field] = value,
            ),
            _discoveryError(field, 'string array'),
          );
        });
      }
      test('$field rejects duplicates', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..[field] = ['code', 'code'],
          ),
          _discoveryError(field, 'unique'),
        );
      });
    }

    for (final field in [
      'response_types_supported',
      'code_challenge_methods_supported',
    ]) {
      test('$field cannot be omitted', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..remove(field),
          ),
          _discoveryError(field, 'non-empty string array'),
        );
      });
    }
    for (final (field, values, requiredValue) in [
      ('response_types_supported', ['token'], 'code'),
      ('grant_types_supported', ['refresh_token'], 'authorization_code'),
      ('code_challenge_methods_supported', ['plain'], 'S256'),
    ]) {
      test('$field must include $requiredValue', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..[field] = values,
          ),
          _discoveryError(field, 'must include $requiredValue'),
        );
      });
    }

    // Each array entry is one RFC 6749 section 3.3 scope-token, not a scope list.
    // https://www.rfc-editor.org/rfc/rfc6749#section-3.3
    for (final scope in [
      'two scopes',
      'quote"',
      r'back\slash',
      '\u007f',
      '\u0000',
      '\u00e9',
    ]) {
      test('rejects invalid OAuth scope token ${scope.codeUnits}', () {
        expect(
          () => McpAuthorizationServerMetadata.fromJson(
            _metadata()..['scopes_supported'] = [scope],
          ),
          _discoveryError('scopes_supported', 'invalid OAuth scope token'),
        );
      });
    }

    for (final field in [
      'client_id_metadata_document_supported',
      'authorization_response_iss_parameter_supported',
    ]) {
      for (final value in <Object>['true', 1, <bool>[], <String, bool>{}]) {
        test('$field rejects nonboolean value $value', () {
          expect(
            () => McpAuthorizationServerMetadata.fromJson(
              _metadata()..[field] = value,
            ),
            _discoveryError(field, 'boolean'),
          );
        });
      }
    }

    test('optional nulls preserve defaults and input is not modified', () {
      final input = _metadata()
        ..addAll({
          'revocation_endpoint': null,
          'registration_endpoint': null,
          'jwks_uri': null,
          'scopes_supported': null,
          'grant_types_supported': null,
          'client_id_metadata_document_supported': null,
          'authorization_response_iss_parameter_supported': false,
        });
      final before = Map<String, Object?>.from(input);
      final result = McpAuthorizationServerMetadata.fromJson(input);
      expect(input, before);
      expect(result.issuerIdentifier, 'https://auth.example/tenant');
      expect(result.revocationEndpoint, isNull);
      expect(result.registrationEndpoint, isNull);
      expect(result.jwksUri, isNull);
      expect(result.scopesSupported, isNull);
      expect(result.grantTypesSupported, isNull);
      expect(result.clientIdMetadataDocumentSupported, isNull);
      expect(result.authorizationResponseIssParameterSupported, isFalse);
      expect(result.toJson(), before);
      expect(
        () => result.responseTypesSupported.add('token'),
        throwsUnsupportedError,
      );
      expect(
        () => result.codeChallengeMethodsSupported.add('plain'),
        throwsUnsupportedError,
      );
    });

    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      test('loopback HTTP metadata is allowed for $host', () {
        final result = McpAuthorizationServerMetadata.fromJson(
          _metadata()
            ..['issuer'] = 'http://$host:8080/tenant'
            ..['authorization_endpoint'] = 'http://$host:8080/authorize'
            ..['token_endpoint'] = 'http://$host:8080/token',
        );
        expect(result.issuerIdentifier, 'http://$host:8080/tenant');
        expect(
          result.authorizationEndpoint.toString(),
          'http://$host:8080/authorize',
        );
        expect(result.tokenEndpoint.toString(), 'http://$host:8080/token');
      });
    }
  });

  group('Bearer quoted challenge boundary matrix', () {
    for (final (header, realm) in <(String, String)>[
      ('Bearer realm=token', 'token'),
      (' , \t bEaReR ReAlM = token', 'token'),
      (r'Bearer realm="a\"b"', 'a"b'),
      (r'Bearer realm="a\\b"', r'a\b'),
      (r'Bearer realm="a\ b"', 'a b'),
      ('Bearer realm="a\\\tb"', 'a\tb'),
      ('Bearer realm=""', ''),
    ]) {
      test('accepts valid quoting $header', () {
        final parsed = parseMcpBearerChallenges([header]);
        expect(parsed, hasLength(1));
        expect(parsed.single.realm, realm);
        expect(parsed.single.parameters, {'realm': realm});
        expect(() => parsed.clear(), throwsUnsupportedError);
        expect(
          () => parsed.single.parameters['realm'] = 'changed',
          throwsUnsupportedError,
        );
      });
    }
    for (final suffix in [
      'realm=',
      'realm= ',
      'realm=@',
      'realm="unfinished',
      'realm="ends\\',
      'realm="bad\rvalue"',
      'realm="bad\nvalue"',
      'realm="bad\u007fvalue"',
      'realm="bad\\\u0000value"',
      'realm="bad\\\u007fvalue"',
      'realm=one, REALM=two',
      '=missing',
    ]) {
      test('rejects malformed challenge ${suffix.codeUnits}', () {
        expect(parseMcpBearerChallenges(['Bearer $suffix']), isEmpty);
      });
    }
    test(
      'a malformed field does not contaminate a subsequent header value',
      () {
        final parsed = parseMcpBearerChallenges([
          'Bearer realm="unterminated',
          'Basic realm="legacy", Bearer realm="good", scope=" read   write "',
        ]);
        expect(parsed, hasLength(1));
        expect(parsed.single.realm, 'good');
        expect(parsed.single.scopes, ['read', 'write']);
        expect(() => parsed.single.scopes.add('admin'), throwsUnsupportedError);
      },
    );
  });

  group('MCP discovery document failure boundaries', () {
    for (final (name, bytes, message, status)
        in <(String, List<int>, String, int?)>[
          ('invalid UTF-8', [255], 'not valid UTF-8', 200),
          ('invalid JSON', utf8.encode('{broken'), 'not valid JSON', null),
          ('array JSON', utf8.encode('[]'), 'JSON object', null),
          ('null JSON', utf8.encode('null'), 'JSON object', null),
          ('string JSON', utf8.encode('"not metadata"'), 'JSON object', null),
        ]) {
      test(
        'rejects $name and preserves metadata location',
        () => _withMetadataServer((endpoint, paths) async {
          await expectLater(
            discoverMcpProtectedResourceMetadata(endpoint),
            throwsA(
              isA<McpAuthorizationDiscoveryException>()
                  .having(
                    (error) => error.message,
                    'message',
                    contains(message),
                  )
                  .having(
                    (error) => error.uri,
                    'uri',
                    endpoint.resolve('/metadata'),
                  )
                  .having((error) => error.statusCode, 'status', status),
            ),
          );
          expect(paths, ['/mcp', '/metadata']);
        }, writeMetadata: (response, _) => response.add(bytes)),
      );
    }
    test(
      'rejects challenged metadata HTTP errors without well-known fallback',
      () => _withMetadataServer((endpoint, paths) async {
        await expectLater(
          discoverMcpProtectedResourceMetadata(endpoint),
          throwsA(
            isA<McpAuthorizationDiscoveryException>()
                .having(
                  (error) => error.message,
                  'message',
                  'Protected Resource Metadata request failed.',
                )
                .having((error) => error.statusCode, 'status', 503)
                .having(
                  (error) => error.uri,
                  'uri',
                  endpoint.resolve('/metadata'),
                ),
          ),
        );
        expect(paths, ['/mcp', '/metadata']);
      }, writeMetadata: (response, _) => response.statusCode = 503),
    );

    test(
      'rejects non-JSON challenged metadata',
      () => _withMetadataServer(
        (endpoint, paths) async {
          await expectLater(
            discoverMcpProtectedResourceMetadata(endpoint),
            _discoveryError('Protected Resource Metadata', 'application/json'),
          );
          expect(paths, ['/mcp', '/metadata']);
        },
        writeMetadata: (response, endpoint) {
          response.headers.contentType = ContentType.text;
          response.write(jsonEncode(_resourceMetadata(endpoint)));
        },
      ),
    );

    for (final delta in [0, -1]) {
      test(
        'metadata byte limit boundary $delta',
        () => _withMetadataServer((endpoint, paths) async {
          final length = utf8
              .encode(jsonEncode(_resourceMetadata(endpoint)))
              .length;
          final future = discoverMcpProtectedResourceMetadata(
            endpoint,
            maxMetadataBytes: length + delta,
          );
          if (delta == 0) {
            final result = await future;
            expect(result.metadata.resource, endpoint);
            expect(result.metadata.authorizationServers, [
              Uri.parse('https://auth.example/tenant'),
            ]);
          } else {
            await expectLater(
              future,
              throwsA(
                isA<McpAuthorizationDiscoveryException>()
                    .having(
                      (error) => error.message,
                      'message',
                      'Protected Resource Metadata exceeds ${length - 1} bytes.',
                    )
                    .having((error) => error.statusCode, 'status', 200),
              ),
            );
          }
          expect(paths, ['/mcp', '/metadata']);
        }),
      );
    }
    for (final (field, value, detail) in <(String, Object?, String)>[
      ('resource', 'http://[broken', 'not a valid URI'),
      ('authorization_servers', ['http://[broken'], 'absolute issuer URL'),
      (
        'authorization_servers',
        ['https://AUTH.example', 'https://auth.example'],
        'must be unique',
      ),
      ('scopes_supported', ['two scopes'], 'invalid OAuth scope token'),
      ('resource_name', false, 'non-empty string'),
    ]) {
      test(
        'rejects malformed protected resource field $field: $value',
        () => _withMetadataServer(
          (endpoint, paths) async {
            await expectLater(
              discoverMcpProtectedResourceMetadata(endpoint),
              _discoveryError('Protected Resource Metadata', detail),
            );
            expect(paths, ['/mcp', '/metadata']);
          },
          writeMetadata: (response, endpoint) => response.write(
            jsonEncode(_resourceMetadata(endpoint)..[field] = value),
          ),
        ),
      );
    }
    for (final isServer in [false, true]) {
      for (final limit in [0, -1]) {
        test(
          'rejects invalid $isServer metadata byte limit $limit before I/O',
          () async {
            final endpoint = Uri.parse(
              'https://must-not-be-contacted.invalid/mcp',
            );
            final future = isServer
                ? discoverMcpAuthorizationServerMetadata(
                    endpoint,
                    maxMetadataBytes: limit,
                  )
                : discoverMcpProtectedResourceMetadata(
                    endpoint,
                    maxMetadataBytes: limit,
                  );
            await expectLater(
              future,
              throwsA(
                isA<ArgumentError>()
                    .having(
                      (error) => error.name,
                      'argument',
                      'maxMetadataBytes',
                    )
                    .having((error) => error.invalidValue, 'value', limit),
              ),
            );
          },
        );
      }
    }
  });

  group('discovery fallback and request boundaries', () {
    for (final value in [
      'http://remote.invalid/mcp',
      'https://user:secret@remote.invalid/mcp',
      'https://remote.invalid/mcp#fragment',
      'file:///tmp/mcp',
      '/relative',
    ]) {
      test('rejects unsafe endpoint $value before opening a request', () async {
        final opened = <HttpClientRequest>[];
        await expectLater(
          discoverMcpProtectedResourceMetadata(
            Uri.parse(value),
            onRequestOpened: opened.add,
          ),
          _discoveryError('endpoint', 'HTTPS URL'),
        );
        expect(opened, isEmpty);
      });
    }

    test(
      'malformed challenged URI fails without fallback requests',
      () => _withMetadataServer(
        (endpoint, paths) async {
          await expectLater(
            discoverMcpProtectedResourceMetadata(endpoint),
            throwsA(
              isA<McpAuthorizationDiscoveryException>()
                  .having(
                    (error) => error.message,
                    'message',
                    'Bearer resource_metadata is not a valid absolute URL.',
                  )
                  .having((error) => error.uri, 'uri', endpoint),
            ),
          );
          expect(paths, ['/mcp']);
        },
        writeResponse: (request, endpoint) {
          request.response.statusCode = 401;
          request.response.headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer resource_metadata="http://[broken"',
          );
        },
      ),
    );

    for (final endpointPath in ['/mcp', '/']) {
      test(
        'missing metadata exhausts unique well-known URLs for $endpointPath',
        () => _withMetadataServer(
          (endpoint, paths) async {
            final expected = [
              if (endpointPath != '/')
                '/.well-known/oauth-protected-resource/mcp',
              '/.well-known/oauth-protected-resource',
            ];
            final attempted = expected.map(endpoint.resolve).join(', ');
            await expectLater(
              discoverMcpProtectedResourceMetadata(endpoint),
              throwsA(
                isA<McpAuthorizationDiscoveryException>()
                    .having(
                      (error) => error.message,
                      'message',
                      'Protected Resource Metadata was not found at $attempted.',
                    )
                    .having((error) => error.uri, 'uri', endpoint)
                    .having((error) => error.statusCode, 'status', isNull),
              ),
            );
            expect(paths, [endpointPath, ...expected]);
          },
          endpointPath: endpointPath,
          writeResponse: (request, endpoint) {
            request.response.statusCode = request.uri.path.endsWith('/mcp')
                ? 404
                : 410;
          },
        ),
      );
    }

    for (final status in [403, 503]) {
      test(
        'well-known HTTP $status stops fallback and retains response context',
        () => _withMetadataServer(
          (endpoint, paths) async {
            await expectLater(
              discoverMcpProtectedResourceMetadata(endpoint),
              throwsA(
                isA<McpAuthorizationDiscoveryException>()
                    .having(
                      (error) => error.message,
                      'message',
                      'Protected Resource Metadata request failed.',
                    )
                    .having(
                      (error) => error.uri,
                      'uri',
                      endpoint.resolve(
                        '/.well-known/oauth-protected-resource/mcp',
                      ),
                    )
                    .having((error) => error.statusCode, 'status', status),
              ),
            );
            expect(paths, [
              '/mcp',
              '/.well-known/oauth-protected-resource/mcp',
            ]);
          },
          writeResponse: (request, endpoint) {
            request.response.statusCode = request.uri.path == '/mcp'
                ? 401
                : status;
          },
        ),
      );
    }

    test(
      'invalid JSON probe can recover through well-known metadata',
      () => _withMetadataServer(
        (endpoint, paths) async {
          final result = await discoverMcpProtectedResourceMetadata(endpoint);
          expect(result.metadata.resource, endpoint);
          expect(
            result.metadataUri,
            endpoint.resolve('/.well-known/oauth-protected-resource/mcp'),
          );
          expect(result.challenge, isNull);
          expect(paths, ['/mcp', '/.well-known/oauth-protected-resource/mcp']);
        },
        writeResponse: (request, endpoint) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            request.uri.path == '/mcp'
                ? '{not-json'
                : jsonEncode(_resourceMetadata(endpoint)),
          );
        },
      ),
    );

    for (final issuerPath in ['/', '/tenant', '/tenant/']) {
      test(
        'wrong metadata content type reports final issuer URL for $issuerPath',
        () => _withMetadataServer(
          (endpoint, paths) async {
            final suffix = issuerPath == '/' ? '' : issuerPath;
            final expected = [
              '/.well-known/oauth-authorization-server$suffix',
              '/.well-known/openid-configuration$suffix',
              if (issuerPath != '/') '/tenant/.well-known/openid-configuration',
            ];
            await expectLater(
              discoverMcpAuthorizationServerMetadata(endpoint),
              throwsA(
                isA<McpAuthorizationDiscoveryException>()
                    .having(
                      (error) => error.message,
                      'message',
                      contains(
                        'Authorization Server Metadata must use application/json.',
                      ),
                    )
                    .having(
                      (error) => error.uri,
                      'uri',
                      endpoint.resolve(expected.last),
                    )
                    .having((error) => error.statusCode, 'status', 200),
              ),
            );
            expect(paths, expected);
          },
          endpointPath: issuerPath,
          writeResponse: (request, endpoint) {
            request.response.headers.contentType = ContentType.text;
            request.response.write(
              jsonEncode(_metadata()..['issuer'] = endpoint.toString()),
            );
          },
        ),
      );
    }
  });

  group('discovery exception diagnostics', () {
    test('without optional context', () {
      expect(
        const McpAuthorizationDiscoveryException('invalid').toString(),
        'McpAuthorizationDiscoveryException: invalid',
      );
    });
    test('with URI and HTTP status', () {
      expect(
        McpAuthorizationDiscoveryException(
          'invalid',
          uri: Uri.parse('https://auth.example/metadata'),
          statusCode: 503,
        ).toString(),
        'McpAuthorizationDiscoveryException HTTP 503 (https://auth.example/metadata): invalid',
      );
    });
  });
}
