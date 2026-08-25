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

  test('push request canonicalizes and round-trips muted conversations', () {
    final request = PlatformPushSubscriptionRequest(
      deviceId: deviceId,
      provider: 'fcm',
      token: 'opaque-token',
      mutedConversationIds: const ['conversation-b', 'conversation-a'],
    );

    expect(request.mutedConversationIds, ['conversation-a', 'conversation-b']);
    final decoded = PlatformPushSubscriptionRequest.fromWampKeywords(
      request.toWampKeywords(),
    );
    expect(decoded.mutedConversationIds, request.mutedConversationIds);
  });

  test('push request remains compatible when mute policy is absent', () {
    final decoded = PlatformPushSubscriptionRequest.fromWampKeywords({
      'device_id': deviceId,
      'provider': 'fcm',
      'token': 'opaque-token',
    });

    expect(decoded.mutedConversationIds, isEmpty);
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

  test('push subscription bounds reject malformed mute policy', () {
    PlatformPushSubscriptionRequest requestWith(Iterable<String> values) =>
        PlatformPushSubscriptionRequest(
          deviceId: deviceId,
          provider: 'fcm',
          token: 'opaque-token',
          mutedConversationIds: values,
        );

    expect(
      () => requestWith(const ['conversation', 'conversation']),
      throwsFormatException,
    );
    expect(() => requestWith(const ['']), throwsFormatException);
    expect(
      () => requestWith([
        'x' * (PlatformPushSubscriptionRequest.maxConversationIdLength + 1),
      ]),
      throwsFormatException,
    );
    expect(
      () => requestWith(
        List<String>.generate(
          PlatformPushSubscriptionRequest.maxMutedConversations + 1,
          (index) => 'conversation-$index',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => PlatformPushSubscriptionRequest.fromWampKeywords({
        'device_id': deviceId,
        'provider': 'fcm',
        'token': 'opaque-token',
        'muted_conversation_ids': 'conversation',
      }),
      throwsFormatException,
    );
    expect(
      () => PlatformPushSubscriptionRequest.fromWampKeywords({
        'device_id': deviceId,
        'provider': 'fcm',
        'token': 'opaque-token',
        'muted_conversation_ids': [42],
      }),
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
