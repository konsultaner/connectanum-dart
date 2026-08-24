import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory directory;
  late AccountStore accounts;
  late MailboxStore mailbox;
  late MessageService service;
  late _TestDevice alice;
  late _TestDevice bob;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wamp-message-service-');
    accounts = AccountStore('${directory.path}/accounts.json');
    mailbox = MailboxStore('${directory.path}/messages.json');
    await accounts.initialize();
    await mailbox.initialize();
    await accounts.create(_account('alice'));
    await accounts.create(_account('bob'));
    alice = await _enroll(accounts, 'alice', 1);
    bob = await _enroll(accounts, 'bob', 2);
    service = MessageService(accounts: accounts, mailbox: mailbox);
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'accepts signed key coverage for every active participant device',
    () async {
      final message = _message(alice, bob);

      final receipt = await service.send(
        'alice',
        message,
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final retry = await service.send(
        'alice',
        message,
        now: DateTime.utc(2026, 8, 24, 12, 1),
      );

      expect(receipt.duplicate, isFalse);
      expect(retry.duplicate, isTrue);
      expect(
        (await service.sync('bob', afterCursor: 0)).messages,
        hasLength(1),
      );
    },
  );

  test(
    'rejects caller spoofing, missing device coverage, and bad signatures',
    () async {
      final valid = _message(alice, bob);
      expect(
        () =>
            service.send('mallory', valid, now: DateTime.utc(2026, 8, 24, 12)),
        throwsStateError,
      );

      final missingBob = EncryptedChatMessage(
        messageId: valid.messageId,
        conversationId: valid.conversationId,
        senderUsername: valid.senderUsername,
        senderDeviceId: valid.senderDeviceId,
        recipientUsername: valid.recipientUsername,
        createdAt: valid.createdAt,
        encryptedPayload: valid.encryptedPayload,
        wrappedKeys: [valid.wrappedKeys.first],
      );
      expect(
        () => service.send(
          'alice',
          missingBob,
          now: DateTime.utc(2026, 8, 24, 12),
        ),
        throwsFormatException,
      );

      final bobEnvelope = valid.wrappedKeys.last;
      final badSignature = WrappedConversationKey(
        conversationId: bobEnvelope.conversationId,
        senderUsername: bobEnvelope.senderUsername,
        senderDeviceId: bobEnvelope.senderDeviceId,
        recipientUsername: bobEnvelope.recipientUsername,
        recipientDeviceId: bobEnvelope.recipientDeviceId,
        sealedKey: bobEnvelope.sealedKey,
        signature: _token(64, 44),
        createdAt: bobEnvelope.createdAt,
      );
      final tampered = EncryptedChatMessage(
        messageId: valid.messageId,
        conversationId: valid.conversationId,
        senderUsername: valid.senderUsername,
        senderDeviceId: valid.senderDeviceId,
        recipientUsername: valid.recipientUsername,
        createdAt: valid.createdAt,
        encryptedPayload: valid.encryptedPayload,
        wrappedKeys: [valid.wrappedKeys.first, badSignature],
      );
      expect(
        () =>
            service.send('alice', tampered, now: DateTime.utc(2026, 8, 24, 12)),
        throwsFormatException,
      );

      final oneTime = EncryptedChatMessage(
        messageId: _token(16, 77),
        conversationId: valid.conversationId,
        senderUsername: valid.senderUsername,
        senderDeviceId: valid.senderDeviceId,
        recipientUsername: valid.recipientUsername,
        createdAt: valid.createdAt,
        oneTime: true,
        encryptedPayload: valid.encryptedPayload,
        wrappedKeys: valid.wrappedKeys,
      );
      expect(
        () =>
            service.send('alice', oneTime, now: DateTime.utc(2026, 8, 24, 12)),
        throwsFormatException,
      );
    },
  );

  test(
    'device lookup can preserve historical revoked signing identities',
    () async {
      await accounts.revokeDevice(
        'alice',
        alice.record.deviceId,
        now: DateTime.utc(2026, 8, 24, 13),
      );

      expect((await service.lookupDevices('alice')).devices, isEmpty);
      final historical = await service.lookupDevices(
        'alice',
        includeRevoked: true,
      );
      expect(historical.devices.single.deviceId, alice.record.deviceId);
      expect(historical.devices.single.isRevoked, isTrue);
    },
  );
}

EncryptedChatMessage _message(_TestDevice sender, _TestDevice recipient) {
  final conversationId = _token(32, 8);
  final createdAt = DateTime.utc(2026, 8, 24, 12);
  return EncryptedChatMessage(
    messageId: _token(16, 9),
    conversationId: conversationId,
    senderUsername: sender.record.username,
    senderDeviceId: sender.record.deviceId,
    recipientUsername: recipient.record.username,
    createdAt: createdAt,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 10)),
    wrappedKeys: [
      _wrapped(sender, sender.record, conversationId, createdAt),
      _wrapped(sender, recipient.record, conversationId, createdAt),
    ],
  );
}

WrappedConversationKey _wrapped(
  _TestDevice sender,
  DeviceRecord recipient,
  String conversationId,
  DateTime createdAt,
) {
  final sealedKey = _token(80, recipient.username == 'alice' ? 11 : 12);
  final payload = WrappedConversationKey.signaturePayloadFor(
    conversationId: conversationId,
    senderUsername: sender.record.username,
    senderDeviceId: sender.record.deviceId,
    recipientUsername: recipient.username,
    recipientDeviceId: recipient.deviceId,
    sealedKey: sealedKey,
    createdAt: createdAt,
  );
  return WrappedConversationKey(
    conversationId: conversationId,
    senderUsername: sender.record.username,
    senderDeviceId: sender.record.deviceId,
    recipientUsername: recipient.username,
    recipientDeviceId: recipient.deviceId,
    sealedKey: sealedKey,
    signature: _encode(
      sender.signingKey.sign(Uint8List.fromList(payload)).signature.asTypedList,
    ),
    createdAt: createdAt,
  );
}

Future<_TestDevice> _enroll(
  AccountStore accounts,
  String username,
  int seed,
) async {
  final signingKey = SigningKey.generate();
  final signingPublicKey = signingKey.verifyKey.asTypedList;
  final exchangePublicKey = Uint8List.fromList(
    List<int>.generate(32, (index) => (index + seed) % 256),
  );
  final deviceId = _encode(
    sha256.convert([...signingPublicKey, ...exchangePublicKey]).bytes,
  );
  final createdAt = DateTime.utc(2026, 8, 24, 11);
  final payload = DeviceEnrollment.attestationPayloadFor(
    username: username,
    deviceId: deviceId,
    deviceName: '$username device',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    createdAt: createdAt,
  );
  final enrollment = DeviceEnrollment(
    deviceId: deviceId,
    deviceName: '$username device',
    signingPublicKey: _encode(signingPublicKey),
    exchangePublicKey: _encode(exchangePublicKey),
    attestation: _encode(
      signingKey.sign(Uint8List.fromList(payload)).signature.asTypedList,
    ),
    createdAt: createdAt,
  );
  final record = await DeviceService(
    store: accounts,
  ).enroll(username, enrollment, now: createdAt);
  return _TestDevice(signingKey, record);
}

StoredAccount _account(String username) => StoredAccount(
  username: username,
  displayName: username,
  storedKey: 'stored',
  serverKey: 'server',
  salt: 'salt',
  iterations: 3,
  memoryKiB: 65536,
  kdf: 'argon2id13',
  createdAt: DateTime.utc(2026, 8, 24),
);

final class _TestDevice {
  const _TestDevice(this.signingKey, this.record);

  final SigningKey signingKey;
  final DeviceRecord record;
}

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');

String _token(int length, int value) =>
    _encode(List<int>.filled(length, value));
