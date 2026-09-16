import 'dart:convert';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('device records enforce identity and timestamp ordering', () {
    final enrolled = DateTime.utc(2026, 8, 24, 12);
    final before = enrolled.subtract(const Duration(seconds: 1));
    for (final (username, lastSeen, revoked) in <(String, DateTime, DateTime?)>[
      ('', enrolled, null),
      ('alice', before, null),
      ('alice', enrolled, before),
    ]) {
      expect(
        () => DeviceRecord(
          username: username,
          enrollment: _enrollment(),
          enrolledAt: enrolled,
          lastSeenAt: lastSeen,
          revokedAt: revoked,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => DeviceEnrollment.fromWampKeywords(null),
      throwsFormatException,
    );
    for (final value in <Map<String, dynamic>?>[
      null,
      {},
      {'devices': false},
      {
        'devices': [false],
      },
    ]) {
      expect(
        () => DeviceDirectory.fromWampKeywords(value),
        throwsFormatException,
      );
    }
    for (final name in ['a' * 81, 'control\u0000character']) {
      expect(
        () => DeviceEnrollment.fromWampKeywords({
          ..._enrollment().toWampKeywords(),
          'device_name': name,
        }),
        throwsFormatException,
      );
    }
  });

  test('conversation signature construction rejects empty identities', () {
    for (final (conversation, sender, recipient) in [
      ('', 'alice', 'bob'),
      ('a' * 201, 'alice', 'bob'),
      ('conversation', '', 'bob'),
      ('conversation', 'alice', ''),
    ]) {
      expect(
        () => WrappedConversationKey.signaturePayloadFor(
          conversationId: conversation,
          senderUsername: sender,
          senderDeviceId: _token(32, 1),
          recipientUsername: recipient,
          recipientDeviceId: _token(32, 2),
          sealedKey: _token(80, 3),
          createdAt: DateTime.utc(2026),
        ),
        throwsFormatException,
      );
    }
  });

  test('device enrollment has a stable account-bound attestation payload', () {
    final enrollment = _enrollment();

    final restored = DeviceEnrollment.fromWampKeywords(
      enrollment.toWampKeywords(),
    );

    expect(restored.deviceName, 'Alice phone');
    expect(
      utf8.decode(restored.attestationPayload(' Alice ')),
      [
        DeviceEnrollment.attestationVersion,
        'alice',
        _token(32, 1),
        'Alice phone',
        _token(32, 2),
        _token(32, 3),
        '2026-08-24T12:00:00.000Z',
      ].join('\n'),
    );
  });

  test('device enrollment rejects malformed key material', () {
    expect(
      () => DeviceEnrollment(
        deviceId: _token(31, 1),
        deviceName: 'Alice phone',
        signingPublicKey: _token(32, 2),
        exchangePublicKey: _token(32, 3),
        attestation: _token(64, 4),
        createdAt: DateTime.utc(2026, 8, 24),
      ),
      throwsFormatException,
    );
  });

  test(
    'device wire fields require typed dates and canonical unpadded keys',
    () {
      final wire = _enrollment().toWampKeywords();
      for (final invalid in <Map<String, dynamic>>[
        {'device_name': ''},
        {'device_name': 42},
        {'created_at': 42},
        {'created_at': 'invalid'},
        {'created_at': '2026-08-24T12:00:00'},
        {'signing_public_key': '='},
        {'signing_public_key': 'a'},
        {'signing_public_key': '${'A' * 42}B'},
      ]) {
        expect(
          () => DeviceEnrollment.fromWampKeywords({...wire, ...invalid}),
          throwsFormatException,
        );
      }
    },
  );

  test('device directory preserves active and revoked records', () {
    final active = DeviceRecord(
      username: 'alice',
      enrollment: _enrollment(),
      enrolledAt: DateTime.utc(2026, 8, 24, 12, 1),
      lastSeenAt: DateTime.utc(2026, 8, 24, 12, 2),
    );
    final revoked = DeviceRecord(
      username: 'alice',
      enrollment: DeviceEnrollment(
        deviceId: _token(32, 8),
        deviceName: 'Old tablet',
        signingPublicKey: _token(32, 9),
        exchangePublicKey: _token(32, 10),
        attestation: _token(64, 11),
        createdAt: DateTime.utc(2026, 8, 20),
      ),
      enrolledAt: DateTime.utc(2026, 8, 20, 1),
      lastSeenAt: DateTime.utc(2026, 8, 21),
      revokedAt: DateTime.utc(2026, 8, 22),
    );

    final restored = DeviceDirectory.fromWampKeywords(
      DeviceDirectory([active, revoked]).toWampKeywords(),
    );

    expect(restored.devices, hasLength(2));
    expect(restored.devices.first.isRevoked, isFalse);
    expect(restored.devices.first.deviceId, _token(32, 1));
    expect(restored.devices.last.isRevoked, isTrue);
  });

  test('conversation-key envelope is versioned and signature-bound', () {
    final envelope = WrappedConversationKey(
      conversationId: 'chat-alice-bob',
      senderUsername: 'alice',
      senderDeviceId: _token(32, 1),
      recipientUsername: 'bob',
      recipientDeviceId: _token(32, 2),
      sealedKey: _token(80, 3),
      signature: _token(64, 4),
      createdAt: DateTime.utc(2026, 8, 24, 12),
    );

    final restored = WrappedConversationKey.fromWampKeywords(
      envelope.toWampKeywords(),
    );

    expect(restored.conversationId, 'chat-alice-bob');
    for (final length in [79, 4097]) {
      expect(
        () => WrappedConversationKey.fromWampKeywords({
          ...envelope.toWampKeywords(),
          'sealed_key': _token(length, 3),
        }).signaturePayload(),
        throwsFormatException,
      );
    }
    expect(
      utf8.decode(restored.signaturePayload()),
      contains(WrappedConversationKey.algorithm),
    );
    expect(
      () => WrappedConversationKey.fromWampKeywords({
        ...envelope.toWampKeywords(),
        'algorithm': 'unknown',
      }),
      throwsFormatException,
    );
  });
}

DeviceEnrollment _enrollment() => DeviceEnrollment(
  deviceId: _token(32, 1),
  deviceName: 'Alice phone',
  signingPublicKey: _token(32, 2),
  exchangePublicKey: _token(32, 3),
  attestation: _token(64, 4),
  createdAt: DateTime.utc(2026, 8, 24, 12),
);

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');
