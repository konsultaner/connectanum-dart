@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  for (final value in <Object?>[
    null,
    '',
    '   ',
    42,
    true,
    <String>[],
    'http://[invalid',
    'https://127.0.0.1:8080/introspect',
    'ftp://127.0.0.1:8080/introspect',
    'http:/introspect',
    'http://127.0.0.1:0/introspect',
  ]) {
    test('unsupported introspection URL $value does not claim support', () {
      expect(
        HttpAuthBenchHarness.supports(_settings({'introspection_url': value})),
        isFalse,
      );
    });
  }
  for (final type in ['anonymous', 'ticket', 'wampcra', 'custom', 'OAuth']) {
    test('valid URL does not opt a $type provider into OAuth emulation', () {
      expect(
        HttpAuthBenchHarness.supports(
          _settings({'url': 'http://127.0.0.1:8080/introspect'}, type: type),
        ),
        isFalse,
      );
    });
  }
  for (final path in ['', '/']) {
    test('root path $path serves claims through the supplied logger', () async {
      final reservation = await ServerSocket.bind('127.0.0.1', 0);
      final port = reservation.port;
      await reservation.close();
      final logger = Logger('HTTP configuration probe $port');
      final records = <LogRecord>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final subscription = logger.onRecord
          .where((record) => record.loggerName == logger.name)
          .listen(records.add);
      addTearDown(() async {
        await subscription.cancel();
        Logger.root.level = previousLevel;
      });
      final harness = await HttpAuthBenchHarness.maybeStart(
        settings: _settings({
          'url': 'http://127.0.0.1:$port$path',
          'client_id': '  client  ',
          'client_secret': '  secret  ',
          'auth_id_claim': ' ',
          'auth_role_claim': ' ',
          'default_auth_id': ' ',
          'default_auth_role': ' ',
          'issuer': '  issuer  ',
          'audience': ['first', '', 42, 'second'],
        }),
        logger: logger,
      );
      expect(harness, isNotNull);
      addTearDown(() => harness!.close());
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('client:secret'))}',
      );
      request.write('token=${HttpAuthBenchHarness.defaultOAuthAccessToken}');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      final claims =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect(claims['active'], isTrue);
      expect(claims['sub'], HttpAuthBenchHarness.defaultAuthId);
      expect(claims['role'], HttpAuthBenchHarness.defaultAuthRole);
      expect(claims, isNot(contains('')));
      expect(claims['iss'], 'issuer');
      expect(claims['aud'], ['first', '42', 'second']);
      await harness!.close();
      expect(
        records.where((r) => r.message.startsWith('Starting HTTP auth')),
        hasLength(1),
      );
      expect(
        records.where((r) => r.message == 'Stopping HTTP auth bench harness'),
        hasLength(1),
      );
    });
  }
}

RouterSettings _settings(
  Map<String, Object?> options, {
  String type = 'oauth',
}) {
  final builder = RouterSettingsBuilder()
    ..addHttpAuthProvider(
      'probe',
      HttpAuthProviderDefinition(type: type, options: options),
    );
  return builder.build();
}
