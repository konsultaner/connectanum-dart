import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP authorization discovery', () {
    test('parses Bearer challenges without splitting quoted commas', () {
      final challenges = parseMcpBearerChallenges(<String>[
        'Basic realm="legacy", Bearer realm="mcp", '
            'resource_metadata="https://mcp.example/.well-known/'
            'oauth-protected-resource", scope="tools:read tools:call", '
            'error="insufficient_scope", '
            'error_description="Authorize, then retry"',
      ]);

      expect(challenges, hasLength(1));
      expect(challenges.single.realm, 'mcp');
      expect(
        challenges.single.resourceMetadata,
        Uri.parse('https://mcp.example/.well-known/oauth-protected-resource'),
      );
      expect(challenges.single.scopes, <String>['tools:read', 'tools:call']);
      expect(challenges.single.error, 'insufficient_scope');
      expect(challenges.single.errorDescription, 'Authorize, then retry');
    });

    test(
      'discovers challenged metadata without forwarding credentials',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final endpoint = Uri.parse(
          'http://${server.address.address}:${server.port}/mcp',
        );
        final metadataUri = endpoint.replace(path: '/oauth/resource');
        final seenPaths = <String>[];
        final seenAuthorization = <String, String?>{};
        final seenSessions = <String, String?>{};

        server.listen((request) async {
          seenPaths.add(request.uri.path);
          seenAuthorization[request.uri.path] = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          seenSessions[request.uri.path] = request.headers.value(
            'MCP-Session-Id',
          );
          await request.drain<void>();
          if (request.uri.path == endpoint.path) {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.headers.add(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer realm="router", '
              'resource_metadata="$metadataUri", '
              'scope="tools:read tools:call"',
            );
            await request.response.close();
            return;
          }
          if (request.uri.path == metadataUri.path) {
            await _writeJson(request.response, <String, Object?>{
              'resource': endpoint.toString(),
              'authorization_servers': <String>['https://auth.example/tenant'],
              'scopes_supported': <String>['tools:read'],
              'resource_name': 'Router MCP',
              'bearer_methods_supported': <String>['header'],
            });
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final client = McpStreamableHttpClient.withBearerToken(
          endpoint,
          'secret-token',
        )..sessionId = 'active-session';
        addTearDown(client.close);

        final discovery = await client.discoverProtectedResourceMetadata();

        expect(seenPaths, <String>[endpoint.path, metadataUri.path]);
        expect(seenAuthorization.values, everyElement(isNull));
        expect(seenSessions.values, everyElement(isNull));
        expect(client.sessionId, 'active-session');
        expect(discovery.metadataUri, metadataUri);
        expect(discovery.metadata.resource, endpoint);
        expect(discovery.metadata.authorizationServers, <Uri>[
          Uri.parse('https://auth.example/tenant'),
        ]);
        expect(discovery.metadata.resourceName, 'Router MCP');
        expect(discovery.requiredScopes, <String>['tools:read', 'tools:call']);
      },
    );

    test('falls back to path-specific then root well-known metadata', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/public/mcp',
      );
      const pathSpecific = '/.well-known/oauth-protected-resource/public/mcp';
      const root = '/.well-known/oauth-protected-resource';
      final seenPaths = <String>[];

      server.listen((request) async {
        seenPaths.add(request.uri.path);
        await request.drain<void>();
        if (request.uri.path == endpoint.path) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.add(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer realm="router"',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == pathSpecific) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (request.uri.path == root) {
          await _writeJson(request.response, <String, Object?>{
            'resource': endpoint.toString(),
            'authorization_servers': <String>['https://auth.example'],
            'scopes_supported': <String>['tools:read'],
          });
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final client = McpStreamableHttpClient(endpoint);
      addTearDown(client.close);
      final discovery = await client.discoverProtectedResourceMetadata();

      expect(seenPaths, <String>[endpoint.path, pathSpecific, root]);
      expect(discovery.metadataUri.path, root);
      expect(discovery.challenge?.realm, 'router');
      expect(discovery.requiredScopes, <String>['tools:read']);
    });

    test(
      'ignores a direct non-metadata JSON response before fallback',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final endpoint = Uri.parse(
          'http://${server.address.address}:${server.port}/public/mcp',
        );
        const pathSpecific = '/.well-known/oauth-protected-resource/public/mcp';
        final seenPaths = <String>[];

        server.listen((request) async {
          seenPaths.add(request.uri.path);
          await request.drain<void>();
          if (request.uri.path == endpoint.path) {
            await _writeJson(request.response, <String, Object?>{
              'jsonrpc': '2.0',
              'result': <String, Object?>{},
            });
            return;
          }
          if (request.uri.path == pathSpecific) {
            await _writeJson(request.response, <String, Object?>{
              'resource': endpoint.toString(),
              'authorization_servers': <String>['https://auth.example'],
            });
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final client = McpStreamableHttpClient(endpoint);
        addTearDown(client.close);
        final discovery = await client.discoverProtectedResourceMetadata();

        expect(seenPaths, <String>[endpoint.path, pathSpecific]);
        expect(discovery.metadataUri.path, pathSpecific);
      },
    );

    test('rejects metadata for a different protected resource', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/mcp',
      );
      final metadataUri = endpoint.replace(path: '/oauth/resource');

      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == endpoint.path) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.add(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer resource_metadata="$metadataUri"',
          );
          await request.response.close();
          return;
        }
        await _writeJson(request.response, <String, Object?>{
          'resource': endpoint.replace(path: '/other').toString(),
          'authorization_servers': <String>['https://auth.example'],
        });
      });

      final client = McpStreamableHttpClient(endpoint);
      addTearDown(client.close);

      await expectLater(
        client.discoverProtectedResourceMetadata(),
        throwsA(
          isA<McpAuthorizationDiscoveryException>().having(
            (error) => error.message,
            'message',
            contains('does not match'),
          ),
        ),
      );
    });

    test(
      'discovers path issuer metadata in MCP priority order without credentials',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final issuer = Uri.parse(
          'http://${server.address.address}:${server.port}/tenant1',
        );
        const oauthPath = '/.well-known/oauth-authorization-server/tenant1';
        const openIdInsertedPath = '/.well-known/openid-configuration/tenant1';
        const openIdAppendedPath = '/tenant1/.well-known/openid-configuration';
        final seenPaths = <String>[];
        final seenTraceHeaders = <String?>[];
        final sawCredentials = <bool>[];

        server.listen((request) async {
          seenPaths.add(request.uri.path);
          seenTraceHeaders.add(request.headers.value('x-consumer-trace'));
          sawCredentials.add(
            request.headers.value(HttpHeaders.authorizationHeader) != null ||
                request.headers.value(HttpHeaders.cookieHeader) != null ||
                request.headers.value('MCP-Session-Id') != null ||
                request.headers.value('MCP-Protocol-Version') != null ||
                request.headers.value('Last-Event-ID') != null,
          );
          await request.drain<void>();
          if (request.uri.path == oauthPath) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          if (request.uri.path == openIdInsertedPath) {
            await _writeJson(request.response, <String, Object?>{
              'issuer': issuer.replace(path: '/other').toString(),
              'authorization_endpoint': issuer
                  .replace(path: '/oauth/authorize')
                  .toString(),
              'token_endpoint': issuer.replace(path: '/oauth/token').toString(),
              'response_types_supported': <String>['code'],
            });
            return;
          }
          if (request.uri.path == openIdAppendedPath) {
            await _writeJson(request.response, <String, Object?>{
              'issuer': issuer.toString(),
              'authorization_endpoint': issuer
                  .replace(path: '/oauth/authorize')
                  .toString(),
              'token_endpoint': issuer.replace(path: '/oauth/token').toString(),
              'revocation_endpoint': issuer
                  .replace(path: '/oauth/revoke')
                  .toString(),
              'registration_endpoint': issuer
                  .replace(path: '/oauth/register')
                  .toString(),
              'jwks_uri': issuer.replace(path: '/oauth/jwks').toString(),
              'scopes_supported': <String>['mcp:tools', 'mcp:meta'],
              'response_types_supported': <String>['code'],
              'grant_types_supported': <String>[
                'authorization_code',
                'refresh_token',
              ],
              'code_challenge_methods_supported': <String>['S256'],
              'token_endpoint_auth_methods_supported': <String>['none'],
              'revocation_endpoint_auth_methods_supported': <String>['none'],
              'client_id_metadata_document_supported': true,
              'authorization_response_iss_parameter_supported': true,
              'custom_capability': <String, Object?>{'enabled': true},
            });
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final client = McpStreamableHttpClient.withBearerToken(
          issuer,
          'secret-token',
        )..sessionId = 'active-session';
        addTearDown(client.close);

        final discovery = await client.discoverAuthorizationServerMetadata(
          issuer,
          headers: const <String, String>{
            'x-consumer-trace': 'authorization-server-discovery',
          },
        );

        expect(seenPaths, <String>[
          oauthPath,
          openIdInsertedPath,
          openIdAppendedPath,
        ]);
        expect(
          seenTraceHeaders,
          everyElement('authorization-server-discovery'),
        );
        expect(sawCredentials, everyElement(isFalse));
        expect(client.sessionId, 'active-session');
        expect(discovery.metadataUri.path, openIdAppendedPath);
        expect(discovery.metadata.issuer, issuer);
        expect(discovery.metadata.issuerIdentifier, issuer.toString());
        expect(
          discovery.metadata.authorizationEndpoint.path,
          '/oauth/authorize',
        );
        expect(discovery.metadata.tokenEndpoint.path, '/oauth/token');
        expect(discovery.metadata.revocationEndpoint?.path, '/oauth/revoke');
        expect(
          discovery.metadata.registrationEndpoint?.path,
          '/oauth/register',
        );
        expect(discovery.metadata.jwksUri?.path, '/oauth/jwks');
        expect(discovery.metadata.scopesSupported, <String>[
          'mcp:tools',
          'mcp:meta',
        ]);
        expect(discovery.metadata.responseTypesSupported, <String>['code']);
        expect(discovery.metadata.grantTypesSupported, <String>[
          'authorization_code',
          'refresh_token',
        ]);
        expect(discovery.metadata.codeChallengeMethodsSupported, <String>[
          'S256',
        ]);
        expect(discovery.metadata.tokenEndpointAuthMethodsSupported, <String>[
          'none',
        ]);
        expect(
          discovery.metadata.revocationEndpointAuthMethodsSupported,
          <String>['none'],
        );
        expect(discovery.metadata.clientIdMetadataDocumentSupported, isTrue);
        expect(
          discovery.metadata.authorizationResponseIssParameterSupported,
          isTrue,
        );
        expect(discovery.metadata.raw['custom_capability'], <String, Object?>{
          'enabled': true,
        });
      },
    );

    test('rejects a non-boolean authorization response issuer flag', () {
      expect(
        () => McpAuthorizationServerMetadata.fromJson(<String, Object?>{
          'issuer': 'https://auth.example',
          'authorization_endpoint': 'https://auth.example/authorize',
          'token_endpoint': 'https://auth.example/token',
          'response_types_supported': <String>['code'],
          'code_challenge_methods_supported': <String>['S256'],
          'authorization_response_iss_parameter_supported': 'true',
        }),
        throwsA(
          isA<McpAuthorizationDiscoveryException>().having(
            (error) => error.message,
            'message',
            contains('authorization_response_iss_parameter_supported'),
          ),
        ),
      );
    });

    test('discovers a root issuer through the OpenID fallback', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final issuer = Uri.parse(
        'http://${server.address.address}:${server.port}',
      );
      final seenPaths = <String>[];

      server.listen((request) async {
        seenPaths.add(request.uri.path);
        await request.drain<void>();
        if (request.uri.path == '/.well-known/oauth-authorization-server') {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.uri.path == '/.well-known/openid-configuration') {
          await _writeJson(request.response, <String, Object?>{
            'issuer': issuer.toString(),
            'authorization_endpoint': issuer
                .replace(path: '/authorize')
                .toString(),
            'token_endpoint': issuer.replace(path: '/token').toString(),
            'response_types_supported': <String>['code'],
            'code_challenge_methods_supported': <String>['S256'],
          });
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final discovery = await discoverMcpAuthorizationServerMetadata(issuer);

      expect(seenPaths, <String>[
        '/.well-known/oauth-authorization-server',
        '/.well-known/openid-configuration',
      ]);
      expect(discovery.metadataUri.path, '/.well-known/openid-configuration');
      expect(discovery.metadata.issuer, issuer);
    });

    test('rejects insecure authorization-server endpoints', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final issuer = Uri.parse(
        'http://${server.address.address}:${server.port}',
      );

      server.listen((request) async {
        await request.drain<void>();
        await _writeJson(request.response, <String, Object?>{
          'issuer': issuer.toString(),
          'authorization_endpoint': 'http://auth.example/authorize',
          'token_endpoint': issuer.replace(path: '/token').toString(),
          'response_types_supported': <String>['code'],
        });
      });

      await expectLater(
        discoverMcpAuthorizationServerMetadata(issuer),
        throwsA(
          isA<McpAuthorizationDiscoveryException>().having(
            (error) => error.message,
            'message',
            contains('authorization_endpoint'),
          ),
        ),
      );
    });

    test('rejects authorization-server metadata without S256 PKCE', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final issuer = Uri.parse(
        'http://${server.address.address}:${server.port}',
      );

      server.listen((request) async {
        await request.drain<void>();
        await _writeJson(request.response, <String, Object?>{
          'issuer': issuer.toString(),
          'authorization_endpoint': issuer
              .replace(path: '/authorize')
              .toString(),
          'token_endpoint': issuer.replace(path: '/token').toString(),
          'response_types_supported': <String>['code'],
          'code_challenge_methods_supported': <String>['plain'],
        });
      });

      await expectLater(
        discoverMcpAuthorizationServerMetadata(issuer),
        throwsA(
          isA<McpAuthorizationDiscoveryException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('code_challenge_methods_supported'),
              contains('S256'),
            ),
          ),
        ),
      );
    });

    test('rejects credentials supplied as discovery headers', () async {
      await expectLater(
        discoverMcpAuthorizationServerMetadata(
          Uri.parse('https://auth.example'),
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer secret',
          },
        ),
        throwsArgumentError,
      );
    });

    test('exposes parsed Bearer challenges on HTTP failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/mcp',
      );

      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.forbidden;
        request.response.headers.add(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer error="insufficient_scope", scope="tools:call"',
        );
        await request.response.close();
      });

      final client = McpStreamableHttpClient(endpoint);
      addTearDown(client.close);

      try {
        await client.pingDirect();
        fail('Expected the protected endpoint to reject the request.');
      } on McpStreamableHttpException catch (error) {
        expect(
          error.responseHeaders[HttpHeaders.wwwAuthenticateHeader],
          isNotEmpty,
        );
        expect(error.bearerChallenges, hasLength(1));
        expect(error.bearerChallenges.single.error, 'insufficient_scope');
        expect(error.bearerChallenges.single.scopes, <String>['tools:call']);
      }
    });

    test('bounds a stalled protected-resource discovery body', () async {
      final responseStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        if (!releaseResponse.isCompleted) {
          releaseResponse.complete();
        }
        await server.close(force: true);
      });
      final endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/mcp',
      );

      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.bufferOutput = false;
        request.response.write('{"resource":');
        await request.response.flush();
        responseStarted.complete();
        await releaseResponse.future;
        await request.response.close();
      });

      final client = McpStreamableHttpClient(endpoint)
        ..sessionId = 'active-session';
      addTearDown(client.close);

      final discovery = client.discoverProtectedResourceMetadata(
        timeout: const Duration(milliseconds: 200),
      );
      await responseStarted.future.timeout(const Duration(seconds: 3));

      await expectLater(
        discovery.timeout(const Duration(seconds: 3)),
        throwsA(
          isA<McpAuthorizationDiscoveryException>()
              .having(
                (error) => error.message,
                'message',
                contains('timed out'),
              )
              .having((error) => error.uri, 'uri', endpoint),
        ),
      );
      expect(client.sessionId, 'active-session');
    });

    test(
      'bounds protected-resource discovery before response headers',
      () async {
        final requestReceived = Completer<void>();
        final releaseResponse = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          if (!releaseResponse.isCompleted) {
            releaseResponse.complete();
          }
          await server.close(force: true);
        });
        final endpoint = Uri.parse(
          'http://${server.address.address}:${server.port}/mcp',
        );

        server.listen((request) async {
          await request.drain<void>();
          requestReceived.complete();
          await releaseResponse.future;
        });

        final discovery = discoverMcpProtectedResourceMetadata(
          endpoint,
          timeout: const Duration(milliseconds: 200),
        );
        await requestReceived.future.timeout(const Duration(seconds: 3));

        await expectLater(
          discovery.timeout(const Duration(seconds: 3)),
          throwsA(
            isA<McpAuthorizationDiscoveryException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('timed out'),
                )
                .having((error) => error.uri, 'uri', endpoint),
          ),
        );
      },
    );

    test('shares one deadline across authorization-server fallbacks', () async {
      final stalledResponseStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        if (!releaseResponse.isCompleted) {
          releaseResponse.complete();
        }
        await server.close(force: true);
      });
      final issuer = Uri.parse(
        'http://${server.address.address}:${server.port}',
      );

      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/.well-known/oauth-authorization-server') {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.bufferOutput = false;
        request.response.write('{"issuer":');
        await request.response.flush();
        stalledResponseStarted.complete();
        await releaseResponse.future;
        await request.response.close();
      });

      final stopwatch = Stopwatch()..start();
      final discovery = discoverMcpAuthorizationServerMetadata(
        issuer,
        timeout: const Duration(milliseconds: 500),
      );
      await stalledResponseStarted.future.timeout(const Duration(seconds: 3));

      await expectLater(
        discovery.timeout(const Duration(seconds: 3)),
        throwsA(
          isA<McpAuthorizationDiscoveryException>()
              .having(
                (error) => error.message,
                'message',
                contains('timed out'),
              )
              .having(
                (error) => error.uri?.path,
                'uri path',
                '/.well-known/openid-configuration',
              ),
        ),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 700)));
    });

    test('rejects non-positive discovery deadlines before I/O', () async {
      await expectLater(
        discoverMcpProtectedResourceMetadata(
          Uri.parse('https://mcp.example'),
          timeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      await expectLater(
        discoverMcpAuthorizationServerMetadata(
          Uri.parse('https://auth.example'),
          timeout: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('preserves request lifecycle hook timeout failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => request.drain<void>());
      final ownerError = TimeoutException('owner lifecycle timeout');

      await expectLater(
        discoverMcpProtectedResourceMetadata(
          Uri.parse('http://${server.address.address}:${server.port}/mcp'),
          onRequestOpened: (request) => throw ownerError,
        ),
        throwsA(same(ownerError)),
      );
    });
  });
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, Object?> value,
) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(value));
  await response.close();
}
