import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'support/rpc_fixture.dart';

void main() {
  late RpcFixture fixture;
  late RpcPeer alice;
  late RpcPeer bob;
  late RpcPeer charlie;

  setUp(() async {
    fixture = await RpcFixture.start();
    alice = await fixture.connect('alice', 1);
    bob = await fixture.connect('bob', 2);
    charlie = await fixture.connect('charlie', 3);
  });

  test(
    'messages and receipts use durable cursors and private wakeups',
    () async {
      final subscription = await bob.session.subscribe(
        WampAppProtocol.mailboxChanged,
      );
      final wakeup = subscription.eventStream!.first.timeout(
        const Duration(seconds: 10),
      );
      final unrelated = await charlie.session.subscribe(
        WampAppProtocol.mailboxChanged,
      );
      final unrelatedEvents = <wamp.Event>[];
      final listener = unrelated.eventStream!.listen(unrelatedEvents.add);
      addTearDown(listener.cancel);

      final message = _message(alice, [bob]);
      final sent = MessageSendReceipt.fromWampKeywords(
        await alice.call(WampAppProtocol.messageSend, message.toWampKeywords()),
      );
      expect(sent.messageId, message.messageId);
      expect(sent.cursor, 1);
      expect(sent.duplicate, isFalse);
      expect((await wakeup).argumentsKeywords, {'cursor': 1});
      final duplicate = MessageSendReceipt.fromWampKeywords(
        await alice.call(WampAppProtocol.messageSend, message.toWampKeywords()),
      );
      expect(duplicate.cursor, 1);
      expect(duplicate.acceptedAt, sent.acceptedAt);
      expect(duplicate.duplicate, isTrue);
      final received = await _sync(bob);
      expect(received.nextCursor, 1);
      expect(
        received.messages.single.message.toWampKeywords(),
        message.toWampKeywords(),
      );
      expect((await _sync(charlie)).messages, isEmpty);

      final delivered = MessageReceipt.fromWampKeywords(
        await bob.call(WampAppProtocol.messageReceipt, {
          'message_id': message.messageId,
          'state': 'delivered',
        }),
      );
      expect(delivered.cursor, 2);
      expect(delivered.recipientUsername, 'bob');
      expect(delivered.deliveredAt, isNotNull);
      expect(delivered.readAt, isNull);
      final read = MessageReceipt.fromWampKeywords(
        await bob.call(WampAppProtocol.messageReceipt, {
          'message_id': message.messageId,
          'state': 'read',
        }),
      );
      expect(read.cursor, 3);
      expect(read.deliveredAt, delivered.deliveredAt);
      expect(read.readAt, isNotNull);
      expect(
        await bob.call(WampAppProtocol.messageReceipt, {
          'message_id': message.messageId,
          'state': 'read',
        }),
        read.toWampKeywords(),
      );
      final page = await _sync(alice, afterCursor: 1, limit: 1);
      expect(page.nextCursor, 2);
      expect(page.messages.single.recipientStateFor('bob')!.readAt, isNull);
      final last = await _sync(alice, afterCursor: page.nextCursor);
      expect(last.nextCursor, 3);
      expect(
        last.messages.single.recipientStateFor('bob')!.readAt,
        read.readAt,
      );
      expect((await _sync(bob, afterCursor: 3)).messages, isEmpty);
      // A later, eligible publication is a delivery barrier on Charlie's socket.
      final controlNotification = unrelated.eventStream!.first.timeout(
        const Duration(seconds: 10),
      );
      await charlie.call(
        WampAppProtocol.messageSend,
        _message(charlie, [bob], messageSeed: 10).toWampKeywords(),
      );
      expect((await controlNotification).argumentsKeywords, {'cursor': 4});
      expect(unrelatedEvents.map((event) => event.argumentsKeywords), [
        {'cursor': 4},
      ]);
    },
  );

  test('invalid and unauthorized RPCs do not change the mailbox', () async {
    final message = _message(alice, [bob]);
    await expectRpcError(
      charlie.call(WampAppProtocol.messageSend, message.toWampKeywords()),
      WampAppProtocol.errorNotAuthorized,
    );
    final tampered = message.toWampKeywords();
    final keys = (tampered['wrapped_keys'] as List)
        .cast<Map<String, dynamic>>();
    keys.last['signature'] = token(64, 99);
    await expectRpcError(
      alice.call(WampAppProtocol.messageSend, tampered),
      WampAppProtocol.errorInvalidMessage,
    );
    expect((await _sync(bob)).messages, isEmpty);
    final sent = await alice.call(
      WampAppProtocol.messageSend,
      message.toWampKeywords(),
    );
    expect(sent['cursor'], 1);
    await expectRpcError(
      alice.call(WampAppProtocol.messageSend, {
        ...message.toWampKeywords(),
        'encrypted_payload': Uint8List(64),
      }),
      WampAppProtocol.errorMessageConflict,
    );
    for (final peer in [alice, charlie]) {
      await expectRpcError(
        peer.call(WampAppProtocol.messageReceipt, {
          'message_id': message.messageId,
          'state': 'delivered',
        }),
        WampAppProtocol.errorNotAuthorized,
      );
    }
    await expectRpcError(
      bob.call(WampAppProtocol.messageReceipt, {
        'message_id': token(16, 98),
        'state': 'read',
      }),
      WampAppProtocol.errorMessageNotFound,
    );
    final batch = await _sync(bob);
    expect(batch.nextCursor, 1);
    expect(batch.messages.single.recipientStateFor('bob'), isNull);
  });

  test(
    'one-time consumption is signed, atomic, and bound to one device',
    () async {
      final secondBob = await fixture.connect('bob', 4);
      final message = _message(alice, [bob, secondBob], oneTime: true);
      await alice.call(WampAppProtocol.messageSend, message.toWampKeywords());
      await expectRpcError(
        bob.call(WampAppProtocol.messageReceipt, {
          'message_id': message.messageId,
          'state': 'read',
        }),
        WampAppProtocol.errorInvalidMessage,
      );
      final proof = _consumption(bob, message.messageId);
      await expectRpcError(
        charlie.call(WampAppProtocol.messageConsume, proof.toWampKeywords()),
        WampAppProtocol.errorNotAuthorized,
      );
      await expectRpcError(
        bob.call(WampAppProtocol.messageConsume, {
          ...proof.toWampKeywords(),
          'signature': token(64, 98),
        }),
        WampAppProtocol.errorNotAuthorized,
      );
      expect((await _sync(bob)).nextCursor, 1);
      final subscription = await alice.session.subscribe(
        WampAppProtocol.mailboxChanged,
      );
      final wakeup = subscription.eventStream!.first.timeout(
        const Duration(seconds: 10),
      );
      final consumed = MessageReceipt.fromWampKeywords(
        await bob.call(WampAppProtocol.messageConsume, proof.toWampKeywords()),
      );
      expect(consumed.cursor, 2);
      expect(consumed.consumedAt, isNotNull);
      expect(consumed.readAt, consumed.consumedAt);
      expect((await wakeup).argumentsKeywords, {'cursor': 2});
      expect(
        await bob.call(WampAppProtocol.messageConsume, proof.toWampKeywords()),
        consumed.toWampKeywords(),
      );
      await expectRpcError(
        secondBob.call(
          WampAppProtocol.messageConsume,
          _consumption(secondBob, message.messageId).toWampKeywords(),
        ),
        WampAppProtocol.errorMessageConsumed,
      );
      final batch = await _sync(secondBob);
      expect(batch.nextCursor, 2);
      expect(batch.messages, hasLength(1));
      expect(
        batch.messages.single.recipientStateFor('bob')!.consumedByDeviceId,
        bob.deviceId,
      );
      await expectRpcError(
        bob.call(
          WampAppProtocol.messageConsume,
          _consumption(bob, token(16, 99)).toWampKeywords(),
        ),
        WampAppProtocol.errorMessageNotFound,
      );
    },
  );

  test(
    'malformed wire arguments fail explicitly and leave the session usable',
    () async {
      final cases = <(String, Map<String, dynamic>)>[
        (WampAppProtocol.deviceLookup, {}),
        (
          WampAppProtocol.deviceLookup,
          {'username': 'bob', 'include_revoked': 1},
        ),
        (WampAppProtocol.messageSend, {}),
        (WampAppProtocol.messageSync, {}),
        (WampAppProtocol.messageSync, {'after_cursor': 0, 'limit': '1'}),
        (WampAppProtocol.messageSync, {'after_cursor': -1}),
        (WampAppProtocol.messageSync, {'after_cursor': 1}),
        (WampAppProtocol.messageSync, {'after_cursor': 0, 'limit': 0}),
        (WampAppProtocol.messageReceipt, {'message_id': 1, 'state': 'read'}),
        (
          WampAppProtocol.messageReceipt,
          {'message_id': token(16, 10), 'state': 'consumed'},
        ),
        (WampAppProtocol.messageConsume, {}),
      ];
      for (final (procedure, keywords) in cases) {
        await expectRpcError(
          alice.call(procedure, keywords),
          WampAppProtocol.errorInvalidMessage,
        );
      }
      final directory = DeviceDirectory.fromWampKeywords(
        await alice.call(WampAppProtocol.deviceLookup, {'username': 'bob'}),
      );
      expect(directory.devices.single.deviceId, bob.deviceId);
      final sent = await alice.call(
        WampAppProtocol.messageSend,
        _message(alice, [bob]).toWampKeywords(),
      );
      expect(sent['cursor'], 1);
    },
  );

  test(
    'attachment references must be durable before a message is accepted',
    () async {
      final message = _message(alice, [bob], attachmentIds: [token(16, 80)]);
      await expectRpcError(
        alice.call(WampAppProtocol.messageSend, message.toWampKeywords()),
        WampAppProtocol.errorAttachmentIncomplete,
      );
      expect((await _sync(bob)).messages, isEmpty);
    },
  );

  test(
    'filesystem failures are redacted and recovery uses the same session',
    () async {
      final file = File('${fixture.directory.path}/messages.json');
      final original = await file.readAsBytes();
      await file.delete();
      final obstruction = await Directory(file.path).create();
      try {
        for (final (procedure, keywords) in [
          (WampAppProtocol.messageSync, <String, dynamic>{'after_cursor': 0}),
          (
            WampAppProtocol.messageSend,
            _message(alice, [bob]).toWampKeywords(),
          ),
          (
            WampAppProtocol.messageReceipt,
            <String, dynamic>{'message_id': token(16, 10), 'state': 'read'},
          ),
        ]) {
          await expectLater(
            alice.call(procedure, keywords),
            throwsA(
              isA<wamp.Error>()
                  .having(
                    (error) => error.error,
                    'URI',
                    WampAppProtocol.errorMessageUnavailable,
                  )
                  .having((error) => error.arguments, 'redacted error', [
                    'The message service is temporarily unavailable.',
                  ]),
            ),
          );
        }
      } finally {
        await obstruction.delete();
        await file.writeAsBytes(original, flush: true);
      }
      expect((await _sync(bob)).messages, isEmpty);
      final sent = await alice.call(
        WampAppProtocol.messageSend,
        _message(alice, [bob]).toWampKeywords(),
      );
      expect(sent['cursor'], 1);
      expect((await _sync(bob)).messages, hasLength(1));
    },
  );
}

Future<MailboxBatch> _sync(
  RpcPeer peer, {
  int afterCursor = 0,
  int? limit,
}) async => MailboxBatch.fromWampKeywords(
  await peer.call(WampAppProtocol.messageSync, {
    'after_cursor': afterCursor,
    'limit': ?limit,
  }),
);

EncryptedChatMessage _message(
  RpcPeer sender,
  List<RpcPeer> recipients, {
  bool oneTime = false,
  int messageSeed = 9,
  List<String> attachmentIds = const [],
}) {
  final createdAt = DateTime.now().toUtc();
  final conversationId = token(32, 8);
  return EncryptedChatMessage(
    messageId: token(16, messageSeed),
    conversationId: conversationId,
    senderUsername: sender.username,
    senderDeviceId: sender.deviceId,
    recipientUsername: recipients.first.username,
    createdAt: createdAt,
    oneTime: oneTime,
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 10)),
    attachmentIds: attachmentIds,
    wrappedKeys: [
      for (final recipient in [sender, ...recipients])
        _wrapped(sender, recipient, conversationId, createdAt),
    ],
  );
}

WrappedConversationKey _wrapped(
  RpcPeer sender,
  RpcPeer recipient,
  String conversationId,
  DateTime createdAt,
) {
  final sealedKey = token(80, 11);
  final payload = WrappedConversationKey.signaturePayloadFor(
    conversationId: conversationId,
    senderUsername: sender.username,
    senderDeviceId: sender.deviceId,
    recipientUsername: recipient.username,
    recipientDeviceId: recipient.deviceId,
    sealedKey: sealedKey,
    createdAt: createdAt,
  );
  return WrappedConversationKey(
    conversationId: conversationId,
    senderUsername: sender.username,
    senderDeviceId: sender.deviceId,
    recipientUsername: recipient.username,
    recipientDeviceId: recipient.deviceId,
    sealedKey: sealedKey,
    signature: sender.sign(payload),
    createdAt: createdAt,
  );
}

OneTimeMessageConsumption _consumption(RpcPeer peer, String messageId) =>
    OneTimeMessageConsumption(
      messageId: messageId,
      deviceId: peer.deviceId,
      signature: peer.sign(
        OneTimeMessageConsumption.signaturePayloadFor(
          username: peer.username,
          messageId: messageId,
          deviceId: peer.deviceId,
        ),
      ),
    );
