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
        recipientUsername: message.recipientUsername,
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
}

EncryptedChatMessage _message() {
  final senderDevice = _token(32, 1);
  return EncryptedChatMessage(
    messageId: _token(16, 2),
    conversationId: _token(32, 3),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 11, 59),
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
