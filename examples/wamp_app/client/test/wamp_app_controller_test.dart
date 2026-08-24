import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  test('registration normalizes identity and connects with the same challenge secret', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);

    await controller.registerAndConnect(
      serverAddress: 'ws://localhost:8080',
      username: ' Alice ',
      displayName: 'Alice Example',
      password: 'correct horse battery',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(controller.connection?.username, 'alice');
    expect(gateway.registered?.username, 'alice');
    expect(gateway.loginPassword, 'correct horse battery');
    expect(trustStore.password, 'correct horse battery');
    expect(controller.localDevice?.deviceId, trustStore.session?.deviceId);
  });

  test(
    'remote cleartext endpoints fail before credentials reach a gateway',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);

      await controller.login(
        serverAddress: 'ws://chat.example.test/ws',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.failed);
      expect(controller.errorMessage, contains('wss://'));
      expect(gateway.loginPassword, isNull);
    },
  );

  test('sign out closes the authenticated connection', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    await controller.signOut();

    expect(controller.status, WampAppStatus.signedOut);
    expect(gateway.closed, isTrue);
    expect(trustStore.session?.disposed, isTrue);
  });

  test(
    'replacement stays connected when closing the old transport fails',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.failNextClose = true;

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.connected);
      expect(controller.errorMessage, isNull);
    },
  );

  test('failed replacement preserves the existing trusted session', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final existing = controller.connection;
    gateway.loginFailure = StateError('replacement unavailable');

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(controller.connection, same(existing));
    expect(gateway.closed, isFalse);
  });

  test(
    'trust failure closes the transport and never reports connected',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore()
        ..failure = const VaultUnlockException();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.failed);
      expect(controller.connection, isNull);
      expect(gateway.closed, isTrue);
      expect(controller.errorMessage, contains('encrypted device storage'));
    },
  );
}

class _RecordingGateway implements AccountGateway {
  AccountRegistration? registered;
  String? loginPassword;
  bool closed = false;
  bool failNextClose = false;
  Object? loginFailure;

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    registered = registration;
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
    loginPassword = password;
    final loginFailure = this.loginFailure;
    if (loginFailure != null) throw loginFailure;
    return AccountConnection(
      endpoint: endpoint,
      username: AccountRegistration.normalizeUsername(username),
      displayName: 'Alice Example',
      enrollDeviceCallback: (enrollment) async => activeDeviceRecord(
        AccountRegistration.normalizeUsername(username),
        enrollment,
      ),
      listDevicesCallback: (_) async => DeviceDirectory(const []),
      lookupDevicesCallback: (_, _) async => DeviceDirectory(const []),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: (_) => throw UnimplementedError(),
      syncMessagesCallback: (afterCursor, _) async =>
          MailboxBatch(nextCursor: afterCursor, messages: const []),
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      closeTransport: () async {
        closed = true;
        if (failNextClose) {
          failNextClose = false;
          throw StateError('old transport already failed');
        }
      },
    );
  }
}
