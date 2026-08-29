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
  late AttachmentStore attachments;
  late MailboxStore mailbox;
  late MessageService service;
  late _TestDevice alice;
  late _TestDevice bob;
  late _TestDevice carol;
  late _TestDevice mallory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wamp-message-service-');
    accounts = AccountStore('${directory.path}/accounts.json');
    attachments = AttachmentStore('${directory.path}/attachments');
    mailbox = MailboxStore('${directory.path}/messages.json');
    await accounts.initialize();
    await attachments.initialize();
    await mailbox.initialize();
    await accounts.create(_account('alice'));
    await accounts.create(_account('bob'));
    await accounts.create(_account('carol'));
    await accounts.create(_account('mallory'));
    alice = await _enroll(accounts, 'alice', 1);
    bob = await _enroll(accounts, 'bob', 2);
    carol = await _enroll(accounts, 'carol', 3);
    mallory = await _enroll(accounts, 'mallory', 4);
    service = MessageService(
      accounts: accounts,
      mailbox: mailbox,
      attachments: attachments,
    );
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

  test('rejects messages until every referenced chunk is durable', () async {
    final attachmentId = _token(16, 80);
    final message = _message(
      alice,
      bob,
      messageSeed: 79,
      attachmentIds: [attachmentId],
    );

    await expectLater(
      service.send('alice', message, now: DateTime.utc(2026, 8, 24, 12)),
      throwsA(isA<AttachmentIncomplete>()),
    );
    expect((await mailbox.sync('alice', afterCursor: 0)).messages, isEmpty);

    final bytes = Uint8List.fromList(
      List<int>.filled(WampAppAttachmentLimits.secretBoxOverheadBytes, 81),
    );
    await attachments.put(
      EncryptedAttachmentChunk(
        senderUsername: 'alice',
        messageId: message.messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
        ciphertextSha256: sha256.convert(bytes).toString(),
        encryptedBytes: bytes,
      ),
    );

    final receipt = await service.send(
      'alice',
      message,
      now: DateTime.utc(2026, 8, 24, 12),
    );
    expect(receipt.duplicate, isFalse);
  });

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
        recipientUsername: valid.recipientUsername!,
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
        recipientUsername: valid.recipientUsername!,
        createdAt: valid.createdAt,
        encryptedPayload: valid.encryptedPayload,
        wrappedKeys: [valid.wrappedKeys.first, badSignature],
      );
      expect(
        () =>
            service.send('alice', tampered, now: DateTime.utc(2026, 8, 24, 12)),
        throwsFormatException,
      );
    },
  );

  test('one-time messages require an active consuming device', () async {
    final message = _message(alice, bob, oneTime: true, messageSeed: 77);
    final sent = await service.send(
      'alice',
      message,
      now: DateTime.utc(2026, 8, 24, 12),
    );

    expect(sent.duplicate, isFalse);
    expect(
      () => service.consumeOneTime(
        'bob',
        OneTimeMessageConsumption(
          messageId: message.messageId,
          deviceId: _token(32, 99),
          signature: _token(64, 98),
        ),
      ),
      throwsStateError,
    );
    final forged = _consumption(alice, 'bob', message.messageId);
    final claimedBob = OneTimeMessageConsumption(
      messageId: forged.messageId,
      deviceId: bob.record.deviceId,
      signature: forged.signature,
    );
    expect(() => service.consumeOneTime('bob', claimedBob), throwsStateError);
    final consumed = await service.consumeOneTime(
      'bob',
      _consumption(bob, 'bob', message.messageId),
      now: DateTime.utc(2026, 8, 24, 12, 1),
    );
    expect(consumed.receipt.consumedAt, DateTime.utc(2026, 8, 24, 12, 1));
  });

  test(
    'one-time attachment consumption deletes ciphertext before success',
    () async {
      final attachmentId = _token(16, 91);
      final message = _message(
        alice,
        bob,
        oneTime: true,
        messageSeed: 90,
        attachmentIds: [attachmentId],
      );
      final bytes = Uint8List.fromList(
        List<int>.filled(WampAppAttachmentLimits.secretBoxOverheadBytes, 92),
      );
      await attachments.put(
        EncryptedAttachmentChunk(
          senderUsername: 'alice',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          chunkCount: 1,
          ciphertextSha256: sha256.convert(bytes).toString(),
          encryptedBytes: bytes,
        ),
      );
      await service.send('alice', message, now: DateTime.utc(2026, 8, 24, 12));
      final attachmentService = AttachmentService(
        store: attachments,
        mailbox: mailbox,
      );
      expect(
        (await attachmentService.getChunk(
          'bob',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          now: DateTime.utc(2026, 8, 24, 12),
        )).encryptedBytes,
        bytes,
      );

      final proof = _consumption(bob, 'bob', message.messageId);
      final consumed = await service.consumeOneTime(
        'bob',
        proof,
        now: DateTime.utc(2026, 8, 24, 12, 1),
      );

      expect(consumed.receipt.consumedAt, isNotNull);
      expect(attachments.totalBytes, 0);
      await expectLater(
        attachmentService.getChunk(
          'bob',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
        ),
        throwsA(isA<AttachmentNotFound>()),
      );
      final retry = await service.consumeOneTime('bob', proof);
      expect(retry.receipt.cursor, consumed.receipt.cursor);
      expect(attachments.totalBytes, 0);
    },
  );

  test('revoked devices cannot consume one-time messages', () async {
    final message = _message(alice, bob, oneTime: true, messageSeed: 78);
    await service.send('alice', message, now: DateTime.utc(2026, 8, 24, 12));
    await accounts.revokeDevice(
      'bob',
      bob.record.deviceId,
      now: DateTime.utc(2026, 8, 24, 12, 1),
    );

    expect(
      () => service.consumeOneTime(
        'bob',
        _consumption(bob, 'bob', message.messageId),
      ),
      throwsStateError,
    );
    expect((await service.sync('alice', afterCursor: 0)).nextCursor, 1);
  });

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

  test(
    'group send is one atomic record visible only to participants',
    () async {
      final message = _groupMessage(alice, [alice, bob, carol]);

      final sent = await service.send(
        'alice',
        message,
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final retry = await service.send(
        'alice',
        message,
        now: DateTime.utc(2026, 8, 24, 12, 1),
      );

      expect(sent.duplicate, isFalse);
      expect(retry.duplicate, isTrue);
      for (final username in ['alice', 'bob', 'carol']) {
        final batch = await service.sync(username, afterCursor: 0);
        expect(batch.messages, hasLength(1));
        expect(batch.messages.single.message.messageId, message.messageId);
      }
      expect((await service.sync('mallory', afterCursor: 0)).messages, isEmpty);
    },
  );

  test(
    'group send requires every active device of every participant',
    () async {
      await _enroll(accounts, 'bob', 5);
      final missingSecondBobDevice = _groupMessage(alice, [alice, bob, carol]);

      expect(
        () => service.send(
          'alice',
          missingSecondBobDevice,
          now: DateTime.utc(2026, 8, 24, 12),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'group recipients update only their own durable receipt state',
    () async {
      final message = _groupMessage(alice, [alice, bob, carol]);
      await service.send('alice', message, now: DateTime.utc(2026, 8, 24, 12));

      await Future.wait([
        service.markReceipt(
          'bob',
          message.messageId,
          read: false,
          now: DateTime.utc(2026, 8, 24, 12, 1),
        ),
        service.markReceipt(
          'carol',
          message.messageId,
          read: true,
          now: DateTime.utc(2026, 8, 24, 12, 2),
        ),
      ]);

      final latest = (await service.sync(
        'alice',
        afterCursor: 0,
      )).messages.last;
      expect(latest.recipientStateFor('bob')?.deliveredAt, isNotNull);
      expect(latest.recipientStateFor('bob')?.readAt, isNull);
      expect(latest.recipientStateFor('carol')?.readAt, isNotNull);
      expect(latest.deliveredAtFor('alice'), DateTime.utc(2026, 8, 24, 12, 2));
      expect(latest.readAtFor('alice'), isNull);
      expect(
        () => service.markReceipt('alice', message.messageId, read: true),
        throwsStateError,
      );
      expect(
        () => service.markReceipt(
          mallory.record.username,
          message.messageId,
          read: true,
        ),
        throwsStateError,
      );
    },
  );
}

OneTimeMessageConsumption _consumption(
  _TestDevice device,
  String username,
  String messageId,
) {
  final payload = OneTimeMessageConsumption.signaturePayloadFor(
    username: username,
    messageId: messageId,
    deviceId: device.record.deviceId,
  );
  return OneTimeMessageConsumption(
    messageId: messageId,
    deviceId: device.record.deviceId,
    signature: _encode(
      device.signingKey.sign(Uint8List.fromList(payload)).signature.asTypedList,
    ),
  );
}

EncryptedChatMessage _message(
  _TestDevice sender,
  _TestDevice recipient, {
  bool oneTime = false,
  int messageSeed = 9,
  List<String> attachmentIds = const [],
}) {
  final conversationId = _token(32, 8);
  final createdAt = DateTime.utc(2026, 8, 24, 12);
  return EncryptedChatMessage(
    messageId: _token(16, messageSeed),
    conversationId: conversationId,
    senderUsername: sender.record.username,
    senderDeviceId: sender.record.deviceId,
    recipientUsername: recipient.record.username,
    createdAt: createdAt,
    oneTime: oneTime,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 10)),
    attachmentIds: attachmentIds,
    wrappedKeys: [
      _wrapped(sender, sender.record, conversationId, createdAt),
      _wrapped(sender, recipient.record, conversationId, createdAt),
    ],
  );
}

EncryptedChatMessage _groupMessage(
  _TestDevice sender,
  List<_TestDevice> participants,
) {
  final conversationId = _token(32, 80);
  final createdAt = DateTime.utc(2026, 8, 24, 12);
  return EncryptedChatMessage.group(
    messageId: _token(16, 81),
    conversationId: conversationId,
    senderUsername: sender.record.username,
    senderDeviceId: sender.record.deviceId,
    participantUsernames: participants
        .map((device) => device.record.username)
        .toList(growable: false),
    createdAt: createdAt,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 82)),
    wrappedKeys: [
      for (final participant in participants)
        _wrapped(sender, participant.record, conversationId, createdAt),
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
