@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  final basic = 'Basic ${base64Encode(utf8.encode('client:secret'))}';
  for (final (label, options, authorization) in [
    (
      'basic',
      <String, Object?>{
        'client_id': 'client',
        'client_secret': 'secret',
        'bearer_token': 'must-not-override-basic',
      },
      basic,
    ),
    (
      'bearer',
      <String, Object?>{'bearer_token': 'service-secret'},
      'Bearer service-secret',
    ),
    (
      'incomplete basic',
      <String, Object?>{
        'client_id': 'client',
        'bearer_token': 'service-secret',
      },
      'Bearer service-secret',
    ),
  ]) {
    group('$label credentials', () {
      for (final rejected in [null, 'Basic !!!', 'Bearer wrong-secret']) {
        test('rejects $rejected and remains usable', () async {
          final fixture = await _Fixture.start(options);
          final response = await fixture.request(authorization: rejected);
          expect(response.status, HttpStatus.unauthorized);
          expect(response.mimeType, 'application/json');
          expect(jsonDecode(response.body), {'active': false});
          await fixture.expectActive(authorization);
        });
      }
      test('unknown token is inactive with HTTP 200', () async {
        final fixture = await _Fixture.start(options);
        final response = await fixture.request(
          authorization: authorization,
          token: 'not-the-benchmark-token',
        );
        expect(response.status, HttpStatus.ok);
        expect(jsonDecode(response.body), {'active': false});
        await fixture.expectActive(authorization);
      });
      for (final method in ['GET', 'HEAD', 'PUT', 'OPTIONS']) {
        test('$method is rejected without poisoning later POSTs', () async {
          final fixture = await _Fixture.start(options);
          final response = await fixture.request(
            method: method,
            authorization: authorization,
          );
          expect(response.status, HttpStatus.methodNotAllowed);
          expect(response.body, isEmpty);
          await fixture.expectActive(authorization);
        });
      }
      test('unknown path does not fall back to another provider', () async {
        final fixture = await _Fixture.start(options);
        final response = await fixture.request(
          path: '/unknown',
          authorization: authorization,
        );
        expect(response.status, HttpStatus.notFound);
        expect(response.body, isEmpty);
        await fixture.expectActive(authorization);
      });
    });
  }

  test(
    'complete Basic credentials take precedence over configured bearer',
    () async {
      final fixture = await _Fixture.start({
        'client_id': 'client',
        'client_secret': 'secret',
        'bearer_token': 'must-not-override-basic',
      });
      final response = await fixture.request(
        authorization: 'Bearer must-not-override-basic',
      );
      expect(response.status, HttpStatus.unauthorized);
      expect(jsonDecode(response.body), {'active': false});
      await fixture.expectActive(basic);
    },
  );

  test(
    'anonymous introspection and repeated close release the bound port',
    () async {
      final fixture = await _Fixture.start({});
      await fixture.expectActive(null);
      await fixture.harness.close();
      await fixture.harness.close();
      final rebound = await ServerSocket.bind('127.0.0.1', fixture.port);
      await rebound.close();
    },
  );

  test('providers share a listener but not credentials or claims', () async {
    final port = await _unusedPort();
    final settings = _settings({
      'alpha': {
        'introspection_url': 'http://127.0.0.1:$port/alpha',
        'bearer_token': 'alpha-secret',
        'default_auth_id': 'alpha-user',
        'default_auth_role': 'alpha-role',
        'issuer': 'alpha-issuer',
        'audience': 'alpha-audience',
      },
      'beta': {
        'url': 'http://127.0.0.1:$port/beta',
        'bearer_token': 'beta-secret',
        'auth_id_claim': 'user',
        'auth_role_claim': 'membership',
        'default_auth_id': 'beta-user',
        'default_auth_role': 'beta-role',
      },
    });
    final harness = await HttpAuthBenchHarness.maybeStart(settings: settings);
    expect(harness, isNotNull);
    addTearDown(() => harness!.close());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final fixture = _Fixture(port, harness!, client);
    final alpha = await fixture.request(
      path: '/alpha',
      authorization: 'Bearer alpha-secret',
    );
    expect(alpha.status, HttpStatus.ok);
    final alphaClaims = jsonDecode(alpha.body) as Map;
    expect(alphaClaims['sub'], 'alpha-user');
    expect(alphaClaims['role'], 'alpha-role');
    expect(alphaClaims['iss'], 'alpha-issuer');
    expect(alphaClaims['aud'], 'alpha-audience');
    final rejected = await fixture.request(
      path: '/beta',
      authorization: 'Bearer alpha-secret',
    );
    expect(rejected.status, HttpStatus.unauthorized);
    expect(jsonDecode(rejected.body), {'active': false});
    final beta = await fixture.request(
      path: '/beta',
      authorization: 'Bearer beta-secret',
    );
    expect(beta.status, HttpStatus.ok);
    final betaClaims = jsonDecode(beta.body) as Map;
    expect(betaClaims['user'], 'beta-user');
    expect(betaClaims['membership'], 'beta-role');
    expect(betaClaims, isNot(contains('sub')));
    expect(betaClaims, isNot(contains('role')));
    expect(betaClaims, isNot(contains('iss')));
    expect(betaClaims, isNot(contains('aud')));
  });

  for (final acquired in [1, 3]) {
    test('failed later bind rolls back $acquired earlier listeners', () async {
      final occupied = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(occupied.close);
      final occupiedPort = occupied.port;
      final availablePorts = await _unusedPorts(acquired);
      // An isolate lets a failed pre-fix probe release leaked sockets on exit.
      final result = await Isolate.run(
        () => _probeFailedStartup(availablePorts, occupiedPort),
      );
      expect(result.failedBind, isTrue);
      expect(
        result.reclaimedPorts,
        List.filled(acquired, true),
        reason: 'Startup failure must close listeners already acquired.',
      );
      await occupied.close();
      final settings = _settings({
        for (final port in [...availablePorts, occupiedPort])
          '$port': {'url': 'http://127.0.0.1:$port/introspect'},
      });
      final harness = await HttpAuthBenchHarness.maybeStart(settings: settings);
      expect(harness, isNotNull);
      addTearDown(() => harness!.close());
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      for (final port in [...availablePorts, occupiedPort]) {
        await _Fixture(port, harness!, client).expectActive(null);
      }
    });
  }
}

Future<({bool failedBind, List<bool> reclaimedPorts})> _probeFailedStartup(
  List<int> availablePorts,
  int occupiedPort,
) async {
  final settings = _settings({
    for (final port in availablePorts)
      '$port': {'url': 'http://127.0.0.1:$port/introspect'},
    'occupied': {'url': 'http://127.0.0.1:$occupiedPort/introspect'},
  });
  var failedBind = false;
  try {
    final harness = await HttpAuthBenchHarness.maybeStart(settings: settings);
    await harness?.close();
  } on SocketException {
    failedBind = true;
  }
  final reclaimed = <bool>[];
  for (final port in availablePorts) {
    try {
      final rebound = await ServerSocket.bind('127.0.0.1', port);
      await rebound.close();
      reclaimed.add(true);
    } on SocketException {
      reclaimed.add(false);
    }
  }
  return (failedBind: failedBind, reclaimedPorts: reclaimed);
}

class _Fixture {
  _Fixture(this.port, this.harness, this.client);
  final int port;
  final HttpAuthBenchHarness harness;
  final HttpClient client;

  static Future<_Fixture> start(Map<String, Object?> options) async {
    final port = await _unusedPort();
    final harness = await HttpAuthBenchHarness.maybeStart(
      settings: _settings({
        'provider': {'url': 'http://127.0.0.1:$port/introspect', ...options},
      }),
    );
    expect(harness, isNotNull);
    addTearDown(() => harness!.close());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    return _Fixture(port, harness!, client);
  }

  Future<({int status, String body, String? mimeType})> request({
    String method = 'POST',
    String path = '/introspect',
    String? authorization,
    String token = HttpAuthBenchHarness.defaultOAuthAccessToken,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    if (method == 'POST') {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: {'token': token}).query);
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      mimeType: response.headers.contentType?.mimeType,
    );
  }

  Future<void> expectActive(String? authorization) async {
    final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final response = await request(authorization: authorization);
    expect(response.status, HttpStatus.ok);
    expect(response.mimeType, 'application/json');
    final claims = jsonDecode(response.body) as Map;
    expect(claims['active'], isTrue);
    expect(claims['sub'], HttpAuthBenchHarness.defaultAuthId);
    expect(claims['role'], HttpAuthBenchHarness.defaultAuthRole);
    expect(claims['exp'], inInclusiveRange(before + 295, before + 305));
  }
}

RouterSettings _settings(Map<String, Map<String, Object?>> providers) {
  final builder = RouterSettingsBuilder();
  providers.forEach((name, options) {
    builder.addHttpAuthProvider(
      name,
      HttpAuthProviderDefinition(type: 'oauth', options: options),
    );
  });
  return builder.build();
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<List<int>> _unusedPorts(int count) async {
  final sockets = <ServerSocket>[];
  try {
    for (var index = 0; index < count; index++) {
      sockets.add(await ServerSocket.bind('127.0.0.1', 0));
    }
    return sockets.map((socket) => socket.port).toList();
  } finally {
    await Future.wait(sockets.map((socket) => socket.close()));
  }
}
