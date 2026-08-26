import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_chat_group.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/message_cipher.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  test(
    'encrypts for both devices and opens only with the recipient key',
    () async {
      final fixtures = await _fixtures();
      addTearDown(fixtures.dispose);

      final encrypted = MessageCipher().encrypt(
        senderUsername: 'alice',
        recipientUsername: 'bob',
        text: 'server never sees this text',
        trust: fixtures.alice,
        participantDevices: [fixtures.aliceRecord, fixtures.bobRecord],
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final decrypted = MessageCipher().decrypt(
        message: encrypted,
        username: 'bob',
        trust: fixtures.bob,
        sender: fixtures.aliceRecord,
      );

      expect(encrypted.wrappedKeys, hasLength(2));
      expect(decrypted.text, 'server never sees this text');
      expect(decrypted.peerUsername, 'alice');
      expect(decrypted.outgoing, isFalse);
    },
  );

  test('ciphertext tampering fails closed', () async {
    final fixtures = await _fixtures();
    addTearDown(fixtures.dispose);
    final encrypted = MessageCipher().encrypt(
      senderUsername: 'alice',
      recipientUsername: 'bob',
      text: 'authentic',
      trust: fixtures.alice,
      participantDevices: [fixtures.aliceRecord, fixtures.bobRecord],
      now: DateTime.utc(2026, 8, 24, 12),
    );
    final payload = encrypted.encryptedPayload..[30] ^= 0xff;
    final tampered = EncryptedChatMessage(
      messageId: encrypted.messageId,
      conversationId: encrypted.conversationId,
      senderUsername: encrypted.senderUsername,
      senderDeviceId: encrypted.senderDeviceId,
      recipientUsername: encrypted.recipientUsername!,
      createdAt: encrypted.createdAt,
      encryptedPayload: payload,
      wrappedKeys: encrypted.wrappedKeys,
    );

    expect(
      () => MessageCipher().decrypt(
        message: tampered,
        username: 'bob',
        trust: fixtures.bob,
        sender: fixtures.aliceRecord,
      ),
      throwsFormatException,
    );
  });

  test(
    'attachment descriptors stay inside E2EE payload and bind outer ids',
    () async {
      final fixtures = await _fixtures();
      addTearDown(fixtures.dispose);
      final descriptor = EncryptedAttachmentDescriptor(
        attachmentId: 'attachment_identifier_1234',
        kind: ChatAttachmentKind.image,
        name: 'private-name.jpg',
        contentType: 'image/jpeg',
        plaintextBytes: 7,
        chunkBytes: 1024,
        chunkCount: 1,
        plaintextSha256:
            '00c2022f72e87c4dd19fbbcde2e81698de69782c23f0b8c56c9b3581b1e2d770',
        key: Uint8List.fromList(List<int>.generate(32, (index) => index)),
      );
      final encrypted = MessageCipher().encrypt(
        senderUsername: 'alice',
        recipientUsername: 'bob',
        text: '',
        trust: fixtures.alice,
        participantDevices: [fixtures.aliceRecord, fixtures.bobRecord],
        now: DateTime.utc(2026, 8, 24, 12),
        attachments: [descriptor],
      );

      expect(encrypted.attachmentIds, [descriptor.attachmentId]);
      expect(
        encrypted.toJson().toString(),
        isNot(contains('private-name.jpg')),
      );
      expect(encrypted.toJson().toString(), isNot(contains('image/jpeg')));
      final decrypted = MessageCipher().decrypt(
        message: encrypted,
        username: 'bob',
        trust: fixtures.bob,
        sender: fixtures.aliceRecord,
      );
      expect(decrypted.text, isEmpty);
      expect(decrypted.attachments.single.toJson(), descriptor.toJson());

      final conflicting = EncryptedChatMessage(
        messageId: encrypted.messageId,
        conversationId: encrypted.conversationId,
        senderUsername: encrypted.senderUsername,
        senderDeviceId: encrypted.senderDeviceId,
        recipientUsername: encrypted.recipientUsername!,
        createdAt: encrypted.createdAt,
        encryptedPayload: encrypted.encryptedPayload,
        wrappedKeys: encrypted.wrappedKeys,
        attachmentIds: const ['different_attachment_1234'],
      );
      expect(
        () => MessageCipher().decrypt(
          message: conflicting,
          username: 'bob',
          trust: fixtures.bob,
          sender: fixtures.aliceRecord,
        ),
        throwsFormatException,
      );
    },
  );

  test('one group ciphertext opens for every participant device', () async {
    final fixtures = await _fixtures();
    addTearDown(fixtures.dispose);
    final group = LocalChatGroup(
      conversationId: 'group-conversation',
      title: 'Launch crew',
      memberUsernames: const ['carol', 'alice', 'bob'],
      createdBy: 'alice',
      createdAt: DateTime.utc(2026, 8, 24, 11),
    );

    final encrypted = MessageCipher().encryptGroup(
      senderUsername: 'alice',
      group: group,
      text: 'one atomic encrypted payload',
      trust: fixtures.alice,
      participantDevices: [
        fixtures.aliceRecord,
        fixtures.bobRecord,
        fixtures.carolRecord,
      ],
      now: DateTime.utc(2026, 8, 24, 12),
    );
    final bobMessage = MessageCipher().decrypt(
      message: encrypted,
      username: 'bob',
      trust: fixtures.bob,
      sender: fixtures.aliceRecord,
    );
    final carolMessage = MessageCipher().decrypt(
      message: encrypted,
      username: 'carol',
      trust: fixtures.carol,
      sender: fixtures.aliceRecord,
    );

    expect(encrypted.wrappedKeys, hasLength(3));
    expect(bobMessage.text, 'one atomic encrypted payload');
    expect(carolMessage.text, bobMessage.text);
    expect(bobMessage.group?.hasSameDefinition(group), isTrue);
    expect(carolMessage.group?.hasSameDefinition(group), isTrue);

    final conflictingOuter = EncryptedChatMessage.group(
      messageId: encrypted.messageId,
      conversationId: encrypted.conversationId,
      senderUsername: encrypted.senderUsername,
      senderDeviceId: encrypted.senderDeviceId,
      participantUsernames: const ['alice', 'bob'],
      createdAt: encrypted.createdAt,
      encryptedPayload: encrypted.encryptedPayload,
      wrappedKeys: encrypted.wrappedKeys
          .where((key) => key.recipientUsername != 'carol')
          .toList(growable: false),
    );
    expect(
      () => MessageCipher().decrypt(
        message: conflictingOuter,
        username: 'bob',
        trust: fixtures.bob,
        sender: fixtures.aliceRecord,
      ),
      throwsFormatException,
    );
  });

  test(
    'encrypted vault persists mailbox cursor and plaintext history',
    () async {
      final storage = _MemoryStorage();
      final vault = EncryptedDeviceVault(
        storage: storage,
        keyDeriver: const _TestDeriver(),
        iterations: 1,
        memoryKiB: 64,
      );
      final endpoint = ServerEndpoint.parse('wss://chat.example/ws');
      final first = await vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'password',
        deviceName: 'Phone',
      );
      final group = LocalChatGroup(
        conversationId: 'group-conversation',
        title: 'Encrypted at rest group',
        memberUsernames: const ['alice', 'bob'],
        createdBy: 'alice',
        createdAt: DateTime.utc(2026, 8, 24, 11),
      );
      final groupMessage = LocalChatMessage(
        messageId: 'message-2',
        conversationId: group.conversationId,
        peerUsername: 'bob',
        text: 'encrypted group history',
        sentAt: DateTime.utc(2026, 8, 24, 12, 1),
        outgoing: false,
        groupTitle: group.title,
        participantUsernames: group.memberUsernames,
        groupCreatedBy: group.createdBy,
        groupCreatedAt: group.createdAt,
      );
      expect(
        LocalChatGroup.fromJson(group.toJson()).hasSameDefinition(group),
        isTrue,
      );
      expect(
        LocalChatMessage.fromJson(groupMessage.toJson()).group
            ?.hasSameDefinition(group),
        isTrue,
      );
      await first.saveMailboxState(
        cursor: 7,
        groups: [group],
        messages: [
          LocalChatMessage(
            messageId: 'message-1',
            conversationId: 'conversation-1',
            peerUsername: 'bob',
            text: 'encrypted at rest',
            sentAt: DateTime.utc(2026, 8, 24, 12),
            outgoing: true,
          ),
          groupMessage,
        ],
      );
      await first.dispose();

      final reopened = await vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'password',
        deviceName: 'Ignored',
      );
      addTearDown(reopened.dispose);
      expect(reopened.mailboxCursor, 7);
      expect(reopened.messages, hasLength(2));
      expect(reopened.messages.first.text, 'encrypted at rest');
      expect(reopened.messages.last.group?.hasSameDefinition(group), isTrue);
      expect(reopened.groups.single.title, 'Encrypted at rest group');
      expect(
        storage.values.values.single,
        isNot(contains('encrypted at rest')),
      );
      expect(
        storage.values.values.single,
        isNot(contains('Encrypted at rest group')),
      );
    },
  );
}

Future<_Fixtures> _fixtures() async {
  final vault = EncryptedDeviceVault(
    storage: _MemoryStorage(),
    keyDeriver: const _TestDeriver(),
    iterations: 1,
    memoryKiB: 64,
  );
  final endpoint = ServerEndpoint.parse('wss://chat.example/ws');
  final alice = await vault.openOrCreate(
    endpoint: endpoint,
    username: 'alice',
    password: 'alice-password',
    deviceName: 'Alice phone',
  );
  final bob = await vault.openOrCreate(
    endpoint: endpoint,
    username: 'bob',
    password: 'bob-password',
    deviceName: 'Bob phone',
  );
  final carol = await vault.openOrCreate(
    endpoint: endpoint,
    username: 'carol',
    password: 'carol-password',
    deviceName: 'Carol phone',
  );
  return _Fixtures(
    alice,
    bob,
    carol,
    activeDeviceRecord('alice', alice.enrollment),
    activeDeviceRecord('bob', bob.enrollment),
    activeDeviceRecord('carol', carol.enrollment),
  );
}

final class _Fixtures {
  const _Fixtures(
    this.alice,
    this.bob,
    this.carol,
    this.aliceRecord,
    this.bobRecord,
    this.carolRecord,
  );

  final DeviceTrustSession alice;
  final DeviceTrustSession bob;
  final DeviceTrustSession carol;
  final DeviceRecord aliceRecord;
  final DeviceRecord bobRecord;
  final DeviceRecord carolRecord;

  Future<void> dispose() async {
    await alice.dispose();
    await bob.dispose();
    await carol.dispose();
  }
}

final class _TestDeriver implements VaultKeyDeriver {
  const _TestDeriver();

  @override
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  }) async => Uint8List.fromList(
    List<int>.generate(
      32,
      (index) => password.codeUnitAt(index % password.length),
    ),
  );
}

final class _MemoryStorage implements VaultStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
