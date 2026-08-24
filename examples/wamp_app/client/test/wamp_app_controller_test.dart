import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('registration normalizes identity and connects with the same challenge secret', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(gateway: gateway);
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
  });

  test(
    'remote cleartext endpoints fail before credentials reach a gateway',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(gateway: gateway);
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
    final controller = WampAppController(gateway: gateway);
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    await controller.signOut();

    expect(controller.status, WampAppStatus.signedOut);
    expect(gateway.closed, isTrue);
  });

  test(
    'replacement stays connected when closing the old transport fails',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(gateway: gateway);
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
}

class _RecordingGateway implements AccountGateway {
  AccountRegistration? registered;
  String? loginPassword;
  bool closed = false;
  bool failNextClose = false;

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
    return AccountConnection(
      endpoint: endpoint,
      username: AccountRegistration.normalizeUsername(username),
      displayName: 'Alice Example',
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
