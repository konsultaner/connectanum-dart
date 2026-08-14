import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

void main() {
  group('MCP OAuth Client ID Metadata Document', () {
    late HttpServer server;
    late McpAuthorizationServerMetadata authorizationServer;

    setUpAll(() async {
      final fixture = await _authorizationServer(metadataDocument: true);
      server = fixture.server;
      authorizationServer = fixture.metadata;
    });

    tearDownAll(() => server.close(force: true));

    test('emits immutable public-client metadata without credentials', () {
      final clientId = Uri.parse(
        'https://consumer.example/oauth/client-metadata.json',
      );
      final redirect = Uri.parse('http://127.0.0.1:34891/callback');
      final document = McpOAuthClientMetadataDocument.publicClient(
        clientId: clientId,
        clientName: 'Consumer application',
        redirectUris: <Uri>[redirect],
        clientUri: Uri.parse('https://consumer.example/application'),
        logoUri: Uri.parse('https://consumer.example/application/logo.png'),
        scopes: const <String>['mcp:tools', 'resource/read', 'mcp:tools'],
      );

      expect(document.clientId, clientId);
      expect(document.clientAuthentication.clientId, clientId.toString());
      expect(document.clientAuthentication.method, 'none');
      expect(document.requestsRefreshTokens, isTrue);
      expect(document.toJson(), <String, Object?>{
        'client_id': clientId.toString(),
        'client_name': 'Consumer application',
        'redirect_uris': <String>[redirect.toString()],
        'token_endpoint_auth_method': 'none',
        'grant_types': <String>['authorization_code', 'refresh_token'],
        'response_types': <String>['code'],
        'client_uri': 'https://consumer.example/application',
        'logo_uri': 'https://consumer.example/application/logo.png',
        'scope': 'mcp:tools resource/read',
      });
      expect(
        () => document.redirectUris.add(
          Uri.parse('https://consumer.example/other'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => document.scopes.add('resource/write'),
        throwsUnsupportedError,
      );
      expect(
        () => (document.toJson()['grant_types']! as List<String>).add(
          'client_credentials',
        ),
        throwsUnsupportedError,
      );
      final roundTripped = (jsonDecode(jsonEncode(document.toJson())) as Map)
          .cast<String, Object?>();
      expect(roundTripped['grant_types'], <Object?>[
        'authorization_code',
        'refresh_token',
      ]);
      expect(document.toJson().keys, isNot(contains('client_secret')));
    });

    test('can opt out of refresh-token grant advertisement', () {
      final document = McpOAuthClientMetadataDocument.publicClient(
        clientId: Uri.parse(
          'https://consumer.example/oauth/client-metadata.json',
        ),
        clientName: 'Consumer application',
        redirectUris: <Uri>[
          Uri.parse('http://127.0.0.1:34891/callback'),
        ],
        requestRefreshTokens: false,
      );

      expect(document.requestsRefreshTokens, isFalse);
      expect(document.toJson()['grant_types'], <String>['authorization_code']);
    });

    test('creates an authorization request with exact registered identity', () {
      final clientId = Uri.parse(
        'https://consumer.example/oauth/client-metadata.json',
      );
      final redirect = Uri.parse('http://localhost:34891/callback');
      final resource = Uri.parse('https://router.example/mcp');
      final document = McpOAuthClientMetadataDocument.publicClient(
        clientId: clientId,
        clientName: 'Consumer application',
        redirectUris: <Uri>[redirect],
        scopes: const <String>['mcp:tools'],
      );

      final request = document.createAuthorizationRequest(
        authorizationServer: authorizationServer,
        resource: resource,
        redirectUri: redirect,
        pkce: McpPkcePair.fromVerifier(_verifier),
      );

      expect(request.clientId, clientId.toString());
      expect(request.redirectUri, redirect);
      expect(request.resource, resource);
      expect(request.scopes, const <String>['mcp:tools']);
      expect(request.uri.queryParameters['client_id'], clientId.toString());
      expect(request.uri.queryParameters['redirect_uri'], redirect.toString());
    });

    test(
      'requires advertised public-client support and exact redirect',
      () async {
        final unsupported = await _authorizationServer(metadataDocument: false);
        addTearDown(() => unsupported.server.close(force: true));
        final confidentialOnly = await _authorizationServer(
          metadataDocument: true,
          tokenEndpointAuthMethods: const <String>['client_secret_basic'],
        );
        addTearDown(() => confidentialOnly.server.close(force: true));
        final document = McpOAuthClientMetadataDocument.publicClient(
          clientId: Uri.parse(
            'https://consumer.example/oauth/client-metadata.json',
          ),
          clientName: 'Consumer application',
          redirectUris: <Uri>[Uri.parse('http://127.0.0.1:34891/callback')],
        );

        expect(
          () => document.createAuthorizationRequest(
            authorizationServer: unsupported.metadata,
            resource: Uri.parse('https://router.example/mcp'),
            redirectUri: document.redirectUris.single,
          ),
          throwsA(isA<McpOAuthClientMetadataException>()),
        );
        expect(
          () => document.createAuthorizationRequest(
            authorizationServer: confidentialOnly.metadata,
            resource: Uri.parse('https://router.example/mcp'),
            redirectUri: document.redirectUris.single,
          ),
          throwsA(isA<McpOAuthClientMetadataException>()),
        );
        expect(
          () => document.createAuthorizationRequest(
            authorizationServer: authorizationServer,
            resource: Uri.parse('https://router.example/mcp'),
            redirectUri: Uri.parse('http://127.0.0.1:34892/callback'),
          ),
          throwsA(isA<McpOAuthClientMetadataException>()),
        );
      },
    );

    test('rejects unsafe identifiers and malformed public metadata', () {
      final validRedirect = Uri.parse('http://[::1]:34891/callback');
      final invalidClientIds = <Uri>[
        Uri.parse('http://consumer.example/oauth/client.json'),
        Uri.parse('https://consumer.example/'),
        Uri.parse('https://user@consumer.example/oauth/client.json'),
        Uri.parse('https://consumer.example/oauth/client.json?version=1'),
        Uri.parse('https://consumer.example/oauth/client.json#fragment'),
      ];
      for (final clientId in invalidClientIds) {
        expect(
          () => McpOAuthClientMetadataDocument.publicClient(
            clientId: clientId,
            clientName: 'Consumer application',
            redirectUris: <Uri>[validRedirect],
          ),
          throwsA(isA<McpOAuthClientMetadataException>()),
          reason: clientId.toString(),
        );
      }

      expect(
        () => McpOAuthClientMetadataDocument.publicClient(
          clientId: Uri.parse(
            'https://consumer.example/oauth/client-metadata.json',
          ),
          clientName: 'Consumer\napplication',
          redirectUris: <Uri>[validRedirect],
        ),
        throwsA(isA<McpOAuthClientMetadataException>()),
      );
      expect(
        () => McpOAuthClientMetadataDocument.publicClient(
          clientId: Uri.parse(
            'https://consumer.example/oauth/client-metadata.json',
          ),
          clientName: 'Consumer application',
          redirectUris: <Uri>[Uri.parse('http://consumer.example/callback')],
        ),
        throwsA(isA<McpOAuthClientMetadataException>()),
      );
      expect(
        () => McpOAuthClientMetadataDocument.publicClient(
          clientId: Uri.parse(
            'https://consumer.example/oauth/client-metadata.json',
          ),
          clientName: 'Consumer application',
          redirectUris: <Uri>[validRedirect, validRedirect],
        ),
        throwsA(isA<McpOAuthClientMetadataException>()),
      );
    });
  });
}

Future<({HttpServer server, McpAuthorizationServerMetadata metadata})>
_authorizationServer({
  required bool metadataDocument,
  List<String> tokenEndpointAuthMethods = const <String>['none'],
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final issuer = Uri.parse(
    'http://${server.address.address}:${server.port}/issuer',
  );
  server.listen((request) async {
    await request.drain<void>();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'issuer': issuer.toString(),
        'authorization_endpoint': issuer.replace(path: '/authorize').toString(),
        'token_endpoint': issuer.replace(path: '/token').toString(),
        'response_types_supported': <String>['code'],
        'grant_types_supported': <String>['authorization_code'],
        'code_challenge_methods_supported': <String>['S256'],
        'token_endpoint_auth_methods_supported': tokenEndpointAuthMethods,
        'client_id_metadata_document_supported': metadataDocument,
      }),
    );
    await request.response.close();
  });
  final metadata = (await discoverMcpAuthorizationServerMetadata(
    issuer,
  )).metadata;
  return (server: server, metadata: metadata);
}
