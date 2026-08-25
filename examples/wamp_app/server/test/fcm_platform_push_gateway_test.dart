import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
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
  Object body,
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
