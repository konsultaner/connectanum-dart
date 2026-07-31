import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

void main() {
  group('MCP OAuth token exchange', () {
    late HttpServer server;
    late Uri issuer;
    late Uri resource;
    late List<String>? authMethods;
    late FutureOr<void> Function(HttpRequest request, String body) tokenHandler;
    late McpAuthorizationServerMetadata authorizationServer;
    var tokenRequestCount = 0;

    setUp(() async {
      tokenRequestCount = 0;
      authMethods = <String>['none'];
      tokenHandler = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': 'mcp-access-token',
            'token_type': 'bearer',
            'expires_in': 900,
            'refresh_token': 'mcp-refresh-token',
            'scope': 'tools:read prompts:read',
            'issued_token_type': 'urn:example:access-token',
          }),
        );
        await request.response.close();
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      issuer = Uri.parse(
        'http://${server.address.address}:${server.port}/issuer',
      );
      resource = issuer.replace(path: '/mcp');
      server.listen((request) async {
        if (request.uri.path == '/token') {
          tokenRequestCount += 1;
          final body = await utf8.decoder.bind(request).join();
          await tokenHandler(request, body);
          return;
        }
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'issuer': issuer.toString(),
            'authorization_endpoint': issuer
                .replace(path: '/authorize')
                .toString(),
            'token_endpoint': issuer.replace(path: '/token').toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>['authorization_code'],
            'code_challenge_methods_supported': <String>['S256'],
            'token_endpoint_auth_methods_supported': ?authMethods,
          }),
        );
        await request.response.close();
      });
      authorizationServer = (await discoverMcpAuthorizationServerMetadata(
        issuer,
      )).metadata;
    });

    tearDown(() => server.close(force: true));

    test('redeems a public-client code with PKCE and MCP resource', () async {
      late HttpRequest capturedRequest;
      late Map<String, String> capturedForm;
      tokenHandler = (request, body) async {
        capturedRequest = request;
        capturedForm = Uri.splitQueryString(body);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': 'mcp-access-token',
            'token_type': 'bearer',
            'expires_in': 900,
            'refresh_token': 'mcp-refresh-token',
            'scope': 'tools:read prompts:read',
            'issued_token_type': 'urn:example:access-token',
          }),
        );
        await request.response.close();
      };
      final code = _authorizationCode(authorizationServer, resource);

      final grant = await exchangeMcpAuthorizationCode(
        code,
        clientAuthentication: McpOAuthClientAuthentication.none(
          'consumer-client',
        ),
        headers: const <String, String>{'User-Agent': 'consumer-test'},
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.headers.contentType?.mimeType,
        'application/x-www-form-urlencoded',
      );
      expect(
        capturedRequest.headers.value(HttpHeaders.acceptHeader),
        contains('application/json'),
      );
      expect(
        capturedRequest.headers.value(HttpHeaders.authorizationHeader),
        isNull,
      );
      expect(capturedRequest.headers.value('MCP-Session-Id'), isNull);
      expect(capturedRequest.headers.value(HttpHeaders.cookieHeader), isNull);
      expect(
        capturedRequest.headers.value(HttpHeaders.userAgentHeader),
        'consumer-test',
      );
      expect(capturedForm, <String, String>{
        'grant_type': 'authorization_code',
        'code': 'authorization-code',
        'redirect_uri': code.request.redirectUri.toString(),
        'client_id': 'consumer-client',
        'code_verifier': _verifier,
        'resource': resource.toString(),
      });
      expect(grant.accessToken, 'mcp-access-token');
      expect(grant.tokenType, 'Bearer');
      expect(grant.refreshToken, 'mcp-refresh-token');
      expect(grant.expiresIn, const Duration(seconds: 900));
      expect(grant.scopes, <String>['tools:read', 'prompts:read']);
      expect(grant.resource, resource);
      expect(grant.authorizationServer, authorizationServer);
      expect(grant.additionalParameters, <String, Object?>{
        'issued_token_type': 'urn:example:access-token',
      });
    });

    test(
      'supports client_secret_basic with RFC form credential encoding',
      () async {
        authMethods = <String>['client_secret_basic'];
        authorizationServer = (await discoverMcpAuthorizationServerMetadata(
          issuer,
        )).metadata;
        final code = _authorizationCode(
          authorizationServer,
          resource,
          clientId: 'consumer: client',
        );
        late String authorization;
        late Map<String, String> capturedForm;
        tokenHandler = (request, body) async {
          authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          )!;
          capturedForm = Uri.splitQueryString(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'access_token': 'mcp-access-token',
              'token_type': 'Bearer',
            }),
          );
          await request.response.close();
        };

        await exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.clientSecretBasic(
            clientId: 'consumer: client',
            clientSecret: 'secret: value',
          ),
        );

        expect(authorization, startsWith('Basic '));
        expect(
          utf8.decode(base64.decode(authorization.substring('Basic '.length))),
          'consumer%3A+client:secret%3A+value',
        );
        expect(capturedForm.containsKey('client_id'), isFalse);
        expect(capturedForm.containsKey('client_secret'), isFalse);
      },
    );

    test(
      'supports client_secret_post without an Authorization header',
      () async {
        authMethods = <String>['client_secret_post'];
        authorizationServer = (await discoverMcpAuthorizationServerMetadata(
          issuer,
        )).metadata;
        final code = _authorizationCode(authorizationServer, resource);
        late HttpRequest capturedRequest;
        late Map<String, String> capturedForm;
        tokenHandler = (request, body) async {
          capturedRequest = request;
          capturedForm = Uri.splitQueryString(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'access_token': 'mcp-access-token',
              'token_type': 'Bearer',
            }),
          );
          await request.response.close();
        };

        await exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.clientSecretPost(
            clientId: 'consumer-client',
            clientSecret: 'consumer-secret',
          ),
        );

        expect(
          capturedRequest.headers.value(HttpHeaders.authorizationHeader),
          isNull,
        );
        expect(capturedForm['client_id'], 'consumer-client');
        expect(capturedForm['client_secret'], 'consumer-secret');
      },
    );

    test(
      'rejects mismatched clients, unsupported auth, and credential headers',
      () async {
        final code = _authorizationCode(authorizationServer, resource);

        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.none(
              'other-client',
            ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication:
                McpOAuthClientAuthentication.clientSecretBasic(
                  clientId: 'consumer-client',
                  clientSecret: 'consumer-secret',
                ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.none(
              'consumer-client',
            ),
            headers: const <String, String>{
              'Authorization': 'Bearer must-not-forward',
            },
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );

        expect(tokenRequestCount, 0);
      },
    );

    test(
      'uses RFC 8414 client_secret_basic default when metadata omits auth methods',
      () async {
        authMethods = null;
        authorizationServer = (await discoverMcpAuthorizationServerMetadata(
          issuer,
        )).metadata;
        final code = _authorizationCode(authorizationServer, resource);

        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.none(
              'consumer-client',
            ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.clientSecretBasic(
            clientId: 'consumer-client',
            clientSecret: 'consumer-secret',
          ),
        );

        expect(tokenRequestCount, 1);
      },
    );

    test('surfaces typed OAuth errors without exposing secrets', () async {
      authMethods = <String>['client_secret_post'];
      authorizationServer = (await discoverMcpAuthorizationServerMetadata(
        issuer,
      )).metadata;
      final code = _authorizationCode(authorizationServer, resource);
      tokenHandler = (request, body) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'error': 'invalid_grant',
            'error_description': 'The authorization code was rejected.',
            'error_uri': issuer
                .replace(path: '/errors/invalid-grant')
                .toString(),
          }),
        );
        await request.response.close();
      };

      final future = exchangeMcpAuthorizationCode(
        code,
        clientAuthentication: McpOAuthClientAuthentication.clientSecretPost(
          clientId: 'consumer-client',
          clientSecret: 'top-secret-client-value',
        ),
      );

      await expectLater(
        future,
        throwsA(
          isA<McpOAuthTokenException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having(
                (error) => error.oauthError,
                'oauthError',
                'invalid_grant',
              )
              .having(
                (error) => error.errorDescription,
                'errorDescription',
                'The authorization code was rejected.',
              )
              .having(
                (error) => error.toString(),
                'toString',
                isNot(contains('top-secret-client-value')),
              )
              .having(
                (error) => error.toString(),
                'toString',
                isNot(contains('authorization-code')),
              ),
        ),
      );
    });

    test('rejects malformed bearer responses and oversized bodies', () async {
      final code = _authorizationCode(authorizationServer, resource);
      for (final response in <Map<String, Object?>>[
        <String, Object?>{'access_token': '', 'token_type': 'Bearer'},
        <String, Object?>{
          'access_token': 'mcp access token',
          'token_type': 'Bearer',
        },
        <String, Object?>{
          'access_token': 'mcp-access-token',
          'token_type': 'Basic',
        },
        <String, Object?>{
          'access_token': 'mcp-access-token',
          'token_type': 'Bearer',
          'expires_in': 1.5,
        },
        <String, Object?>{
          'access_token': 'mcp-access-token',
          'token_type': 'Bearer',
          'scope': 'tools:read invalid"scope',
        },
      ]) {
        tokenHandler = (request, body) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        };
        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.none(
              'consumer-client',
            ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
      }

      tokenHandler = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('x' * 256);
        await request.response.close();
      };
      await expectLater(
        exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.none(
            'consumer-client',
          ),
          maxResponseBytes: 64,
        ),
        throwsA(isA<McpOAuthTokenException>()),
      );
    });

    test('refuses token redirects and bounds token endpoint waits', () async {
      final code = _authorizationCode(authorizationServer, resource);
      tokenHandler = (request, body) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          issuer.replace(path: '/other-token'),
        );
        await request.response.close();
      };
      await expectLater(
        exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.none(
            'consumer-client',
          ),
        ),
        throwsA(isA<McpOAuthTokenException>()),
      );

      tokenHandler = (request, body) => Completer<void>().future;
      await expectLater(
        exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.none(
            'consumer-client',
          ),
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<McpOAuthTokenException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test(
      'builds an authenticated client only for the granted resource',
      () async {
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.none(
            'consumer-client',
          ),
        );

        final client = McpStreamableHttpClient.withOAuthToken(resource, grant);
        addTearDown(client.close);
        expect(client.endpoint, resource);
        expect(
          () => McpStreamableHttpClient.withOAuthToken(
            resource.replace(path: '/other-mcp'),
            grant,
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
      },
    );
  });
}

McpAuthorizationCode _authorizationCode(
  McpAuthorizationServerMetadata authorizationServer,
  Uri resource, {
  String clientId = 'consumer-client',
}) {
  final request = createMcpAuthorizationRequest(
    authorizationServer: authorizationServer,
    resource: resource,
    clientId: clientId,
    redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
    scopes: const <String>['tools:read', 'prompts:read'],
    pkce: McpPkcePair.fromVerifier(_verifier),
  );
  return parseMcpAuthorizationCallback(
    request.redirectUri.replace(
      queryParameters: <String, String>{
        'code': 'authorization-code',
        'state': request.state,
      },
    ),
    request: request,
  );
}
