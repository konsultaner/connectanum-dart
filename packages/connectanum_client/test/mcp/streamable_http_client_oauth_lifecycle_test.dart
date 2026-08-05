import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _pkceVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

void main() {
  group('MCP Streamable HTTP OAuth lifecycle', () {
    test(
      'client close aborts pending OAuth helpers on a shared transport',
      () async {
        final endpoint = await _OAuthLifecycleEndpoint.bind();
        addTearDown(endpoint.close);
        final httpClient = HttpClient();
        addTearDown(() => httpClient.close(force: true));
        final authorizationServer = endpoint.authorizationServer;
        final authorizationCode = _authorizationCode(
          authorizationServer,
          endpoint.uri,
        );
        final grant = _grant(authorizationServer, endpoint.uri);
        final clientAuthentication = McpOAuthClientAuthentication.none(
          'consumer-client',
        );
        final registration =
            McpOAuthDynamicClientRegistrationRequest.publicClient(
              clientName: 'Consumer application',
              redirectUris: <Uri>[Uri.parse('http://127.0.0.1:34891/callback')],
              applicationType: McpOAuthClientApplicationType.native,
            );
        final operations =
            <
              (
                String,
                Future<void> Function(
                  McpStreamableHttpClient,
                  Map<String, String>,
                ),
              )
            >[
              (
                'protected resource discovery',
                (client, headers) async {
                  await client.discoverProtectedResourceMetadata(
                    headers: headers,
                  );
                },
              ),
              (
                'authorization server discovery',
                (client, headers) async {
                  await client.discoverAuthorizationServerMetadata(
                    endpoint.issuer,
                    headers: headers,
                  );
                },
              ),
              (
                'dynamic client registration',
                (client, headers) async {
                  await client.registerOAuthClient(
                    authorizationServer,
                    registration: registration,
                    headers: headers,
                  );
                },
              ),
              (
                'authorization code exchange',
                (client, headers) async {
                  await client.exchangeAuthorizationCode(
                    authorizationCode,
                    clientAuthentication: clientAuthentication,
                    headers: headers,
                  );
                },
              ),
              (
                'token refresh',
                (client, headers) async {
                  await client.refreshOAuthToken(
                    grant,
                    clientAuthentication: clientAuthentication,
                    headers: headers,
                  );
                },
              ),
              (
                'token revocation',
                (client, headers) async {
                  await client.revokeOAuthToken(
                    grant,
                    clientAuthentication: clientAuthentication,
                    headers: headers,
                  );
                },
              ),
            ];

        for (final (name, operation) in operations) {
          final client = McpStreamableHttpClient(
            endpoint.uri,
            httpClient: httpClient,
          );
          addTearDown(() => client.close(force: true));
          final blocked = endpoint.blockNextResponse();
          final pending = operation(client, const <String, String>{
            'x-test-block-response': '1',
          });
          await blocked;

          client.close();
          try {
            await expectLater(
              pending.timeout(const Duration(seconds: 1)),
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  contains('OAuth HTTP request was pending'),
                ),
              ),
              reason: name,
            );
          } finally {
            endpoint.releaseBlockedResponse();
          }
        }

        final replacement = McpStreamableHttpClient(
          endpoint.uri,
          httpClient: httpClient,
        );
        addTearDown(() => replacement.close(force: true));
        expect(
          await replacement.pingDirect(id: 'replacement-after-oauth-close'),
          isEmpty,
        );
      },
    );

    test('client close aborts a pending OAuth response body', () async {
      final endpoint = await _OAuthLifecycleEndpoint.bind();
      addTearDown(endpoint.close);
      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));
      final client = McpStreamableHttpClient(
        endpoint.uri,
        httpClient: httpClient,
      );
      addTearDown(() => client.close(force: true));

      final bodyStarted = endpoint.blockNextResponseBody();
      final pending = client.discoverProtectedResourceMetadata(
        headers: const <String, String>{'x-test-block-response-body': '1'},
      );
      await bodyStarted;

      client.close();
      try {
        await expectLater(
          pending.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('OAuth HTTP request was pending'),
            ),
          ),
        );
      } finally {
        endpoint.releaseBlockedResponse();
      }

      final replacement = McpStreamableHttpClient(
        endpoint.uri,
        httpClient: httpClient,
      );
      addTearDown(() => replacement.close(force: true));
      expect(
        await replacement.pingDirect(id: 'replacement-after-oauth-body'),
        isEmpty,
      );
    });
  });
}

McpAuthorizationCode _authorizationCode(
  McpAuthorizationServerMetadata authorizationServer,
  Uri resource,
) {
  final request = createMcpAuthorizationRequest(
    authorizationServer: authorizationServer,
    resource: resource,
    clientId: 'consumer-client',
    redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
    scopes: const <String>['mcp:tools'],
    pkce: McpPkcePair.fromVerifier(_pkceVerifier),
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

McpOAuthTokenGrant _grant(
  McpAuthorizationServerMetadata authorizationServer,
  Uri resource,
) {
  final issuedAt = DateTime.now().toUtc();
  final expiresAt = issuedAt.add(const Duration(hours: 1));
  return McpOAuthTokenGrant.fromJson(<String, Object?>{
    'type': 'mcp_oauth_token_grant',
    'version': 1,
    'issued_at': issuedAt.toIso8601String(),
    'expires_in': 3600,
    'expires_at': expiresAt.toIso8601String(),
    'authorization_server': authorizationServer.toJson(),
    'resource': resource.toString(),
    'client_id': 'consumer-client',
    'scopes': <String>['mcp:tools'],
    'tokens': <String, Object?>{
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'token_type': 'Bearer',
    },
  });
}

final class _OAuthLifecycleEndpoint {
  _OAuthLifecycleEndpoint._(this._server) {
    _subscription = _server.listen((request) {
      unawaited(_handle(request));
    });
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  Completer<void>? _blockedResponseSeen;
  Completer<void>? _blockedResponseRelease;
  Completer<void>? _blockedResponseBodySeen;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  Uri get issuer => uri.replace(path: '/oauth');

  McpAuthorizationServerMetadata get authorizationServer =>
      McpAuthorizationServerMetadata.fromJson(<String, Object?>{
        'issuer': issuer.toString(),
        'authorization_endpoint': issuer.replace(path: '/authorize').toString(),
        'token_endpoint': issuer.replace(path: '/token').toString(),
        'revocation_endpoint': issuer.replace(path: '/revoke').toString(),
        'registration_endpoint': issuer.replace(path: '/register').toString(),
        'response_types_supported': <String>['code'],
        'grant_types_supported': <String>[
          'authorization_code',
          'refresh_token',
        ],
        'code_challenge_methods_supported': <String>['S256'],
        'token_endpoint_auth_methods_supported': <String>['none'],
        'revocation_endpoint_auth_methods_supported': <String>['none'],
      });

  static Future<_OAuthLifecycleEndpoint> bind() async =>
      _OAuthLifecycleEndpoint._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );

  Future<void> blockNextResponse() {
    _blockedResponseSeen = Completer<void>();
    _blockedResponseRelease = Completer<void>();
    _blockedResponseBodySeen = null;
    return _blockedResponseSeen!.future;
  }

  Future<void> blockNextResponseBody() {
    _blockedResponseSeen = null;
    _blockedResponseRelease = Completer<void>();
    _blockedResponseBodySeen = Completer<void>();
    return _blockedResponseBodySeen!.future;
  }

  void releaseBlockedResponse() {
    final release = _blockedResponseRelease;
    if (release != null && !release.isCompleted) {
      release.complete();
    }
  }

  Future<void> close() async {
    releaseBlockedResponse();
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      if (request.headers.value('x-test-block-response') == '1') {
        final seen = _blockedResponseSeen;
        if (seen != null && !seen.isCompleted) {
          seen.complete();
        }
        await _blockedResponseRelease!.future;
      }
      if (request.headers.value('x-test-block-response-body') == '1') {
        final encoded = jsonEncode(<String, Object?>{
          'resource': uri.toString(),
          'authorization_servers': <String>[issuer.toString()],
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(encoded.substring(0, encoded.length ~/ 2));
        await request.response.flush();
        final seen = _blockedResponseBodySeen;
        if (seen != null && !seen.isCompleted) {
          seen.complete();
        }
        await _blockedResponseRelease!.future;
        request.response.write(encoded.substring(encoded.length ~/ 2));
        await request.response.close();
        return;
      }
      await _respond(request, body);
    } catch (_) {
      // Client-close tests intentionally abort the request before a response.
    }
  }

  Future<void> _respond(HttpRequest request, String body) async {
    if (request.method == 'GET' && request.uri.path == '/mcp') {
      await _writeJson(request, <String, Object?>{
        'resource': uri.toString(),
        'authorization_servers': <String>[issuer.toString()],
      });
      return;
    }
    if (request.method == 'GET' &&
        request.uri.path == '/.well-known/oauth-authorization-server/oauth') {
      await _writeJson(request, authorizationServer.toJson());
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/register') {
      final registration = (jsonDecode(body) as Map).cast<String, Object?>();
      await _writeJson(request, <String, Object?>{
        'client_id': 'registered-consumer-client',
        ...registration,
      }, statusCode: HttpStatus.created);
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/token') {
      await _writeJson(request, <String, Object?>{
        'access_token': 'replacement-access-token',
        'refresh_token': 'replacement-refresh-token',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'mcp:tools',
      });
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/revoke') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/mcp') {
      final rpc = (jsonDecode(body) as Map).cast<String, Object?>();
      await _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': rpc['id'],
        'result': const <String, Object?>{},
      });
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
