import 'dart:convert';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  final deviceId = base64Url
      .encode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');

  test('push provider and token bounds are inclusive and independent', () {
    final maximum = PlatformPushSubscriptionRequest(
      deviceId: deviceId,
      provider: 'a' * 32,
      token: '!${'x' * 4094}~',
    );
    final decoded = PlatformPushSubscriptionRequest.fromWampKeywords(
      maximum.toWampKeywords(),
    );
    expect(decoded.provider, 'a' * 32);
    expect(decoded.token.length, 4096);
    expect(decoded.token, startsWith('!'));
    expect(decoded.token, endsWith('~'));
    expect(
      PlatformPushSubscriptionKey(
        deviceId: deviceId,
        provider: 'a' * 32,
      ).provider,
      'a' * 32,
    );
    for (final provider in ['', 'a' * 33, '1fcm', 'fc/m']) {
      expect(
        () => PlatformPushSubscriptionRequest(
          deviceId: deviceId,
          provider: provider,
          token: 'valid',
        ),
        throwsFormatException,
      );
      expect(
        () =>
            PlatformPushSubscriptionKey(deviceId: deviceId, provider: provider),
        throwsFormatException,
      );
    }
    for (final token in ['', 'x' * 4097, ' ', '\u007f', '\u0080', 'x\ny']) {
      expect(
        () => PlatformPushSubscriptionRequest(
          deviceId: deviceId,
          provider: 'fcm',
          token: token,
        ),
        throwsFormatException,
      );
    }
  });

  test('exactly 500 muted conversations of 200 characters remain intact', () {
    final ids = List.generate(
      500,
      (index) => '${index.toString().padLeft(3, '0')}${'x' * 197}',
    ).reversed.toList();
    final request = PlatformPushSubscriptionRequest(
      deviceId: deviceId,
      provider: 'fcm',
      token: 'valid',
      mutedConversationIds: ids,
    );
    ids.clear();
    final decoded = PlatformPushSubscriptionRequest.fromWampKeywords(
      request.toWampKeywords(),
    );
    expect(decoded.mutedConversationIds.length, 500);
    expect(decoded.mutedConversationIds.first, '000${'x' * 197}');
    expect(decoded.mutedConversationIds.last, '499${'x' * 197}');
    expect(() => decoded.mutedConversationIds.clear(), throwsUnsupportedError);
  });

  test(
    'push receipts allow equality but reject updates before registration',
    () {
      final registered = DateTime.utc(2026, 9, 16);
      for (final updated in [
        registered,
        registered.add(const Duration(seconds: 1)),
      ]) {
        final receipt = PlatformPushSubscriptionReceipt(
          deviceId: deviceId,
          provider: 'fcm',
          registeredAt: registered,
          updatedAt: updated,
        );
        expect(
          PlatformPushSubscriptionReceipt.fromWampKeywords(
            receipt.toWampKeywords(),
          ).updatedAt,
          updated,
        );
      }
      expect(
        () => PlatformPushSubscriptionReceipt(
          deviceId: deviceId,
          provider: 'fcm',
          registeredAt: registered,
          updatedAt: registered.subtract(const Duration(microseconds: 1)),
        ),
        throwsFormatException,
      );
    },
  );

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

  test(
    'subscription keys round-trip and malformed receipt dates fail closed',
    () {
      final key = PlatformPushSubscriptionKey.fromWampKeywords({
        'device_id': deviceId,
        'provider': ' FCM ',
      });
      expect(key.toWampKeywords(), {'device_id': deviceId, 'provider': 'fcm'});
      expect(
        () => PlatformPushSubscriptionKey.fromWampKeywords(null),
        throwsFormatException,
      );
      final receipt = PlatformPushSubscriptionReceipt(
        deviceId: deviceId,
        provider: 'fcm',
        registeredAt: DateTime.utc(2026, 8, 25, 10),
        updatedAt: DateTime.utc(2026, 8, 25, 11),
      ).toWampKeywords();
      for (final field in ['registered_at', 'updated_at']) {
        for (final value in <Object?>[
          null,
          42,
          'invalid',
          '2026-08-25T11:00:00',
        ]) {
          expect(
            () => PlatformPushSubscriptionReceipt.fromWampKeywords({
              ...receipt,
              field: value,
            }),
            throwsFormatException,
          );
        }
      }
    },
  );

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
