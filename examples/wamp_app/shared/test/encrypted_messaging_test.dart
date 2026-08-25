import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test(
    'encrypted messages use binary WAMP fields and JSON storage encoding',
    () {
      final message = _message();

      final wire = message.toWampKeywords();
      expect(wire['encrypted_payload'], isA<Uint8List>());
      final fromWire = EncryptedChatMessage.fromWampKeywords(wire);
      expect(fromWire.encryptedPayload, message.encryptedPayload);

      final json = message.toJson();
      expect(json['encrypted_payload'], isA<String>());
      final fromJson = EncryptedChatMessage.fromJson(json);
      expect(fromJson.toJson(), json);
    },
  );

  test('message envelopes preserve sorted opaque attachment identifiers', () {
    final attachmentIds = [_token(16, 20), _token(16, 21)]..sort();
    final message = _message(attachmentIds: attachmentIds);

    expect(
      EncryptedChatMessage.fromWampKeywords(
        message.toWampKeywords(),
      ).attachmentIds,
      attachmentIds,
    );
    expect(
      EncryptedChatMessage.fromJson(message.toJson()).attachmentIds,
      attachmentIds,
    );
    expect(
      () => _message(attachmentIds: attachmentIds.reversed.toList()),
      throwsFormatException,
    );
    expect(
      () => _message(attachmentIds: [attachmentIds.first, attachmentIds.first]),
      throwsFormatException,
    );
    expect(
      () => _message(oneTime: true, attachmentIds: [attachmentIds.first]),
      throwsFormatException,
    );
  });

  test('wire parser rejects base64 text in the binary payload field', () {
    final wire = _message().toWampKeywords();
    wire['encrypted_payload'] = base64Url.encode(List<int>.filled(40, 9));

    expect(
      () => EncryptedChatMessage.fromWampKeywords(wire),
      throwsFormatException,
    );
  });

  test('message rejects duplicate or cross-conversation wrapped keys', () {
    final message = _message();
    expect(
      () => EncryptedChatMessage(
        messageId: message.messageId,
        conversationId: message.conversationId,
        senderUsername: message.senderUsername,
        senderDeviceId: message.senderDeviceId,
        recipientUsername: message.recipientUsername!,
        createdAt: message.createdAt,
        encryptedPayload: message.encryptedPayload,
        wrappedKeys: [message.wrappedKeys.single, message.wrappedKeys.single],
      ),
      throwsFormatException,
    );
  });

  test('mailbox batch enforces monotonic bounded cursors', () {
    final first = MailboxMessage(
      cursor: 2,
      message: _message(),
      acceptedAt: DateTime.utc(2026, 8, 24, 12),
    );
    expect(
      () => MailboxBatch(nextCursor: 1, messages: [first]),
      throwsFormatException,
    );
    final batch = MailboxBatch(nextCursor: 2, messages: [first]);
    expect(MailboxBatch.fromWampKeywords(batch.toWampKeywords()).nextCursor, 2);
    expect(
      () => MailboxBatch(
        nextCursor: MailboxBatch.maxMessages + 1,
        messages: List<MailboxMessage>.generate(
          MailboxBatch.maxMessages + 1,
          (index) => MailboxMessage(
            cursor: index + 1,
            message: _message(),
            acceptedAt: DateTime.utc(2026, 8, 24, 12),
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test('mailbox records reject read receipts without delivery', () {
    expect(
      () => MailboxMessage(
        cursor: 1,
        message: _message(),
        acceptedAt: DateTime.utc(2026, 8, 24, 12),
        readAt: DateTime.utc(2026, 8, 24, 12, 1),
      ),
      throwsFormatException,
    );
  });

  test(
    'one-time consumption state round-trips without weakening invariants',
    () {
      final consumedAt = DateTime.utc(2026, 8, 24, 12, 1);
      final stored = MailboxMessage(
        cursor: 2,
        message: _message(oneTime: true),
        acceptedAt: DateTime.utc(2026, 8, 24, 12),
        deliveredAt: consumedAt,
        readAt: consumedAt,
        consumedAt: consumedAt,
        consumedByDeviceId: _token(32, 9),
      );

      expect(
        MailboxMessage.fromWampKeywords(stored.toWampKeywords()).toJson(),
        stored.toJson(),
      );
      expect(
        MailboxMessage.fromJson(stored.toJson()).toJson(),
        stored.toJson(),
      );
      final receipt = MessageReceipt(
        messageId: stored.message.messageId,
        cursor: stored.cursor,
        deliveredAt: consumedAt,
        readAt: consumedAt,
        consumedAt: consumedAt,
      );
      expect(
        MessageReceipt.fromWampKeywords(receipt.toWampKeywords()).consumedAt,
        consumedAt,
      );
    },
  );

  test(
    'one-time consumption state rejects incomplete or mismatched records',
    () {
      final consumedAt = DateTime.utc(2026, 8, 24, 12, 1);
      MailboxMessage create({
        bool oneTime = true,
        DateTime? readAt,
        DateTime? consumed,
        String? deviceId,
      }) => MailboxMessage(
        cursor: 2,
        message: _message(oneTime: oneTime),
        acceptedAt: DateTime.utc(2026, 8, 24, 12),
        deliveredAt: consumedAt,
        readAt: readAt,
        consumedAt: consumed,
        consumedByDeviceId: deviceId,
      );

      expect(
        () => create(readAt: consumedAt, consumed: consumedAt),
        throwsFormatException,
      );
      expect(
        () => create(
          oneTime: false,
          readAt: consumedAt,
          consumed: consumedAt,
          deviceId: _token(32, 9),
        ),
        throwsFormatException,
      );
      expect(
        () => create(
          readAt: consumedAt.add(const Duration(seconds: 1)),
          consumed: consumedAt,
          deviceId: _token(32, 9),
        ),
        throwsFormatException,
      );
    },
  );

  test('mailbox wakeups and receipts preserve their exact cursor', () {
    final wakeup = MailboxWakeup(cursor: 42);
    expect(MailboxWakeup.fromWampKeywords(wakeup.toWampKeywords()).cursor, 42);
    final receipt = MessageReceipt(
      messageId: _token(16, 8),
      cursor: 43,
      deliveredAt: DateTime.utc(2026, 8, 24, 12),
    );
    expect(
      MessageReceipt.fromWampKeywords(receipt.toWampKeywords()).cursor,
      43,
    );
  });

  test('mailbox wakeups reject missing, non-integer, and invalid cursors', () {
    for (final value in <Object?>[null, '1', 0, -1]) {
      expect(
        () => MailboxWakeup.fromWampKeywords({'cursor': value}),
        throwsFormatException,
      );
    }
  });

  test('one-time consumption proofs bind account, message, and device', () {
    final proof = OneTimeMessageConsumption(
      messageId: _token(16, 8),
      deviceId: _token(32, 9),
      signature: _token(64, 10),
    );

    expect(
      OneTimeMessageConsumption.fromWampKeywords(
        proof.toWampKeywords(),
      ).toWampKeywords(),
      proof.toWampKeywords(),
    );
    expect(
      utf8.decode(proof.signaturePayload(' Alice ')),
      [
        OneTimeMessageConsumption.signatureVersion,
        'alice',
        proof.messageId,
        proof.deviceId,
      ].join('\n'),
    );
  });

  test(
    'group envelopes round-trip with sorted participants and binary data',
    () {
      final message = _groupMessage();

      expect(message.isGroup, isTrue);
      expect(message.participantUsernames, ['alice', 'bob', 'carol']);
      expect(message.recipientUsernames, ['bob', 'carol']);
      expect(
        EncryptedChatMessage.fromWampKeywords(
          message.toWampKeywords(),
        ).toJson(),
        message.toJson(),
      );
      expect(
        EncryptedChatMessage.fromJson(message.toJson()).toJson(),
        message.toJson(),
      );
    },
  );

  test('group envelopes reject direct and view-once wire ambiguity', () {
    final wire = _groupMessage().toWampKeywords();
    wire['one_time'] = true;
    expect(
      () => EncryptedChatMessage.fromWampKeywords(wire),
      throwsFormatException,
    );

    final withRecipient = _groupMessage().toWampKeywords();
    withRecipient['recipient_username'] = 'bob';
    expect(
      () => EncryptedChatMessage.fromWampKeywords(withRecipient),
      throwsFormatException,
    );
  });

  test('group envelopes require a wrapped key for every participant', () {
    final message = _groupMessage();
    expect(
      () => EncryptedChatMessage.group(
        messageId: message.messageId,
        conversationId: message.conversationId,
        senderUsername: message.senderUsername,
        senderDeviceId: message.senderDeviceId,
        participantUsernames: message.participantUsernames,
        createdAt: message.createdAt,
        encryptedPayload: message.encryptedPayload,
        wrappedKeys: message.wrappedKeys
            .where((key) => key.recipientUsername != 'carol')
            .toList(growable: false),
      ),
      throwsFormatException,
    );
  });

  test(
    'group recipient receipts remain independent and aggregate for sender',
    () {
      final deliveredBob = DateTime.utc(2026, 8, 24, 12, 1);
      final deliveredCarol = DateTime.utc(2026, 8, 24, 12, 2);
      final readBob = DateTime.utc(2026, 8, 24, 12, 3);
      final stored = MailboxMessage(
        cursor: 4,
        message: _groupMessage(),
        acceptedAt: DateTime.utc(2026, 8, 24, 12),
        recipientStates: {
          'bob': MailboxRecipientState(
            deliveredAt: deliveredBob,
            readAt: readBob,
          ),
          'carol': MailboxRecipientState(deliveredAt: deliveredCarol),
        },
      );

      expect(stored.deliveredAtFor('alice'), deliveredCarol);
      expect(stored.readAtFor('alice'), isNull);
      expect(stored.deliveredAtFor('bob'), deliveredBob);
      expect(stored.readAtFor('bob'), readBob);
      expect(
        MailboxMessage.fromWampKeywords(stored.toWampKeywords()).toJson(),
        stored.toJson(),
      );
    },
  );
}

EncryptedChatMessage _message({
  bool oneTime = false,
  List<String> attachmentIds = const [],
}) {
  final senderDevice = _token(32, 1);
  return EncryptedChatMessage(
    messageId: _token(16, 2),
    conversationId: _token(32, 3),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 11, 59),
    oneTime: oneTime,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 4)),
    attachmentIds: attachmentIds,
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

EncryptedChatMessage _groupMessage() {
  final conversationId = _token(32, 20);
  final senderDevice = _token(32, 21);
  return EncryptedChatMessage.group(
    messageId: _token(16, 22),
    conversationId: conversationId,
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    participantUsernames: const [' Carol ', 'alice', 'Bob'],
    createdAt: DateTime.utc(2026, 8, 24, 12),
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 23)),
    wrappedKeys: [
      for (final entry in const [('alice', 24), ('bob', 25), ('carol', 26)])
        WrappedConversationKey(
          conversationId: conversationId,
          senderUsername: 'alice',
          senderDeviceId: senderDevice,
          recipientUsername: entry.$1,
          recipientDeviceId: _token(32, entry.$2),
          sealedKey: _token(80, entry.$2 + 10),
          signature: _token(64, entry.$2 + 20),
          createdAt: DateTime.utc(2026, 8, 24, 12),
        ),
    ],
  );
}

String _token(int length, int value) =>
    base64Url.encode(List<int>.filled(length, value)).replaceAll('=', '');
