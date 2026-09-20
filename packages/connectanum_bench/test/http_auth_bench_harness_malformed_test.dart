@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

const _secret = 'private-benchmark-credential';
const _sensitiveField = 'untrusted-body-must-not-be-logged';

void main() {
  final malformed = <String, List<int>>{
    'invalid UTF-8 byte': [255],
    'truncated UTF-8 sequence': [0xe2, 0x82],
    'overlong UTF-8 sequence': [0xc0, 0xaf],
    'lone percent': utf8.encode('token=%'),
    'partial percent': utf8.encode('token=%A'),
    'invalid hex': utf8.encode('token=%GG'),
    'escaped invalid UTF-8': utf8.encode('token=%FF'),
    'invalid key escape': utf8.encode('%GG=value'),
    'valid token with malformed trailing field': utf8.encode(
      'token=${HttpAuthBenchHarness.defaultOAuthAccessToken}&$_sensitiveField=%GG',
    ),
  };
  for (final authenticated in [false, true]) {
    for (final entry in malformed.entries) {
      test(
        'rejects ${entry.key} with inactive JSON (protected=$authenticated)',
        () async {
          final fixture = await _Fixture.start(protected: authenticated);
          final response = await fixture.post(
            entry.value,
            authorization: authenticated ? 'Bearer $_secret' : null,
          );
          expect(
            response,
            (status: 400, body: '{"active":false}', mime: 'application/json'),
            reason:
                'Malformed input must not escape as an uncaught handler error.',
          );
          await fixture.expectRecovery();
          expect(fixture.logText, isNot(contains(_sensitiveField)));
          expect(fixture.logText, isNot(contains(_secret)));
        },
      );
    }
  }
  for (final authorization in <String?>[null, 'Bearer wrong', 'Basic wrong']) {
    for (final body in [malformed.values.first, malformed.values.last]) {
      test(
        'checks credentials before decoding ${body.first} ($authorization)',
        () async {
          final fixture = await _Fixture.start(protected: true);
          final response = await fixture.post(
            body,
            authorization: authorization,
          );
          expect(response, (
            status: 401,
            body: '{"active":false}',
            mime: 'application/json',
          ));
          await fixture.expectRecovery();
          expect(fixture.logText, isNot(contains(_secret)));
          expect(fixture.logText, isNot(contains(_sensitiveField)));
        },
      );
    }
  }
  for (final body in [
    '',
    'irrelevant=value',
    'token=unknown',
    'token=%E2%82%AC',
    'token=hello+world',
  ]) {
    test('well-formed inactive form stays HTTP 200: $body', () async {
      final fixture = await _Fixture.start();
      expect(await fixture.post(utf8.encode(body)), (
        status: 200,
        body: '{"active":false}',
        mime: 'application/json',
      ));
      await fixture.expectRecovery();
    });
  }
  test(
    'arbitrary byte chunk boundaries preserve percent-encoded Unicode fields',
    () async {
      final fixture = await _Fixture.start();
      final body = utf8.encode(
        Uri(
          queryParameters: {
            'token': HttpAuthBenchHarness.defaultOAuthAccessToken,
            'label': 'Gr\u00fc\u00dfe',
          },
        ).query,
      );
      final result = await fixture.post(body, splitBytes: true);
      expect(result, isA<({int status, String body, String? mime})>());
      final response = result as ({int status, String body, String? mime});
      expect(response.status, HttpStatus.ok);
      expect((jsonDecode(response.body) as Map)['active'], isTrue);
      expect(fixture.uncaught.isCompleted, isFalse);
    },
  );
}

class _Fixture {
  _Fixture(
    this.harness,
    this.port,
    this.protected,
    this.uncaught,
    this.records,
  );
  final HttpAuthBenchHarness harness;
  final int port;
  final bool protected;
  final Completer<Object> uncaught;
  final List<LogRecord> records;
  final client = HttpClient();

  String get logText =>
      records.map((r) => '${r.message} ${r.error} ${r.stackTrace}').join('\n');

  static Future<_Fixture> start({bool protected = false}) async {
    final reserved = await ServerSocket.bind('127.0.0.1', 0);
    final port = reserved.port;
    await reserved.close();
    final settings =
        (RouterSettingsBuilder()..addHttpAuthProvider(
              'auth',
              HttpAuthProviderDefinition(
                type: 'oauth',
                options: {
                  'url': 'http://127.0.0.1:$port/introspect',
                  if (protected) 'bearer_token': _secret,
                },
              ),
            ))
            .build();
    final logger = Logger.detached('malformed-body')..level = Level.ALL;
    final records = <LogRecord>[];
    final logging = logger.onRecord.listen(records.add);
    addTearDown(logging.cancel);
    final ready = Completer<HttpAuthBenchHarness?>();
    final uncaught = Completer<Object>();
    runZonedGuarded(
      () {
        HttpAuthBenchHarness.maybeStart(
          settings: settings,
          logger: logger,
        ).then(ready.complete, onError: ready.completeError);
      },
      (error, stack) {
        if (!uncaught.isCompleted) uncaught.complete(error);
      },
    );
    final harness = await ready.future;
    expect(harness, isNotNull);
    final fixture = _Fixture(harness!, port, protected, uncaught, records);
    addTearDown(() async {
      fixture.client.close(force: true);
      await harness.close();
    });
    return fixture;
  }

  Future<Object> post(
    List<int> body, {
    String? authorization,
    bool splitBytes = false,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/introspect'),
    );
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    if (splitBytes) {
      for (final byte in body) {
        request.add([byte]);
        await request.flush();
      }
    } else {
      request.add(body);
    }
    final response = request.close().then(
      (reply) async => (
        status: reply.statusCode,
        body: await utf8.decoder.bind(reply).join(),
        mime: reply.headers.contentType?.mimeType,
      ),
    );
    // Own pending HTTP errors when an uncaught server error wins the race.
    unawaited(
      response.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return Future.any<Object>([
      response,
      uncaught.future,
    ]).timeout(const Duration(seconds: 2));
  }

  Future<void> expectRecovery() async {
    final result = await post(
      utf8.encode('token=${HttpAuthBenchHarness.defaultOAuthAccessToken}'),
      authorization: protected ? 'Bearer $_secret' : null,
    );
    expect(result, isA<({int status, String body, String? mime})>());
    final response = result as ({int status, String body, String? mime});
    expect(response.status, HttpStatus.ok);
    final claims = jsonDecode(response.body) as Map;
    expect(claims['active'], isTrue);
    expect(claims['sub'], HttpAuthBenchHarness.defaultAuthId);
    expect(uncaught.isCompleted, isFalse);
  }
}
