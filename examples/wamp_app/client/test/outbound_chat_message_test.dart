import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('outbox state round-trips the exact encrypted envelope', () {
    final fixture = _fixture();
    final queued = OutboundChatMessage(
      envelope: fixture.$1,
      localMessage: fixture.$2,
      state: OutboundMessageState.queued,
      attemptCount: 0,
    );
    final attempted = queued.withAttempt(DateTime.utc(2026, 8, 25, 12, 1));
    final retryable = attempted.withFailure(OutboundMessageState.retryable);
    final decoded = OutboundChatMessage.fromJson(
      jsonDecode(jsonEncode(retryable.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.state, OutboundMessageState.retryable);
    expect(decoded.attemptCount, 1);
    expect(decoded.canRetry, isTrue);
    expect(decoded.canDiscard, isTrue);
    expect(decoded.matchesEnvelope(fixture.$1), isTrue);
    expect(decoded.envelope.toJson(), fixture.$1.toJson());
    expect(decoded.localMessage.toJson(), fixture.$2.toJson());
  });

  test('accepted messages retain their authoritative mailbox cursor', () {
    final fixture = _fixture();
    final accepted =
        OutboundChatMessage(
              envelope: fixture.$1,
              localMessage: fixture.$2,
              state: OutboundMessageState.queued,
              attemptCount: 0,
            )
            .withAttempt(DateTime.utc(2026, 8, 25, 12, 1))
            .withAccepted(
              MessageSendReceipt(
                messageId: fixture.$1.messageId,
                cursor: 7,
                acceptedAt: DateTime.utc(2026, 8, 25, 12, 1),
                duplicate: true,
              ),
            );

    expect(accepted.state, OutboundMessageState.accepted);
    expect(accepted.acceptedCursor, 7);
    expect(accepted.canRetry, isFalse);
    expect(accepted.canDiscard, isFalse);
  });

  test('same id with different wire content is not an exact retry', () {
    final fixture = _fixture();
    final changed = Uint8List.fromList(fixture.$1.encryptedPayload);
    changed[0] ^= 1;
    final conflicting = EncryptedChatMessage(
      messageId: fixture.$1.messageId,
      conversationId: fixture.$1.conversationId,
      senderUsername: fixture.$1.senderUsername,
      senderDeviceId: fixture.$1.senderDeviceId,
      recipientUsername: fixture.$1.recipientUsername!,
      createdAt: fixture.$1.createdAt,
      encryptedPayload: changed,
      wrappedKeys: fixture.$1.wrappedKeys,
    );
    final queued = OutboundChatMessage(
      envelope: fixture.$1,
      localMessage: fixture.$2,
      state: OutboundMessageState.queued,
      attemptCount: 0,
    );

    expect(queued.matchesEnvelope(conflicting), isFalse);
  });

  test('local optimistic metadata must match its encrypted envelope', () {
    final fixture = _fixture();
    final mismatched = LocalChatMessage(
      messageId: fixture.$2.messageId,
      conversationId: 'different-conversation',
      peerUsername: fixture.$2.peerUsername,
      text: fixture.$2.text,
      sentAt: fixture.$2.sentAt,
      outgoing: true,
    );

    expect(
      () => OutboundChatMessage(
        envelope: fixture.$1,
        localMessage: mismatched,
        state: OutboundMessageState.queued,
        attemptCount: 0,
      ),
      throwsFormatException,
    );
  });
}

(EncryptedChatMessage, LocalChatMessage) _fixture() {
  final createdAt = DateTime.utc(2026, 8, 25, 12);
  final senderDeviceId = _token(32, 1);
  final wrappedKeys = ['alice', 'bob']
      .map(
        (username) => WrappedConversationKey(
          conversationId: 'alice-bob',
          senderUsername: 'alice',
          senderDeviceId: senderDeviceId,
          recipientUsername: username,
          recipientDeviceId: _token(32, username == 'alice' ? 2 : 3),
          sealedKey: _token(80, username == 'alice' ? 4 : 5),
          signature: _token(64, username == 'alice' ? 6 : 7),
          createdAt: createdAt,
        ),
      )
      .toList(growable: false);
  final envelope = EncryptedChatMessage(
    messageId: 'message-1',
    conversationId: 'alice-bob',
    senderUsername: 'alice',
    senderDeviceId: senderDeviceId,
    recipientUsername: 'bob',
    createdAt: createdAt,
    encryptedPayload: Uint8List.fromList(
      List<int>.generate(40, (index) => index + 1),
    ),
    wrappedKeys: wrappedKeys,
  );
  return (
    envelope,
    LocalChatMessage(
      messageId: envelope.messageId,
      conversationId: envelope.conversationId,
      peerUsername: 'bob',
      text: 'persist this once',
      sentAt: envelope.createdAt,
      outgoing: true,
    ),
  );
}

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');
