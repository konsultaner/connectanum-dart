import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _rfc7636Verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
const _rfc7636Challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

void main() {
  group('MCP OAuth authorization request', () {
    late HttpServer server;
    late Uri issuer;
    late McpAuthorizationServerMetadata authorizationServer;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      issuer = Uri.parse(
        'http://${server.address.address}:${server.port}/issuer',
      );
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'issuer': issuer.toString(),
            'authorization_endpoint': issuer
                .replace(
                  path: '/authorize',
                  queryParameters: const <String, Object>{
                    'tenant': <String>['consumer', 'secondary'],
                  },
                )
                .toString(),
            'token_endpoint': issuer.replace(path: '/token').toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>['authorization_code'],
            'code_challenge_methods_supported': <String>['S256'],
          }),
        );
        await request.response.close();
      });
      authorizationServer = (await discoverMcpAuthorizationServerMetadata(
        issuer,
      )).metadata;
    });

    tearDownAll(() => server.close(force: true));

    test('derives the RFC 7636 S256 challenge from a verifier', () {
      final pkce = McpPkcePair.fromVerifier(_rfc7636Verifier);

      expect(pkce.verifier, _rfc7636Verifier);
      expect(pkce.challenge, _rfc7636Challenge);
      expect(pkce.method, 'S256');
    });

    test('enforces RFC 7636 verifier length and character boundaries', () {
      expect(() => McpPkcePair.fromVerifier('a' * 43), returnsNormally);
      expect(() => McpPkcePair.fromVerifier('A' * 128), returnsNormally);
      expect(
        () => McpPkcePair.fromVerifier('a' * 42),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => McpPkcePair.fromVerifier('a' * 129),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => McpPkcePair.fromVerifier('${'a' * 42}%'),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });

    test('generates independent verifier and state values securely', () {
      final first = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final second = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );

      expect(first.pkce.verifier, hasLength(43));
      expect(first.pkce.verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(first.pkce.challenge, hasLength(43));
      expect(first.pkce.challenge, isNot(contains('=')));
      expect(first.state, hasLength(43));
      expect(first.state, isNot(second.state));
      expect(first.pkce.verifier, isNot(second.pkce.verifier));
    });

    test('builds an MCP authorization URL with resource, scope, and PKCE', () {
      final resource = issuer.replace(path: '/mcp');
      final redirect = Uri.parse(
        'http://127.0.0.1:34891/callback?application=consumer',
      );
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: resource,
        clientId: 'consumer-client',
        redirectUri: redirect,
        scopes: const <String>['mcp:tools', 'resource/read+write', 'mcp:tools'],
        pkce: McpPkcePair.fromVerifier(_rfc7636Verifier),
      );

      expect(request.uri.path, '/authorize');
      expect(request.uri.queryParametersAll['tenant'], const <String>[
        'consumer',
        'secondary',
      ]);
      expect(request.uri.queryParameters['response_type'], 'code');
      expect(request.uri.queryParameters['client_id'], 'consumer-client');
      expect(request.uri.queryParameters['redirect_uri'], redirect.toString());
      expect(request.uri.queryParameters['resource'], resource.toString());
      expect(
        request.uri.queryParameters['scope'],
        'mcp:tools resource/read+write',
      );
      expect(request.uri.queryParameters['state'], request.state);
      expect(request.uri.queryParameters['code_challenge'], _rfc7636Challenge);
      expect(request.uri.queryParameters['code_challenge_method'], 'S256');
      expect(request.scopes, const <String>[
        'mcp:tools',
        'resource/read+write',
      ]);
    });

    test('persists and restores a bounded authorization transaction', () {
      final now = DateTime.utc(2026, 7, 31, 12);
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
        scopes: const <String>['tools:read', 'prompts:read'],
        pkce: McpPkcePair.fromVerifier(_rfc7636Verifier),
      );
      final transaction = McpOAuthAuthorizationTransaction.capture(
        request,
        lifetime: const Duration(minutes: 5),
        now: now,
      );
      final stored = (jsonDecode(jsonEncode(transaction.toJson())) as Map)
          .cast<String, Object?>();

      final restoredTransaction = McpOAuthAuthorizationTransaction.fromJson(
        stored,
      );
      final restored = restoredTransaction.restore(
        now: now.add(const Duration(minutes: 4)),
      );

      expect(restoredTransaction.createdAt, now);
      expect(
        restoredTransaction.expiresAt,
        now.add(const Duration(minutes: 5)),
      );
      expect(restoredTransaction.isExpired(now: now), isFalse);
      expect(restored.uri, request.uri);
      expect(restored.authorizationServer.issuer, authorizationServer.issuer);
      expect(
        restored.authorizationServer.authorizationEndpoint,
        authorizationServer.authorizationEndpoint,
      );
      expect(restored.resource, request.resource);
      expect(restored.clientId, request.clientId);
      expect(restored.redirectUri, request.redirectUri);
      expect(restored.scopes, request.scopes);
      expect(restored.state, request.state);
      expect(restored.pkce.verifier, request.pkce.verifier);
      expect(restored.pkce.challenge, request.pkce.challenge);
      expect(restoredTransaction.toString(), isNot(contains(request.state)));
      expect(
        restoredTransaction.toString(),
        isNot(contains(request.pkce.verifier)),
      );
    });

    test('refuses expired authorization transaction restoration', () {
      final now = DateTime.utc(2026, 7, 31, 12);
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final transaction = McpOAuthAuthorizationTransaction.capture(
        request,
        lifetime: const Duration(minutes: 1),
        now: now,
      );

      expect(
        () => transaction.restore(now: now.add(const Duration(minutes: 1))),
        throwsA(isA<McpOAuthStateException>()),
      );
      expect(
        () =>
            transaction.restore(now: now.subtract(const Duration(seconds: 1))),
        throwsA(isA<McpOAuthStateException>()),
      );
      expect(
        () => McpOAuthAuthorizationTransaction.capture(
          request,
          lifetime: Duration.zero,
          now: now,
        ),
        throwsA(isA<McpOAuthStateException>()),
      );
    });

    test('rejects tampered persisted transactions without exposing state', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final transaction = McpOAuthAuthorizationTransaction.capture(request);

      Map<String, Object?> storedCopy() {
        return (jsonDecode(jsonEncode(transaction.toJson())) as Map)
            .cast<String, Object?>();
      }

      final unsupportedVersion = storedCopy()..['version'] = 2;
      expect(
        () => McpOAuthAuthorizationTransaction.fromJson(unsupportedVersion),
        throwsA(isA<McpOAuthStateException>()),
      );

      const leakedState = 'persisted-state-secret';
      final badState = storedCopy()..['state'] = leakedState;
      expect(
        () => McpOAuthAuthorizationTransaction.fromJson(badState),
        throwsA(
          isA<McpOAuthStateException>().having(
            (error) => error.toString(),
            'redacted state',
            isNot(contains(leakedState)),
          ),
        ),
      );

      const leakedVerifier = 'persisted-verifier-secret';
      final badVerifier = storedCopy()..['pkce_verifier'] = leakedVerifier;
      expect(
        () => McpOAuthAuthorizationTransaction.fromJson(badVerifier),
        throwsA(
          isA<McpOAuthStateException>().having(
            (error) => error.toString(),
            'redacted verifier',
            isNot(contains(leakedVerifier)),
          ),
        ),
      );

      final invalidLifetime = storedCopy()
        ..['expires_at'] = DateTime.utc(2020).toIso8601String();
      expect(
        () => McpOAuthAuthorizationTransaction.fromJson(invalidLifetime),
        throwsA(isA<McpOAuthStateException>()),
      );
    });

    test('rejects insecure redirect and resource identifiers', () {
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: Uri.parse('http://mcp.example.com/mcp'),
          clientId: 'consumer-client',
          redirectUri: Uri.parse('https://client.example.com/callback'),
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: Uri.parse('https://mcp.example.com/mcp'),
          clientId: 'consumer-client',
          redirectUri: Uri.parse('http://client.example.com/callback'),
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: Uri.parse('https://mcp.example.com/mcp#fragment'),
          clientId: 'consumer-client',
          redirectUri: Uri.parse('https://client.example.com/callback'),
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });

    test('rejects malformed client ids, scopes, and redirect query state', () {
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: issuer.replace(path: '/mcp'),
          clientId: ' ',
          redirectUri: Uri.parse('http://localhost:34891/callback'),
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: issuer.replace(path: '/mcp'),
          clientId: 'consumer-client',
          redirectUri: Uri.parse('http://localhost:34891/callback'),
          scopes: const <String>['mcp:tools invalid'],
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => createMcpAuthorizationRequest(
          authorizationServer: authorizationServer,
          resource: issuer.replace(path: '/mcp'),
          clientId: 'consumer-client',
          redirectUri: Uri.parse(
            'http://localhost:34891/callback?state=attacker',
          ),
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });

    test(
      'rejects controlled parameters in the authorization endpoint',
      () async {
        final collisionServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => collisionServer.close(force: true));
        final collisionIssuer = Uri.parse(
          'http://${collisionServer.address.address}:'
          '${collisionServer.port}/issuer',
        );
        collisionServer.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'issuer': collisionIssuer.toString(),
              'authorization_endpoint': collisionIssuer
                  .replace(
                    path: '/authorize',
                    queryParameters: const <String, String>{
                      'response_type': 'token',
                    },
                  )
                  .toString(),
              'token_endpoint': collisionIssuer
                  .replace(path: '/token')
                  .toString(),
              'response_types_supported': <String>['code'],
              'code_challenge_methods_supported': <String>['S256'],
            }),
          );
          await request.response.close();
        });
        final collisionMetadata = (await discoverMcpAuthorizationServerMetadata(
          collisionIssuer,
        )).metadata;

        expect(
          () => createMcpAuthorizationRequest(
            authorizationServer: collisionMetadata,
            resource: collisionIssuer.replace(path: '/mcp'),
            clientId: 'consumer-client',
            redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
          ),
          throwsA(isA<McpAuthorizationFlowException>()),
        );
      },
    );

    test('accepts a matching authorization callback', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse(
          'http://127.0.0.1:34891/callback?application=consumer',
        ),
      );
      final callback = request.redirectUri.replace(
        queryParameters: <String, String>{
          ...request.redirectUri.queryParameters,
          'code': 'authorization-code',
          'state': request.state,
        },
      );

      final code = parseMcpAuthorizationCallback(callback, request: request);

      expect(code.code, 'authorization-code');
      expect(code.request, same(request));
      expect(code.callbackUri, callback);
    });

    test('requires an advertised authorization response issuer', () {
      final issuerAwareAuthorizationServer =
          McpAuthorizationServerMetadata.fromJson(<String, Object?>{
            ...authorizationServer.toJson(),
            'authorization_response_iss_parameter_supported': true,
          });
      final request = createMcpAuthorizationRequest(
        authorizationServer: issuerAwareAuthorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final matching = request.redirectUri.replace(
        queryParameters: <String, String>{
          'code': 'authorization-code',
          'iss': issuerAwareAuthorizationServer.issuerIdentifier,
          'state': request.state,
        },
      );

      expect(
        parseMcpAuthorizationCallback(matching, request: request).code,
        'authorization-code',
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: <String, String>{
              'code': 'authorization-code',
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.message,
                'message',
                contains('issuer is required'),
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
    });

    test('validates an unadvertised response issuer when present', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final matching = request.redirectUri.replace(
        queryParameters: <String, String>{
          'code': 'authorization-code',
          'iss': authorizationServer.issuerIdentifier,
          'state': request.state,
        },
      );
      final differentlySerializedIssuer = authorizationServer.issuerIdentifier
          .replaceFirst('http:', 'HTTP:');

      expect(
        parseMcpAuthorizationCallback(matching, request: request).code,
        'authorization-code',
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: <String, String>{
              'code': 'authorization-code',
              'iss': differentlySerializedIssuer,
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.message,
                'message',
                contains('issuer does not match'),
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
    });

    test('rejects issuer mismatches before surfacing OAuth errors', () {
      final issuerAwareAuthorizationServer =
          McpAuthorizationServerMetadata.fromJson(<String, Object?>{
            ...authorizationServer.toJson(),
            'authorization_response_iss_parameter_supported': true,
          });
      final request = createMcpAuthorizationRequest(
        authorizationServer: issuerAwareAuthorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      const attackerDescription = 'attacker-controlled details';
      final callback = request.redirectUri.replace(
        queryParameters: <String, String>{
          'error': 'access_denied',
          'error_description': attackerDescription,
          'iss': 'https://attacker.example',
          'state': request.state,
        },
      );

      expect(
        () => parseMcpAuthorizationCallback(callback, request: request),
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('issuer does not match'),
                  isNot(contains(attackerDescription)),
                ),
              )
              .having((error) => error.uri, 'uri', isNull)
              .having((error) => error.oauthError, 'oauthError', isNull)
              .having(
                (error) => error.errorDescription,
                'errorDescription',
                isNull,
              )
              .having((error) => error.errorUri, 'errorUri', isNull),
        ),
      );
    });

    test('rejects mismatched state and redirect targets', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse(
          'http://127.0.0.1:34891/callback?application=consumer',
        ),
      );

      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: const <String, String>{
              'application': 'consumer',
              'code': 'authorization-code',
              'state': 'wrong-state',
            },
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            path: '/other',
            queryParameters: <String, String>{
              'application': 'consumer',
              'code': 'authorization-code',
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: <String, String>{
              'code': 'authorization-code',
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });

    test('surfaces authorization-server callback errors', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );
      final callback = request.redirectUri.replace(
        queryParameters: <String, String>{
          'error': 'access_denied',
          'error_description': 'The resource owner denied access.',
          'error_uri': 'https://auth.example.com/errors/access_denied',
          'state': request.state,
        },
      );

      expect(
        () => parseMcpAuthorizationCallback(callback, request: request),
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.oauthError,
                'oauthError',
                'access_denied',
              )
              .having(
                (error) => error.errorDescription,
                'errorDescription',
                'The resource owner denied access.',
              )
              .having(
                (error) => error.errorUri,
                'errorUri',
                Uri.parse('https://auth.example.com/errors/access_denied'),
              ),
        ),
      );

      final unsafeErrorCallback = request.redirectUri.replace(
        queryParameters: <String, String>{
          'error': 'access_denied',
          'error_uri': 'file:///tmp/oauth-error',
          'state': request.state,
        },
      );
      expect(
        () => parseMcpAuthorizationCallback(
          unsafeErrorCallback,
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });

    test('rejects ambiguous callbacks', () {
      final request = createMcpAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: issuer.replace(path: '/mcp'),
        clientId: 'consumer-client',
        redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      );

      expect(
        () => parseMcpAuthorizationCallback(
          Uri.parse(
            '${request.redirectUri}?code=one&code=two&state=${request.state}',
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => parseMcpAuthorizationCallback(
          Uri.parse(
            '${request.redirectUri}?code=authorization-code'
            '&state=${request.state}'
            '&iss=${Uri.encodeQueryComponent(authorizationServer.issuerIdentifier)}'
            '&iss=${Uri.encodeQueryComponent(authorizationServer.issuerIdentifier)}',
          ),
          request: request,
        ),
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.message,
                'message',
                contains('issuer must occur exactly once'),
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: <String, String>{
              'code': 'authorization-code',
              'error': 'access_denied',
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
      expect(
        () => parseMcpAuthorizationCallback(
          request.redirectUri.replace(
            queryParameters: <String, String>{
              'code': 'authorization-\u200bcode',
              'state': request.state,
            },
          ),
          request: request,
        ),
        throwsA(isA<McpAuthorizationFlowException>()),
      );
    });
  });
}
