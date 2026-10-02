import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test(
    'uses an explicit endpoint without replacing its path or query',
    () async {
      final endpoint = Uri.parse(
        'http://127.0.0.1:12345/custom/send?environment=test',
      );
      Uri? requested;
      final client = _RecordingClient((request, body) async {
        requested = request.url;
        return _jsonResponse(request, 200, {'name': 'offline-message'});
      });
      final gateway = FcmPlatformPushGateway(
        projectId: 'fixture-project',
        client: client,
        endpoint: endpoint,
      );
      addTearDown(gateway.close);
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'offline-token',
          cursor: 1,
        ),
        PlatformPushDeliveryResult.accepted,
      );
      expect(requested, endpoint);
      expect(client.sends, 1);
    },
  );

  test('sends one data-only cursor through the FCM HTTP v1 endpoint', () async {
    final client = _RecordingClient((request, body) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/wampapp-test1/'
          'messages:send',
        ),
      );
      expect(request.headers['content-type'], startsWith('application/json'));
      final payload = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      expect(payload.keys, ['message']);
      expect(payload['message'], {
        'token': 'opaque-provider-token',
        'data': {'cursor': '42'},
        'android': {'priority': 'HIGH'},
        'apns': {
          'headers': {'apns-push-type': 'background', 'apns-priority': '5'},
          'payload': {
            'aps': {'content-available': 1},
          },
        },
        'webpush': {
          'headers': {'Urgency': 'high'},
        },
      });
      expect(utf8.decode(body), isNot(contains('notification')));
      expect(utf8.decode(body), isNot(contains('conversation')));
      expect(utf8.decode(body), isNot(contains('plaintext')));
      return _jsonResponse(request, 200, {
        'name': 'projects/wampapp-test1/messages/accepted-message',
      });
    });
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
    );
    addTearDown(gateway.close);

    final result = await gateway.deliver(
      provider: 'fcm',
      token: 'opaque-provider-token',
      cursor: 42,
    );

    expect(result, PlatformPushDeliveryResult.accepted);
    expect(client.sends, 1);
  });

  test(
    'adds only generic notification metadata when presentation is allowed',
    () async {
      final client = _RecordingClient((request, body) async {
        final payload = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        expect(payload['message'], {
          'token': 'opaque-provider-token',
          'data': {'cursor': '43'},
          'android': {'priority': 'HIGH'},
          'apns': {
            'headers': {'apns-push-type': 'alert', 'apns-priority': '10'},
            'payload': {
              'aps': {'content-available': 1, 'sound': 'default'},
            },
          },
          'webpush': {
            'headers': {'Urgency': 'high'},
          },
          'notification': {'title': 'WampApp', 'body': 'New message'},
        });
        final encoded = utf8.decode(body);
        expect(encoded, isNot(contains('conversation-1')));
        expect(encoded, isNot(contains('alice')));
        expect(encoded, isNot(contains('message_id')));
        expect(encoded, isNot(contains('ciphertext')));
        return _jsonResponse(request, 200, {
          'name': 'projects/wampapp-test1/messages/accepted-message',
        });
      });
      final gateway = FcmPlatformPushGateway(
        projectId: 'wampapp-test1',
        client: client,
      );
      addTearDown(gateway.close);

      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'opaque-provider-token',
          cursor: 43,
          present: true,
        ),
        PlatformPushDeliveryResult.accepted,
      );
    },
  );

  test('unsupported providers and invalid cursors do not reach FCM', () async {
    final client = _RecordingClient(_unexpectedRequest);
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
    );
    addTearDown(gateway.close);

    expect(
      await gateway.deliver(
        provider: 'apns',
        token: 'opaque-provider-token',
        cursor: 1,
      ),
      PlatformPushDeliveryResult.retryableFailure,
    );
    expect(
      await gateway.deliver(
        provider: 'fcm',
        token: 'opaque-provider-token',
        cursor: 0,
      ),
      PlatformPushDeliveryResult.retryableFailure,
    );
    expect(client.sends, 0);
  });

  for (final errorCode in const [
    'INVALID_ARGUMENT',
    'SENDER_ID_MISMATCH',
    'UNREGISTERED',
  ]) {
    test('retires tokens for FCM $errorCode details', () async {
      final client = _RecordingClient((request, _) async {
        return _fcmError(request, 400, errorCode);
      });
      final gateway = FcmPlatformPushGateway(
        projectId: 'wampapp-test1',
        client: client,
      );
      addTearDown(gateway.close);

      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'invalid-provider-token',
          cursor: 3,
        ),
        PlatformPushDeliveryResult.invalidToken,
      );
    });
  }

  test('generic INVALID_ARGUMENT response does not retire a token', () async {
    final client = _RecordingClient((request, _) async {
      return _jsonResponse(request, 400, {
        'error': {
          'status': 'INVALID_ARGUMENT',
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.BadRequest',
              'fieldViolations': [],
            },
          ],
        },
      });
    });
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
    );
    addTearDown(gateway.close);

    expect(
      await gateway.deliver(
        provider: 'fcm',
        token: 'possibly-valid-token',
        cursor: 4,
      ),
      PlatformPushDeliveryResult.retryableFailure,
    );
  });

  test(
    'only typed FCM errors retire tokens, skipping malformed details',
    () async {
      final details = <Object?>[
        {
          '@type': 'type.googleapis.com/google.rpc.BadRequest',
          'errorCode': 'UNREGISTERED',
        },
      ];
      final client = _RecordingClient(
        (request, _) async => _jsonResponse(request, 400, {
          'error': {'details': details},
        }),
      );
      final gateway = FcmPlatformPushGateway(
        projectId: 'fixture-project',
        client: client,
      );
      addTearDown(gateway.close);
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'offline-token',
          cursor: 1,
        ),
        PlatformPushDeliveryResult.retryableFailure,
      );
      details.insertAll(0, [null, false, 7, <Object>[]]);
      details.addAll([
        {
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          'errorCode': 7,
        },
        {
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          'errorCode': 'UNREGISTERED',
        },
      ]);
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'offline-token',
          cursor: 1,
        ),
        PlatformPushDeliveryResult.invalidToken,
      );
      expect(client.sends, 2);
    },
  );

  for (final errorCode in const [
    'QUOTA_EXCEEDED',
    'UNAVAILABLE',
    'INTERNAL',
    'THIRD_PARTY_AUTH_ERROR',
  ]) {
    test('keeps tokens for retryable FCM $errorCode failures', () async {
      final client = _RecordingClient((request, _) async {
        return _fcmError(request, 503, errorCode);
      });
      final gateway = FcmPlatformPushGateway(
        projectId: 'wampapp-test1',
        client: client,
      );
      addTearDown(gateway.close);

      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'possibly-valid-token',
          cursor: 5,
        ),
        PlatformPushDeliveryResult.retryableFailure,
      );
    });
  }

  test('malformed and oversized responses fail closed', () async {
    var response = 0;
    final client = _RecordingClient((request, _) async {
      response += 1;
      if (response == 1) {
        return _textResponse(request, 200, '{not-json');
      }
      return _textResponse(request, 200, 'x' * 9);
    });
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
      maxResponseBytes: 8,
    );
    addTearDown(gateway.close);

    for (var cursor = 1; cursor <= 2; cursor += 1) {
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'possibly-valid-token',
          cursor: cursor,
        ),
        PlatformPushDeliveryResult.retryableFailure,
      );
    }
    expect(client.sends, 2);
  });

  test(
    'accepts only successful HTTP status and a nonblank message name',
    () async {
      var status = 200;
      Object? payload = {'name': 'message-1'};
      final client = _RecordingClient(
        (request, _) async => _jsonResponse(request, status, payload),
      );
      final gateway = FcmPlatformPushGateway(
        projectId: 'fixture-project',
        client: client,
      );
      addTearDown(gateway.close);
      for (final code in [199, 200, 299, 300]) {
        status = code;
        expect(
          await gateway.deliver(
            provider: 'fcm',
            token: 'offline-token',
            cursor: 1,
          ),
          code == 200 || code == 299
              ? PlatformPushDeliveryResult.accepted
              : PlatformPushDeliveryResult.retryableFailure,
          reason: 'status $code',
        );
      }
      status = 200;
      for (final invalid in <Object?>[
        null,
        false,
        1,
        <Object>[],
        'name',
        <String, Object?>{},
        {'name': 1},
        {'name': ''},
        {'name': '  '},
      ]) {
        payload = invalid;
        expect(
          await gateway.deliver(
            provider: 'fcm',
            token: 'offline-token',
            cursor: 1,
          ),
          PlatformPushDeliveryResult.retryableFailure,
        );
      }
    },
  );

  test(
    'enforces the byte cap across chunks, allowing the exact boundary',
    () async {
      var oversized = false;
      var cancelled = false;
      final client = _RecordingClient((request, _) async {
        final payload = utf8.encode('{"name":"x"}${oversized ? ' ' : ''}');
        return http.StreamedResponse(
          Stream<List<int>>.multi((sink) {
            sink.onCancel = () {
              cancelled = true;
            };
            sink.add(payload.sublist(0, 6));
            sink.add(payload.sublist(6));
            sink.close();
          }),
          200,
          request: request,
        );
      });
      final gateway = FcmPlatformPushGateway(
        projectId: 'fixture-project',
        client: client,
        maxResponseBytes: 12,
      );
      addTearDown(gateway.close);
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'offline-token',
          cursor: 1,
        ),
        PlatformPushDeliveryResult.accepted,
      );
      oversized = true;
      cancelled = false;
      expect(
        await gateway.deliver(
          provider: 'fcm',
          token: 'offline-token',
          cursor: 1,
        ),
        PlatformPushDeliveryResult.retryableFailure,
      );
      expect(cancelled, isTrue);
    },
  );

  test('request timeout fails closed', () async {
    final client = _RecordingClient((request, _) async {
      return Completer<http.StreamedResponse>().future;
    });
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
      requestTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(gateway.close);

    expect(
      await gateway.deliver(
        provider: 'fcm',
        token: 'opaque-provider-token',
        cursor: 6,
      ),
      PlatformPushDeliveryResult.retryableFailure,
    );
    expect(client.sends, 1);
  });

  for (final drip in [false, true]) {
    test(
      '${drip ? 'slow-drip' : 'stalled'} response body times out and cancels its subscription',
      () async {
        final cancelled = Completer<void>();
        Timer? timer;
        late StreamController<List<int>> body;
        body = StreamController<List<int>>(
          onListen: () {
            if (drip) {
              timer = Timer.periodic(
                const Duration(milliseconds: 5),
                (_) => body.add([32]),
              );
            }
          },
          onCancel: () {
            timer?.cancel();
            cancelled.complete();
          },
        );
        addTearDown(() async {
          timer?.cancel();
          await body.close();
        });
        final client = _RecordingClient(
          (request, _) async =>
              http.StreamedResponse(body.stream, 200, request: request),
        );
        final gateway = FcmPlatformPushGateway(
          projectId: 'fixture-project',
          client: client,
          requestTimeout: const Duration(milliseconds: 30),
        );
        addTearDown(gateway.close);
        expect(
          await gateway
              .deliver(provider: 'fcm', token: 'offline-token', cursor: 1)
              .timeout(const Duration(seconds: 1)),
          PlatformPushDeliveryResult.retryableFailure,
        );
        await cancelled.future.timeout(const Duration(seconds: 1));
        expect(client.sends, 1);
      },
    );
  }

  test('close is idempotent and prevents later delivery', () async {
    final client = _RecordingClient(_unexpectedRequest);
    final gateway = FcmPlatformPushGateway(
      projectId: 'wampapp-test1',
      client: client,
    );

    await gateway.close();
    await gateway.close();

    expect(client.closes, 1);
    expect(
      await gateway.deliver(
        provider: 'fcm',
        token: 'opaque-provider-token',
        cursor: 1,
      ),
      PlatformPushDeliveryResult.retryableFailure,
    );
    expect(client.sends, 0);
  });

  test('rejects invalid project IDs before issuing requests', () {
    final client = _RecordingClient(_unexpectedRequest);
    addTearDown(client.close);

    expect(
      () => FcmPlatformPushGateway(projectId: '../other', client: client),
      throwsArgumentError,
    );
  });
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.StreamedResponse> Function(
    http.BaseRequest request,
    Uint8List body,
  )
  handler;
  int sends = 0;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends += 1;
    final body = await request.finalize().toBytes();
    return handler(request, body);
  }

  @override
  void close() {
    closes += 1;
  }
}

Future<http.StreamedResponse> _unexpectedRequest(
  http.BaseRequest request,
  Uint8List body,
) => throw StateError('Unexpected HTTP request.');

http.StreamedResponse _fcmError(
  http.BaseRequest request,
  int statusCode,
  String errorCode,
) => _jsonResponse(request, statusCode, {
  'error': {
    'details': [
      {
        '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
        'errorCode': errorCode,
      },
    ],
  },
});

http.StreamedResponse _jsonResponse(
  http.BaseRequest request,
  int statusCode,
  Object? body,
) => _textResponse(request, statusCode, jsonEncode(body));

http.StreamedResponse _textResponse(
  http.BaseRequest request,
  int statusCode,
  String body,
) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  statusCode,
  headers: {'content-type': 'application/json'},
  request: request,
);
