import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test('IO entrypoint exposes both authorization discovery stages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/mcp',
    );
    final issuer = endpoint.replace(path: '/tenant');

    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path ==
          '/.well-known/oauth-authorization-server/tenant') {
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
          }),
        );
        await request.response.close();
        return;
      }
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
  });
}
