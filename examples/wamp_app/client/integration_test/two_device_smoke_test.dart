import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wamp_app/src/app.dart';
import 'package:wamp_app/src/application/call_controller.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

const _serverAddress = String.fromEnvironment('WAMP_APP_SERVER_ADDRESS');
const _username = String.fromEnvironment('WAMP_APP_SMOKE_USERNAME');
const _peerUsername = String.fromEnvironment('WAMP_APP_SMOKE_PEER');
const _outboundText = String.fromEnvironment('WAMP_APP_SMOKE_OUTBOUND');
const _inboundText = String.fromEnvironment('WAMP_APP_SMOKE_INBOUND');
const _role = String.fromEnvironment('WAMP_APP_SMOKE_ROLE');
const _groupTitle = String.fromEnvironment('WAMP_APP_SMOKE_GROUP_TITLE');
const _groupOutboundText = String.fromEnvironment(
  'WAMP_APP_SMOKE_GROUP_OUTBOUND',
);
const _groupInboundText = String.fromEnvironment(
  'WAMP_APP_SMOKE_GROUP_INBOUND',
);
const _oneTimeText = String.fromEnvironment('WAMP_APP_SMOKE_VIEW_ONCE');
const _voiceCallReadyOutbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_CALL_READY_OUTBOUND',
);
const _voiceCallReadyInbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_CALL_READY_INBOUND',
);
const _videoCallReadyOutbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_VIDEO_READY_OUTBOUND',
);
const _videoCallReadyInbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_VIDEO_READY_INBOUND',
);
const _profileDisplayName = String.fromEnvironment(
  'WAMP_APP_SMOKE_PROFILE_DISPLAY_NAME',
);
const _profileStatus = String.fromEnvironment('WAMP_APP_SMOKE_PROFILE_STATUS');
const _peerProfileDisplayName = String.fromEnvironment(
  'WAMP_APP_SMOKE_PEER_PROFILE_DISPLAY_NAME',
);
const _peerProfileStatus = String.fromEnvironment(
  'WAMP_APP_SMOKE_PEER_PROFILE_STATUS',
);
const _contactDisplayName = String.fromEnvironment(
  'WAMP_APP_SMOKE_CONTACT_DISPLAY_NAME',
);
const _controlsReadyOutbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_CONTROLS_READY_OUTBOUND',
);
const _controlsReadyInbound = String.fromEnvironment(
  'WAMP_APP_SMOKE_CONTROLS_READY_INBOUND',
);
const _backupPassphrase = String.fromEnvironment(
  'WAMP_APP_SMOKE_BACKUP_PASSPHRASE',
);
const _password = 'wamp-app-native-smoke-password';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exchanges encrypted chat, account controls, backup, and WebRTC calls',
    (tester) async {
      _validateConfiguration();
      final controller = WampAppController(deviceName: '$_username device');
      addTearDown(controller.dispose);

      await tester.pumpWidget(WampApp(controller: controller));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('submit-account')).evaluate().isNotEmpty,
        label: 'onboarding form',
      );

      await tester.enterText(
        find.byKey(const Key('server-address')),
        _serverAddress,
      );
      await tester.enterText(find.byKey(const Key('username')), _username);
      await tester.enterText(
        find.byKey(const Key('display-name')),
        'Native smoke $_username',
      );
      await tester.enterText(find.byKey(const Key('password')), _password);
      final submit = find.byKey(const Key('submit-account'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);

      await _pumpUntil(
        tester,
        () =>
            controller.status == WampAppStatus.connected &&
            controller.connection?.username == _username &&
            find.byKey(const Key('message-recipient')).evaluate().isNotEmpty,
        label: 'authenticated conversation shell',
        timeout: const Duration(minutes: 2),
      );
      await _waitForPeerDevice(tester, controller);

      final recipient = find.byKey(const Key('message-recipient'));
      final composer = find.byKey(const Key('message-composer'));
      await tester.ensureVisible(recipient);
      await tester.enterText(recipient, _peerUsername);
      await tester.pump();
      await _enterMessageWhenReady(
        tester,
        composer,
        _outboundText,
        label: 'direct-message composer',
      );
      final send = find.byKey(const Key('message-send'));
      await tester.ensureVisible(send);
      await _tapSendAndWaitOutbound(tester, controller, send);
      final outbound = controller.messages.singleWhere(
        (message) =>
            message.outgoing &&
            message.peerUsername == _peerUsername &&
            message.text == _outboundText,
      );
      await _pumpUntil(
        tester,
        () =>
            controller.outboundMessageFor(outbound.messageId) == null &&
            controller.messageError == null,
        label: 'router acceptance of outbound message',
      );

      await _pumpUntil(
        tester,
        () => controller.messages.any(
          (message) =>
              !message.outgoing &&
              message.peerUsername == _peerUsername &&
              message.text == _inboundText,
        ),
        label: 'mailbox wakeup and decrypted inbound message',
        timeout: const Duration(minutes: 2),
      );

      FocusManager.instance.primaryFocus?.unfocus();
      await _pumpUntil(
        tester,
        () =>
            find.text(_outboundText).evaluate().isNotEmpty ||
            find.text(_inboundText).evaluate().isNotEmpty,
        label: 'rendered message history',
      );
      final outboundRendered = find.text(_outboundText).evaluate().isNotEmpty;
      final inboundRendered = find.text(_inboundText).evaluate().isNotEmpty;
      if (!outboundRendered || !inboundRendered) {
        final history = find.byKey(const Key('message-history'));
        final scrollable = find.descendant(
          of: history,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text(outboundRendered ? _inboundText : _outboundText),
          100,
          scrollable: scrollable,
          maxScrolls: 20,
        );
      }
      expect(controller.messageError, isNull);
      expect(
        outboundRendered || find.text(_outboundText).evaluate().isNotEmpty,
        isTrue,
      );
      expect(
        inboundRendered || find.text(_inboundText).evaluate().isNotEmpty,
        isTrue,
      );

      await _exerciseEncryptedGroupSticker(tester, controller);
      await _exerciseViewOnceMessage(tester, controller);
      await _exerciseWebRtcCall(
        tester,
        controller,
        media: CallMediaKind.voice,
        readyOutbound: _voiceCallReadyOutbound,
        readyInbound: _voiceCallReadyInbound,
      );
      await _exerciseWebRtcCall(
        tester,
        controller,
        media: CallMediaKind.video,
        readyOutbound: _videoCallReadyOutbound,
        readyInbound: _videoCallReadyInbound,
      );
      await _exerciseAccountPrivacyControls(tester, controller);
    },
    timeout: const Timeout(Duration(minutes: 21)),
  );
}

Future<void> _exerciseAccountPrivacyControls(
  WidgetTester tester,
  WampAppController controller,
) async {
  await _selectDirectConversation(tester);
  await _updatePublicProfile(tester, controller);
  await _setLocalConversationPreferences(tester, controller);
  await _saveLocalContactAlias(tester, controller);
  await _enableMcpProfileConsent(tester, controller);
  if (_role == 'initiator') {
    await _uploadRemoteBackup(tester, controller);
  }

  final sent = await controller.sendMessage(
    recipientUsername: _peerUsername,
    text: _controlsReadyOutbound,
  );
  if (!sent) {
    fail(
      'Could not send the account-controls marker '
      '(${controller.messageError ?? 'message channel unavailable'}).',
    );
  }
  final outbound = controller.messages.singleWhere(
    (message) => message.outgoing && message.text == _controlsReadyOutbound,
  );
  await _pumpUntil(
    tester,
    () =>
        controller.outboundMessageFor(outbound.messageId) == null &&
        controller.messages.any(
          (message) =>
              !message.outgoing && message.text == _controlsReadyInbound,
        ),
    label: 'peer account-controls marker',
    timeout: const Duration(minutes: 2),
  );

  await _viewPeerProfile(tester);
  await _exerciseSearchAndReadFilters(tester, controller);
}

Future<void> _updatePublicProfile(
  WidgetTester tester,
  WampAppController controller,
) async {
  final edit = find.byKey(const Key('account-profile-edit'));
  await _tapWhenReady(tester, edit, label: 'public-profile editor');
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('profile-save')).evaluate().isNotEmpty,
    label: 'public-profile dialog',
  );
  await tester.enterText(
    find.byKey(const Key('profile-display-name')),
    _profileDisplayName,
  );
  await tester.enterText(
    find.byKey(const Key('profile-status')),
    _profileStatus,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await _tapWhenReady(
    tester,
    find.byKey(const Key('profile-save')),
    label: 'public-profile save',
  );
  await _pumpUntil(
    tester,
    () =>
        find.byKey(const Key('profile-save')).evaluate().isEmpty &&
        !controller.profileBusy &&
        controller.connection?.profile.displayName == _profileDisplayName &&
        controller.connection?.profile.status == _profileStatus,
    label: 'persisted public profile',
  );
  expect(controller.profileError, isNull);
}

Future<void> _setLocalConversationPreferences(
  WidgetTester tester,
  WampAppController controller,
) async {
  final theme = find.byKey(const Key('account-theme-menu'));
  await _tapWhenReady(tester, theme, label: 'appearance menu');
  final dark = find.byKey(const ValueKey('appearance-dark'));
  await _tapWhenReady(tester, dark, label: 'dark appearance');
  await _pumpUntil(
    tester,
    () =>
        !controller.preferenceBusy &&
        controller.themePreference.wireName == 'dark' &&
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
            ThemeMode.dark,
    label: 'local dark appearance',
  );

  final conversationId = controller.directConversationIdFor(_peerUsername);
  if (conversationId == null) {
    fail('The direct conversation was unavailable for local preferences.');
  }
  final mute = find.byKey(const Key('conversation-mute'));
  await _tapWhenReady(tester, mute, label: 'conversation mute');
  await _pumpUntil(
    tester,
    () =>
        !controller.preferenceBusy &&
        controller.isConversationMuted(conversationId),
    label: 'persisted local mute preference',
  );

  final expiry = find.byKey(const Key('message-expiry'));
  await _tapWhenReady(tester, expiry, label: 'disappearing-message menu');
  await _tapWhenReady(
    tester,
    find.text('Delete after 1 hour'),
    label: 'one-hour disappearing-message policy',
  );
  await _pumpUntil(
    tester,
    () =>
        !controller.preferenceBusy &&
        controller.disappearingMessagesFor(conversationId) ==
            const Duration(hours: 1),
    label: 'persisted disappearing-message policy',
  );
  expect(controller.preferenceError, isNull);
}

Future<void> _saveLocalContactAlias(
  WidgetTester tester,
  WampAppController controller,
) async {
  final compact = find.byKey(const Key('account-contacts-compact'));
  final contacts = compact.evaluate().isNotEmpty
      ? compact
      : find.byKey(const Key('account-contacts'));
  await _tapWhenReady(tester, contacts, label: 'local contact manager');
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('contact-save')).evaluate().isNotEmpty,
    label: 'local contact dialog',
  );
  await tester.tap(find.byKey(const Key('contact-add-manual')));
  await tester.enterText(
    find.byKey(const Key('contact-display-name')),
    _contactDisplayName,
  );
  await tester.enterText(
    find.byKey(const Key('contact-username')),
    _peerUsername,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await _tapWhenReady(
    tester,
    find.byKey(const Key('contact-save')),
    label: 'verified local contact save',
  );
  await _pumpUntil(
    tester,
    () =>
        !controller.contactBusy &&
        controller.contacts.any(
          (contact) =>
              contact.username == _peerUsername &&
              contact.displayName == _contactDisplayName,
        ),
    label: 'encrypted local contact alias',
  );
  expect(controller.contactError, isNull);
  await _tapWhenReady(
    tester,
    find.byKey(const Key('contact-close')),
    label: 'contact dialog close',
  );
}

Future<void> _enableMcpProfileConsent(
  WidgetTester tester,
  WampAppController controller,
) async {
  await _tapWhenReady(
    tester,
    find.byKey(const Key('account-mcp-profile-consent')),
    label: 'MCP profile consent',
  );
  await _tapWhenReady(
    tester,
    find.byKey(const Key('mcp-profile-consent-confirm')),
    label: 'MCP profile consent confirmation',
  );
  await _pumpUntil(
    tester,
    () =>
        !controller.mcpConsentBusy && controller.mcpConsent.profileReadAllowed,
    label: 'persisted MCP profile consent',
  );
  expect(controller.mcpConsentError, isNull);
}

Future<void> _uploadRemoteBackup(
  WidgetTester tester,
  WampAppController controller,
) async {
  final compact = find.byKey(const Key('account-backup-compact'));
  if (compact.evaluate().isNotEmpty) {
    await _tapWhenReady(tester, compact, label: 'backup options');
    await _tapWhenReady(
      tester,
      find.byKey(const Key('backup-action-remote')),
      label: 'remote encrypted backup action',
    );
  } else {
    await _tapWhenReady(
      tester,
      find.byKey(const Key('account-backup-remote')),
      label: 'remote encrypted backup action',
    );
  }
  await _pumpUntil(
    tester,
    () => find
        .byKey(const Key('backup-recovery-confirmation'))
        .evaluate()
        .isNotEmpty,
    label: 'backup recovery phrase dialog',
  );
  await tester.enterText(
    find.byKey(const Key('backup-recovery-passphrase')),
    _backupPassphrase,
  );
  await tester.enterText(
    find.byKey(const Key('backup-recovery-confirmation')),
    _backupPassphrase,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await _tapWhenReady(
    tester,
    find.byKey(const Key('backup-passphrase-submit')),
    label: 'encrypted backup creation',
  );
  await _pumpUntil(
    tester,
    () =>
        !controller.backupBusy &&
        find
            .text('Encrypted backup stored on this server.')
            .evaluate()
            .isNotEmpty,
    label: 'remote encrypted backup upload',
    timeout: const Duration(minutes: 2),
  );
  expect(controller.backupError, isNull);
}

Future<void> _viewPeerProfile(WidgetTester tester) async {
  await _selectDirectConversation(tester);
  final recipient = find.byKey(const Key('message-recipient'));
  await tester.enterText(recipient, _peerUsername);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await _tapWhenReady(
    tester,
    find.byKey(const Key('recipient-profile-view')),
    label: 'peer public profile',
  );
  await _pumpUntil(
    tester,
    () =>
        find.text(_peerProfileDisplayName).evaluate().isNotEmpty &&
        find.text(_peerProfileStatus).evaluate().isNotEmpty &&
        find.byKey(const Key('peer-profile-status')).evaluate().isNotEmpty,
    label: 'peer public-profile propagation',
  );
  await _tapWhenReady(tester, find.text('Close'), label: 'peer profile close');
}

Future<void> _exerciseSearchAndReadFilters(
  WidgetTester tester,
  WampAppController controller,
) async {
  final inbound = controller.messages.singleWhere(
    (message) => !message.outgoing && message.text == _controlsReadyInbound,
  );
  final inboundBubble = find.byKey(
    ValueKey('message-bubble-${inbound.messageId}'),
  );
  expect(inbound.readAt, isNull);
  final search = find.byKey(const Key('message-global-search'));
  await _tapWhenReady(tester, search, label: 'global message search');
  await tester.enterText(search, _controlsReadyInbound);
  await _pumpUntil(
    tester,
    () =>
        find.text(_controlsReadyInbound).evaluate().isNotEmpty &&
        inboundBubble.evaluate().length == 1,
    label: 'global search result',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await controller.markMessageRead(inbound.messageId);
  await _pumpUntil(
    tester,
    () => controller.messages.any(
      (message) =>
          message.messageId == inbound.messageId && message.readAt != null,
    ),
    label: 'authenticated read receipt from search result',
  );
  await tester.enterText(search, '');
  await tester.pump(const Duration(milliseconds: 400));

  await _tapWhenReady(
    tester,
    find.byKey(const Key('message-filter-read')),
    label: 'read-message filter',
  );
  await _pumpUntil(
    tester,
    () => inboundBubble.evaluate().length == 1,
    label: 'read-filter result',
  );
  await _tapWhenReady(
    tester,
    find.byKey(const Key('message-filter-unread')),
    label: 'unread-message filter',
  );
  await _pumpUntil(
    tester,
    () => inboundBubble.evaluate().isEmpty,
    label: 'read message excluded from unread filter',
  );
  await _tapWhenReady(
    tester,
    find.byKey(const Key('message-filter-all')),
    label: 'all-message filter reset',
  );
  expect(controller.messageError, isNull);
}

Future<void> _tapWhenReady(
  WidgetTester tester,
  Finder finder, {
  required String label,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 1));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().length != 1) continue;
    await tester.ensureVisible(finder);
    await tester.pump();
    if (finder.hitTestable().evaluate().length != 1) continue;
    await tester.tap(finder);
    return;
  }
  fail('Timed out waiting for $label.');
}

Future<void> _exerciseWebRtcCall(
  WidgetTester tester,
  WampAppController controller, {
  required CallMediaKind media,
  required String readyOutbound,
  required String readyInbound,
}) async {
  await _selectDirectConversation(tester);
  final calls = controller.calls;
  expect(calls, isNotNull);
  expect(calls!.phase, CallUiPhase.idle);
  final label = media == CallMediaKind.voice ? 'voice' : 'video';
  final startKey = media == CallMediaKind.voice
      ? 'conversation-voice-call'
      : 'conversation-video-call';

  if (_role == 'initiator') {
    final start = find.byKey(Key(startKey));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await _pumpUntil(
      tester,
      () =>
          calls.phase == CallUiPhase.outgoingRinging ||
          calls.phase == CallUiPhase.connecting ||
          calls.phase == CallUiPhase.active,
      label: 'outgoing secured $label call',
      timeout: const Duration(minutes: 2),
    );
    expect(find.byKey(const ValueKey('active-call')), findsOneWidget);
  } else {
    await _pumpUntil(
      tester,
      () =>
          calls.phase == CallUiPhase.incomingRinging &&
          find.byKey(const ValueKey('incoming-call')).evaluate().isNotEmpty,
      label: 'incoming secured $label call',
      timeout: const Duration(minutes: 2),
    );
    final accept = find.byKey(const Key('call-accept'));
    await tester.ensureVisible(accept);
    await tester.tap(accept);
  }

  await _pumpUntil(
    tester,
    () =>
        calls.phase == CallUiPhase.active &&
        calls.call?.state == CallState.active &&
        calls.call?.media == media &&
        calls.mediaSession != null &&
        calls.mediaSession?.media == media &&
        calls.peerUsername == _peerUsername &&
        find.byKey(const ValueKey('active-call')).evaluate().isNotEmpty &&
        (media == CallMediaKind.voice ||
            find.byKey(const Key('call-local-video')).evaluate().isNotEmpty),
    label: 'active WebRTC $label media with $_peerUsername',
    timeout: const Duration(minutes: 2),
  );
  expect(calls.errorMessage, isNull);

  await _pumpUntil(
    tester,
    () => !controller.messageBusy,
    label: 'idle encrypted message channel during the active call',
  );
  final markerSent = await controller.sendMessage(
    recipientUsername: _peerUsername,
    text: readyOutbound,
  );
  if (!markerSent) {
    fail(
      'Could not enqueue the active-call marker: '
      '${controller.messageError ?? 'message channel unavailable'}.',
    );
  }
  final outboundReady = controller.messages.singleWhere(
    (message) =>
        message.outgoing &&
        !message.isGroup &&
        message.peerUsername == _peerUsername &&
        message.text == readyOutbound,
  );
  await _pumpUntil(
    tester,
    () =>
        controller.outboundMessageFor(outboundReady.messageId) == null &&
        controller.messages.any(
          (message) =>
              !message.outgoing &&
              !message.isGroup &&
              message.peerUsername == _peerUsername &&
              message.text == readyInbound,
        ),
    label: 'both devices active in the same $label call',
    timeout: const Duration(minutes: 2),
  );

  if (_role == 'initiator') {
    if (media == CallMediaKind.voice) {
      final mute = find.byKey(const Key('call-mute'));
      await tester.ensureVisible(mute);
      await tester.tap(mute);
      await _pumpUntil(
        tester,
        () => calls.mediaSession?.muted ?? false,
        label: 'muted native voice track',
      );
      await tester.tap(mute);
      await _pumpUntil(
        tester,
        () => !(calls.mediaSession?.muted ?? true),
        label: 'unmuted native voice track',
      );
    } else {
      expect(calls.mediaSession?.cameraEnabled, isTrue);
      final camera = find.byKey(const Key('call-camera'));
      await tester.ensureVisible(camera);
      await tester.tap(camera);
      await _pumpUntil(
        tester,
        () => !(calls.mediaSession?.cameraEnabled ?? true),
        label: 'disabled native video track',
      );
      await tester.tap(camera);
      await _pumpUntil(
        tester,
        () => calls.mediaSession?.cameraEnabled ?? false,
        label: 're-enabled native video track',
      );
    }
    final end = find.byKey(const Key('call-end'));
    await tester.ensureVisible(end);
    await tester.tap(end);
  }

  await _pumpUntil(
    tester,
    () =>
        calls.phase == CallUiPhase.ended &&
        calls.mediaSession == null &&
        find.byKey(const ValueKey('call-result')).evaluate().isNotEmpty,
    label: _role == 'initiator'
        ? 'local $label-call teardown'
        : 'remote $label-call teardown',
    timeout: const Duration(minutes: 2),
  );
  expect(calls.errorMessage, isNull);
  await tester.pump(const Duration(milliseconds: 350));
  if (media == CallMediaKind.video) {
    expect(find.byKey(const Key('call-local-video')), findsNothing);
  }
  final dismiss = find.byKey(const Key('call-dismiss'));
  await tester.ensureVisible(dismiss);
  await tester.tap(dismiss);
  await _pumpUntil(
    tester,
    () => calls.phase == CallUiPhase.idle && !calls.hasCall,
    label: 'dismissed completed $label call',
  );
}

Future<void> _exerciseEncryptedGroupSticker(
  WidgetTester tester,
  WampAppController controller,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  if (_role == 'initiator') {
    await _createGroupAndSendSticker(tester, controller);
    return;
  }
  await _receiveStickerAndReply(tester, controller);
}

Future<void> _createGroupAndSendSticker(
  WidgetTester tester,
  WampAppController controller,
) async {
  final createGroup = find.byKey(const Key('conversation-create-group'));
  await tester.ensureVisible(createGroup);
  await tester.tap(createGroup);
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('group-create')).evaluate().isNotEmpty,
    label: 'group creation dialog',
  );
  await tester.enterText(find.byKey(const Key('group-title')), _groupTitle);
  await tester.enterText(find.byKey(const Key('group-members')), _peerUsername);
  await tester.tap(find.byKey(const Key('group-create')));

  await _pumpUntil(
    tester,
    () => controller.groups.any(
      (group) =>
          group.title == _groupTitle &&
          group.memberUsernames.contains(_username) &&
          group.memberUsernames.contains(_peerUsername),
    ),
    label: 'local encrypted group creation',
  );
  final group = controller.groups.singleWhere(
    (group) => group.title == _groupTitle,
  );
  final groupChip = find.byKey(
    ValueKey('conversation-group-${group.conversationId}'),
  );
  await _pumpUntil(
    tester,
    () =>
        groupChip.evaluate().isNotEmpty &&
        find.byKey(const Key('group-members-summary')).evaluate().isNotEmpty,
    label: 'selected group conversation',
  );

  final expression = find.byKey(const Key('message-expression'));
  await tester.ensureVisible(expression);
  await tester.tap(expression);
  final stickerTab = find.byKey(const Key('expression-sticker-tab'));
  await _pumpUntil(
    tester,
    () => stickerTab.hitTestable().evaluate().isNotEmpty,
    label: 'expression picker',
  );
  await tester.tap(stickerTab);
  await tester.pump(const Duration(milliseconds: 400));
  final sticker = find.byKey(const ValueKey('sticker-nice'));
  await tester.ensureVisible(sticker);
  await tester.tap(sticker);
  await _pumpUntil(
    tester,
    () =>
        find.byKey(const Key('expression-close')).evaluate().isEmpty &&
        find.byKey(const Key('selected-attachment-0')).evaluate().isNotEmpty,
    label: 'staged bundled sticker',
  );

  final composer = find.byKey(const Key('message-composer'));
  await _enterMessageWhenReady(
    tester,
    composer,
    _groupOutboundText,
    label: 'group sticker composer',
  );
  final send = find.byKey(const Key('message-send'));
  await tester.ensureVisible(send);
  await _tapSendAndWait(
    tester,
    controller,
    send,
    () => controller.messages.any(
      (message) =>
          _matchesGroupMessage(
            message,
            outgoing: true,
            text: _groupOutboundText,
          ) &&
          message.attachments.length == 1 &&
          message.attachments.single.kind == ChatAttachmentKind.sticker,
    ),
    label: 'encrypted group sticker send',
  );
  final outbound = controller.messages.singleWhere(
    (message) =>
        _matchesGroupMessage(
          message,
          outgoing: true,
          text: _groupOutboundText,
        ) &&
        message.attachments.length == 1,
  );
  await _pumpUntil(
    tester,
    () =>
        controller.outboundMessageFor(outbound.messageId) == null &&
        controller.messageError == null,
    label: 'router acceptance of encrypted group sticker',
    timeout: const Duration(minutes: 2),
  );
  await _pumpUntil(
    tester,
    () => controller.messages.any(
      (message) => _matchesGroupMessage(
        message,
        outgoing: false,
        text: _groupInboundText,
      ),
    ),
    label: 'decrypted same-group reply',
    timeout: const Duration(minutes: 2),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await _pumpUntil(
    tester,
    () => find.text(_groupInboundText).evaluate().isNotEmpty,
    label: 'rendered same-group reply',
  );
  expect(controller.messageError, isNull);
}

Future<void> _receiveStickerAndReply(
  WidgetTester tester,
  WampAppController controller,
) async {
  LocalChatMessage? received;
  await _pumpUntil(
    tester,
    () {
      for (final message in controller.messages) {
        if (_matchesGroupMessage(
              message,
              outgoing: false,
              text: _groupInboundText,
            ) &&
            message.attachments.length == 1 &&
            message.attachments.single.kind == ChatAttachmentKind.sticker) {
          received = message;
          return true;
        }
      }
      return false;
    },
    label: 'decrypted inbound group sticker',
    timeout: const Duration(minutes: 2),
  );
  final groupMessage = received!;
  final group = controller.groups.singleWhere(
    (group) => group.conversationId == groupMessage.conversationId,
  );
  expect(group.title, _groupTitle);
  expect(group.memberUsernames, containsAll([_username, _peerUsername]));

  final groupChip = find.byKey(
    ValueKey('conversation-group-${group.conversationId}'),
  );
  await _pumpUntil(
    tester,
    () => groupChip.evaluate().isNotEmpty,
    label: 'discovered group conversation chip',
  );
  await tester.ensureVisible(groupChip);
  await tester.tap(groupChip);
  await _pumpUntil(
    tester,
    () =>
        tester.widget<ChoiceChip>(groupChip).selected &&
        find.byKey(const Key('group-members-summary')).evaluate().isNotEmpty,
    label: 'selected discovered group',
  );

  final attachment = groupMessage.attachments.single;
  final attachmentCard = find.byKey(
    ValueKey('attachment-open-${attachment.attachmentId}'),
  );
  await _pumpUntil(
    tester,
    () => attachmentCard.evaluate().isNotEmpty,
    label: 'rendered encrypted sticker attachment card',
  );
  await Scrollable.ensureVisible(
    attachmentCard.evaluate().single,
    alignment: 0.5,
  );
  await tester.pump();
  final attachmentRect = tester.getRect(attachmentCard);
  final historyRect = tester.getRect(find.byKey(const Key('message-history')));
  final visibleAttachmentRect = attachmentRect.intersect(historyRect);
  expect(
    visibleAttachmentRect.height,
    greaterThanOrEqualTo(24),
    reason:
        'The encrypted sticker attachment must have a usable tap target in '
        'history (attachment: $attachmentRect, history: $historyRect).',
  );
  await tester.tapAt(visibleAttachmentRect.center);
  final preview = find.byKey(
    ValueKey('attachment-preview-${attachment.attachmentId}'),
  );
  await _pumpUntil(
    tester,
    () => preview.evaluate().isNotEmpty,
    label: 'downloaded and decrypted sticker preview',
    timeout: const Duration(minutes: 2),
  );
  expect(preview, findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Close'));
  await _pumpUntil(
    tester,
    () => preview.evaluate().isEmpty,
    label: 'closed sticker preview',
  );

  final composer = find.byKey(const Key('message-composer'));
  await _enterMessageWhenReady(
    tester,
    composer,
    _groupOutboundText,
    label: 'group reply composer',
  );
  final send = find.byKey(const Key('message-send'));
  await tester.ensureVisible(send);
  await _tapSendAndWait(
    tester,
    controller,
    send,
    () => controller.messages.any(
      (message) => _matchesGroupMessage(
        message,
        outgoing: true,
        text: _groupOutboundText,
      ),
    ),
    label: 'same-group encrypted reply send',
  );
  final reply = controller.messages.singleWhere(
    (message) =>
        _matchesGroupMessage(message, outgoing: true, text: _groupOutboundText),
  );
  await _pumpUntil(
    tester,
    () =>
        controller.outboundMessageFor(reply.messageId) == null &&
        controller.messageError == null,
    label: 'router acceptance of same-group reply',
    timeout: const Duration(minutes: 2),
  );
  expect(controller.messageError, isNull);
}

Future<void> _exerciseViewOnceMessage(
  WidgetTester tester,
  WampAppController controller,
) async {
  await _selectDirectConversation(tester);
  if (_role == 'initiator') {
    await _sendViewOnceMessage(tester, controller);
    return;
  }
  await _receiveViewOnceMessage(tester, controller);
}

Future<void> _selectDirectConversation(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final direct = find.byKey(const Key('conversation-direct'));
  await tester.ensureVisible(direct);
  await tester.tap(direct);
  await _pumpUntil(
    tester,
    () =>
        direct.evaluate().length == 1 &&
        tester.widget<ChoiceChip>(direct).selected &&
        find.byKey(const Key('message-recipient')).evaluate().isNotEmpty,
    label: 'selected direct conversation',
  );
  final recipient = find.byKey(const Key('message-recipient'));
  await tester.ensureVisible(recipient);
  await tester.enterText(recipient, _peerUsername);
  FocusManager.instance.primaryFocus?.unfocus();
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('message-one-time')).evaluate().isNotEmpty,
    label: 'restored direct-message controls',
  );
}

Future<void> _sendViewOnceMessage(
  WidgetTester tester,
  WampAppController controller,
) async {
  final oneTime = find.byKey(const Key('message-one-time'));
  await tester.ensureVisible(oneTime);
  await tester.tap(oneTime);
  await _pumpUntil(
    tester,
    () =>
        oneTime.evaluate().length == 1 &&
        tester.widget<FilterChip>(oneTime).selected,
    label: 'enabled view-once mode',
  );

  final composer = find.byKey(const Key('message-composer'));
  await _enterMessageWhenReady(
    tester,
    composer,
    _oneTimeText,
    label: 'view-once composer',
  );
  final send = find.byKey(const Key('message-send'));
  await _tapSendAndWait(
    tester,
    controller,
    send,
    () => controller.messages.any(_matchesOutboundViewOnce),
    label: 'encrypted view-once send',
  );
  final outbound = controller.messages.singleWhere(_matchesOutboundViewOnce);
  await _pumpUntil(
    tester,
    () =>
        controller.outboundMessageFor(outbound.messageId) == null &&
        controller.messageError == null,
    label: 'router acceptance of view-once message',
    timeout: const Duration(minutes: 2),
  );
  await _pumpUntil(
    tester,
    () => controller.messages.any(
      (message) =>
          message.messageId == outbound.messageId && message.readAt != null,
    ),
    label: 'view-once open receipt',
    timeout: const Duration(minutes: 2),
  );
  expect(controller.messageError, isNull);
}

Future<void> _receiveViewOnceMessage(
  WidgetTester tester,
  WampAppController controller,
) async {
  LocalChatMessage? received;
  await _pumpUntil(
    tester,
    () {
      for (final message in controller.messages) {
        if (!message.outgoing &&
            !message.isGroup &&
            message.peerUsername == _peerUsername &&
            message.oneTime &&
            message.text == _oneTimeText) {
          received = message;
          return true;
        }
      }
      return false;
    },
    label: 'decrypted inbound view-once message',
    timeout: const Duration(minutes: 2),
  );
  final viewOnce = received!;
  expect(find.text(_oneTimeText), findsNothing);

  final reveal = find.byKey(
    ValueKey('message-view-once-${viewOnce.messageId}'),
  );
  await _pumpUntil(
    tester,
    () => reveal.evaluate().isNotEmpty,
    label: 'hidden view-once message',
  );
  await tester.ensureVisible(reveal);
  await tester.tap(reveal);
  final content = find.byKey(const Key('one-time-message-content'));
  await _pumpUntil(
    tester,
    () => content.evaluate().isNotEmpty,
    label: 'revealed view-once dialog',
    timeout: const Duration(minutes: 2),
  );
  expect(find.text(_oneTimeText), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await _pumpUntil(
    tester,
    () =>
        content.evaluate().isEmpty &&
        !controller.messages.any(
          (message) => message.messageId == viewOnce.messageId,
        ),
    label: 'consumed view-once removal',
  );
  expect(find.text(_oneTimeText), findsNothing);
  expect(controller.messageError, isNull);
}

bool _matchesOutboundViewOnce(LocalChatMessage message) =>
    message.outgoing &&
    !message.isGroup &&
    message.peerUsername == _peerUsername &&
    message.oneTime &&
    message.text == _oneTimeText;

bool _matchesGroupMessage(
  LocalChatMessage message, {
  required bool outgoing,
  required String text,
}) =>
    message.outgoing == outgoing &&
    message.isGroup &&
    message.groupTitle == _groupTitle &&
    message.text == text;

Future<void> _enterMessageWhenReady(
  WidgetTester tester,
  Finder composer,
  String text, {
  required String label,
}) async {
  await _pumpUntil(
    tester,
    () =>
        composer.evaluate().length == 1 &&
        composer.hitTestable().evaluate().length == 1 &&
        tester.widget<TextField>(composer).enabled != false,
    label: '$label readiness',
  );
  await tester.ensureVisible(composer);
  await tester.tap(composer);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.showKeyboard(composer);
  await tester.enterText(composer, text);
  await tester.pump();
  expect(
    tester.widget<TextField>(composer).controller?.text,
    text,
    reason: '$label must accept the smoke message.',
  );
}

void _validateConfiguration() {
  final values = {
    'WAMP_APP_SERVER_ADDRESS': _serverAddress,
    'WAMP_APP_SMOKE_USERNAME': _username,
    'WAMP_APP_SMOKE_PEER': _peerUsername,
    'WAMP_APP_SMOKE_OUTBOUND': _outboundText,
    'WAMP_APP_SMOKE_INBOUND': _inboundText,
    'WAMP_APP_SMOKE_ROLE': _role,
    'WAMP_APP_SMOKE_GROUP_TITLE': _groupTitle,
    'WAMP_APP_SMOKE_GROUP_OUTBOUND': _groupOutboundText,
    'WAMP_APP_SMOKE_GROUP_INBOUND': _groupInboundText,
    'WAMP_APP_SMOKE_VIEW_ONCE': _oneTimeText,
    'WAMP_APP_SMOKE_CALL_READY_OUTBOUND': _voiceCallReadyOutbound,
    'WAMP_APP_SMOKE_CALL_READY_INBOUND': _voiceCallReadyInbound,
    'WAMP_APP_SMOKE_VIDEO_READY_OUTBOUND': _videoCallReadyOutbound,
    'WAMP_APP_SMOKE_VIDEO_READY_INBOUND': _videoCallReadyInbound,
    'WAMP_APP_SMOKE_PROFILE_DISPLAY_NAME': _profileDisplayName,
    'WAMP_APP_SMOKE_PROFILE_STATUS': _profileStatus,
    'WAMP_APP_SMOKE_PEER_PROFILE_DISPLAY_NAME': _peerProfileDisplayName,
    'WAMP_APP_SMOKE_PEER_PROFILE_STATUS': _peerProfileStatus,
    'WAMP_APP_SMOKE_CONTACT_DISPLAY_NAME': _contactDisplayName,
    'WAMP_APP_SMOKE_CONTROLS_READY_OUTBOUND': _controlsReadyOutbound,
    'WAMP_APP_SMOKE_CONTROLS_READY_INBOUND': _controlsReadyInbound,
    'WAMP_APP_SMOKE_BACKUP_PASSPHRASE': _backupPassphrase,
  };
  for (final entry in values.entries) {
    if (entry.value.trim().isEmpty) {
      fail('${entry.key} must be provided for the two-device smoke.');
    }
  }
  if (_role != 'initiator' && _role != 'responder') {
    fail('WAMP_APP_SMOKE_ROLE must be initiator or responder.');
  }
  final messageTokens = [
    _outboundText,
    _inboundText,
    _groupOutboundText,
    _groupInboundText,
    _oneTimeText,
    _voiceCallReadyOutbound,
    _voiceCallReadyInbound,
    _videoCallReadyOutbound,
    _videoCallReadyInbound,
    _controlsReadyOutbound,
    _controlsReadyInbound,
  ];
  if (_username == _peerUsername ||
      messageTokens.toSet().length != messageTokens.length) {
    fail('The two smoke clients must use distinct identities and messages.');
  }
  if (_backupPassphrase.length < 16) {
    fail('WAMP_APP_SMOKE_BACKUP_PASSPHRASE must be at least 16 characters.');
  }
}

Future<void> _tapSendAndWaitOutbound(
  WidgetTester tester,
  WampAppController controller,
  Finder send,
) async {
  bool hasOutbound() => controller.messages.any(
    (message) =>
        message.outgoing &&
        message.peerUsername == _peerUsername &&
        message.text == _outboundText,
  );

  await _tapSendAndWait(
    tester,
    controller,
    send,
    hasOutbound,
    label: 'successful encrypted direct-message tap',
  );
}

Future<void> _tapSendAndWait(
  WidgetTester tester,
  WampAppController controller,
  Finder send,
  bool Function() accepted, {
  required String label,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(send);
  DateTime? readySince;
  final readyDeadline = DateTime.now().add(const Duration(minutes: 1));
  while (DateTime.now().isBefore(readyDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    final ready =
        send.evaluate().length == 1 &&
        send.hitTestable().evaluate().length == 1 &&
        tester.widget<IconButton>(send).onPressed != null;
    if (!ready) {
      readySince = null;
      continue;
    }
    readySince ??= DateTime.now();
    if (DateTime.now().difference(readySince) >=
        const Duration(milliseconds: 500)) {
      break;
    }
  }
  if (readySince == null ||
      DateTime.now().difference(readySince) <
          const Duration(milliseconds: 500)) {
    fail(
      'Timed out waiting for $label readiness (${_messageState(controller)}).',
    );
  }
  await tester.tap(send);
  final acceptedDeadline = DateTime.now().add(const Duration(minutes: 1));
  while (DateTime.now().isBefore(acceptedDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (accepted()) return;
    if (!controller.messageBusy && controller.messageError != null) {
      fail('$label failed (${_messageState(controller)}).');
    }
  }
  fail('Timed out waiting for $label (${_messageState(controller)}).');
}

String _messageState(WampAppController controller) =>
    'busy=${controller.messageBusy}, error=${controller.messageError}, '
    'groups=${controller.groups.length}, '
    'outgoingGroups=${controller.messages.where((message) => message.outgoing && message.isGroup).length}';

Future<void> _waitForPeerDevice(
  WidgetTester tester,
  WampAppController controller,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final connection = controller.connection;
    if (connection != null) {
      try {
        final directory = await connection.lookupDevices(_peerUsername);
        if (directory.devices.isNotEmpty) return;
      } catch (error) {
        lastError = error;
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail(
    'Timed out waiting for the peer device directory'
    '${lastError == null ? '.' : ' (${lastError.runtimeType}).'}',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String label,
  Duration timeout = const Duration(minutes: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail('Timed out waiting for $label.');
}
