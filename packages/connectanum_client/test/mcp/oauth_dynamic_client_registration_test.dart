import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP OAuth dynamic client registration', () {
    late HttpServer server;
    late Uri endpoint;
    late Uri issuer;
    late bool advertiseRegistrationEndpoint;
    late Future<void> Function(HttpRequest request, Map<String, Object?> body)
    registrationHandler;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/mcp',
      );
      issuer = endpoint.replace(path: '/oauth');
      advertiseRegistrationEndpoint = true;
      registrationHandler = (request, body) async {
        await _writeJson(request, <String, Object?>{
          'client_id': 'dynamic-consumer-client',
          'client_id_issued_at': 1774922400,
          ...body,
          'server_extension': 'registered',
        }, statusCode: HttpStatus.created);
      };
      server.listen((request) async {
        if (request.uri.path ==
            '/.well-known/oauth-authorization-server/oauth') {
          await request.drain<void>();
          await _writeJson(request, <String, Object?>{
            'issuer': issuer.toString(),
            'authorization_endpoint': issuer
                .replace(path: '/authorize')
                .toString(),
            'token_endpoint': issuer.replace(path: '/token').toString(),
            if (advertiseRegistrationEndpoint)
              'registration_endpoint': issuer
                  .replace(path: '/register')
                  .toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>[
              'authorization_code',
              'refresh_token',
            ],
            'code_challenge_methods_supported': <String>['S256'],
            'token_endpoint_auth_methods_supported': <String>['none'],
          });
          return;
        }
        if (request.uri.path == '/register') {
          final value = jsonDecode(await utf8.decoder.bind(request).join());
          if (value is! Map) {
            await _writeJson(request, const <String, Object?>{
              'error': 'invalid_client_metadata',
            }, statusCode: HttpStatus.badRequest);
            return;
          }
          await registrationHandler(request, value.cast<String, Object?>());
          return;
        }
        if (request.uri.path == '/mcp') {
          await request.drain<void>();
          request.response.headers.set('MCP-Session-Id', 'active-session');
          await _writeJson(request, <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'initialize',
            'result': <String, Object?>{
              'protocolVersion':
                  McpStreamableHttpClient.latestSessionProtocolVersion,
              'capabilities': const <String, Object?>{},
              'serverInfo': const <String, Object?>{
                'name': 'registration-test',
                'version': '1',
              },
            },
          });
          return;
        }
        await request.drain<void>();
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('registers a public client and reuses its issued identity', () async {
      late HttpRequest capturedRequest;
      late Map<String, Object?> capturedBody;
      registrationHandler = (request, body) async {
        capturedRequest = request;
        capturedBody = body;
        await _writeJson(request, <String, Object?>{
          'client_id': 'dynamic-consumer-client',
          'client_id_issued_at': 1774922400,
          ...body,
          'server_extension': 'registered',
        }, statusCode: HttpStatus.created);
      };
      final authorizationServer = await _discover(issuer);
      final redirectUri = Uri.parse('http://127.0.0.1:34891/callback');
      final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: 'Consumer application',
        redirectUris: <Uri>[redirectUri],
        applicationType: McpOAuthClientApplicationType.native,
        clientUri: Uri.parse('https://consumer.example/app'),
        scopes: const <String>['mcp:tools', 'mcp:meta', 'mcp:tools'],
      );

      final registration = await registerMcpOAuthClient(
        authorizationServer: authorizationServer,
        registration: request,
        headers: const <String, String>{'User-Agent': 'consumer-test'},
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.headers.contentType?.mimeType, 'application/json');
      expect(
        capturedRequest.headers.value(HttpHeaders.acceptHeader),
        contains('application/json'),
      );
      expect(
        capturedRequest.headers.value(HttpHeaders.authorizationHeader),
        isNull,
      );
      expect(capturedRequest.headers.value(HttpHeaders.cookieHeader), isNull);
      expect(capturedRequest.headers.value('MCP-Session-Id'), isNull);
      expect(
        capturedRequest.headers.value(HttpHeaders.userAgentHeader),
        'consumer-test',
      );
      expect(capturedBody, <String, Object?>{
        'client_name': 'Consumer application',
        'redirect_uris': <String>[redirectUri.toString()],
        'token_endpoint_auth_method': 'none',
        'grant_types': <String>['authorization_code', 'refresh_token'],
        'response_types': <String>['code'],
        'application_type': 'native',
        'client_uri': 'https://consumer.example/app',
        'scope': 'mcp:tools mcp:meta',
      });
      expect(registration.clientId, 'dynamic-consumer-client');
      expect(registration.clientIdIssuedAt, 1774922400);
      expect(registration.redirectUris, <Uri>[redirectUri]);
      expect(registration.scopes, <String>['mcp:tools', 'mcp:meta']);
      expect(registration.clientAuthentication.clientId, registration.clientId);
      expect(registration.clientAuthentication.method, 'none');
      expect(registration.additionalParameters, <String, Object?>{
        'server_extension': 'registered',
      });
      expect(
        () => registration.redirectUris.add(endpoint),
        throwsUnsupportedError,
      );

      final authorizationRequest = registration.createAuthorizationRequest(
        resource: endpoint,
        redirectUri: redirectUri,
        pkce: McpPkcePair.fromVerifier(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
      );
      expect(
        authorizationRequest.uri.queryParameters['client_id'],
        'dynamic-consumer-client',
      );
      expect(
        authorizationRequest.uri.queryParameters['resource'],
        endpoint.toString(),
      );
      expect(
        authorizationRequest.uri.queryParameters['scope'],
        'mcp:tools mcp:meta',
      );
    });

    test('persists and restores an issuer-bound public registration', () async {
      registrationHandler = (request, body) async {
        await _writeJson(request, <String, Object?>{
          'client_id': 'durable-consumer-client',
          'client_id_issued_at': 1774922400,
          ...body,
          'server_extension': <String, Object?>{
            'mode': 'durable',
            'features': <String>['authorization', 'refresh'],
          },
        }, statusCode: HttpStatus.created);
      };
      final authorizationServer = await _discover(issuer);
      final redirectUri = Uri.parse('http://127.0.0.1:34891/callback');
      final registration = await registerMcpOAuthClient(
        authorizationServer: authorizationServer,
        registration: McpOAuthDynamicClientRegistrationRequest.publicClient(
          clientName: 'Consumer application',
          redirectUris: <Uri>[redirectUri],
          applicationType: McpOAuthClientApplicationType.native,
          clientUri: Uri.parse('https://consumer.example/app'),
          logoUri: Uri.parse('https://consumer.example/logo.png'),
          scopes: const <String>['mcp:tools', 'mcp:meta'],
        ),
      );
      final stored = (jsonDecode(jsonEncode(registration.toJson())) as Map)
          .cast<String, Object?>();

      final restored = McpOAuthDynamicClientRegistration.fromJson(
        stored,
        expectedAuthorizationServerIssuer: issuer,
      );

      expect(restored.clientId, registration.clientId);
      expect(restored.clientIdIssuedAt, registration.clientIdIssuedAt);
      expect(restored.clientName, registration.clientName);
      expect(restored.redirectUris, registration.redirectUris);
      expect(restored.applicationType, registration.applicationType);
      expect(restored.clientUri, registration.clientUri);
      expect(restored.logoUri, registration.logoUri);
      expect(restored.scopes, registration.scopes);
      expect(restored.grantTypes, registration.grantTypes);
      expect(restored.responseTypes, registration.responseTypes);
      expect(
        restored.authorizationServer.issuer,
        registration.authorizationServer.issuer,
      );
      expect(restored.additionalParameters, registration.additionalParameters);
      expect(restored.clientAuthentication.clientId, registration.clientId);
      expect(restored.clientAuthentication.method, 'none');
      expect(restored.toString(), isNot(contains(registration.clientId)));

      final authorizationRequest = restored.createAuthorizationRequest(
        resource: endpoint,
        redirectUri: redirectUri,
        pkce: McpPkcePair.fromVerifier(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
      );
      expect(
        authorizationRequest.uri.queryParameters['client_id'],
        registration.clientId,
      );
      expect(
        authorizationRequest.uri.queryParameters['resource'],
        endpoint.toString(),
      );
    });

    test(
      'rejects tampered registration state without exposing values',
      () async {
        final authorizationServer = await _discover(issuer);
        final redirectUri = Uri.parse('http://127.0.0.1:34891/callback');
        final registration = await registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: McpOAuthDynamicClientRegistrationRequest.publicClient(
            clientName: 'Consumer application',
            redirectUris: <Uri>[redirectUri],
            applicationType: McpOAuthClientApplicationType.native,
          ),
        );

        Map<String, Object?> storedCopy() {
          return (jsonDecode(jsonEncode(registration.toJson())) as Map)
              .cast<String, Object?>();
        }

        expect(
          () => McpOAuthDynamicClientRegistration.fromJson(
            storedCopy()..['version'] = 2,
          ),
          throwsA(isA<McpOAuthClientRegistrationStateException>()),
        );
        expect(
          () => McpOAuthDynamicClientRegistration.fromJson(
            storedCopy(),
            expectedAuthorizationServerIssuer: Uri.parse(
              'https://other.example/oauth',
            ),
          ),
          throwsA(isA<McpOAuthClientRegistrationStateException>()),
        );

        const leakedSecret = 'persisted-registration-secret';
        final confidential = storedCopy();
        (confidential['registration'] as Map)['client_secret'] = leakedSecret;
        expect(
          () => McpOAuthDynamicClientRegistration.fromJson(confidential),
          throwsA(
            isA<McpOAuthClientRegistrationStateException>().having(
              (error) => error.toString(),
              'redacted persisted registration',
              isNot(contains(leakedSecret)),
            ),
          ),
        );

        const leakedManagementToken = 'persisted-registration-access-token';
        final managedRegistration = storedCopy();
        (managedRegistration['registration']
                as Map)['registration_access_token'] =
            leakedManagementToken;
        expect(
          () => McpOAuthDynamicClientRegistration.fromJson(managedRegistration),
          throwsA(
            isA<McpOAuthClientRegistrationStateException>().having(
              (error) => error.toString(),
              'redacted registration access token',
              isNot(contains(leakedManagementToken)),
            ),
          ),
        );

        final nonJsonExtension = storedCopy();
        (nonJsonExtension['registration'] as Map)['server_extension'] =
            DateTime.utc(2026, 7, 31);
        expect(
          () => McpOAuthDynamicClientRegistration.fromJson(nonJsonExtension),
          throwsA(isA<McpOAuthClientRegistrationStateException>()),
        );
      },
    );

    test('allows a non-OIDC server to ignore application_type', () async {
      registrationHandler = (request, body) async {
        final registered = Map<String, Object?>.of(body)
          ..remove('application_type');
        await _writeJson(request, <String, Object?>{
          'client_id': 'dynamic-consumer-client',
          ...registered,
        }, statusCode: HttpStatus.created);
      };
      final authorizationServer = await _discover(issuer);

      final registration = await registerMcpOAuthClient(
        authorizationServer: authorizationServer,
        registration: McpOAuthDynamicClientRegistrationRequest.publicClient(
          clientName: 'Consumer application',
          redirectUris: <Uri>[Uri.parse('https://consumer.example/callback')],
          applicationType: McpOAuthClientApplicationType.web,
        ),
      );

      expect(registration.clientId, 'dynamic-consumer-client');
      expect(registration.applicationType, McpOAuthClientApplicationType.web);
    });

    test(
      'uses only the explicit initial access token and preserves MCP state',
      () async {
        late HttpRequest capturedRequest;
        registrationHandler = (request, body) async {
          capturedRequest = request;
          await _writeJson(request, <String, Object?>{
            'client_id': 'dynamic-consumer-client',
            ...body,
          }, statusCode: HttpStatus.created);
        };
        final authorizationServer = await _discover(issuer);
        final client = McpStreamableHttpClient.withBearerToken(
          endpoint,
          'active-mcp-token',
        );
        addTearDown(client.close);
        await client.initialize();
        expect(client.sessionId, 'active-session');

        final registration = await client.registerOAuthClient(
          authorizationServer,
          registration: McpOAuthDynamicClientRegistrationRequest.publicClient(
            clientName: 'Consumer application',
            redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
            applicationType: McpOAuthClientApplicationType.native,
          ),
          initialAccessToken: 'registration-access-token',
        );

        expect(registration.clientId, 'dynamic-consumer-client');
        expect(
          capturedRequest.headers.value(HttpHeaders.authorizationHeader),
          'Bearer registration-access-token',
        );
        expect(capturedRequest.headers.value('MCP-Session-Id'), isNull);
        expect(capturedRequest.headers.value('MCP-Protocol-Version'), isNull);
        expect(capturedRequest.headers.value('Last-Event-ID'), isNull);
        expect(capturedRequest.headers.value(HttpHeaders.cookieHeader), isNull);
        expect(client.sessionId, 'active-session');
        expect(client.lastEventId, isNull);
      },
    );

    test(
      'requires discovery support and validates registration inputs',
      () async {
        advertiseRegistrationEndpoint = false;
        final authorizationServer = await _discover(issuer);
        final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
          clientName: 'Consumer application',
          redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
          applicationType: McpOAuthClientApplicationType.native,
        );

        await expectLater(
          registerMcpOAuthClient(
            authorizationServer: authorizationServer,
            registration: request,
          ),
          throwsA(isA<McpOAuthClientRegistrationException>()),
        );
        expect(
          () => McpOAuthDynamicClientRegistrationRequest.publicClient(
            clientName: 'Consumer application',
            redirectUris: <Uri>[Uri.parse('custom-app:/callback')],
            applicationType: McpOAuthClientApplicationType.native,
          ),
          throwsA(isA<McpOAuthClientRegistrationException>()),
        );
        expect(
          () => McpOAuthDynamicClientRegistrationRequest.publicClient(
            clientName: 'Consumer web application',
            redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
            applicationType: McpOAuthClientApplicationType.web,
          ),
          throwsA(isA<McpOAuthClientRegistrationException>()),
        );

        advertiseRegistrationEndpoint = true;
        final supported = await _discover(issuer);
        await expectLater(
          registerMcpOAuthClient(
            authorizationServer: supported,
            registration: request,
            headers: const <String, String>{
              'Authorization': 'Bearer caller-controlled',
            },
          ),
          throwsA(isA<McpOAuthClientRegistrationException>()),
        );
        await expectLater(
          registerMcpOAuthClient(
            authorizationServer: supported,
            registration: request,
            headers: const <String, String>{'Last-Event-ID': 'resume-state'},
          ),
          throwsA(isA<McpOAuthClientRegistrationException>()),
        );
      },
    );

    test(
      'surfaces typed registration errors without credential leakage',
      () async {
        registrationHandler = (request, body) async {
          await _writeJson(request, const <String, Object?>{
            'error': 'invalid_redirect_uri',
            'error_description':
                'registration-access-token is not allowed for this redirect',
          }, statusCode: HttpStatus.badRequest);
        };
        final authorizationServer = await _discover(issuer);
        final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
          clientName: 'Consumer application',
          redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
          applicationType: McpOAuthClientApplicationType.native,
        );

        try {
          await registerMcpOAuthClient(
            authorizationServer: authorizationServer,
            registration: request,
            initialAccessToken: 'registration-access-token',
          );
          fail('registration should fail');
        } on McpOAuthClientRegistrationException catch (exception) {
          expect(exception.registrationError, 'invalid_redirect_uri');
          expect(exception.statusCode, HttpStatus.badRequest);
          expect(
            exception.toString(),
            isNot(contains('registration-access-token')),
          );
          expect(exception.toString(), isNot(contains('not allowed')));
        }
      },
    );

    test('refuses redirects and oversized registration responses', () async {
      var requestCount = 0;
      registrationHandler = (request, body) async {
        requestCount += 1;
        if (requestCount == 1) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            issuer.replace(path: '/unexpected').toString(),
          );
          await request.response.close();
          return;
        }
        await _writeJson(request, <String, Object?>{
          'client_id': 'dynamic-consumer-client',
          ...body,
          'oversized': 'x' * 256,
        }, statusCode: HttpStatus.created);
      };
      final authorizationServer = await _discover(issuer);
      final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: 'Consumer application',
        redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
        applicationType: McpOAuthClientApplicationType.native,
      );

      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
        ),
        throwsA(
          isA<McpOAuthClientRegistrationException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.found,
          ),
        ),
      );
      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
          maxResponseBytes: 128,
        ),
        throwsA(isA<McpOAuthClientRegistrationException>()),
      );
      expect(requestCount, 2);
    });

    test('rejects malformed responses and bounds registration waits', () async {
      var requestCount = 0;
      registrationHandler = (request, body) async {
        requestCount += 1;
        if (requestCount == 1) {
          request.response.statusCode = HttpStatus.created;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{');
          await request.response.close();
          return;
        }
        await Completer<void>().future;
      };
      final authorizationServer = await _discover(issuer);
      final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: 'Consumer application',
        redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
        applicationType: McpOAuthClientApplicationType.native,
      );

      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
        ),
        throwsA(
          isA<McpOAuthClientRegistrationException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.created,
          ),
        ),
      );
      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
          timeout: const Duration(milliseconds: 25),
        ),
        throwsA(
          isA<McpOAuthClientRegistrationException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(requestCount, 2);
    });

    test('rejects confidential or changed registrations', () async {
      var returnSecret = true;
      registrationHandler = (request, body) async {
        await _writeJson(request, <String, Object?>{
          'client_id': 'dynamic-consumer-client',
          ...body,
          if (returnSecret) ...<String, Object?>{
            'token_endpoint_auth_method': 'client_secret_basic',
            'client_secret': 'server-issued-secret',
            'client_secret_expires_at': 0,
          } else
            'redirect_uris': <String>['https://attacker.example/callback'],
        }, statusCode: HttpStatus.created);
      };
      final authorizationServer = await _discover(issuer);
      final request = McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: 'Consumer application',
        redirectUris: <Uri>[Uri.parse('http://localhost:34891/callback')],
        applicationType: McpOAuthClientApplicationType.native,
      );

      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
        ),
        throwsA(
          isA<McpOAuthClientRegistrationException>().having(
            (error) => error.toString(),
            'redacted error',
            isNot(contains('server-issued-secret')),
          ),
        ),
      );
      returnSecret = false;
      await expectLater(
        registerMcpOAuthClient(
          authorizationServer: authorizationServer,
          registration: request,
        ),
        throwsA(isA<McpOAuthClientRegistrationException>()),
      );
    });
  });
}

Future<McpAuthorizationServerMetadata> _discover(Uri issuer) async {
  return (await discoverMcpAuthorizationServerMetadata(issuer)).metadata;
}

Future<void> _writeJson(
  HttpRequest request,
  Map<String, Object?> body, {
  int statusCode = HttpStatus.ok,
}) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
