import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory directory;
  late MailboxStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wamp-mailbox-');
    store = MailboxStore('${directory.path}/messages.json');
    await store.initialize();
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'retries identical message IDs idempotently and rejects conflicts',
    () async {
      final message = _message();
      final first = await store.append(
        message,
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final retry = await store.append(
        EncryptedChatMessage.fromJson(message.toJson()),
        now: DateTime.utc(2026, 8, 24, 12, 1),
      );

      expect(first.duplicate, isFalse);
      expect(retry.duplicate, isTrue);
      expect(retry.message.cursor, first.message.cursor);

      final changed = message.toJson()..['encrypted_payload'] = _token(64, 99);
      expect(
        () => store.append(EncryptedChatMessage.fromJson(changed)),
        throwsA(isA<MessageConflict>()),
      );
    },
  );

  test(
    'sync isolates participants and resumes from a durable cursor',
    () async {
      await store.append(_message(), now: DateTime.utc(2026, 8, 24, 12));

      final alice = await store.sync('alice', afterCursor: 0);
      final bob = await store.sync('bob', afterCursor: 0);
      final mallory = await store.sync('mallory', afterCursor: 0);

      expect(alice.messages, hasLength(1));
      expect(bob.messages, hasLength(1));
      expect(mallory.messages, isEmpty);
      expect(mallory.nextCursor, 1);
      expect(
        (await store.sync('bob', afterCursor: bob.nextCursor)).messages,
        isEmpty,
      );

      final reopened = MailboxStore(store.file.path);
      expect(
        (await reopened.sync(
          'alice',
          afterCursor: 0,
        )).messages.single.message.messageId,
        _message().messageId,
      );
    },
  );

  test('recipient receipts are idempotent monotonic mailbox events', () async {
    final sent = await store.append(
      _message(),
      now: DateTime.utc(2026, 8, 24, 12),
    );
    final delivered = await store.markReceipt(
      'bob',
      sent.message.message.messageId,
      read: false,
      now: DateTime.utc(2026, 8, 24, 12, 1),
    );
    final retry = await store.markReceipt(
      'bob',
      sent.message.message.messageId,
      read: false,
      now: DateTime.utc(2026, 8, 24, 12, 2),
    );
    final read = await store.markReceipt(
      'bob',
      sent.message.message.messageId,
      read: true,
      now: DateTime.utc(2026, 8, 24, 12, 3),
    );

    expect(retry.deliveredAt, delivered.deliveredAt);
    expect(read.readAt, DateTime.utc(2026, 8, 24, 12, 3));
    final updates = await store.sync('alice', afterCursor: 1);
    expect(updates.messages.map((entry) => entry.cursor), [2, 3]);
    expect(updates.messages.last.readAt, read.readAt);
    expect(
      () => store.markReceipt(
        'alice',
        sent.message.message.messageId,
        read: true,
      ),
      throwsStateError,
    );
  });

  test('separate store instances serialize shared-file appends', () async {
    final second = MailboxStore(store.file.path);
    await Future.wait([
      store.append(_message()),
      second.append(_message(messageSeed: 22)),
    ]);

    final batch = await store.sync('alice', afterCursor: 0);
    expect(batch.messages.map((entry) => entry.cursor), [1, 2]);
    expect(
      batch.messages.map((entry) => entry.message.messageId).toSet(),
      hasLength(2),
    );
  });

  test('expired ciphertext is omitted while advancing the cursor', () async {
    await store.append(
      _message(expiresAt: DateTime.utc(2026, 8, 24, 12, 1)),
      now: DateTime.utc(2026, 8, 24, 12),
    );

    final batch = await store.sync(
      'bob',
      afterCursor: 0,
      now: DateTime.utc(2026, 8, 24, 12, 2),
    );
    expect(batch.messages, isEmpty);
    expect(batch.nextCursor, 1);
  });
}

EncryptedChatMessage _message({DateTime? expiresAt, int messageSeed = 2}) {
  final senderDevice = _token(32, 1);
  return EncryptedChatMessage(
    messageId: _token(16, messageSeed),
    conversationId: _token(32, 3),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 11, 59),
    expiresAt: expiresAt,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 4)),
    wrappedKeys: [
      WrappedConversationKey(
        conversationId: _token(32, 3),
        senderUsername: 'alice',
        senderDeviceId: senderDevice,
        recipientUsername: 'bob',
        recipientDeviceId: _token(32, 5),
        sealedKey: _token(80, 6),
        signature: _token(64, 7),
        createdAt: DateTime.utc(2026, 8, 24, 11, 59),
      ),
    ],
  );
}

String _token(int length, int value) =>
    base64Url.encode(List<int>.filled(length, value)).replaceAll('=', '');
