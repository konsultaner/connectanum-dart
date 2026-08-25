import 'dart:convert';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  final deviceId = base64Url
      .encode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');

  test('push request normalizes provider and round-trips opaque token', () {
    final request = PlatformPushSubscriptionRequest(
      deviceId: deviceId,
      provider: ' FCM ',
      token: 'opaque:provider-token_1',
    );

    expect(request.provider, 'fcm');
    expect(
      PlatformPushSubscriptionRequest.fromWampKeywords(
        request.toWampKeywords(),
      ).token,
      request.token,
    );
  });

  test('push receipt never includes the provider token', () {
    final receipt = PlatformPushSubscriptionReceipt(
      deviceId: deviceId,
      provider: 'fcm',
      registeredAt: DateTime.utc(2026, 8, 25, 10),
      updatedAt: DateTime.utc(2026, 8, 25, 11),
    );

    final wire = receipt.toWampKeywords();
    expect(wire, isNot(contains('token')));
    expect(
      PlatformPushSubscriptionReceipt.fromWampKeywords(wire).updatedAt,
      receipt.updatedAt,
    );
  });

  test('push subscription bounds reject malformed provider tokens', () {
    expect(
      () => PlatformPushSubscriptionRequest(
        deviceId: deviceId,
        provider: 'fcm',
        token: 'line\nbreak',
      ),
      throwsFormatException,
    );
    expect(
      () => PlatformPushSubscriptionRequest(
        deviceId: deviceId,
        provider: 'not a provider',
        token: 'token',
      ),
      throwsFormatException,
    );
    expect(
      () => PlatformPushSubscriptionRequest(
        deviceId: 'not-a-device',
        provider: 'fcm',
        token: 'token',
      ),
      throwsFormatException,
    );
    expect(
      () => PlatformPushSubscriptionRequest(
        deviceId: deviceId,
        provider: 'fcm',
        token: List<String>.filled(
          PlatformPushSubscriptionRequest.maxTokenLength + 1,
          'x',
        ).join(),
      ),
      throwsFormatException,
    );
  });

  test('unregister key rejects a missing provider or device', () {
    expect(
      () => PlatformPushSubscriptionKey(deviceId: deviceId, provider: ''),
      throwsFormatException,
    );
    expect(
      () =>
          PlatformPushSubscriptionKey.fromWampKeywords({'device_id': deviceId}),
      throwsFormatException,
    );
  });
}
