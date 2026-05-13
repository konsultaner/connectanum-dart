import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart' show CraAuthentication;
import 'package:connectanum_router/src/router/auth/http_auth_provider.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    HttpAuthProviderRegistry.clear();
    registerDefaultHttpAuthProviders();
  });

  test('registers default HTTP auth provider factories', () {
    expect(HttpAuthProviderRegistry.factoryFor('jwt'), isNotNull);
    expect(HttpAuthProviderRegistry.factoryFor('oidc'), isNotNull);
    expect(HttpAuthProviderRegistry.factoryFor('oauth'), isNotNull);
  });

  test('jwt provider authenticates HS256 bearer tokens', () async {
    final provider = await HttpAuthProviderRegistry.factoryFor('jwt')!.create({
      'name': 'edge-jwt',
      'hmac_secret': 'jwt-secret',
      'issuer': 'https://issuer.example',
      'audience': const ['connectanum-http'],
      'auth_id_claim': 'sub',
      'auth_role_claim': 'role',
    });

    final result = await provider.authenticate(
      _request(
        token: _encodeHs256Jwt(
          secret: 'jwt-secret',
          claims: <String, Object?>{
            'sub': 'jwt-user',
            'role': 'member',
            'iss': 'https://issuer.example',
            'aud': const ['connectanum-http'],
            'exp': _futureEpochSeconds(),
          },
        ),
      ),
    );

    expect(result.success, isTrue);
    final authenticated = result.authenticated!;
    expect(authenticated.authId, 'jwt-user');
    expect(authenticated.authRole, 'member');
    expect(authenticated.authMethod, 'jwt');
    expect(authenticated.authProvider, 'edge-jwt');
    expect(authenticated.details['authprovider'], 'edge-jwt');
  });

  test('jwt provider rejects invalid signatures', () async {
    final provider = await HttpAuthProviderRegistry.factoryFor(
      'jwt',
    )!.create({'name': 'edge-jwt', 'hmac_secret': 'jwt-secret'});

    final result = await provider.authenticate(
      _request(
        token: _encodeHs256Jwt(
          secret: 'wrong-secret',
          claims: <String, Object?>{
            'sub': 'jwt-user',
            'exp': _futureEpochSeconds(),
          },
        ),
      ),
    );

    expect(result.success, isFalse);
    expect(result.failure!.reason, 'invalid_token');
  });

  test('jwt provider rejects unsupported algorithms', () async {
    final provider = await HttpAuthProviderRegistry.factoryFor('jwt')!.create({
      'name': 'edge-jwt',
      'algorithm': 'RS256',
      'hmac_secret': 'jwt-secret',
    });

    final result = await provider.authenticate(
      _request(
        token: _encodeHs256Jwt(
          secret: 'jwt-secret',
          claims: <String, Object?>{
            'sub': 'jwt-user',
            'exp': _futureEpochSeconds(),
          },
        ),
      ),
    );

    expect(result.success, isFalse);
    expect(result.failure!.reason, 'unsupported_alg');
  });

  test(
    'oidc provider maps scopes to roles when role claim is absent',
    () async {
      final provider = await HttpAuthProviderRegistry.factoryFor('oidc')!
          .create({
            'name': 'oidc-provider',
            'hmac_secret': 'jwt-secret',
            'scope_role_map': const {'admin': 'admin-role'},
            'roles_claim': 'roles',
          });

      final result = await provider.authenticate(
        _request(
          token: _encodeHs256Jwt(
            secret: 'jwt-secret',
            claims: <String, Object?>{
              'sub': 'oidc-user',
              'scope': 'openid admin',
              'roles': const ['api-user'],
              'exp': _futureEpochSeconds(),
            },
          ),
        ),
      );

      expect(result.success, isTrue);
      final authenticated = result.authenticated!;
      expect(authenticated.authMethod, 'oidc');
      expect(authenticated.authRole, 'admin-role');
      expect(
        authenticated.roles.keys,
        containsAll(<String>['api-user', 'admin-role']),
      );
    },
  );

  test('oauth provider authenticates active introspection responses', () async {
    final requests = <Map<String, String>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add({
        'authorization':
            request.headers.value(HttpHeaders.authorizationHeader) ?? '',
        'content-type':
            request.headers.value(HttpHeaders.contentTypeHeader) ?? '',
        'body': body,
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'active': true,
          'sub': 'oauth-user',
          'role': 'member',
          'iss': 'https://issuer.example',
          'aud': const ['connectanum-http'],
          'exp': _futureEpochSeconds(),
        }),
      );
      await request.response.close();
    });

    final provider = await HttpAuthProviderRegistry.factoryFor('oauth')!.create(
      {
        'name': 'oauth-introspection',
        'introspection_url': 'http://127.0.0.1:${server.port}/introspect',
        'client_id': 'client-id',
        'client_secret': 'client-secret',
        'issuer': 'https://issuer.example',
        'audience': const ['connectanum-http'],
      },
    );

    final result = await provider.authenticate(_request(token: 'opaque-token'));

    expect(result.success, isTrue);
    expect(result.authenticated!.authMethod, 'oauth');
    expect(result.authenticated!.authProvider, 'oauth-introspection');
    expect(requests, hasLength(1));
    expect(requests.single['authorization'], startsWith('Basic '));
    expect(requests.single['body'], contains('token=opaque-token'));
  });

  test('oauth provider rejects inactive introspection responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object?>{'active': false}));
      await request.response.close();
    });

    final provider = await HttpAuthProviderRegistry.factoryFor('oauth')!.create(
      {'introspection_url': 'http://127.0.0.1:${server.port}/introspect'},
    );

    final result = await provider.authenticate(_request(token: 'opaque-token'));

    expect(result.success, isFalse);
    expect(result.failure!.reason, 'invalid_token');
  });
}

HttpAuthBearerRequest _request({required String token}) {
  return HttpAuthBearerRequest(
    token: token,
    realmUri: 'realm1',
    method: 'GET',
    path: '/api/secure',
    headers: const <String, String>{},
    transport: const TransportMetadata(
      connectionId: 1,
      peerAddress: '127.0.0.1',
      isEncrypted: true,
    ),
    sessionProfileName: 'http-jwt',
  );
}

String _encodeHs256Jwt({
  required String secret,
  required Map<String, Object?> claims,
}) {
  final header = <String, Object?>{'alg': 'HS256', 'typ': 'JWT'};
  final encodedHeader = base64Url
      .encode(utf8.encode(jsonEncode(header)))
      .replaceAll('=', '');
  final encodedClaims = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  final signingInput = '$encodedHeader.$encodedClaims';
  final signature = CraAuthentication.encodeByteHmac(
    Uint8List.fromList(utf8.encode(secret)),
    32,
    utf8.encode(signingInput),
  );
  return '$signingInput.${base64Url.encode(signature).replaceAll('=', '')}';
}

int _futureEpochSeconds() =>
    DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch ~/
    1000;
