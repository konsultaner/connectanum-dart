import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/app.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  testWidgets('registers and opens the authenticated shell', (tester) async {
    final controller = WampAppController(
      gateway: _FakeGateway(),
      trustStore: FakeDeviceTrustStore(),
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

    expect(find.text('Connected, with room to talk'), findsOneWidget);
    expect(find.text('Alice Example'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('Encrypted device vault'), findsOneWidget);
    expect(find.text('Test device'), findsOneWidget);
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
}

class _FakeGateway implements AccountGateway {
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
      revokeDeviceCallback: (_) => throw UnimplementedError(),
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
