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

    expect(delivered.receipt.cursor, 2);
    expect(delivered.senderUsername, 'alice');
    expect(delivered.recipientUsername, 'bob');
    expect(retry.receipt.cursor, delivered.receipt.cursor);
    expect(retry.receipt.deliveredAt, delivered.receipt.deliveredAt);
    expect(read.receipt.cursor, 3);
    expect(read.receipt.readAt, DateTime.utc(2026, 8, 24, 12, 3));
    final updates = await store.sync('alice', afterCursor: 1);
    expect(updates.messages.map((entry) => entry.cursor), [2, 3]);
    expect(updates.messages.last.readAt, read.receipt.readAt);
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
    expect(
      () => store.markReceipt(
        'bob',
        _message().messageId,
        read: false,
        now: DateTime.utc(2026, 8, 24, 12, 2),
      ),
      throwsA(isA<MessageNotFound>()),
    );
    expect((await store.sync('alice', afterCursor: 0)).nextCursor, 1);
  });

  test(
    'one-time consumption is atomic, durable, and device-idempotent',
    () async {
      final deviceId = _token(32, 5);
      final otherDeviceId = _token(32, 6);
      final sent = await store.append(
        _message(
          oneTime: true,
          expiresAt: DateTime.utc(2026, 8, 24, 13),
          recipientDeviceSeeds: const [5, 6],
        ),
        now: DateTime.utc(2026, 8, 24, 12),
      );
      final delivered = await store.markReceipt(
        'bob',
        sent.message.message.messageId,
        read: false,
        now: DateTime.utc(2026, 8, 24, 12, 1),
      );
      final consumed = await store.consumeOneTime(
        'bob',
        deviceId,
        sent.message.message.messageId,
        now: DateTime.utc(2026, 8, 24, 12, 2),
      );
      final retry = await store.consumeOneTime(
        'bob',
        deviceId,
        sent.message.message.messageId,
        now: DateTime.utc(2026, 8, 24, 14),
      );

      expect(delivered.receipt.cursor, 2);
      expect(consumed.receipt.cursor, 3);
      expect(consumed.receipt.readAt, DateTime.utc(2026, 8, 24, 12, 2));
      expect(consumed.receipt.consumedAt, consumed.receipt.readAt);
      expect(retry.receipt.cursor, consumed.receipt.cursor);
      expect(retry.receipt.consumedAt, consumed.receipt.consumedAt);
      expect(
        () => store.consumeOneTime(
          'bob',
          otherDeviceId,
          sent.message.message.messageId,
        ),
        throwsA(isA<OneTimeMessageConsumed>()),
      );
      expect(
        () => store.markReceipt(
          'bob',
          sent.message.message.messageId,
          read: true,
        ),
        throwsFormatException,
      );
      expect(
        () => store.consumeOneTime(
          'alice',
          deviceId,
          sent.message.message.messageId,
        ),
        throwsStateError,
      );

      final recipient = await store.sync(
        'bob',
        afterCursor: 0,
        now: DateTime.utc(2026, 8, 24, 12, 3),
      );
      expect(recipient.messages, hasLength(1));
      expect(recipient.messages.single.cursor, consumed.receipt.cursor);
      expect(recipient.messages.single.consumedByDeviceId, deviceId);
      final sender = await store.sync(
        'alice',
        afterCursor: 0,
        now: DateTime.utc(2026, 8, 24, 12, 3),
      );
      expect(sender.messages.map((entry) => entry.cursor), [1, 2, 3]);
    },
  );

  test(
    'expired one-time consumption fails without advancing the cursor',
    () async {
      final message = _message(
        oneTime: true,
        expiresAt: DateTime.utc(2026, 8, 24, 12, 1),
      );
      await store.append(message, now: DateTime.utc(2026, 8, 24, 12));

      expect(
        () => store.consumeOneTime(
          'bob',
          _token(32, 5),
          message.messageId,
          now: DateTime.utc(2026, 8, 24, 12, 2),
        ),
        throwsA(isA<MessageNotFound>()),
      );
      expect((await store.sync('alice', afterCursor: 0)).nextCursor, 1);
    },
  );

  test(
    'competing store instances allow exactly one consuming device',
    () async {
      final message = _message(
        oneTime: true,
        recipientDeviceSeeds: const [5, 6],
      );
      await store.append(message);
      final second = MailboxStore(store.file.path);

      Future<Object> consume(MailboxStore candidate, int seed) async {
        try {
          return await candidate.consumeOneTime(
            'bob',
            _token(32, seed),
            message.messageId,
          );
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        consume(store, 5),
        consume(second, 6),
      ]);
      expect(results.whereType<MailboxReceiptUpdate>(), hasLength(1));
      expect(results.whereType<OneTimeMessageConsumed>(), hasLength(1));
      expect((await store.sync('alice', afterCursor: 0)).nextCursor, 2);
    },
  );
}

EncryptedChatMessage _message({
  DateTime? expiresAt,
  int messageSeed = 2,
  bool oneTime = false,
  List<int> recipientDeviceSeeds = const [5],
}) {
  final senderDevice = _token(32, 1);
  return EncryptedChatMessage(
    messageId: _token(16, messageSeed),
    conversationId: _token(32, 3),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 11, 59),
    expiresAt: expiresAt,
    oneTime: oneTime,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 4)),
    wrappedKeys: [
      for (final seed in recipientDeviceSeeds)
        WrappedConversationKey(
          conversationId: _token(32, 3),
          senderUsername: 'alice',
          senderDeviceId: senderDevice,
          recipientUsername: 'bob',
          recipientDeviceId: _token(32, seed),
          sealedKey: _token(80, seed + 20),
          signature: _token(64, seed + 40),
          createdAt: DateTime.utc(2026, 8, 24, 11, 59),
        ),
    ],
  );
}

String _token(int length, int value) =>
    base64Url.encode(List<int>.filled(length, value)).replaceAll('=', '');
