import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:test/test.dart';

const _clientId = 'https://consumer.example/oauth/client-metadata.json';

void main() {
  test('IO entrypoint exposes the OAuth dynamic-registration flow', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/mcp',
    );
    final issuer = endpoint.replace(path: '/tenant');
    var registrationRequestCount = 0;
    var tokenRequestCount = 0;
    var revocationRequestCount = 0;

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
            'registration_endpoint': issuer
                .replace(path: '/register')
                .toString(),
            'revocation_endpoint': issuer.replace(path: '/revoke').toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>[
              'authorization_code',
              'refresh_token',
            ],
            'code_challenge_methods_supported': <String>['S256'],
            'token_endpoint_auth_methods_supported': <String>['none'],
            'revocation_endpoint_auth_methods_supported': <String>['none'],
            'client_id_metadata_document_supported': true,
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/register') {
        registrationRequestCount += 1;
        expect(request.method, 'POST');
        expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
        expect(request.headers.value('mcp-session-id'), isNull);
        expect(request.headers.value('mcp-protocol-version'), isNull);
        expect(request.headers.value('x-consumer-trace'), 'registration');
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        expect(body['client_name'], 'Consumer application');
        expect(body['redirect_uris'], <String>[
          'http://127.0.0.1:34891/callback',
        ]);
        expect(body['token_endpoint_auth_method'], 'none');
        expect(body['application_type'], 'native');
        expect(body['scope'], 'tools:read');
        request.response.statusCode = HttpStatus.created;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            ...body,
            'client_id': _clientId,
            'client_id_issued_at': 1785436800,
            'server_extension': 'preserved',
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/token') {
        tokenRequestCount += 1;
        expect(request.method, 'POST');
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['client_id'], _clientId);
        expect(form['resource'], endpoint.toString());
        if (form['grant_type'] == 'authorization_code') {
          expect(form['code_verifier'], isNotEmpty);
        } else {
          expect(form['grant_type'], 'refresh_token');
          expect(form['refresh_token'], 'consumer-refresh-token');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'access_token': tokenRequestCount == 1
                ? 'consumer-access-token'
                : 'consumer-refreshed-access-token',
            'token_type': 'Bearer',
            'scope': 'tools:read',
            if (tokenRequestCount == 1)
              'refresh_token': 'consumer-refresh-token',
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/revoke') {
        revocationRequestCount += 1;
        expect(request.method, 'POST');
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['token'], 'consumer-refresh-token');
        expect(form['token_type_hint'], 'refresh_token');
        request.response.statusCode = HttpStatus.ok;
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
    expect(
      authorizationServer.metadata.registrationEndpoint?.path,
      '/register',
    );

    final redirectUri = Uri.parse('http://127.0.0.1:34891/callback');
    final registration = await client.registerOAuthClient(
      authorizationServer.metadata,
      registration: McpOAuthDynamicClientRegistrationRequest.publicClient(
        clientName: 'Consumer application',
        redirectUris: <Uri>[redirectUri],
        applicationType: McpOAuthClientApplicationType.native,
        scopes: discovery.requiredScopes,
      ),
      headers: const <String, String>{'x-consumer-trace': 'registration'},
    );
    final authorizationRequest = registration.createAuthorizationRequest(
      resource: endpoint,
      redirectUri: redirectUri,
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

    expect(registration.clientId, _clientId);
    expect(registration.clientIdIssuedAt, 1785436800);
    expect(registration.additionalParameters['server_extension'], 'preserved');
    expect(
      authorizationRequest.uri.queryParameters['resource'],
      endpoint.toString(),
    );
    expect(authorizationRequest.uri.queryParameters['scope'], 'tools:read');
    expect(authorizationCode.code, 'authorization-code');
    final grant = await client.exchangeAuthorizationCode(
      authorizationCode,
      clientAuthentication: registration.clientAuthentication,
    );
    final authenticatedClient = McpStreamableHttpClient.withOAuthToken(
      endpoint,
      grant,
    );
    addTearDown(authenticatedClient.close);
    expect(grant.accessToken, 'consumer-access-token');
    expect(grant.refreshToken, 'consumer-refresh-token');
    expect(grant.scopes, <String>['tools:read']);
    expect(authenticatedClient.endpoint, endpoint);
    final refreshed = await client.refreshOAuthToken(
      grant,
      clientAuthentication: registration.clientAuthentication,
    );
    expect(refreshed.accessToken, 'consumer-refreshed-access-token');
    expect(refreshed.refreshToken, grant.refreshToken);
    await client.revokeOAuthToken(
      refreshed,
      clientAuthentication: registration.clientAuthentication,
    );
    expect(registrationRequestCount, 1);
    expect(tokenRequestCount, 2);
    expect(revocationRequestCount, 1);
    expect(client.sessionId, isNull);
  });
}
