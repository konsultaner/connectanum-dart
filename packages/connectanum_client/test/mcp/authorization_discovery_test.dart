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
