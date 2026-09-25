import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

Future<void> _withServer(
  void Function(HttpRequest request, Uri endpoint) respond,
  Future<void> Function(Uri endpoint, List<String> paths) check,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final endpoint = Uri.parse('http://127.0.0.1:${server.port}/mcp');
  final paths = <String>[];
  server.listen((request) async {
    paths.add(request.uri.path);
    await request.drain<void>();
    respond(request, endpoint);
    await request.response.close();
  });
  try {
    await check(endpoint, paths);
  } finally {
    await server.close(force: true);
  }
}

void _resource(HttpResponse response, Uri endpoint) {
  response.headers.contentType = ContentType.json;
  response.write(
    jsonEncode({
      'resource': endpoint.toString(),
      'authorization_servers': ['https://auth.example'],
    }),
  );
}

void main() {
  for (final metadataFirst in [false, true]) {
    test(
      'metadata-bearing challenge wins metadataFirst=$metadataFirst',
      () => _withServer(
        (request, endpoint) {
          if (request.uri.path == '/mcp') {
            final selected =
                'Bearer realm="selected", scope="tools:call", '
                'resource_metadata="${endpoint.resolve('/metadata')}"';
            const other = 'Bearer realm="other", scope="tools:read"';
            request.response.statusCode = 401;
            request.response.headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              metadataFirst ? '$selected, $other' : '$other, $selected',
            );
          } else {
            _resource(request.response, endpoint);
          }
        },
        (endpoint, paths) async {
          final result = await discoverMcpProtectedResourceMetadata(endpoint);
          expect(result.challenge?.realm, 'selected');
          expect(result.challenge?.scopes, ['tools:call']);
          expect(result.metadataUri, endpoint.resolve('/metadata'));
          expect(result.metadata.resource, endpoint);
          expect(paths, ['/mcp', '/metadata']);
        },
      ),
    );
  }

  for (final scope in ['read\twrite', 'read\\write', 'read"write']) {
    test(
      'malformed challenge scope is rejected before metadata: $scope',
      () => _withServer(
        (request, endpoint) {
          if (request.uri.path == '/mcp') {
            final escaped = scope
                .replaceAll('\\', '\\\\')
                .replaceAll('"', '\\"')
                .replaceAll('\t', '\\\t');
            request.response.statusCode = 401;
            request.response.headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer scope="$escaped", resource_metadata="${endpoint.resolve('/metadata')}"',
            );
          } else {
            _resource(request.response, endpoint);
          }
        },
        (endpoint, paths) async {
          await expectLater(
            discoverMcpProtectedResourceMetadata(endpoint),
            throwsA(
              isA<McpAuthorizationDiscoveryException>().having(
                (error) => error.message,
                'message',
                contains('scope'),
              ),
            ),
          );
          expect(paths, ['/mcp']);
        },
      ),
    );
  }

  for (final status in [401, 503]) {
    test(
      'valid authorization metadata body cannot override HTTP $status',
      () => _withServer(
        (request, endpoint) {
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'issuer': endpoint.toString(),
              'authorization_endpoint': endpoint
                  .resolve('/authorize')
                  .toString(),
              'token_endpoint': endpoint.resolve('/token').toString(),
              'response_types_supported': ['code'],
              'code_challenge_methods_supported': ['S256'],
            }),
          );
        },
        (endpoint, paths) async {
          await expectLater(
            discoverMcpAuthorizationServerMetadata(endpoint),
            throwsA(
              isA<McpAuthorizationDiscoveryException>()
                  .having((error) => error.statusCode, 'status', status)
                  .having(
                    (error) => error.uri,
                    'uri',
                    endpoint.resolve('/mcp/.well-known/openid-configuration'),
                  ),
            ),
          );
          expect(paths, [
            '/.well-known/oauth-authorization-server/mcp',
            '/.well-known/openid-configuration/mcp',
            '/mcp/.well-known/openid-configuration',
          ]);
        },
      ),
    );
  }
}
