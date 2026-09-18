@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

final _resource = Uri.parse('https://consumer.example/mcp');
final _redirect = Uri.parse('http://127.0.0.1:31415/callback');
const _metadata =
    'https://consumer.example/.well-known/oauth-protected-resource';
const _scopeCharacters =
    r"!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~";
const _verifier =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';

void main() {
  for (final origin in ['previous request', 'challenge']) {
    for (final codePoint in [
      for (var code = 0; code <= 128; code++) code,
      0xa0,
      0xe4,
      0x1f680,
    ]) {
      final scope = String.fromCharCode(codePoint);
      final allowed = _scopeCharacters.contains(scope);
      test('$origin scope U+${codePoint.toRadixString(16)} is '
          '${allowed ? 'preserved' : 'rejected'}', () {
        final fixture = _Fixture();
        final challengeScope = origin == 'challenge' ? scope : 'tools:call';
        final previous = origin == 'previous request' ? [scope] : <String>[];
        if (allowed) {
          final request = _valid(
            () => fixture.request(scope: challengeScope, previous: previous),
          );
          final expected = ['tools:read', ...previous, challengeScope];
          _expectRequest(request, expected);
        } else {
          expect(
            () => fixture.request(scope: challengeScope, previous: previous),
            throwsA(isA<McpOAuthStepUpException>()),
          );
        }
        expect(fixture.http.requests, isEmpty);
      });
    }
  }

  for (final origin in ['previous request', 'challenge']) {
    test('rejects empty $origin scope', () {
      final fixture = _Fixture();
      expect(
        () => fixture.request(
          scope: origin == 'challenge' ? '' : 'tools:call',
          previous: origin == 'previous request' ? [''] : [],
        ),
        throwsA(isA<McpOAuthStepUpException>()),
      );
      expect(fixture.http.requests, isEmpty);
    });
  }

  test('scope union preserves first occurrence, case and complete tokens', () {
    final fixture = _Fixture();
    final request = _valid(
      () => fixture.request(
        previous: ['tools:read', 'Tools:Read', 'resources:read', 'Tools:Read'],
        scope: 'tools:call tools:read resources:read tools:call',
      ),
    );
    _expectRequest(request, [
      'tools:read',
      'Tools:Read',
      'resources:read',
      'tools:call',
    ]);
    expect(fixture.http.requests, isEmpty);
  });

  final metadataCases = <(String?, bool)>[
    (_metadata, true),
    ('https://other.example:8443/resource?tenant=a', true),
    ('http://localhost/resource', true),
    ('http://LOCALHOST:8080/resource', true),
    ('http://127.0.0.1:8080/resource', true),
    ('http://[::1]:8080/resource', true),
    (null, false),
    ('', false),
    ('/relative', false),
    ('//consumer.example/resource', false),
    ('https:/resource', false),
    ('https://user@consumer.example/resource', false),
    ('https://user:password@consumer.example/resource', false),
    ('$_metadata#fragment', false),
    ('$_metadata#', false),
    ('http://consumer.example/resource', false),
    ('http://192.0.2.1/resource', false),
    ('http://[2001:db8::1]/resource', false),
    ('http://localhost.example/resource', false),
    ('ftp://localhost/resource', false),
    ('file:///resource', false),
    ('ws://localhost/resource', false),
  ];
  for (var i = 0; i < metadataCases.length; i++) {
    final (metadata, allowed) = metadataCases[i];
    test('metadata URI $i is ${allowed ? 'accepted' : 'rejected'}', () {
      final fixture = _Fixture();
      if (allowed) {
        final request = _valid(() => fixture.request(metadata: metadata));
        _expectRequest(request, ['tools:read', 'tools:call']);
      } else {
        expect(
          () => fixture.request(metadata: metadata),
          throwsA(isA<McpOAuthStepUpException>()),
        );
      }
      expect(fixture.http.requests, isEmpty);
    });
  }
}

void _expectRequest(McpAuthorizationRequest request, List<String> scopes) {
  expect(request.scopes, scopes);
  expect(request.resource, _resource);
  expect(request.clientId, 'step-up-test');
  expect(request.redirectUri, _redirect);
  expect(request.authorizationServer.issuer, Uri.parse('https://auth.example'));
  expect(request.uri.queryParameters['scope'], scopes.join(' '));
  expect(request.uri.queryParameters['resource'], _resource.toString());
  expect(request.uri.queryParameters['client_id'], 'step-up-test');
  expect(request.uri.queryParameters['redirect_uri'], _redirect.toString());
  expect(request.pkce.verifier, _verifier);
  expect(request.uri.queryParameters['code_challenge'], request.pkce.challenge);
  expect(request.uri.queryParameters['code_challenge_method'], 'S256');
}

T _valid<T>(T Function() construct) {
  late T value;
  expect(() => value = construct(), returnsNormally);
  return value;
}

final class _Fixture {
  _Fixture() {
    client = McpStreamableHttpClient(
      _resource,
      httpClient: http,
      closeHttpClient: true,
    );
    addTearDown(client.close);
  }

  final http = _NoNetworkClient();
  late final McpStreamableHttpClient client;
  final grant = _valid(
    () => McpOAuthTokenGrant.fromJson({
      'type': 'mcp_oauth_token_grant',
      'version': 1,
      'issued_at': '2026-01-01T00:00:00Z',
      'authorization_server': {
        'issuer': 'https://auth.example',
        'authorization_endpoint': 'https://auth.example/authorize',
        'token_endpoint': 'https://auth.example/token',
        'response_types_supported': ['code'],
        'code_challenge_methods_supported': ['S256'],
      },
      'resource': _resource.toString(),
      'client_id': 'step-up-test',
      'scopes': ['tools:read'],
      'tokens': {'access_token': 'test-token', 'token_type': 'Bearer'},
    }, now: DateTime.utc(2026, 1, 2)),
  );

  McpAuthorizationRequest request({
    String scope = 'tools:call',
    List<String> previous = const [],
    String? metadata = _metadata,
  }) => client.createStepUpAuthorizationRequest(
    currentGrant: grant,
    authorizationFailure: McpStreamableHttpException(
      statusCode: HttpStatus.forbidden,
      reasonPhrase: 'Forbidden',
      body: '',
      bearerChallenges: [
        McpBearerChallenge({
          'error': 'insufficient_scope',
          'scope': scope,
          'resource_metadata': ?metadata,
        }),
      ],
    ),
    redirectUri: _redirect,
    previouslyRequestedScopes: previous,
    pkce: McpPkcePair.fromVerifier(_verifier),
  );
}

final class _NoNetworkClient implements HttpClient {
  final requests = <Invocation>[];

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    requests.add(invocation);
    throw StateError('Step-up request construction must not perform HTTP I/O');
  }
}
