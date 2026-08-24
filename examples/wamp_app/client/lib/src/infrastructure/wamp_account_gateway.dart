import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

abstract interface class AccountGateway {
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  });

  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  });
}

class AccountConnection {
  AccountConnection({
    required this.endpoint,
    required this.username,
    required this.displayName,
    required this.closeTransport,
    required this.enrollDeviceCallback,
    required this.listDevicesCallback,
    required this.lookupDevicesCallback,
    required this.revokeDeviceCallback,
    required this.sendMessageCallback,
    required this.syncMessagesCallback,
    required this.markMessageReceiptCallback,
    required this.mailboxWakeups,
    required this.latestMailboxWakeupCursorCallback,
    required this.latestMailboxWakeupErrorCallback,
  });

  final ServerEndpoint endpoint;
  final String username;
  final String displayName;
  final Future<void> Function() closeTransport;
  final Future<DeviceRecord> Function(DeviceEnrollment enrollment)
  enrollDeviceCallback;
  final Future<DeviceDirectory> Function(bool includeRevoked)
  listDevicesCallback;
  final Future<DeviceDirectory> Function(String username, bool includeRevoked)
  lookupDevicesCallback;
  final Future<DeviceRecord> Function(String deviceId) revokeDeviceCallback;
  final Future<MessageSendReceipt> Function(EncryptedChatMessage message)
  sendMessageCallback;
  final Future<MailboxBatch> Function(int afterCursor, int limit)
  syncMessagesCallback;
  final Future<MessageReceipt> Function(String messageId, bool read)
  markMessageReceiptCallback;
  final Stream<MailboxWakeup> mailboxWakeups;
  final int Function() latestMailboxWakeupCursorCallback;
  final Object? Function() latestMailboxWakeupErrorCallback;
  bool _closed = false;

  int get latestMailboxWakeupCursor => latestMailboxWakeupCursorCallback();
  Object? get latestMailboxWakeupError => latestMailboxWakeupErrorCallback();

  Future<DeviceRecord> enrollDevice(DeviceEnrollment enrollment) {
    _ensureOpen();
    return enrollDeviceCallback(enrollment);
  }

  Future<DeviceDirectory> listDevices({bool includeRevoked = false}) {
    _ensureOpen();
    return listDevicesCallback(includeRevoked);
  }

  Future<DeviceRecord> revokeDevice(String deviceId) {
    _ensureOpen();
    return revokeDeviceCallback(deviceId);
  }

  Future<DeviceDirectory> lookupDevices(
    String username, {
    bool includeRevoked = false,
  }) {
    _ensureOpen();
    return lookupDevicesCallback(username, includeRevoked);
  }

  Future<MessageSendReceipt> sendMessage(EncryptedChatMessage message) {
    _ensureOpen();
    return sendMessageCallback(message);
  }

  Future<MailboxBatch> syncMessages({
    required int afterCursor,
    int limit = 100,
  }) {
    _ensureOpen();
    return syncMessagesCallback(afterCursor, limit);
  }

  Future<MessageReceipt> markMessageDelivered(
    String messageId, {
    bool read = false,
  }) {
    _ensureOpen();
    return markMessageReceiptCallback(messageId, read);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await closeTransport();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Account connection is closed.');
  }
}

class WampAccountGateway implements AccountGateway {
  const WampAccountGateway({
    this.connectionTimeout = const Duration(seconds: 15),
    this.derivationTimeout = const Duration(seconds: 75),
  });

  final Duration connectionTimeout;
  final Duration derivationTimeout;

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    endpoint.requireSecureRegistration();
    registration.validate();
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    Session? session;
    try {
      session = await _connect(client);
      final result = await session
          .callSingle(
            WampAppProtocol.accountRegister,
            argumentsKeywords: registration.toWampKeywords(),
          )
          .timeout(connectionTimeout);
      return RegistrationReceipt.fromWampKeywords(result.argumentsKeywords);
    } finally {
      await _close(client, session);
    }
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    endpoint.requireSecureRegistration();
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final authentication = ScramAuthentication(
      password,
      derivationTimeout: derivationTimeout,
      challengeTimeout: connectionTimeout + derivationTimeout,
    );
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.appRealm,
      authId: normalizedUsername,
      authenticationMethods: [authentication],
    );
    final wakeups = _MailboxWakeupFeed();
    try {
      final session = await _connect(client);
      await session
          .subscribePayloadHandler(
            WampAppProtocol.mailboxChanged,
            wakeups.addEvent,
          )
          .timeout(connectionTimeout);
      final displayName = session.authExtra?['display_name'];
      return AccountConnection(
        endpoint: endpoint,
        username: session.authId ?? normalizedUsername,
        displayName: displayName is String ? displayName : normalizedUsername,
        enrollDeviceCallback: (enrollment) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceEnroll,
                argumentsKeywords: enrollment.toWampKeywords(),
              )
              .timeout(connectionTimeout);
          return DeviceRecord.fromWampKeywords(result.argumentsKeywords!);
        },
        listDevicesCallback: (includeRevoked) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceList,
                argumentsKeywords: {'include_revoked': includeRevoked},
              )
              .timeout(connectionTimeout);
          return DeviceDirectory.fromWampKeywords(result.argumentsKeywords);
        },
        revokeDeviceCallback: (deviceId) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceRevoke,
                argumentsKeywords: {'device_id': deviceId},
              )
              .timeout(connectionTimeout);
          return DeviceRecord.fromWampKeywords(result.argumentsKeywords!);
        },
        lookupDevicesCallback: (username, includeRevoked) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceLookup,
                argumentsKeywords: {
                  'username': username,
                  'include_revoked': includeRevoked,
                },
              )
              .timeout(connectionTimeout);
          return DeviceDirectory.fromWampKeywords(result.argumentsKeywords);
        },
        sendMessageCallback: (message) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageSend,
                argumentsKeywords: message.toWampKeywords(),
              )
              .timeout(connectionTimeout);
          return MessageSendReceipt.fromWampKeywords(result.argumentsKeywords);
        },
        syncMessagesCallback: (afterCursor, limit) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageSync,
                argumentsKeywords: {
                  'after_cursor': afterCursor,
                  'limit': limit,
                },
              )
              .timeout(connectionTimeout);
          return MailboxBatch.fromWampKeywords(result.argumentsKeywords);
        },
        markMessageReceiptCallback: (messageId, read) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageReceipt,
                argumentsKeywords: {
                  'message_id': messageId,
                  'state': read ? 'read' : 'delivered',
                },
              )
              .timeout(connectionTimeout);
          return MessageReceipt.fromWampKeywords(result.argumentsKeywords);
        },
        mailboxWakeups: wakeups.stream,
        latestMailboxWakeupCursorCallback: () => wakeups.latestCursor,
        latestMailboxWakeupErrorCallback: () => wakeups.latestError,
        closeTransport: () async {
          try {
            await wakeups.close();
            await _close(client, session);
          } finally {
            await authentication.dispose();
          }
        },
      );
    } catch (_) {
      try {
        await wakeups.close();
        await client.disconnect();
      } finally {
        await authentication.dispose();
      }
      rethrow;
    }
  }

  Future<Session> _connect(Client client) {
    return client
        .connect(
          options: ClientConnectOptions(
            reconnectCount: 0,
            reconnectTime: const Duration(milliseconds: 100),
          ),
        )
        .first
        .timeout(connectionTimeout + derivationTimeout);
  }

  Future<void> _close(Client client, Session? session) async {
    if (session != null && session.isConnected()) {
      await session.close(timeout: Duration.zero);
    }
    await client.disconnect();
  }
}

final class _MailboxWakeupFeed {
  final StreamController<MailboxWakeup> _controller =
      StreamController<MailboxWakeup>.broadcast(sync: true);
  int _latestCursor = 0;
  Object? _latestError;
  bool _closed = false;

  Stream<MailboxWakeup> get stream => _controller.stream;
  int get latestCursor => _latestCursor;
  Object? get latestError => _latestError;

  void addEvent(EventPayload event) {
    if (_closed) return;
    try {
      final wakeup = MailboxWakeup.fromWampKeywords(event.argumentsKeywords);
      if (wakeup.cursor <= _latestCursor) return;
      _latestCursor = wakeup.cursor;
      _controller.add(wakeup);
    } catch (error, stackTrace) {
      _latestError = error;
      _controller.addError(error, stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}
