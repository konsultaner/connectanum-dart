import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/app.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/domain/local_chat_group.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app/src/infrastructure/contact_importer_contract.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app/src/infrastructure/voice_note_recorder.dart';
import 'package:wamp_app/src/ui/expression_picker.dart';
import 'package:wamp_app/src/ui/home_page.dart';
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

    await tester.enterText(find.byKey(const Key('message-recipient')), 'bob');
    await tester.pumpAndSettle();
    final expiry = find.byKey(const Key('message-expiry'));
    await tester.tap(expiry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete after 1 day'));
    await tester.pumpAndSettle();
    expect(find.text('Delete after 1 day'), findsOneWidget);
    final directId = controller.directConversationIdFor('bob')!;
    expect(
      controller.disappearingMessagesFor(directId),
      const Duration(days: 1),
    );

    await tester.tap(find.text('Launch crew'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-recipient')), findsNothing);
    expect(find.text('@alice  @bob'), findsOneWidget);
    expect(tester.widget<FilterChip>(oneTime).onSelected, isNull);
    expect(find.byKey(const Key('conversation-create-group')), findsOneWidget);
    expect(find.text('Keep chat messages'), findsOneWidget);

    await tester.tap(expiry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete after 7 days'));
    await tester.pumpAndSettle();
    expect(
      controller.disappearingMessagesFor('launch-crew'),
      const Duration(days: 7),
    );

    await tester.tap(find.byKey(const Key('conversation-direct')));
    await tester.pumpAndSettle();
    expect(find.text('Delete after 1 day'), findsOneWidget);
  });

  testWidgets('direct call actions fail closed with a recoverable result', (
    tester,
  ) async {
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    final voiceCall = find.byKey(const Key('conversation-voice-call'));
    final videoCall = find.byKey(const Key('conversation-video-call'));
    expect(voiceCall, findsOneWidget);
    expect(videoCall, findsOneWidget);
    expect(tester.widget<IconButton>(voiceCall).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('message-recipient')), 'bob');
    await tester.pump();
    expect(tester.widget<IconButton>(voiceCall).onPressed, isNotNull);
    await tester.tap(voiceCall);
    await tester.pumpAndSettle();

    expect(find.text('Call unavailable'), findsOneWidget);
    expect(find.byKey(const Key('call-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call-dismiss')));
    await tester.pumpAndSettle();
    expect(find.text('Encrypted messages'), findsOneWidget);
  });

  testWidgets('edits the public profile and views a recipient profile', (
    tester,
  ) async {
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account-profile-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-display-name')),
      'Alice Updated',
    );
    await tester.enterText(
      find.byKey(const Key('profile-status')),
      'Shipping safely',
    );
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(find.text('Alice Updated'), findsOneWidget);
    expect(find.byKey(const Key('account-profile-status')), findsOneWidget);
    expect(find.text('Shipping safely'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('message-recipient')), 'bob');
    await tester.tap(find.byKey(const Key('recipient-profile-view')));
    await tester.pumpAndSettle();

    expect(find.text('Public profile'), findsOneWidget);
    expect(find.text('Bob Example'), findsOneWidget);
    expect(find.byKey(const Key('peer-profile-status')), findsOneWidget);
    expect(find.text('Testing WampApp'), findsOneWidget);
  });

  testWidgets('imports, verifies, selects, renames, and removes a contact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeGateway();
    final trustStore = FakeDeviceTrustStore();
    final importer = _FakeContactImporter([
      ImportedContactCandidate(displayName: 'Bob Address Book'),
    ]);
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(
      WampApp(controller: controller, contactImporter: importer),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account-contacts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-privacy-boundary')), findsOneWidget);
    expect(
      find.textContaining('Phone numbers, email addresses'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('contact-import')));
    await tester.pumpAndSettle();
    expect(importer.calls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('contact-display-name')))
          .controller!
          .text,
      'Bob Address Book',
    );

    await tester.enterText(find.byKey(const Key('contact-username')), 'Bob');
    await tester.tap(find.byKey(const Key('contact-save')));
    await tester.pumpAndSettle();

    expect(gateway.profileLookups, ['bob']);
    expect(controller.contacts.single.username, 'bob');
    expect(controller.contacts.single.displayName, 'Bob Address Book');
    expect(trustStore.session!.saveContactsCalls, 1);
    final contact = find.byKey(const ValueKey('contact-bob'));
    await tester.ensureVisible(contact);
    await tester.tap(contact);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-privacy-boundary')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-recipient')))
          .controller!
          .text,
      'bob',
    );
    expect(find.byKey(const ValueKey('contact-recipient-bob')), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-contacts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contact-edit-bob')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('contact-display-name')),
      'Bob Local',
    );
    await tester.tap(find.byKey(const Key('contact-save')));
    await tester.pumpAndSettle();

    expect(controller.contacts.single.displayName, 'Bob Local');
    expect(find.text('Bob Local'), findsOneWidget);
    expect(gateway.profileLookups, ['bob']);
    expect(trustStore.session!.saveContactsCalls, 2);

    await tester.tap(find.byKey(const ValueKey('contact-remove-bob')));
    await tester.pumpAndSettle();
    expect(controller.contacts, isEmpty);
    expect(find.byKey(const ValueKey('contact-bob')), findsNothing);
    expect(trustStore.session!.saveContactsCalls, 3);
    await tester.tap(find.byKey(const Key('contact-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contact-recipient-bob')), findsNothing);
  });

  testWidgets('contact manager fits the compact authenticated shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(
      WampApp(
        controller: controller,
        contactImporter: _FakeContactImporter(const []),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account-contacts-compact')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-privacy-boundary')), findsOneWidget);
    expect(find.byKey(const Key('contact-import')), findsOneWidget);
    expect(find.byKey(const Key('contact-add-manual')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirms MCP profile sharing and revokes it immediately', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    final consent = find.byKey(const Key('account-mcp-profile-consent'));
    await tester.tap(consent);
    await tester.pumpAndSettle();

    expect(find.text('Allow MCP public-profile access?'), findsOneWidget);
    expect(find.textContaining('Chats, messages, attachments'), findsOneWidget);
    expect(gateway.mcpProfileReadAllowed, isFalse);

    await tester.tap(find.byKey(const Key('mcp-profile-consent-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.mcpProfileReadAllowed, isTrue);
    expect(gateway.mcpConsentUpdates, [true]);

    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(find.text('Allow MCP public-profile access?'), findsNothing);
    expect(gateway.mcpProfileReadAllowed, isFalse);
    expect(gateway.mcpConsentUpdates, [true, false]);
  });

  testWidgets('switches appearance and mutes direct and group chats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(
        initialGroups: [
          LocalChatGroup(
            conversationId: 'launch-crew',
            title: 'Launch crew',
            memberUsernames: const ['alice', 'bob'],
            createdBy: 'alice',
            createdAt: DateTime.utc(2026, 8, 25, 11),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    Future<void> chooseAppearance(WampAppThemePreference preference) async {
      await tester.tap(find.byKey(const Key('account-theme-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('appearance-${preference.wireName}')),
      );
      await tester.pumpAndSettle();
    }

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await tester.enterText(find.byKey(const Key('message-recipient')), 'bob');
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'Unsent encrypted draft',
    );
    await chooseAppearance(WampAppThemePreference.dark);
    expect(controller.themePreference, WampAppThemePreference.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Unsent encrypted draft'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-recipient')))
          .controller
          ?.text,
      'bob',
    );
    await chooseAppearance(WampAppThemePreference.light);
    expect(controller.themePreference, WampAppThemePreference.light);
    await chooseAppearance(WampAppThemePreference.system);
    expect(controller.themePreference, WampAppThemePreference.system);

    await tester.pumpAndSettle();
    final directId = controller.directConversationIdFor('bob')!;
    expect(find.byKey(const Key('conversation-mute')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation-mute')));
    await tester.pumpAndSettle();
    expect(controller.isConversationMuted(directId), isTrue);

    await tester.tap(find.text('Launch crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-mute')));
    await tester.pumpAndSettle();
    expect(controller.isConversationMuted('launch-crew'), isTrue);
    expect(controller.isConversationMuted(directId), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searches local history and filters received read state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final deliveredAt = DateTime.utc(2026, 8, 25, 12, 1);
    final readAt = DateTime.utc(2026, 8, 25, 12, 2);
    final messages = [
      LocalChatMessage(
        messageId: 'unread-direct',
        conversationId: 'alice-bob',
        peerUsername: 'bob',
        text: 'Launch checklist',
        sentAt: DateTime.utc(2026, 8, 25, 12),
        outgoing: false,
      ),
      LocalChatMessage(
        messageId: 'read-group',
        conversationId: 'launch-crew',
        peerUsername: 'carol',
        text: 'Board minutes',
        sentAt: DateTime.utc(2026, 8, 25, 12, 3),
        outgoing: false,
        deliveredAt: deliveredAt,
        readAt: readAt,
        groupTitle: 'Launch crew',
        participantUsernames: const ['alice', 'bob', 'carol'],
        groupCreatedBy: 'alice',
        groupCreatedAt: DateTime.utc(2026, 8, 25, 11),
      ),
      LocalChatMessage(
        messageId: 'outgoing-read',
        conversationId: 'alice-dave',
        peerUsername: 'dave',
        text: 'Outbound only',
        sentAt: DateTime.utc(2026, 8, 25, 12, 4),
        outgoing: true,
        deliveredAt: deliveredAt,
        readAt: readAt,
      ),
      LocalChatMessage(
        messageId: 'hidden-once',
        conversationId: 'alice-erin',
        peerUsername: 'erin',
        text: 'Secret token',
        sentAt: DateTime.utc(2026, 8, 25, 12, 5),
        outgoing: false,
        oneTime: true,
      ),
    ];
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(
        initialMessages: messages,
        initialGroups: [
          LocalChatGroup(
            conversationId: 'launch-crew',
            title: 'Launch crew',
            memberUsernames: const ['alice', 'bob', 'carol'],
            createdBy: 'alice',
            createdAt: DateTime.utc(2026, 8, 25, 11),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();
    Finder messageText(String value) => find.descendant(
      of: find.byKey(const Key('message-history')),
      matching: find.text(value),
    );

    expect(tester.takeException(), isNull);
    expect(messageText('Secret token'), findsNothing);
    expect(find.text('Tap to view once'), findsOneWidget);

    final unreadFilter = find.byKey(const Key('message-filter-unread'));
    await tester.ensureVisible(unreadFilter);
    await tester.tap(unreadFilter);
    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'Launch checklist',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageText('Launch checklist'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'Outbound only',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageText('Outbound only'), findsNothing);
    expect(
      find.text('No local messages match this search and filter.'),
      findsOneWidget,
    );

    final allFilter = find.byKey(const Key('message-filter-all'));
    await tester.ensureVisible(allFilter);
    await tester.tap(allFilter);
    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'Launch checklist',
    );
    await tester.pump(const Duration(milliseconds: 75));
    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'Outbound only',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageText('Outbound only'), findsOneWidget);
    expect(messageText('Launch checklist'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'LAUNCH BOARD',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageText('Board minutes'), findsOneWidget);
    expect(messageText('Launch checklist'), findsNothing);
    expect(find.text('Local search · 1 result'), findsOneWidget);

    final boardMinutes = messageText('Board minutes');
    await tester.scrollUntilVisible(
      boardMinutes,
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('message-history')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(boardMinutes);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-global-search')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('group-members-summary')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('message-global-search')),
      'Secret token',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageText('Secret token'), findsNothing);
    expect(
      find.text('No local messages match this search and filter.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('message-search-clear')));
    final directConversation = find.byKey(const Key('conversation-direct'));
    await tester.ensureVisible(directConversation);
    await tester.tap(directConversation);
    final readFilter = find.byKey(const Key('message-filter-read'));
    await tester.ensureVisible(readFilter);
    await tester.tap(readFilter);
    await tester.pumpAndSettle();
    expect(messageText('Outbound only'), findsNothing);
    expect(
      find.text('No read received messages in this conversation.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('records, stages, and cancels encrypted voice notes', (
    tester,
  ) async {
    final capture = _FakeVoiceNoteCapture();
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          controller: controller,
          connection: controller.connection!,
          voiceNoteCaptureFactory: () => capture,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final microphone = find.byKey(const Key('message-voice'));
    await tester.ensureVisible(microphone);
    await tester.tap(microphone);
    await tester.pump();
    expect(find.byKey(const Key('voice-recording-status')), findsOneWidget);
    expect(find.byKey(const Key('message-composer')), findsNothing);

    await tester.ensureVisible(microphone);
    await tester.tap(microphone);
    await tester.pump();
    expect(capture.sessions.first.stopCalls, 1);
    expect(find.byKey(const Key('voice-recording-status')), findsNothing);
    expect(find.byKey(const Key('selected-attachment-0')), findsOneWidget);
    expect(find.textContaining('voice-note-'), findsOneWidget);

    await tester.tap(microphone);
    await tester.pump();
    expect(find.byKey(const Key('voice-recording-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-recording-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('voice-recording-status')), findsNothing);
    expect(find.byKey(const Key('selected-attachment-1')), findsNothing);
    expect(capture.sessions.last.cancelCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('searches emoji and stages an encrypted sticker', (tester) async {
    final renderer = _FakeStickerRenderer();
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          controller: controller,
          connection: controller.connection!,
          stickerRenderer: renderer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final oneTime = find.byKey(const Key('message-one-time'));
    await tester.ensureVisible(oneTime);
    await tester.tap(oneTime);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(oneTime).selected, isTrue);

    final composer = find.byKey(const Key('message-composer'));
    await tester.enterText(composer, 'See  later');
    tester.widget<TextField>(composer).controller!.selection =
        const TextSelection.collapsed(offset: 4);

    final expression = find.byKey(const Key('message-expression'));
    await tester.ensureVisible(expression);
    await tester.tap(expression);
    await tester.pumpAndSettle();
    expect(find.text('Emoji & stickers'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('expression-search')),
      'thumbs up',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emoji-👍')));
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, 'See 👍 later');

    await tester.tap(find.byKey(const Key('expression-sticker-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sticker-nice')));
    await tester.pumpAndSettle();

    expect(renderer.renderedDesigns.single.id, 'nice');
    expect(find.byKey(const Key('selected-attachment-0')), findsOneWidget);
    expect(find.textContaining('sticker-nice-'), findsOneWidget);
    expect(tester.widget<FilterChip>(oneTime).selected, isFalse);
  });

  testWidgets('rejects a sticker beyond the attachment cap', (tester) async {
    final renderer = _FakeStickerRenderer();
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          controller: controller,
          connection: controller.connection!,
          stickerRenderer: renderer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> stageSticker() async {
      final expression = find.byKey(const Key('message-expression'));
      await tester.ensureVisible(expression);
      await tester.tap(expression);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression-sticker-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-nice')));
      await tester.pumpAndSettle();
    }

    for (
      var index = 0;
      index < WampAppAttachmentLimits.maxAttachmentsPerMessage;
      index += 1
    ) {
      await stageSticker();
    }
    await tester.drag(
      find.byKey(const Key('selected-attachments')),
      const Offset(-4000, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-attachment-7')), findsOneWidget);
    expect(renderer.renderedDesigns, hasLength(8));

    final expression = find.byKey(const Key('message-expression'));
    await tester.ensureVisible(expression);
    await tester.tap(expression);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expression-sticker-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sticker-nice')));
    await tester.pump();

    expect(renderer.renderedDesigns, hasLength(8));
    expect(
      find.text('A message can contain up to 8 attachments.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('expression-close')), findsOneWidget);
  });

  testWidgets('renders bundled stickers as bounded PNG payloads', (
    tester,
  ) async {
    final bytes = await const BundledStickerRenderer().render(
      wampAppStickers.first,
    );
    addTearDown(() => bytes.fillRange(0, bytes.length, 0));

    expect(bytes.take(8), const [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(bytes.length, lessThan(WampAppAttachmentLimits.maxAttachmentBytes));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Image.memory(bytes),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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

  testWidgets('restores an encrypted backup before opening the device vault', (
    tester,
  ) async {
    final operations = <String>[];
    final trustStore = FakeDeviceTrustStore(operations: operations);
    final backupFiles = FakeDeviceBackupFileGateway()
      ..archiveToOpen = Uint8List.fromList(utf8.encode('encrypted archive'));
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: trustStore,
      backupFiles: backupFiles,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(WampApp(controller: controller));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restore-local-backup')), findsOneWidget);
    expect(find.byKey(const Key('restore-remote-backup')), findsOneWidget);
    expect(find.byKey(const Key('backup-restore-boundary')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('username')), 'alice');
    await tester.enterText(
      find.byKey(const Key('password')),
      'correct horse battery',
    );
    final restore = find.byKey(const Key('restore-local-backup'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-recovery-passphrase')),
      'sixteen byte recovery phrase',
    );
    await tester.tap(find.byKey(const Key('backup-passphrase-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Encrypted messages'), findsOneWidget);
    expect(backupFiles.openCalls, 1);
    expect(trustStore.importCalls, 1);
    expect(operations, ['backup-import', 'vault-open']);
    expect(trustStore.password, 'correct horse battery');
  });

  testWidgets('validates and exports an encrypted device backup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backupFiles = FakeDeviceBackupFileGateway();
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
      backupFiles: backupFiles,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'wss://localhost/ws',
      username: 'alice',
      password: 'correct horse battery',
    );
    await tester.pumpWidget(WampApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup-export-boundary')), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-backup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-action-local')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-recovery-passphrase')),
      'too short',
    );
    await tester.tap(find.byKey(const Key('backup-passphrase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Use 16 to 1024 UTF-8 bytes.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('backup-recovery-passphrase')),
      'sixteen byte recovery phrase',
    );
    await tester.enterText(
      find.byKey(const Key('backup-recovery-confirmation')),
      'a different recovery phrase',
    );
    await tester.tap(find.byKey(const Key('backup-passphrase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('The recovery phrases do not match.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('backup-recovery-confirmation')),
      'sixteen byte recovery phrase',
    );
    await tester.tap(find.byKey(const Key('backup-passphrase-submit')));
    await tester.pumpAndSettle();

    expect(backupFiles.saveCalls, 1);
    expect(utf8.decode(backupFiles.savedArchive!), 'fake encrypted backup');
    expect(backupFiles.suggestedName, endsWith('.wampbackup'));
    expect(find.text('Encrypted device backup saved.'), findsOneWidget);
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
  bool mcpProfileReadAllowed = false;
  int mcpConsentRevision = 0;
  final List<bool> mcpConsentUpdates = [];
  final List<String> profileLookups = [];

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
    var profile = AccountProfile(
      username: username,
      displayName: 'Alice Example',
      status: '',
      revision: 0,
      updatedAt: DateTime.utc(2026, 8, 24),
    );
    return AccountConnection(
      endpoint: endpoint,
      username: username,
      initialProfile: profile,
      initialMcpConsent: WampAppMcpConsent.denied,
      getProfileCallback: (lookup) async {
        profileLookups.add(lookup);
        return lookup == username
            ? profile
            : AccountProfile(
                username: AccountRegistration.normalizeUsername(lookup),
                displayName: 'Bob Example',
                status: 'Testing WampApp',
                revision: 2,
                updatedAt: DateTime.utc(2026, 8, 25),
              );
      },
      updateProfileCallback: (update) async {
        profile = AccountProfile(
          username: username,
          displayName: update.displayName,
          status: update.status,
          revision: update.expectedRevision + 1,
          updatedAt: DateTime.utc(2026, 8, 25),
          avatarBytes: update.avatarAction == ProfileAvatarAction.set
              ? update.avatarBytes
              : null,
          avatarContentType: update.avatarAction == ProfileAvatarAction.set
              ? update.avatarContentType
              : null,
        );
        return profile;
      },
      getMcpConsentCallback: () async => WampAppMcpConsent(
        profileReadAllowed: mcpProfileReadAllowed,
        revision: mcpConsentRevision,
        updatedAt: mcpConsentRevision == 0 ? null : DateTime.utc(2026, 8, 25),
      ),
      updateMcpConsentCallback: (update) async {
        if (update.expectedRevision != mcpConsentRevision) {
          throw const McpConsentException(McpConsentFailureKind.conflict);
        }
        mcpProfileReadAllowed = update.profileReadAllowed;
        mcpConsentRevision += 1;
        mcpConsentUpdates.add(mcpProfileReadAllowed);
        return WampAppMcpConsent(
          profileReadAllowed: mcpProfileReadAllowed,
          revision: mcpConsentRevision,
          updatedAt: DateTime.utc(2026, 8, 25),
        );
      },
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

final class _FakeContactImporter implements ContactImporter {
  _FakeContactImporter(this.candidates);

  final List<ImportedContactCandidate> candidates;
  int calls = 0;

  @override
  String get actionLabel => 'Choose contact';

  @override
  Future<List<ImportedContactCandidate>> pickContacts() async {
    calls += 1;
    return candidates;
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

final class _FakeVoiceNoteCapture implements VoiceNoteCapture {
  final sessions = <_FakeVoiceNoteCaptureSession>[];
  bool disposed = false;

  @override
  Future<VoiceNoteCaptureSession> start() async {
    final session = _FakeVoiceNoteCaptureSession();
    sessions.add(session);
    return session;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FakeStickerRenderer implements StickerRenderer {
  final renderedDesigns = <StickerDesign>[];

  @override
  Future<Uint8List> render(StickerDesign design) async {
    renderedDesigns.add(design);
    return Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]);
  }
}

final class _FakeVoiceNoteCaptureSession implements VoiceNoteCaptureSession {
  final _completion = Completer<VoiceNoteRecording>();
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<VoiceNoteRecording> get completed => _completion.future;

  @override
  Future<VoiceNoteRecording> stop() async {
    stopCalls += 1;
    final recording = _FakeVoiceNoteRecording();
    _completion.complete(recording);
    return recording;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    _completion.completeError(const VoiceNoteRecordingCancelled());
  }
}

final class _FakeVoiceNoteRecording implements VoiceNoteRecording {
  Uint8List? _bytes = Uint8List.fromList(List<int>.filled(364, 7));

  @override
  int get byteCount => _bytes?.length ?? 0;

  @override
  int get durationMilliseconds => 10;

  @override
  Uint8List takeBytes() {
    final bytes = _bytes!;
    _bytes = null;
    return bytes;
  }

  @override
  void dispose() {
    final bytes = _bytes;
    _bytes = null;
    bytes?.fillRange(0, bytes.length, 0);
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
