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
    late List<String>? revocationAuthMethods;
    late FutureOr<void> Function(HttpRequest request, String body) tokenHandler;
    late FutureOr<void> Function(HttpRequest request, String body)
    revocationHandler;
    late McpAuthorizationServerMetadata authorizationServer;
    var tokenRequestCount = 0;
    var revocationRequestCount = 0;

    setUp(() async {
      tokenRequestCount = 0;
      revocationRequestCount = 0;
      authMethods = <String>['none'];
      revocationAuthMethods = <String>['none'];
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
      revocationHandler = (request, body) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(<int>[0xff]);
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
        if (request.uri.path == '/revoke') {
          revocationRequestCount += 1;
          final body = await utf8.decoder.bind(request).join();
          await revocationHandler(request, body);
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
            'revocation_endpoint': issuer.replace(path: '/revoke').toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>[
              'authorization_code',
              'refresh_token',
            ],
            'code_challenge_methods_supported': <String>['S256'],
            'token_endpoint_auth_methods_supported': ?authMethods,
            'revocation_endpoint_auth_methods_supported':
                ?revocationAuthMethods,
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
        clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
          clientId: 'consumer-client',
          authorizationServer: authorizationServer,
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
      'rejects unbound and mismatched pre-registered clients before exchange',
      () async {
        final code = _authorizationCode(authorizationServer, resource);
        final otherAuthorizationServer =
            McpAuthorizationServerMetadata.fromJson(
              <String, Object?>{
                ...authorizationServer.toJson(),
                'issuer': issuer.replace(path: '/other-issuer').toString(),
              },
            );

        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.none(
              'consumer-client',
            ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: otherAuthorizationServer,
            ),
          ),
          throwsA(
            isA<McpOAuthTokenException>().having(
              (error) => error.toString(),
              'redacted issuer mismatch',
              allOf(
                isNot(contains(authorizationServer.issuerIdentifier)),
                isNot(contains(otherAuthorizationServer.issuerIdentifier)),
              ),
            ),
          ),
        );

        expect(tokenRequestCount, 0);
      },
    );

    test(
      'rejects mismatched pre-registered clients before refresh and revoke',
      () async {
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );
        final otherAuthorizationServer =
            McpAuthorizationServerMetadata.fromJson(
              <String, Object?>{
                ...authorizationServer.toJson(),
                'issuer': issuer.replace(path: '/other-issuer').toString(),
              },
            );
        final mismatchedClient = McpOAuthClientAuthentication.registeredPublic(
          clientId: 'consumer-client',
          authorizationServer: otherAuthorizationServer,
        );

        await expectLater(
          refreshMcpOAuthToken(
            grant,
            clientAuthentication: mismatchedClient,
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await expectLater(
          revokeMcpOAuthToken(
            grant,
            clientAuthentication: mismatchedClient,
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );

        expect(tokenRequestCount, 1);
        expect(revocationRequestCount, 0);
      },
    );

    test(
      'never sends a confidential client secret to a mismatched issuer',
      () async {
        authMethods = <String>['client_secret_basic'];
        final otherAuthorizationServer =
            McpAuthorizationServerMetadata.fromJson(
              <String, Object?>{
                ...authorizationServer.toJson(),
                'issuer': issuer.replace(path: '/other-issuer').toString(),
                'token_endpoint_auth_methods_supported': <String>[
                  'client_secret_basic',
                ],
              },
            );
        final secret = 'must-not-cross-issuer-boundaries';

        await expectLater(
          exchangeMcpAuthorizationCode(
            _authorizationCode(authorizationServer, resource),
            clientAuthentication:
                McpOAuthClientAuthentication.clientSecretBasic(
                  clientId: 'consumer-client',
                  clientSecret: secret,
                  authorizationServer: otherAuthorizationServer,
                ),
          ),
          throwsA(
            isA<McpOAuthTokenException>().having(
              (error) => error.toString(),
              'redacted issuer mismatch',
              isNot(contains(secret)),
            ),
          ),
        );

        expect(tokenRequestCount, 0);
      },
    );

    test(
      'keeps HTTPS Client ID Metadata Document identities portable',
      () async {
        final portableClientId =
            'https://consumer.example/oauth/client-metadata.json';
        final cimdAuthorizationServer = McpAuthorizationServerMetadata.fromJson(
          <String, Object?>{
            ...authorizationServer.toJson(),
            'client_id_metadata_document_supported': true,
          },
        );

        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(
            cimdAuthorizationServer,
            resource,
            clientId: portableClientId,
          ),
          clientAuthentication: McpOAuthClientAuthentication.none(
            portableClientId,
          ),
        );

        expect(grant.clientId, portableClientId);
        expect(tokenRequestCount, 1);
      },
    );

    test('persists and restores a bound OAuth token grant', () async {
      tokenHandler = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': 'durable-access-token',
            'token_type': 'Bearer',
            'expires_in': 900,
            'refresh_token': 'durable-refresh-token',
            'scope': 'tools:read prompts:read',
            'server_extension': <String, Object?>{
              'mode': 'durable',
              'features': <String>['refresh', 'revocation'],
            },
            'client_secret': 'must-not-persist',
            'registration_access_token': 'must-not-persist-either',
          }),
        );
        await request.response.close();
      };
      final beforeExchange = DateTime.now().toUtc();
      final grant = await exchangeMcpAuthorizationCode(
        _authorizationCode(authorizationServer, resource),
        clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
          clientId: 'consumer-client',
          authorizationServer: authorizationServer,
        ),
      );
      final afterExchange = DateTime.now().toUtc();
      final stored = (jsonDecode(jsonEncode(grant.toJson())) as Map)
          .cast<String, Object?>();

      final restored = McpOAuthTokenGrant.fromJson(
        stored,
        expectedAuthorizationServerIssuer: authorizationServer.issuer,
        expectedResource: resource,
        expectedClientId: 'consumer-client',
        now: afterExchange,
      );

      expect(grant.issuedAt.isBefore(beforeExchange), isFalse);
      expect(grant.issuedAt.isAfter(afterExchange), isFalse);
      expect(grant.expiresAt, grant.issuedAt.add(const Duration(seconds: 900)));
      expect(restored.accessToken, grant.accessToken);
      expect(restored.refreshToken, grant.refreshToken);
      expect(restored.expiresIn, grant.expiresIn);
      expect(restored.issuedAt, grant.issuedAt);
      expect(restored.expiresAt, grant.expiresAt);
      expect(restored.scopes, grant.scopes);
      expect(restored.resource, grant.resource);
      expect(restored.clientId, grant.clientId);
      expect(restored.authorizationServer.issuer, authorizationServer.issuer);
      expect(restored.additionalParameters, grant.additionalParameters);
      expect(restored.additionalParameters, isNot(contains('client_secret')));
      expect(
        restored.additionalParameters,
        isNot(contains('registration_access_token')),
      );
      expect(
        restored.isAccessTokenExpired(
          now: restored.expiresAt!.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(restored.isAccessTokenExpired(now: restored.expiresAt), isTrue);
      expect(restored.toString(), isNot(contains(grant.accessToken)));
      expect(restored.toString(), isNot(contains(grant.refreshToken!)));
      expect(restored.toString(), isNot(contains(grant.clientId)));
      expect(restored.toString(), isNot(contains('durable')));
      final extension =
          restored.additionalParameters['server_extension']
              as Map<String, Object?>;
      expect(
        () => (extension['features'] as List<Object?>).add('tampered'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('persists a grant without advertised access-token expiry', () async {
      tokenHandler = (request, body) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': 'unbounded-access-token',
            'token_type': 'Bearer',
            'refresh_token': 'unbounded-refresh-token',
          }),
        );
        await request.response.close();
      };
      final grant = await exchangeMcpAuthorizationCode(
        _authorizationCode(authorizationServer, resource),
        clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
          clientId: 'consumer-client',
          authorizationServer: authorizationServer,
        ),
      );
      final stored = grant.toJson();
      final restored = McpOAuthTokenGrant.fromJson(
        (jsonDecode(jsonEncode(stored)) as Map).cast<String, Object?>(),
        expectedAuthorizationServerIssuer: authorizationServer.issuer,
        expectedResource: resource,
        expectedClientId: 'consumer-client',
      );

      expect(stored, isNot(contains('expires_in')));
      expect(stored, isNot(contains('expires_at')));
      expect(restored.expiresIn, isNull);
      expect(restored.expiresAt, isNull);
      expect(restored.isAccessTokenExpired(now: DateTime.utc(2100)), isFalse);
    });

    test(
      'rejects invalid grant state and expired bearer use redacted',
      () async {
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );

        Map<String, Object?> storedCopy() {
          return (jsonDecode(jsonEncode(grant.toJson())) as Map)
              .cast<String, Object?>();
        }

        expect(
          () => McpOAuthTokenGrant.fromJson(storedCopy()..['version'] = 2),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );
        expect(
          () => McpOAuthTokenGrant.fromJson(
            storedCopy(),
            expectedAuthorizationServerIssuer: Uri.parse(
              'https://other.example/oauth',
            ),
          ),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );
        expect(
          () => McpOAuthTokenGrant.fromJson(
            storedCopy(),
            expectedResource: resource.replace(path: '/other-mcp'),
          ),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );
        expect(
          () => McpOAuthTokenGrant.fromJson(
            storedCopy(),
            expectedClientId: 'other-client',
          ),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );

        final future = storedCopy();
        final futureIssuedAt = grant.issuedAt.add(const Duration(days: 1));
        future['issued_at'] = futureIssuedAt.toIso8601String();
        future['expires_at'] = futureIssuedAt
            .add(grant.expiresIn!)
            .toIso8601String();
        expect(
          () => McpOAuthTokenGrant.fromJson(future, now: grant.issuedAt),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );

        final inconsistentExpiry = storedCopy()
          ..['expires_at'] = grant.expiresAt!
              .add(const Duration(seconds: 1))
              .toIso8601String();
        expect(
          () => McpOAuthTokenGrant.fromJson(inconsistentExpiry),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );

        const leakedAccessToken = 'persisted-access-token-leak';
        final invalidToken = storedCopy();
        (invalidToken['tokens'] as Map)['access_token'] =
            '$leakedAccessToken\n';
        expect(
          () => McpOAuthTokenGrant.fromJson(invalidToken),
          throwsA(
            isA<McpOAuthTokenGrantStateException>().having(
              (error) => error.toString(),
              'redacted grant state',
              allOf(
                isNot(contains(leakedAccessToken)),
                isNot(contains(grant.refreshToken!)),
              ),
            ),
          ),
        );

        final nonJsonExtension = storedCopy();
        (nonJsonExtension['tokens'] as Map)['server_extension'] = DateTime.utc(
          2026,
          7,
          31,
        );
        expect(
          () => McpOAuthTokenGrant.fromJson(nonJsonExtension),
          throwsA(isA<McpOAuthTokenGrantStateException>()),
        );

        final persistedCredential = storedCopy();
        (persistedCredential['tokens'] as Map)['client_secret'] =
            'persisted-client-secret';
        expect(
          () => McpOAuthTokenGrant.fromJson(persistedCredential),
          throwsA(
            isA<McpOAuthTokenGrantStateException>().having(
              (error) => error.toString(),
              'redacted client credential',
              isNot(contains('persisted-client-secret')),
            ),
          ),
        );

        final expired = storedCopy();
        final expiredIssuedAt = DateTime.utc(2026, 7, 31, 10);
        expired['issued_at'] = expiredIssuedAt.toIso8601String();
        expired['expires_at'] = expiredIssuedAt
            .add(grant.expiresIn!)
            .toIso8601String();
        final restoredExpired = McpOAuthTokenGrant.fromJson(
          expired,
          now: expiredIssuedAt.add(const Duration(hours: 1)),
        );
        expect(
          restoredExpired.isAccessTokenExpired(
            now: expiredIssuedAt.add(const Duration(hours: 1)),
          ),
          isTrue,
        );
        expect(
          () =>
              McpStreamableHttpClient.withOAuthToken(resource, restoredExpired),
          throwsA(
            isA<McpOAuthTokenException>().having(
              (error) => error.toString(),
              'redacted expired grant',
              allOf(
                isNot(contains(restoredExpired.accessToken)),
                isNot(contains(restoredExpired.refreshToken!)),
              ),
            ),
          ),
        );
      },
    );

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
            authorizationServer: authorizationServer,
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
            authorizationServer: authorizationServer,
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
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'other-client',
              authorizationServer: authorizationServer,
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
                  authorizationServer: authorizationServer,
                ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await expectLater(
          exchangeMcpAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: authorizationServer,
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
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: authorizationServer,
            ),
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        await exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.clientSecretBasic(
            clientId: 'consumer-client',
            clientSecret: 'consumer-secret',
            authorizationServer: authorizationServer,
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
          authorizationServer: authorizationServer,
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
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: authorizationServer,
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
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
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
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        ),
        throwsA(isA<McpOAuthTokenException>()),
      );

      tokenHandler = (request, body) => Completer<void>().future;
      await expectLater(
        exchangeMcpAuthorizationCode(
          code,
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
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
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
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

    test(
      'refreshes and revokes without mutating Streamable session state',
      () async {
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );
        late HttpRequest refreshRequest;
        late Map<String, String> refreshForm;
        tokenHandler = (request, body) async {
          refreshRequest = request;
          refreshForm = Uri.splitQueryString(body);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'access_token': 'refreshed-access-token',
              'token_type': 'Bearer',
              'expires_in': 300,
              'scope': 'tools:read',
            }),
          );
          await request.response.close();
        };
        late HttpRequest revocationRequest;
        late Map<String, String> revocationForm;
        revocationHandler = (request, body) async {
          revocationRequest = request;
          revocationForm = Uri.splitQueryString(body);
          request.response.statusCode = HttpStatus.ok;
          request.response.write(<int>[0xff]);
          await request.response.close();
        };
        final client = McpStreamableHttpClient(resource)
          ..sessionId = 'active-session'
          ..lastEventId = 'active-cursor';
        addTearDown(client.close);

        final refreshed = await client.refreshOAuthToken(
          grant,
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
          scopes: const <String>['tools:read'],
          headers: const <String, String>{'x-consumer-trace': 'refresh'},
        );
        await client.revokeOAuthToken(
          refreshed,
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
          headers: const <String, String>{'x-consumer-trace': 'revoke'},
        );

        expect(refreshRequest.method, 'POST');
        expect(
          refreshRequest.headers.contentType?.mimeType,
          'application/x-www-form-urlencoded',
        );
        expect(
          refreshRequest.headers.value(HttpHeaders.authorizationHeader),
          isNull,
        );
        expect(refreshRequest.headers.value('MCP-Session-Id'), isNull);
        expect(refreshRequest.headers.value('Last-Event-ID'), isNull);
        expect(refreshRequest.headers.value('x-consumer-trace'), 'refresh');
        expect(refreshForm, <String, String>{
          'grant_type': 'refresh_token',
          'refresh_token': 'mcp-refresh-token',
          'client_id': 'consumer-client',
          'resource': resource.toString(),
          'scope': 'tools:read',
        });
        expect(refreshed.accessToken, 'refreshed-access-token');
        expect(refreshed.refreshToken, grant.refreshToken);
        expect(refreshed.expiresIn, const Duration(seconds: 300));
        expect(refreshed.scopes, <String>['tools:read']);
        expect(refreshed.resource, grant.resource);
        expect(grant.accessToken, 'mcp-access-token');
        expect(grant.scopes, <String>['tools:read', 'prompts:read']);

        expect(revocationRequest.method, 'POST');
        expect(
          revocationRequest.headers.value(HttpHeaders.authorizationHeader),
          isNull,
        );
        expect(revocationRequest.headers.value('MCP-Session-Id'), isNull);
        expect(revocationRequest.headers.value('Last-Event-ID'), isNull);
        expect(revocationRequest.headers.value('x-consumer-trace'), 'revoke');
        expect(revocationForm, <String, String>{
          'token': 'mcp-refresh-token',
          'token_type_hint': 'refresh_token',
          'client_id': 'consumer-client',
        });
        expect(tokenRequestCount, 2);
        expect(revocationRequestCount, 1);
        expect(client.sessionId, 'active-session');
        expect(client.lastEventId, 'active-cursor');
      },
    );

    test(
      'revokes an access token with the RFC 8414 default client auth method',
      () async {
        revocationAuthMethods = null;
        authorizationServer = (await discoverMcpAuthorizationServerMetadata(
          issuer,
        )).metadata;
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );
        late HttpRequest revocationRequest;
        late Map<String, String> revocationForm;
        revocationHandler = (request, body) async {
          revocationRequest = request;
          revocationForm = Uri.splitQueryString(body);
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
        };

        await revokeMcpOAuthToken(
          grant,
          tokenKind: McpOAuthTokenKind.accessToken,
          clientAuthentication: McpOAuthClientAuthentication.clientSecretBasic(
            clientId: 'consumer-client',
            clientSecret: 'consumer-secret',
            authorizationServer: authorizationServer,
          ),
        );

        expect(
          revocationRequest.headers.value(HttpHeaders.authorizationHeader),
          'Basic ${base64.encode(utf8.encode('consumer-client:consumer-secret'))}',
        );
        expect(revocationForm, <String, String>{
          'token': 'mcp-access-token',
          'token_type_hint': 'access_token',
        });
        expect(revocationRequestCount, 1);
      },
    );

    test(
      'rejects refresh scope expansion and redacts lifecycle errors',
      () async {
        final grant = await exchangeMcpAuthorizationCode(
          _authorizationCode(authorizationServer, resource),
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );

        await expectLater(
          refreshMcpOAuthToken(
            grant,
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: authorizationServer,
            ),
            scopes: const <String>['admin'],
          ),
          throwsA(isA<McpOAuthTokenException>()),
        );
        expect(tokenRequestCount, 1);

        tokenHandler = (request, body) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'access_token': 'expanded-scope-access-token',
              'token_type': 'Bearer',
              'scope': 'tools:read prompts:read',
            }),
          );
          await request.response.close();
        };
        await expectLater(
          refreshMcpOAuthToken(
            grant,
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: 'consumer-client',
              authorizationServer: authorizationServer,
            ),
            scopes: const <String>['tools:read'],
          ),
          throwsA(
            isA<McpOAuthTokenException>().having(
              (error) => error.message,
              'message',
              contains('scopes exceed'),
            ),
          ),
        );

        tokenHandler = (request, body) async {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'error': 'invalid_grant',
                'error_description': 'Refresh token is no longer valid.',
              }),
            );
          await request.response.close();
        };
        final future = refreshMcpOAuthToken(
          grant,
          clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
            clientId: 'consumer-client',
            authorizationServer: authorizationServer,
          ),
        );

        await expectLater(
          future,
          throwsA(
            isA<McpOAuthTokenException>()
                .having(
                  (error) => error.oauthError,
                  'oauthError',
                  'invalid_grant',
                )
                .having(
                  (error) => error.toString(),
                  'toString',
                  allOf(
                    isNot(contains(grant.accessToken)),
                    isNot(contains(grant.refreshToken!)),
                  ),
                ),
          ),
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
