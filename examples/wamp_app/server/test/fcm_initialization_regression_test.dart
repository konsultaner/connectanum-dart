import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory directory;
  late File credentials;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fcm-initialization-');
    credentials = File('${directory.path}/credentials.json');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<FcmPlatformPushGateway> initialize(
    _OfflineClient client, {
    String? projectId,
    Duration timeout = const Duration(seconds: 10),
  }) => http.runWithClient(
    () => FcmPlatformPushGateway.fromConfig(
      FcmPlatformPushConfig(
        serviceAccountPath: credentials.path,
        projectId: projectId,
      ),
      initializationTimeout: timeout,
    ),
    () => client,
  );

  for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
    test(
      'rejects initialization timeout $timeout before allocating HTTP',
      () async {
        var allocations = 0;
        await expectLater(
          http.runWithClient(
            () => FcmPlatformPushGateway.fromConfig(
              FcmPlatformPushConfig(serviceAccountPath: credentials.path),
              initializationTimeout: timeout,
            ),
            () {
              allocations++;
              throw StateError('No client should be allocated.');
            },
          ),
          throwsArgumentError,
        );
        expect(allocations, 0);
      },
    );
  }

  final invalidDocuments = <String, List<int>?>{
    'missing file': null,
    'empty file': [],
    'invalid UTF-8': [0xff],
    'invalid JSON': utf8.encode('private-test-password'),
    'non-object JSON': utf8.encode('[]'),
    'wrong credential type': utf8.encode('{"type":"user_account"}'),
    'missing credential fields': utf8.encode('{"type":"service_account"}'),
    'missing project': utf8.encode(
      jsonEncode(_document()..remove('project_id')),
    ),
    'oversized valid document': utf8.encode(
      jsonEncode(_document()).padRight(128 * 1024 + 1),
    ),
  };
  for (final entry in invalidDocuments.entries) {
    test('redacts ${entry.key} and closes the unopened HTTP client', () async {
      if (entry.value != null) await credentials.writeAsBytes(entry.value!);
      final client = _OfflineClient((request, body) => _tokenResponse(request));
      await expectLater(initialize(client), throwsA(_initializationFailure));
      expect(client.requests, isEmpty);
      expect(client.closes, 1);
    });
  }

  for (final override in [false, true]) {
    test(
      'authenticates offline with ${override ? 'explicit' : 'credential'} project and owns HTTP lifetime',
      () async {
        final document = _document();
        if (override) document.remove('project_id');
        // JSON whitespace counts toward the byte cap; exactly 128 KiB is valid.
        await credentials.writeAsString(
          jsonEncode(document).padRight(128 * 1024),
        );
        final project = override ? 'explicit-project' : 'fixture-project';
        final client = _OfflineClient((request, body) {
          expect(request.method, 'POST');
          if (request.url.host == 'oauth2.googleapis.com') {
            expect(
              request.url,
              Uri.parse('https://oauth2.googleapis.com/token'),
            );
            final form = Uri.splitQueryString(body);
            expect(
              form['grant_type'],
              'urn:ietf:params:oauth:grant-type:jwt-bearer',
            );
            final jwt = form['assertion']!.split('.');
            expect(jwt, hasLength(3));
            final claims = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(jwt[1]))),
            );
            expect(claims['iss'], 'fixture@example.invalid');
            expect(claims['aud'], 'https://oauth2.googleapis.com/token');
            expect(
              claims['scope'],
              'https://www.googleapis.com/auth/firebase.messaging',
            );
            return _tokenResponse(request);
          }
          expect(
            request.url,
            Uri.parse(
              'https://fcm.googleapis.com/v1/projects/$project/messages:send',
            ),
          );
          expect(request.headers['Authorization'], 'Bearer offline-test-token');
          final message = (jsonDecode(body) as Map)['message'] as Map;
          expect(message['token'], 'offline-device');
          expect(message['data'], {'cursor': '7'});
          return _response(request, 200, {'name': 'offline-message'});
        });
        final gateway = await initialize(
          client,
          projectId: override ? project : null,
        );
        addTearDown(gateway.close);
        expect(gateway.providers, {'fcm'});
        expect(() => gateway.providers.add('other'), throwsUnsupportedError);
        expect(client.closes, 0);
        expect(
          await gateway.deliver(
            provider: 'fcm',
            token: 'offline-device',
            cursor: 7,
          ),
          PlatformPushDeliveryResult.accepted,
        );
        expect(client.requests, hasLength(2));
        await gateway.close();
        await gateway.close();
        expect(client.closes, 1);
        expect(
          await gateway.deliver(
            provider: 'fcm',
            token: 'offline-device',
            cursor: 8,
          ),
          PlatformPushDeliveryResult.retryableFailure,
        );
        expect(client.requests, hasLength(2));
      },
    );
  }

  test(
    'cleans up both clients if gateway construction rejects the project',
    () async {
      await credentials.writeAsString(jsonEncode(_document()));
      final client = _OfflineClient((request, body) => _tokenResponse(request));
      await expectLater(
        initialize(client, projectId: '../private-project'),
        throwsA(_initializationFailure),
      );
      expect(client.requests, hasLength(1));
      expect(client.closes, 1);
    },
  );

  for (final failure in [
    'HTTP rejection',
    'malformed token',
    'transport exception',
  ]) {
    test('redacts $failure and releases the base client', () async {
      await credentials.writeAsString(jsonEncode(_document()));
      final client = _OfflineClient((request, body) {
        if (failure == 'transport exception') {
          throw http.ClientException('private-test-password');
        }
        return _response(request, failure == 'HTTP rejection' ? 401 : 200, {
          'error': 'private-test-password',
        });
      });
      await expectLater(initialize(client), throwsA(_initializationFailure));
      expect(client.requests, hasLength(1));
      expect(client.closes, 1);
    });
  }

  for (final lateFailure in [false, true]) {
    test(
      'timeout fails closed despite late OAuth ${lateFailure ? 'failure' : 'success'}',
      () async {
        await credentials.writeAsString(jsonEncode(_document()));
        final pending = Completer<http.StreamedResponse>();
        final started = Completer<http.BaseRequest>();
        final client = _OfflineClient((request, body) {
          started.complete(request);
          return pending.future;
        });
        // Attach the error observer before waiting for the deterministic request barrier.
        final result = expectLater(
          initialize(client, timeout: const Duration(milliseconds: 250)),
          throwsA(_initializationFailure),
        );
        final request = await started.future;
        await result;
        expect(client.closes, 1);
        final responseDrained = Completer<void>();
        pending.complete(
          http.StreamedResponse(
            (() async* {
              yield utf8.encode(
                jsonEncode(
                  lateFailure ? {'error': 'late-private-error'} : _token,
                ),
              );
              responseDrained.complete();
            })(),
            lateFailure ? 401 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        );
        await responseDrained.future;
        await Future<void>.delayed(Duration.zero);
        expect(client.closes, 1);
        expect(client.requests, hasLength(1));
      },
    );
  }

  test('rejects nonpositive delivery bounds before sending', () {
    final client = _OfflineClient((request, body) => _tokenResponse(request));
    addTearDown(client.close);
    for (final size in [0, -1]) {
      expect(
        () => FcmPlatformPushGateway(
          projectId: 'fixture-project',
          client: client,
          maxResponseBytes: size,
        ),
        throwsArgumentError,
      );
    }
    for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
      expect(
        () => FcmPlatformPushGateway(
          projectId: 'fixture-project',
          client: client,
          requestTimeout: timeout,
        ),
        throwsArgumentError,
      );
    }
    expect(client.requests, isEmpty);
  });
}

final _initializationFailure = isA<StateError>().having(
  (error) => error.message,
  'redacted error',
  'FCM platform push initialization failed.',
);

const _token = {
  'access_token': 'offline-test-token',
  'token_type': 'Bearer',
  'expires_in': 3600,
};

http.StreamedResponse _tokenResponse(http.BaseRequest request) =>
    _response(request, 200, _token);

http.StreamedResponse _response(
  http.BaseRequest request,
  int status,
  Object body,
) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

// Never delegates to a real HTTP client, even if production selects a wrong URL.
final class _OfflineClient extends http.BaseClient {
  _OfflineClient(this.handler);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest, String)
  handler;
  final requests = <Uri>[];
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closes != 0) throw StateError('HTTP client is closed.');
    requests.add(request.url);
    return handler(request, await request.finalize().bytesToString());
  }

  @override
  void close() => closes++;
}

Map<String, Object> _document() => {
  'type': 'service_account',
  'project_id': 'fixture-project',
  'client_id': '1234567890',
  'client_email': 'fixture@example.invalid',
  'private_key': _testKey,
};

// Generated solely for offline tests; never associated with a real account.
const _testKey = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDXOzg5CJASqn09
KBPqSutNUNPOAdAQR3pdmCjVNW0DGD6lV78vrQ0Z04HrQ0jOnz+sWjzQkORMg2qW
CtFx7Pjyv/euTciTN5fAk/tVfhxvF0GnUBmavzP49VdIAPokh8/hCOcT+s0wN6Ih
bVzRvhnRAS/NRm8QNOKhqsTJ3ffvNL078GNJQTb9jLI7OcVblAJnMWPwz+GeMhTi
oO4vnxQL4eN0+L9zsu76UlDQpSFoQpzwO0Cgqqm7VW/mMT1mw0BoRhduSZamShXq
5vxeaeryW19N5DKJR1QDS7At7TjepzoaYe79BG9IMTc2J2SGouC0d7I7opHTzTdW
Sttn9xGdAgMBAAECggEALiFgswStUHrfHeD9p71IAom8484KqLqRNQc8VTo+s6ea
IbkVXqQSB0OIeIKy06pZLNkoaLFtZSLTkPYfnvHiB7FyZhcA0uDa8ykkeNXvRTYw
Wap22m55trXq76FZ+8NqIDrWwDcEjH2YD98PQlsi0GOXOcGLY2daXbkqtXOQROHd
doZehaZMd2OSUCy/onGnR4l0gWK3wITVv7h9jM+K1DZtSUGr6dJRdB3yOwg6chQJ
Rx2YKoAYy9G1qOAD1H4YxmWuqr3xqq3afYmBflU1jZvsckkfo0ZtjSxJUMSQMGFv
2DYj7fOUqgVUmQL9DTJtZQBfMsQgtxe5juoTAoQktwKBgQD9KWO9fALWYZe/6zyG
REO3PhelnspKpZNCLOvreUn97Y29VwAW8FKJwFuAYCBOvxJ+NVCGjSZN2A/LIBbS
FRakmjLqAuHAUJPMIu8GSDBDDEF8N5HmhC2vYnngHYYVz3Vgf8l/0S7sq2jWaFBW
KGypHCwwMcTY4DVkNYMIZnE15wKBgQDZpPbmTOC7+kx8zRX0Q5rNnOh/i/JOE0OX
kWzs0Xx37amuACyGJlUw5zI/0reEQnr0i5H5Zdza4eMHD4nTdSRMMDo27znwVK6V
wTmwmN5lNQQ+X5Ez2u0H73SAAkx+FgbhSs5OKeuR1nTXQvHDk936cQ0g7qi5VuA2
Xuhk3pnD2wKBgQCNeWPTsEmlpEQ5bCwWnG97J6fvVh2WOZFhmdj9bnp6/RYIiWXz
a7m0YVrBEvb7Cqw6+3BUwOx29BdfXD9kh4Rv1/w76gBeiKkPmzYYPJ872M1/rU5L
k/Iz4MRbCiS0a4scskzYsP2YJPIhX4oFm/GdT7Eh/a4TxLgRmBXxy83YYQKBgF+k
ntuV7SyuUe6GMZ+mFeFFkuZ6GYE19f4lajin1ordZjOQ4AAT2FwlPW/Oqdb1YBMX
Qo7WtLd7jMkNiwPh9pGEoBCEEHIMxKwKvc9dXl4bbkH6vVSMYJ2cHRYj7Hl8NInM
1dyDj4IHPFFcmeHYmTP1ek9+kabhBqbeDkJFkE0BAoGAcMJWyhh379z2xOA4gDFO
YmtMMdJjsmNGTByP7nhMpCWJ8/r47sTOu9cWprUpXa7VW010EhgPw7hm+Gk2skuz
IRTgWgmOSTzhV4Sz3ep9EuAbXIOj34/lGRKGzX+2Vbp5vDvqKpmErRKWRjqWrG6L
Ccty4FGocoB9CHBvuvMJNA4=
-----END PRIVATE KEY-----
''';
