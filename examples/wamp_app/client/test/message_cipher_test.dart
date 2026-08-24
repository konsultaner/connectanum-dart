import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
      recipientUsername: encrypted.recipientUsername,
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
      await first.saveMailboxState(
        cursor: 7,
        messages: [
          LocalChatMessage(
            messageId: 'message-1',
            conversationId: 'conversation-1',
            peerUsername: 'bob',
            text: 'encrypted at rest',
            sentAt: DateTime.utc(2026, 8, 24, 12),
            outgoing: true,
          ),
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
      expect(reopened.messages.single.text, 'encrypted at rest');
      expect(
        storage.values.values.single,
        isNot(contains('encrypted at rest')),
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
  return _Fixtures(
    alice,
    bob,
    activeDeviceRecord('alice', alice.enrollment),
    activeDeviceRecord('bob', bob.enrollment),
  );
}

final class _Fixtures {
  const _Fixtures(this.alice, this.bob, this.aliceRecord, this.bobRecord);

  final DeviceTrustSession alice;
  final DeviceTrustSession bob;
  final DeviceRecord aliceRecord;
  final DeviceRecord bobRecord;

  Future<void> dispose() async {
    await alice.dispose();
    await bob.dispose();
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
