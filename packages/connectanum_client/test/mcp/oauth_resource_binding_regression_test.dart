@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _clientId = 'resource-binding-test';
const _verifier =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';

void main() {
  final resource = Uri.parse(
    'https://consumer.example:8443/mcp?tenant=a&view=full',
  );
  final mismatches = <String, Uri>{
    'scheme': resource.replace(scheme: 'http'),
    'host': resource.replace(host: 'other.example'),
    'port': resource.replace(port: 8444),
    'path case': resource.replace(path: '/MCP'),
    'path suffix': resource.replace(path: '/mcp/'),
    'query value': resource.replace(query: 'tenant=b&view=full'),
    'query order': resource.replace(query: 'view=full&tenant=a'),
    'missing query': resource.replace(query: ''),
    'user name': resource.replace(userInfo: 'other'),
    'user password': resource.replace(userInfo: 'other:password'),
    'fragment': resource.replace(fragment: 'other'),
    'empty fragment': resource.replace(fragment: ''),
  };
  for (final entry in mismatches.entries) {
    test('rejects mismatched ${entry.key} before any token request', () async {
      final server = await _TokenEndpoint.bind();
      addTearDown(server.close);
      final http = _RecordingClient(HttpClient());
      final client = _valid(
        () => McpStreamableHttpClient(
          entry.value,
          httpClient: http,
          closeHttpClient: true,
        ),
      );
      addTearDown(client.close);
      final code = _authorizationCode(server.metadata, resource);
      final authentication = McpOAuthClientAuthentication.registeredPublic(
        clientId: _clientId,
        authorizationServer: server.metadata,
      );

      await expectLater(
        () => client.exchangeAuthorizationCode(
          code,
          clientAuthentication: authentication,
        ),
        throwsA(
          isA<McpOAuthTokenException>().having(
            (error) => error.endpoint,
            'rejected resource',
            entry.value,
          ),
        ),
      );
      expect(http.posts, isEmpty);
      expect(server.forms, isEmpty);
    });
  }

  final equivalentResources = <(String, Uri, Uri)>[
    ('identical query and port', resource, resource),
    (
      'scheme and host case',
      Uri.parse('HTTPS://CONSUMER.EXAMPLE/mcp'),
      Uri.parse('https://consumer.example/mcp'),
    ),
    (
      'explicit default port',
      Uri.parse('https://consumer.example/mcp'),
      Uri.parse('https://consumer.example:443/mcp'),
    ),
    (
      'implicit default port',
      Uri.parse('https://consumer.example:443/mcp'),
      Uri.parse('https://consumer.example/mcp'),
    ),
  ];
  for (final (name, expected, endpoint) in equivalentResources) {
    test('matching resource $name exchanges exact code and grant', () async {
      final server = await _TokenEndpoint.bind();
      addTearDown(server.close);
      final http = _RecordingClient(HttpClient());
      final client = _valid(
        () => McpStreamableHttpClient(
          endpoint,
          httpClient: http,
          closeHttpClient: true,
        ),
      );
      addTearDown(client.close);
      final code = _authorizationCode(server.metadata, expected);
      await expectLater(
        Future<McpOAuthTokenGrant>.sync(
          () => client.exchangeAuthorizationCode(
            code,
            clientAuthentication: McpOAuthClientAuthentication.registeredPublic(
              clientId: _clientId,
              authorizationServer: server.metadata,
            ),
          ),
        ),
        completion(
          isA<McpOAuthTokenGrant>()
              .having(
                (grant) => grant.accessToken,
                'token',
                'test-access-token',
              )
              .having((grant) => grant.tokenType, 'type', 'Bearer')
              .having((grant) => grant.resource, 'resource', expected)
              .having((grant) => grant.clientId, 'client', _clientId)
              .having((grant) => grant.scopes, 'scopes', ['mcp:tools']),
        ),
      );
      expect(http.posts, [server.uri.replace(path: '/token')]);
      expect(server.forms, [
        {
          'grant_type': 'authorization_code',
          'code': 'test-authorization-code',
          'redirect_uri': code.request.redirectUri.toString(),
          'code_verifier': _verifier,
          'client_id': _clientId,
          'resource': expected.toString(),
        },
      ]);
    });
  }
}

T _valid<T>(T Function() construct) {
  late T value;
  expect(() => value = construct(), returnsNormally);
  return value;
}

McpAuthorizationCode _authorizationCode(
  McpAuthorizationServerMetadata metadata,
  Uri resource,
) {
  final request = _valid(
    () => createMcpAuthorizationRequest(
      authorizationServer: metadata,
      resource: resource,
      clientId: _clientId,
      redirectUri: Uri.parse('http://127.0.0.1:31415/callback'),
      scopes: ['mcp:tools'],
      pkce: McpPkcePair.fromVerifier(_verifier),
    ),
  );
  return _valid(
    () => parseMcpAuthorizationCallback(
      request.redirectUri.replace(
        queryParameters: {
          'code': 'test-authorization-code',
          'state': request.state,
        },
      ),
      request: request,
    ),
  );
}

final class _RecordingClient implements HttpClient {
  _RecordingClient(this.delegate);
  final HttpClient delegate;
  final posts = <Uri>[];

  @override
  Future<HttpClientRequest> postUrl(Uri uri) {
    posts.add(uri);
    return delegate.postUrl(uri);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TokenEndpoint {
  _TokenEndpoint(this.server) {
    server.listen((request) async {
      final form = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      forms.add(form);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'access_token': 'test-access-token',
          'token_type': 'Bearer',
          'scope': 'mcp:tools',
        }),
      );
      await request.response.close();
    });
  }

  final HttpServer server;
  final forms = <Map<String, String>>[];
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}');
  McpAuthorizationServerMetadata get metadata => _valid(
    () => McpAuthorizationServerMetadata.fromJson({
      'issuer': uri.toString(),
      'authorization_endpoint': uri.replace(path: '/authorize').toString(),
      'token_endpoint': uri.replace(path: '/token').toString(),
      'response_types_supported': ['code'],
      'grant_types_supported': ['authorization_code'],
      'code_challenge_methods_supported': ['S256'],
      'token_endpoint_auth_methods_supported': ['none'],
    }),
  );

  static Future<_TokenEndpoint> bind() async =>
      _TokenEndpoint(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> close() => server.close(force: true);
}
