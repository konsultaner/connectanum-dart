@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  group('HttpAuthBenchHarness.supports', () {
    test('returns false when no oauth providers are configured', () {
      expect(
        HttpAuthBenchHarness.supports(
          const RouterSettings(realms: <RealmSettings>[], listeners: []),
        ),
        isFalse,
      );
    });

    test('returns true for oauth introspection bench settings', () async {
      final settings = _buildOauthSettings(port: await _unusedPort());

      expect(HttpAuthBenchHarness.supports(settings), isTrue);
    });
  });

  test('serves active and inactive oauth introspection responses', () async {
    final settings = _buildOauthSettings(port: await _unusedPort());
    final harness = await HttpAuthBenchHarness.maybeStart(settings: settings);
    addTearDown(() async => harness?.close());

    expect(harness, isNotNull);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<Map<String, Object?>> introspect(String token) async {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${_portFromSettings(settings)}/introspect'),
      );
      final credentials = base64Encode(
        utf8.encode('bench-client:bench-secret'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic $credentials',
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        Uri(
          queryParameters: <String, String>{
            'token': token,
            'token_type_hint': 'access_token',
          },
        ).query,
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      expect(
        response.statusCode,
        anyOf(HttpStatus.ok, HttpStatus.unauthorized),
      );
      return Map<String, Object?>.from(
        (jsonDecode(body) as Map).cast<String, Object?>(),
      );
    }

    final active = await introspect(
      HttpAuthBenchHarness.defaultOAuthAccessToken,
    );
    expect(active['active'], isTrue);
    expect(active['sub'], 'oauth-user');
    expect(active['role'], 'member');
    expect(active['iss'], 'https://issuer.example');
    expect(active['aud'], ['connectanum-http']);

    final inactive = await introspect('wrong-token');
    expect(inactive['active'], isFalse);
  });
}

RouterSettings _buildOauthSettings({required int port}) {
  final builder = RouterSettingsBuilder()
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('http-oauth')
        ..setRealm('bench.secure')
        ..setAuthMethods(const <String>['oauth'])
        ..setHttpProvider('bench-oauth'),
    )
    ..addHttpAuthProvider(
      'bench-oauth',
      HttpAuthProviderDefinition(
        type: 'oauth',
        options: <String, Object?>{
          'introspection_url': 'http://127.0.0.1:$port/introspect',
          'client_id': 'bench-client',
          'client_secret': 'bench-secret',
          'issuer': 'https://issuer.example',
          'audience': const <String>['connectanum-http'],
          'auth_id_claim': 'sub',
          'auth_role_claim': 'role',
        },
      ),
    );
  return builder.build();
}

int _portFromSettings(RouterSettings settings) {
  final provider = settings.httpAuthProviders['bench-oauth']!;
  final url = provider.options['introspection_url']! as String;
  return Uri.parse(url).port;
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
