import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
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

  test('lost reply retries one exact envelope and reconciles once', () async {
    final gateway = _OutboxGateway()..acceptThenTimeout = true;
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
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];

    final queued = await controller.sendMessage(
      recipientUsername: 'bob',
      text: 'send exactly once',
    );

    expect(queued, isTrue);
    expect(controller.messages, hasLength(1));
    expect(
      trustStore.session!.outbox.single.state,
      OutboundMessageState.retryable,
    );
    expect(controller.messageError, isNull);
    final messageId = controller.messages.single.messageId;
    final firstWire = jsonEncode(gateway.attempts.single.toJson());

    expect(await controller.retryMessage(messageId), isTrue);

    expect(gateway.attempts, hasLength(2));
    expect(jsonEncode(gateway.attempts.last.toJson()), firstWire);
    expect(gateway.attempts.last.messageId, messageId);
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.messageId, messageId);
    expect(trustStore.session!.outbox, isEmpty);
    expect(trustStore.session!.messages, hasLength(1));
  });

  test('message conflicts are terminal until explicitly discarded', () async {
    final gateway = _OutboxGateway()
      ..nextFailureKind = MessageSendFailureKind.conflict;
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
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];

    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'conflicting message',
      ),
      isTrue,
    );
    final messageId = controller.messages.single.messageId;
    expect(
      controller.outboundMessageFor(messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(await controller.retryMessage(messageId), isFalse);
    expect(gateway.attempts, hasLength(1));

    expect(await controller.discardOutboundMessage(messageId), isTrue);
    expect(controller.messages, isEmpty);
    expect(trustStore.session!.outbox, isEmpty);
  });

  test('mailbox envelope mismatch becomes a terminal conflict', () async {
    final gateway = _OutboxGateway()..failBeforeAccept = true;
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
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'retain local plaintext',
      ),
      isTrue,
    );
    final original = gateway.attempts.single;
    final changedPayload = Uint8List.fromList(original.encryptedPayload);
    changedPayload[0] ^= 1;
    final conflicting = EncryptedChatMessage(
      messageId: original.messageId,
      conversationId: original.conversationId,
      senderUsername: original.senderUsername,
      senderDeviceId: original.senderDeviceId,
      recipientUsername: original.recipientUsername!,
      createdAt: original.createdAt,
      encryptedPayload: changedPayload,
      wrappedKeys: original.wrappedKeys,
      oneTime: original.oneTime,
      expiresAt: original.expiresAt,
    );
    gateway.store(conflicting);

    await controller.refreshMessages();

    expect(controller.messages.single.text, 'retain local plaintext');
    expect(
      controller.outboundMessageFor(original.messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(await controller.retryMessage(original.messageId), isFalse);
    expect(gateway.attempts, hasLength(1));
  });

  test('reconnect does not retry a terminal message conflict', () async {
    final gateway = _OutboxGateway()
      ..nextFailureKind = MessageSendFailureKind.conflict;
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
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    await controller.sendMessage(
      recipientUsername: 'bob',
      text: 'do not retry automatically',
    );
    final messageId = gateway.attempts.single.messageId;

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(gateway.attempts, hasLength(1));
    expect(
      controller.outboundMessageFor(messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(controller.messages.single.messageId, messageId);
  });

  test('sign out fences a late send response from the old session', () async {
    final gateway = _OutboxGateway();
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
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    final blocked = gateway.blockNextSend();
    final sending = controller.sendMessage(
      recipientUsername: 'bob',
      text: 'late response',
    );
    await _waitFor(() => gateway.attempts.isNotEmpty);
    final oldSession = trustStore.session!;

    await controller.signOut();
    blocked.complete(
      MessageSendReceipt(
        messageId: gateway.attempts.single.messageId,
        cursor: 1,
        acceptedAt: DateTime.utc(2026, 8, 25, 12),
        duplicate: false,
      ),
    );

    expect(await sending, isTrue);
    expect(controller.status, WampAppStatus.signedOut);
    expect(controller.messageBusy, isFalse);
    expect(controller.messageError, isNull);
    expect(oldSession.outbox.single.state, OutboundMessageState.queued);
    expect(oldSession.outbox.single.attemptCount, 1);
  });

  test(
    'reconnect retries a transient outbox entry once with the same id',
    () async {
      final gateway = _OutboxGateway()..failBeforeAccept = true;
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
      gateway.deviceDirectories['bob'] = [
        activeDeviceRecord('bob', trustStore.session!.enrollment),
      ];
      expect(
        await controller.sendMessage(
          recipientUsername: 'bob',
          text: 'recover after reconnect',
        ),
        isTrue,
      );
      final firstWire = jsonEncode(gateway.attempts.single.toJson());

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(gateway.attempts, hasLength(2));
      expect(jsonEncode(gateway.attempts.last.toJson()), firstWire);
      expect(controller.messages, hasLength(1));
      expect(trustStore.session!.outbox, isEmpty);
    },
  );

  test('creates and atomically sends an encrypted group envelope', () async {
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
    final enrollment = trustStore.session!.enrollment;
    gateway.deviceDirectories['bob'] = [activeDeviceRecord('bob', enrollment)];
    gateway.deviceDirectories['carol'] = [
      activeDeviceRecord('carol', enrollment),
    ];

    final group = await controller.createGroup(
      title: ' Launch crew ',
      memberUsernames: const [' Carol ', 'bob'],
    );
    expect(group, isNotNull);
    expect(group!.title, 'Launch crew');
    expect(group.memberUsernames, ['alice', 'bob', 'carol']);
    expect(controller.groups.single.hasSameDefinition(group), isTrue);

    await controller.sendGroupMessage(
      groupId: group.conversationId,
      text: 'one atomic message',
    );

    expect(gateway.sentMessages, hasLength(1));
    expect(gateway.sentMessages.single.isGroup, isTrue);
    expect(gateway.sentMessages.single.participantUsernames, [
      'alice',
      'bob',
      'carol',
    ]);
    expect(gateway.sentMessages.single.wrappedKeys, hasLength(3));
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
  final Map<String, List<DeviceRecord>> deviceDirectories = {};
  final List<EncryptedChatMessage> sentMessages = [];

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
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    return AccountConnection(
      endpoint: endpoint,
      username: normalizedUsername,
      displayName: 'Alice Example',
      enrollDeviceCallback: (enrollment) async {
        final record = activeDeviceRecord(normalizedUsername, enrollment);
        deviceDirectories[normalizedUsername] = [record];
        return record;
      },
      listDevicesCallback: (_) async =>
          DeviceDirectory(deviceDirectories[normalizedUsername] ?? const []),
      lookupDevicesCallback: (lookupUsername, _) async => DeviceDirectory(
        deviceDirectories[AccountRegistration.normalizeUsername(
              lookupUsername,
            )] ??
            const [],
      ),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: (message) async {
        sentMessages.add(message);
        connection.serverCursor += 1;
        return MessageSendReceipt(
          messageId: message.messageId,
          cursor: connection.serverCursor,
          acceptedAt: DateTime.utc(2026, 8, 24, 12),
          duplicate: false,
        );
      },
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

final class _OutboxGateway implements AccountGateway {
  final Map<String, List<DeviceRecord>> deviceDirectories = {};
  final List<EncryptedChatMessage> attempts = [];
  final List<MailboxMessage> _mailbox = [];
  bool acceptThenTimeout = false;
  bool failBeforeAccept = false;
  MessageSendFailureKind? nextFailureKind;
  int _cursor = 0;
  Completer<MessageSendReceipt>? _sendGate;

  Completer<MessageSendReceipt> blockNextSend() =>
      _sendGate = Completer<MessageSendReceipt>();

  void store(EncryptedChatMessage message) {
    _cursor += 1;
    _mailbox.add(
      MailboxMessage(
        cursor: _cursor,
        message: message,
        acceptedAt: DateTime.utc(2026, 8, 25, 12, _cursor),
      ),
    );
  }

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    final normalized = AccountRegistration.normalizeUsername(username);
    return AccountConnection(
      endpoint: endpoint,
      username: normalized,
      displayName: 'Alice Example',
      enrollDeviceCallback: (enrollment) async {
        final device = activeDeviceRecord(normalized, enrollment);
        deviceDirectories[normalized] = [device];
        return device;
      },
      listDevicesCallback: (_) async =>
          DeviceDirectory(deviceDirectories[normalized] ?? const []),
      lookupDevicesCallback: (lookup, _) async => DeviceDirectory(
        deviceDirectories[AccountRegistration.normalizeUsername(lookup)] ??
            const [],
      ),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: _send,
      syncMessagesCallback: (afterCursor, limit) async {
        final messages = _mailbox
            .where((message) => message.cursor > afterCursor)
            .take(limit)
            .toList(growable: false);
        return MailboxBatch(nextCursor: _cursor, messages: messages);
      },
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: (_) => throw UnimplementedError(),
      mailboxWakeups: const Stream<MailboxWakeup>.empty(),
      latestMailboxWakeupCursorCallback: () => 0,
      latestMailboxWakeupErrorCallback: () => null,
      closeTransport: () async {},
    );
  }

  Future<MessageSendReceipt> _send(EncryptedChatMessage message) async {
    attempts.add(message);
    final sendGate = _sendGate;
    _sendGate = null;
    if (sendGate != null) return sendGate.future;
    final failureKind = nextFailureKind;
    nextFailureKind = null;
    if (failureKind != null) throw MessageSendException(failureKind);
    if (failBeforeAccept) {
      failBeforeAccept = false;
      throw TimeoutException('send response was not available');
    }
    final existing = _mailbox
        .where((stored) => stored.message.messageId == message.messageId)
        .firstOrNull;
    if (existing != null) {
      if (jsonEncode(existing.message.toJson()) !=
          jsonEncode(message.toJson())) {
        throw const MessageSendException(MessageSendFailureKind.conflict);
      }
      return MessageSendReceipt(
        messageId: message.messageId,
        cursor: existing.cursor,
        acceptedAt: existing.acceptedAt,
        duplicate: true,
      );
    }
    _cursor += 1;
    final acceptedAt = DateTime.utc(2026, 8, 25, 12, _cursor);
    _mailbox.add(
      MailboxMessage(cursor: _cursor, message: message, acceptedAt: acceptedAt),
    );
    if (acceptThenTimeout) {
      acceptThenTimeout = false;
      throw TimeoutException('accepted reply was lost');
    }
    return MessageSendReceipt(
      messageId: message.messageId,
      cursor: _cursor,
      acceptedAt: acceptedAt,
      duplicate: false,
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
