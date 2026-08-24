import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
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

  test(
    'mailbox wakeups coalesce into serialized cursor synchronization',
    () async {
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
      final connection = gateway.connections.single;
      final blocked = connection.blockNextSync();

      connection.emitWakeup(1);
      await _waitFor(() => connection.syncAfterCursors.length == 2);
      connection.emitWakeup(2);
      connection.emitWakeup(3);
      connection.emitWakeup(2);
      blocked.complete();

      await _waitFor(
        () => trustStore.session?.mailboxCursor == 3 && !controller.messageBusy,
      );
      expect(connection.syncAfterCursors, [0, 0, 1]);
      expect(controller.messageError, isNull);
    },
  );

  test('sign out fences late mailbox wakeups from the old session', () async {
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
    final connection = gateway.connections.single;
    final syncCount = connection.syncAfterCursors.length;

    await controller.signOut();
    connection.emitWakeup(7);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(connection.syncAfterCursors, hasLength(syncCount));
    expect(controller.status, WampAppStatus.signedOut);
  });

  test(
    'replacement fences mailbox wakeups from the previous session',
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
      final previous = gateway.connections.single;
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final replacement = gateway.connections.last;

      previous.emitWakeup(7);
      replacement.emitWakeup(1);
      await _waitFor(
        () =>
            replacement.syncAfterCursors.length == 2 && !controller.messageBusy,
      );

      expect(previous.syncAfterCursors, [0]);
      expect(replacement.syncAfterCursors, [0, 0]);
    },
  );

  test('malformed mailbox wakeups surface as synchronization errors', () async {
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

    gateway.connections.single.emitError(
      const FormatException('Mailbox wakeup cursor is invalid.'),
    );
    await _waitFor(() => controller.messageError != null);

    expect(controller.messageError, 'Mailbox wakeup cursor is invalid.');
    expect(controller.messages, isEmpty);
  });

  test('sign out fences a late one-time consume response', () async {
    final gateway = _RecordingGateway();
    final message = LocalChatMessage(
      messageId: 'one-time-message',
      conversationId: 'alice-bob',
      peerUsername: 'bob',
      text: 'ephemeral plaintext',
      sentAt: DateTime.utc(2026, 8, 24, 12),
      outgoing: false,
      oneTime: true,
    );
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(initialMessages: [message]),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final connection = gateway.connections.single;
    final blocked = connection.blockNextConsume();

    final reveal = controller.consumeOneTimeMessage(message.messageId);
    await _waitFor(() => connection.consumeCalls.length == 1);
    await controller.signOut();
    blocked.complete(
      MessageReceipt(
        messageId: message.messageId,
        cursor: 1,
        deliveredAt: DateTime.utc(2026, 8, 24, 12, 1),
        readAt: DateTime.utc(2026, 8, 24, 12, 1),
        consumedAt: DateTime.utc(2026, 8, 24, 12, 1),
      ),
    );

    expect(await reveal, isNull);
    expect(controller.status, WampAppStatus.signedOut);
    expect(controller.messageError, isNull);
  });
}

class _RecordingGateway implements AccountGateway {
  AccountRegistration? registered;
  String? loginPassword;
  bool closed = false;
  bool failNextClose = false;
  Object? loginFailure;
  final List<_GatewayConnection> connections = [];

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
    final connection = _GatewayConnection()..serverCursor = 0;
    connections.add(connection);
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
      syncMessagesCallback: connection.sync,
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: connection.consume,
      mailboxWakeups: connection.wakeups.stream,
      latestMailboxWakeupCursorCallback: () => connection.latestWakeupCursor,
      latestMailboxWakeupErrorCallback: () => null,
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

final class _GatewayConnection {
  final StreamController<MailboxWakeup> wakeups =
      StreamController<MailboxWakeup>.broadcast(sync: true);
  final List<int> syncAfterCursors = [];
  int latestWakeupCursor = 0;
  int serverCursor = 0;
  final List<OneTimeMessageConsumption> consumeCalls = [];
  Completer<void>? _syncGate;
  Completer<MessageReceipt>? _consumeGate;

  Completer<void> blockNextSync() => _syncGate = Completer<void>();

  Completer<MessageReceipt> blockNextConsume() =>
      _consumeGate = Completer<MessageReceipt>();

  Future<MailboxBatch> sync(int afterCursor, int _) async {
    syncAfterCursors.add(afterCursor);
    final cursor = serverCursor;
    final gate = _syncGate;
    _syncGate = null;
    await gate?.future;
    return MailboxBatch(nextCursor: cursor, messages: const []);
  }

  Future<MessageReceipt> consume(OneTimeMessageConsumption consumption) {
    consumeCalls.add(consumption);
    final gate = _consumeGate;
    _consumeGate = null;
    if (gate == null) throw StateError('No consume response was configured.');
    return gate.future;
  }

  void emitWakeup(int cursor) {
    serverCursor = cursor > serverCursor ? cursor : serverCursor;
    latestWakeupCursor = cursor > latestWakeupCursor
        ? cursor
        : latestWakeupCursor;
    wakeups.add(MailboxWakeup(cursor: cursor));
  }

  void emitError(Object error) => wakeups.addError(error);
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
