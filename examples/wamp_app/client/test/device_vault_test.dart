import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/message_cipher.dart';
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

  test(
    'persists the exact bounded outbox only inside encrypted storage',
    () async {
      final first = await vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'correct horse battery',
        deviceName: 'Alice phone',
      );
      final aliceRecord = _record('alice', first.enrollment);
      final bobRecord = _record('bob', first.enrollment);
      final attachment = EncryptedAttachmentDescriptor(
        attachmentId: 'outbox_attachment_1234',
        kind: ChatAttachmentKind.file,
        name: 'private-contract.pdf',
        contentType: 'application/pdf',
        plaintextBytes: 12,
        chunkBytes: 1024,
        chunkCount: 1,
        plaintextSha256:
            'f4c4d1448fdc87c22f0e5415166a8ab27e9b11d267597a4972266d4f6959d23f',
        key: Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
      );
      final encrypted = MessageCipher().encrypt(
        senderUsername: 'alice',
        recipientUsername: 'bob',
        text: 'durable retry plaintext',
        trust: first,
        participantDevices: [aliceRecord, bobRecord],
        now: DateTime.utc(2026, 8, 25, 12),
        attachments: [attachment],
      );
      final pending = OutboundChatMessage(
        envelope: encrypted,
        localMessage: LocalChatMessage(
          messageId: encrypted.messageId,
          conversationId: encrypted.conversationId,
          peerUsername: 'bob',
          text: 'durable retry plaintext',
          sentAt: encrypted.createdAt,
          outgoing: true,
          attachments: [attachment],
        ),
        state: OutboundMessageState.retryable,
        attemptCount: 1,
        lastAttemptAt: DateTime.utc(2026, 8, 25, 12, 1),
      );
      expect(
        OutboundChatMessage.fromJson(pending.toJson())
            .localMessage
            .attachments
            .single
            .toJson(),
        attachment.toJson(),
      );

      await first.saveMailboxState(
        cursor: 0,
        messages: const [],
        outbox: [pending],
      );
      final encoded = storage.values.values.single;
      expect(encoded, isNot(contains('durable retry plaintext')));
      expect(encoded, isNot(contains('private-contract.pdf')));
      expect(encoded, isNot(contains('application/pdf')));
      expect(encoded, isNot(contains(encrypted.messageId)));
      await first.dispose();

      final reopened = await vault.openOrCreate(
        endpoint: endpoint,
        username: 'alice',
        password: 'correct horse battery',
        deviceName: 'Ignored replacement name',
      );
      addTearDown(reopened.dispose);
      expect(reopened.outbox, hasLength(1));
      expect(reopened.outbox.single.state, OutboundMessageState.retryable);
      expect(reopened.outbox.single.envelope.toJson(), encrypted.toJson());
      expect(
        reopened.outbox.single.localMessage.text,
        'durable retry plaintext',
      );
      expect(
        reopened.outbox.single.localMessage.attachments.single.toJson(),
        attachment.toJson(),
      );
    },
  );

  test('preferences remain encrypted and survive vault reopen', () async {
    final first = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    await first.savePreferences(
      LocalAppPreferences(
        theme: WampAppThemePreference.dark,
        mutedConversationIds: const ['private-conversation-id'],
      ),
    );
    final encoded = storage.values.values.single;
    expect(encoded, isNot(contains('private-conversation-id')));
    expect(encoded, isNot(contains('dark')));
    await first.dispose();

    final reopened = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Ignored replacement name',
    );
    addTearDown(reopened.dispose);
    expect(reopened.preferences.theme, WampAppThemePreference.dark);
    expect(reopened.preferences.isMuted('private-conversation-id'), isTrue);
  });

  test('failed preference writes leave live state unchanged', () async {
    final session = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    addTearDown(session.dispose);
    storage.writeFailure = StateError('disk full');

    await expectLater(
      session.savePreferences(
        LocalAppPreferences(theme: WampAppThemePreference.dark),
      ),
      throwsStateError,
    );
    expect(session.preferences.theme, WampAppThemePreference.system);
  });

  test('vaults without preferences migrate to safe defaults', () async {
    final session = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    await session.dispose();
    await _rewriteInnerDocument(
      storage,
      password: 'correct horse battery',
      update: (document) => document.remove('preferences'),
    );

    final reopened = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    addTearDown(reopened.dispose);
    expect(reopened.preferences.theme, WampAppThemePreference.system);
    expect(reopened.preferences.mutedConversationIds, isEmpty);
  });

  test('malformed encrypted preferences fail vault unlock closed', () async {
    final session = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    await session.dispose();
    await _rewriteInnerDocument(
      storage,
      password: 'correct horse battery',
      update: (document) => document['preferences'] = 'dark',
    );

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

  test('rejects oversized or mailbox-ambiguous outbox state', () async {
    final session = await vault.openOrCreate(
      endpoint: endpoint,
      username: 'alice',
      password: 'correct horse battery',
      deviceName: 'Alice phone',
    );
    addTearDown(session.dispose);
    final aliceRecord = _record('alice', session.enrollment);
    final bobRecord = _record('bob', session.enrollment);
    final outbox = List<OutboundChatMessage>.generate(
      OutboundChatMessage.maxEntries + 1,
      (index) => _pendingMessage(session, aliceRecord, bobRecord, index),
    );

    await expectLater(
      session.saveMailboxState(cursor: 0, messages: const [], outbox: outbox),
      throwsFormatException,
    );
    expect(session.outbox, isEmpty);

    final pending = outbox.first;
    await expectLater(
      session.saveMailboxState(
        cursor: 0,
        messages: [pending.localMessage],
        outbox: [pending],
      ),
      throwsFormatException,
    );
    expect(session.messages, isEmpty);
    expect(session.outbox, isEmpty);
  });
}

final class MemoryVaultStorage implements VaultStorage {
  final Map<String, String> values = {};
  Object? writeFailure;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
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

Future<void> _rewriteInnerDocument(
  MemoryVaultStorage storage, {
  required String password,
  required void Function(Map<String, dynamic> document) update,
}) async {
  final entry = storage.values.entries.single;
  final envelope = jsonDecode(entry.value) as Map<String, dynamic>;
  final salt = envelope['salt'] as String;
  final key = await const _TestKeyDeriver().derive(
    password: password,
    salt: salt,
    iterations: 2,
    memoryKiB: 64,
    timeout: const Duration(seconds: 1),
  );
  final ciphertext = _decodeUnpadded(envelope['ciphertext'] as String);
  final box = SecretBox(key);
  final plaintext = box.decrypt(EncryptedMessage.fromList(ciphertext));
  try {
    final document = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    update(document);
    final rewritten = Uint8List.fromList(utf8.encode(jsonEncode(document)));
    try {
      envelope['ciphertext'] = base64Url
          .encode(box.encrypt(rewritten).asTypedList)
          .replaceAll('=', '');
      storage.values[entry.key] = jsonEncode(envelope);
    } finally {
      rewritten.fillRange(0, rewritten.length, 0);
    }
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
    key.fillRange(0, key.length, 0);
  }
}

Uint8List _decodeUnpadded(String value) {
  final padding = (4 - value.length % 4) % 4;
  final suffix = List<String>.filled(padding, '=').join();
  return base64Url.decode('$value$suffix');
}

DeviceRecord _record(String username, DeviceEnrollment enrollment) {
  return DeviceRecord(
    username: username,
    enrollment: enrollment,
    enrolledAt: DateTime.utc(2026, 8, 24, 12),
    lastSeenAt: DateTime.utc(2026, 8, 24, 12),
  );
}

OutboundChatMessage _pendingMessage(
  DeviceTrustSession trust,
  DeviceRecord alice,
  DeviceRecord bob,
  int index,
) {
  final encrypted = MessageCipher().encrypt(
    senderUsername: 'alice',
    recipientUsername: 'bob',
    text: 'bounded outbox entry $index',
    trust: trust,
    participantDevices: [alice, bob],
    now: DateTime.utc(2026, 8, 25, 12).add(Duration(seconds: index)),
  );
  return OutboundChatMessage(
    envelope: encrypted,
    localMessage: LocalChatMessage(
      messageId: encrypted.messageId,
      conversationId: encrypted.conversationId,
      peerUsername: 'bob',
      text: 'bounded outbox entry $index',
      sentAt: encrypted.createdAt,
      outgoing: true,
    ),
    state: OutboundMessageState.queued,
    attemptCount: 0,
  );
}
