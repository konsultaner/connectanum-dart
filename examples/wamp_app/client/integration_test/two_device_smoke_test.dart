import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wamp_app/src/app.dart';
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
const _password = 'wamp-app-native-smoke-password';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exchanges encrypted direct, group, sticker, and view-once messages',
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
    },
    timeout: const Timeout(Duration(minutes: 7)),
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
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('expression-sticker-tab')).evaluate().isNotEmpty,
    label: 'expression picker',
  );
  await tester.tap(find.byKey(const Key('expression-sticker-tab')));
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
  await tester.ensureVisible(attachmentCard);
  await tester.tap(attachmentCard);
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
  ];
  if (_username == _peerUsername ||
      messageTokens.toSet().length != messageTokens.length) {
    fail('The two smoke clients must use distinct identities and messages.');
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
