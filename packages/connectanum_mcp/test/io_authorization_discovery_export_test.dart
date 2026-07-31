import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test('IO entrypoint exposes the OAuth authorization-code flow', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/mcp',
    );
    final issuer = endpoint.replace(path: '/tenant');

    server.listen((request) async {
      if (request.uri.path ==
          '/.well-known/oauth-authorization-server/tenant') {
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
            'code_challenge_methods_supported': <String>['S256'],
            'token_endpoint_auth_methods_supported': <String>['none'],
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/token') {
        expect(request.method, 'POST');
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['resource'], endpoint.toString());
        expect(form['code_verifier'], isNotEmpty);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': 'consumer-access-token',
            'token_type': 'Bearer',
            'scope': 'tools:read',
          }),
        );
        await request.response.close();
        return;
      }
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'resource': endpoint.toString(),
          'authorization_servers': <String>[issuer.toString()],
          'scopes_supported': <String>['tools:read'],
        }),
      );
      await request.response.close();
    });

    final client = McpStreamableHttpClient(endpoint);
    addTearDown(client.close);
    final discovery = await client.discoverProtectedResourceMetadata();
    final authorizationServer = await client
        .discoverAuthorizationServerMetadata(
          discovery.metadata.authorizationServers.single,
        );

    expect(discovery.metadata.resource, endpoint);
    expect(discovery.requiredScopes, <String>['tools:read']);
    expect(authorizationServer.metadata.issuer, issuer);
    expect(
      authorizationServer.metadata.authorizationEndpoint.path,
      '/authorize',
    );
    expect(authorizationServer.metadata.tokenEndpoint.path, '/token');

    final authorizationRequest = client.createAuthorizationRequest(
      authorizationServer: authorizationServer.metadata,
      clientId: 'consumer-client',
      redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
      scopes: discovery.requiredScopes,
      pkce: McpPkcePair.fromVerifier(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      ),
    );
    final callback = authorizationRequest.redirectUri.replace(
      queryParameters: <String, String>{
        'code': 'authorization-code',
        'state': authorizationRequest.state,
      },
    );
    final authorizationCode = parseMcpAuthorizationCallback(
      callback,
      request: authorizationRequest,
    );

    expect(
      authorizationRequest.uri.queryParameters['resource'],
      endpoint.toString(),
    );
    expect(authorizationRequest.uri.queryParameters['scope'], 'tools:read');
    expect(authorizationCode.code, 'authorization-code');
    final grant = await client.exchangeAuthorizationCode(
      authorizationCode,
      clientAuthentication: McpOAuthClientAuthentication.none(
        'consumer-client',
      ),
    );
    final authenticatedClient = McpStreamableHttpClient.withOAuthToken(
      endpoint,
      grant,
    );
    addTearDown(authenticatedClient.close);
    expect(grant.accessToken, 'consumer-access-token');
    expect(grant.scopes, <String>['tools:read']);
    expect(authenticatedClient.endpoint, endpoint);
    expect(client.sessionId, isNull);
  });
}
