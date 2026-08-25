import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/app.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_chat_group.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  testWidgets('registers and opens the authenticated shell', (tester) async {
    final oneTimeMessage = LocalChatMessage(
      messageId: 'one-time-message',
      conversationId: 'alice-bob',
      peerUsername: 'bob',
      text: 'hidden until consumed',
      sentAt: DateTime.utc(2026, 8, 24, 12),
      outgoing: false,
      oneTime: true,
    );
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(
        initialMessages: [oneTimeMessage],
        initialGroups: [
          LocalChatGroup(
            conversationId: 'launch-crew',
            title: 'Launch crew',
            memberUsernames: const ['alice', 'bob'],
            createdBy: 'alice',
            createdAt: DateTime.utc(2026, 8, 24, 11),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(WampApp(controller: controller));

    expect(
      find.text('Your conversations.\nYour keys. Your server.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(
      find.byKey(const Key('display-name')),
      'Alice Example',
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'correct horse battery',
    );
    final submit = find.byKey(const Key('submit-account'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Encrypted messages'), findsOneWidget);
    expect(find.byKey(const Key('message-recipient')), findsOneWidget);
    expect(find.byKey(const Key('message-composer')), findsOneWidget);
    expect(find.text('Alice Example'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('Encrypted device vault'), findsOneWidget);
    expect(find.text('Test device'), findsOneWidget);
    expect(find.text('hidden until consumed'), findsNothing);
    expect(find.text('Tap to view once'), findsOneWidget);
    expect(find.byKey(const Key('message-attach')), findsOneWidget);

    final oneTime = find.byKey(const Key('message-one-time'));
    await tester.ensureVisible(oneTime);
    await tester.tap(oneTime);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(oneTime).selected, isTrue);

    final expiry = find.byKey(const Key('message-expiry'));
    await tester.tap(expiry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete after 1 day'));
    await tester.pumpAndSettle();
    expect(find.text('Delete after 1 day'), findsOneWidget);

    await tester.tap(find.text('Launch crew'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-recipient')), findsNothing);
    expect(find.text('@alice  @bob'), findsOneWidget);
    expect(tester.widget<FilterChip>(oneTime).onSelected, isNull);
    expect(find.byKey(const Key('conversation-create-group')), findsOneWidget);
  });

  testWidgets('renders encrypted attachment metadata without loading bytes', (
    tester,
  ) async {
    final attachmentId = _token(16, 40);
    final attachmentMessage = LocalChatMessage(
      messageId: 'attachment-message',
      conversationId: 'alice-bob',
      peerUsername: 'bob',
      text: '',
      sentAt: DateTime.utc(2026, 8, 24, 12, 1),
      outgoing: false,
      attachments: [
        EncryptedAttachmentDescriptor(
          attachmentId: attachmentId,
          kind: ChatAttachmentKind.image,
          name: 'vacation.jpg',
          contentType: 'image/jpeg',
          plaintextBytes: 1536,
          chunkBytes: WampAppAttachmentLimits.defaultChunkBytes,
          chunkCount: 1,
          plaintextSha256: List<String>.filled(64, '0').join(),
          key: Uint8List(32),
        ),
      ],
    );
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(initialMessages: [attachmentMessage]),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );

    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-attach')), findsOneWidget);
    expect(find.text('vacation.jpg'), findsOneWidget);
    expect(find.text('1.5 KiB · encrypted'), findsOneWidget);
    expect(
      find.byKey(ValueKey('attachment-open-$attachmentId')),
      findsOneWidget,
    );
  });

  testWidgets('clears password after a failed attempt', (tester) async {
    final controller = WampAppController(
      gateway: _FailingGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(WampApp(controller: controller));

    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(
      find.byKey(const Key('display-name')),
      'Alice Example',
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'correct horse battery',
    );
    final submit = find.byKey(const Key('submit-account'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final password = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(password.controller.text, isEmpty);
    expect(find.byKey(const Key('connection-error')), findsOneWidget);
  });

  testWidgets('retries and discards a persisted outbound message', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final pending = _retryableOutbox();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(initialOutbox: [pending]),
    );
    addTearDown(controller.dispose);

    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('persisted retry'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    final retry = find.byKey(const Key('message-retry-persisted-message'));
    final discard = find.byKey(const Key('message-discard-persisted-message'));
    expect(retry, findsOneWidget);
    expect(discard, findsOneWidget);
    expect(gateway.sendAttempts, 1);

    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(gateway.sendAttempts, 2);
    expect(find.text('Not sent'), findsOneWidget);

    await tester.ensureVisible(discard);
    await tester.tap(discard);
    await tester.pumpAndSettle();

    expect(find.text('persisted retry'), findsNothing);
    expect(find.byKey(const Key('message-history')), findsNothing);
  });
}

class _FakeGateway implements AccountGateway {
  int sendAttempts = 0;

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    return RegistrationReceipt(
      username: registration.username,
      displayName: registration.displayName,
      createdAt: DateTime.utc(2026, 8, 24),
    );
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    return AccountConnection(
      endpoint: endpoint,
      username: username,
      displayName: 'Alice Example',
      enrollDeviceCallback: (enrollment) async =>
          activeDeviceRecord(username, enrollment),
      listDevicesCallback: (_) async => DeviceDirectory(const []),
      lookupDevicesCallback: (_, _) async => DeviceDirectory(const []),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: (_) async {
        sendAttempts += 1;
        throw const MessageSendException(MessageSendFailureKind.retryable);
      },
      syncMessagesCallback: (afterCursor, _) async =>
          MailboxBatch(nextCursor: afterCursor, messages: const []),
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: (_) => throw UnimplementedError(),
      mailboxWakeups: const Stream<MailboxWakeup>.empty(),
      latestMailboxWakeupCursorCallback: () => 0,
      latestMailboxWakeupErrorCallback: () => null,
      closeTransport: () async {},
    );
  }
}

class _FailingGateway extends _FakeGateway {
  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) {
    throw StateError('offline');
  }
}

OutboundChatMessage _retryableOutbox() {
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
    messageId: 'persisted-message',
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
  return OutboundChatMessage(
    envelope: envelope,
    localMessage: LocalChatMessage(
      messageId: envelope.messageId,
      conversationId: envelope.conversationId,
      peerUsername: 'bob',
      text: 'persisted retry',
      sentAt: envelope.createdAt,
      outgoing: true,
    ),
    state: OutboundMessageState.retryable,
    attemptCount: 1,
    lastAttemptAt: DateTime.utc(2026, 8, 25, 12, 1),
  );
}

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');
