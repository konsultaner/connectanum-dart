import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wamp_app/src/app.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';

const _serverAddress = String.fromEnvironment('WAMP_APP_SERVER_ADDRESS');
const _username = String.fromEnvironment('WAMP_APP_SMOKE_USERNAME');
const _peerUsername = String.fromEnvironment('WAMP_APP_SMOKE_PEER');
const _outboundText = String.fromEnvironment('WAMP_APP_SMOKE_OUTBOUND');
const _inboundText = String.fromEnvironment('WAMP_APP_SMOKE_INBOUND');
const _password = 'wamp-app-native-smoke-password';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'registers and exchanges an encrypted message with the peer device',
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
      await tester.ensureVisible(composer);
      await tester.enterText(composer, _outboundText);
      final send = find.byKey(const Key('message-send'));
      await tester.ensureVisible(send);
      await _tapSendUntilOutbound(tester, controller, send);
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
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

void _validateConfiguration() {
  final values = {
    'WAMP_APP_SERVER_ADDRESS': _serverAddress,
    'WAMP_APP_SMOKE_USERNAME': _username,
    'WAMP_APP_SMOKE_PEER': _peerUsername,
    'WAMP_APP_SMOKE_OUTBOUND': _outboundText,
    'WAMP_APP_SMOKE_INBOUND': _inboundText,
  };
  for (final entry in values.entries) {
    if (entry.value.trim().isEmpty) {
      fail('${entry.key} must be provided for the two-device smoke.');
    }
  }
  if (_username == _peerUsername || _outboundText == _inboundText) {
    fail('The two smoke clients must use distinct identities and messages.');
  }
}

Future<void> _tapSendUntilOutbound(
  WidgetTester tester,
  WampAppController controller,
  Finder send,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 1));
  bool hasOutbound() => controller.messages.any(
    (message) =>
        message.outgoing &&
        message.peerUsername == _peerUsername &&
        message.text == _outboundText,
  );

  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (hasOutbound()) return;
    if (tester.widget<IconButton>(send).onPressed != null) {
      await tester.tap(send, warnIfMissed: false);
    }
  }
  fail('Timed out waiting for a successful encrypted-message tap.');
}

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
