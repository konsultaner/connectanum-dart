import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  late MemoryVaultStorage storage;
  late EncryptedDeviceVault vault;
  final endpoint = ServerEndpoint.parse('ws://localhost:8080/ws');

  setUp(() {
    storage = MemoryVaultStorage();
    vault = EncryptedDeviceVault(
      storage: storage,
      keyDeriver: const _TestKeyDeriver(),
      iterations: 2,
      memoryKiB: 64,
    );
  });

  test('persists only encrypted, account-bound device material', () async {
    final first = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    addTearDown(first.dispose);

    final encoded = storage.values.values.single;
    expect(encoded, contains('ciphertext'));
    expect(encoded, isNot(contains('correct horse battery')));
    expect(encoded, isNot(contains('signing_seed')));
    expect(encoded, isNot(contains('exchange_private_key')));
    expect(encoded, isNot(contains('alice')));

    final reopened = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Ignored replacement name',
    );
    addTearDown(reopened.dispose);
    expect(reopened.deviceId, first.deviceId);
  });

  test('wrong password and ciphertext tampering fail closed', () async {
    final created = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    await created.dispose();

    await expectLater(
      vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'wrong horse battery',
        deviceName: 'Alice phone',
      ),
      throwsA(isA<VaultUnlockException>()),
    );

    final key = storage.values.keys.single;
    final envelope = jsonDecode(storage.values[key]!) as Map<String, dynamic>;
    final ciphertext = envelope['ciphertext'] as String;
    envelope['ciphertext'] =
        '${ciphertext[0] == 'A' ? 'B' : 'A'}'
        '${ciphertext.substring(1)}';
    storage.values[key] = jsonEncode(envelope);
    await expectLater(
      vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'correct horse battery',
        deviceName: 'Alice phone',
      ),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('ciphertext copied to another account is rejected', () async {
    final alice = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'same password',
      deviceName: 'Alice phone',
    );
    await alice.dispose();
    final aliceEntry = storage.values.entries.single;

    final bob = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'bob',
      password: 'same password',
      deviceName: 'Bob phone',
    );
    await bob.dispose();
    final bobKey = storage.values.keys.singleWhere(
      (key) => key != aliceEntry.key,
    );
    storage.values[bobKey] = aliceEntry.value;

    await expectLater(
      vault.openOrCreate(
        endpoint: endpoint,
        username: 'bob',
        password: 'same password',
        deviceName: 'Bob phone',
      ),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('concurrent opens cannot create competing device identities', () async {
    final sessions = await Future.wait([
      vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'correct horse battery',
        deviceName: 'Alice phone',
      ),
      vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'correct horse battery',
        deviceName: 'Alice phone',
      ),
    ]);
    addTearDown(
      () => Future.wait(sessions.map((session) => session.dispose())),
    );

    expect(sessions[0].deviceId, sessions[1].deviceId);
  });

  test('safety verification survives encrypted vault reopen', () async {
    final alice = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    final bob = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'bob',
      password: 'another correct horse',
      deviceName: 'Bob phone',
    );
    final bobRecord = _record('bob', bob.enrollment);

    expect(alice.isVerified(bobRecord), isFalse);
    await alice.markVerified(bobRecord);
    await alice.dispose();
    await bob.dispose();

    final reopened = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    addTearDown(reopened.dispose);
    expect(reopened.isVerified(bobRecord), isTrue);
  });

  test('conversation keys are recipient-sealed and sender-signed', () async {
    final alice = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    final bob = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'bob',
      password: 'another correct horse',
      deviceName: 'Bob phone',
    );
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);
    final aliceRecord = _record('alice', alice.enrollment);
    final bobRecord = _record('bob', bob.enrollment);
    final conversationKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );

    final envelope = alice.wrapConversationKey(
      conversationId: 'alice-bob',
      recipient: bobRecord,
      conversationKey: conversationKey,
    );
    final opened = bob.unwrapConversationKey(
      envelope: envelope,
      sender: aliceRecord,
    );
    expect(opened, conversationKey);
    opened.fillRange(0, opened.length, 0);

    final signature = envelope.signature;
    final tampered = WrappedConversationKey(
      conversationId: envelope.conversationId,
      senderUsername: envelope.senderUsername,
      senderDeviceId: envelope.senderDeviceId,
      recipientUsername: envelope.recipientUsername,
      recipientDeviceId: envelope.recipientDeviceId,
      sealedKey: envelope.sealedKey,
      signature: '${signature[0] == 'A' ? 'B' : 'A'}${signature.substring(1)}',
      createdAt: envelope.createdAt,
    );
    expect(
      () => bob.unwrapConversationKey(envelope: tampered, sender: aliceRecord),
      throwsFormatException,
    );
  });
}

final class MemoryVaultStorage implements VaultStorage {
  final Map<String, String> values = {};

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

final class _TestKeyDeriver implements VaultKeyDeriver {
  const _TestKeyDeriver();

  @override
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  }) async {
    return Uint8List.fromList(
      sha256.convert(utf8.encode('$password\n$salt')).bytes,
    );
  }
}

DeviceRecord _record(String username, DeviceEnrollment enrollment) {
  return DeviceRecord(
    username: username,
    enrollment: enrollment,
    enrolledAt: DateTime.utc(2026, 8, 24, 12),
    lastSeenAt: DateTime.utc(2026, 8, 24, 12),
  );
}
