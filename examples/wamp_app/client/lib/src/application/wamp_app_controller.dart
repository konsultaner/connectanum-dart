import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_chat_message.dart';
import '../infrastructure/device_vault.dart';
import '../infrastructure/message_cipher.dart';
import '../infrastructure/wamp_account_gateway.dart';

enum WampAppStatus { signedOut, busy, connected, failed }

class WampAppController extends ChangeNotifier {
  WampAppController({
    AccountGateway? gateway,
    DeviceTrustStore? trustStore,
    MessageCipher? messageCipher,
    this.deviceName = 'This device',
  }) : _gateway = gateway ?? const WampAccountGateway(),
       _trustStore = trustStore ?? EncryptedDeviceVault(),
       _messageCipher = messageCipher ?? MessageCipher();

  final AccountGateway _gateway;
  final DeviceTrustStore _trustStore;
  final MessageCipher _messageCipher;
  final String deviceName;
  WampAppStatus _status = WampAppStatus.signedOut;
  AccountConnection? _connection;
  DeviceTrustSession? _trustSession;
  DeviceRecord? _localDevice;
  Object? _error;
  Object? _messageError;
  List<LocalChatMessage> _messages = const [];
  bool _messageBusy = false;
  int _operationGeneration = 0;
  bool _disposed = false;

  WampAppStatus get status => _status;
  bool get isBusy => _status == WampAppStatus.busy;
  AccountConnection? get connection => _connection;
  DeviceRecord? get localDevice => _localDevice;
  String? get safetyNumber => _trustSession?.safetyNumber;
  List<LocalChatMessage> get messages => _messages;
  bool get messageBusy => _messageBusy;
  String? get messageError => switch (_messageError) {
    FormatException(:final message) => message,
    _ when _messageError != null => 'The encrypted message operation failed.',
    _ => null,
  };
  String? get errorMessage => switch (_error) {
    FormatException(:final message) => message,
    VaultUnlockException() => 'Could not unlock encrypted device storage.',
    _ when _error != null =>
      'Could not connect. Check the address and credentials.',
    _ => null,
  };

  Future<void> registerAndConnect({
    required String serverAddress,
    required String username,
    required String displayName,
    required String password,
  }) async {
    await _run(password: password, () async {
      final endpoint = ServerEndpoint.parse(serverAddress);
      endpoint.requireSecureRegistration();
      final registration = AccountRegistration(
        username: username,
        password: password,
        displayName: displayName,
      );
      registration.validate();
      await _gateway.register(endpoint: endpoint, registration: registration);
      return _gateway.login(
        endpoint: endpoint,
        username: registration.username,
        password: password,
      );
    });
  }

  Future<void> login({
    required String serverAddress,
    required String username,
    required String password,
  }) async {
    await _run(password: password, () {
      final endpoint = ServerEndpoint.parse(serverAddress);
      endpoint.requireSecureRegistration();
      return _gateway.login(
        endpoint: endpoint,
        username: username,
        password: password,
      );
    });
  }

  Future<void> signOut() async {
    _operationGeneration += 1;
    final connection = _connection;
    final trustSession = _trustSession;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _error = null;
    _messageError = null;
    _messages = const [];
    _messageBusy = false;
    _status = WampAppStatus.signedOut;
    if (!_disposed) notifyListeners();
    await _closeState(connection, trustSession);
  }

  Future<void> _run(
    Future<AccountConnection> Function() action, {
    required String password,
  }) async {
    if (_disposed || isBusy) return;
    final generation = ++_operationGeneration;
    _error = null;
    _messageError = null;
    _status = WampAppStatus.busy;
    notifyListeners();
    AccountConnection? next;
    DeviceTrustSession? nextTrust;
    DeviceRecord? nextDevice;
    List<LocalChatMessage>? nextMessages;
    try {
      next = await action();
      nextTrust = await _trustStore.openOrCreate(
        endpoint: next.endpoint,
        username: next.username,
        password: password,
        deviceName: deviceName,
      );
      nextDevice = await next.enrollDevice(nextTrust.enrollment);
      if (nextDevice.isRevoked ||
          nextDevice.username != next.username ||
          nextDevice.deviceId != nextTrust.deviceId) {
        throw const FormatException(
          'The server returned an invalid local device record.',
        );
      }
      nextMessages = await _synchronize(next, nextTrust, nextDevice);
    } catch (error) {
      try {
        await _closeState(next, nextTrust);
      } catch (_) {
        // Preserve the connection or trust failure that triggered cleanup.
      }
      if (generation != _operationGeneration || _disposed) return;
      _error = error;
      _status = _connection != null && _trustSession != null
          ? WampAppStatus.connected
          : WampAppStatus.failed;
      notifyListeners();
      return;
    }

    if (generation != _operationGeneration || _disposed) {
      await _closeState(next, nextTrust);
      return;
    }

    final previous = _connection;
    final previousTrust = _trustSession;
    _connection = next;
    _trustSession = nextTrust;
    _localDevice = nextDevice;
    _messages = List<LocalChatMessage>.unmodifiable(nextMessages);
    _status = WampAppStatus.connected;
    notifyListeners();
    try {
      await _closeState(previous, previousTrust);
    } catch (_) {
      // The replacement connection remains valid even if stale cleanup fails.
    }
  }

  Future<void> sendMessage({
    required String recipientUsername,
    required String text,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null) {
      return;
    }
    final generation = _operationGeneration;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final ownDevices = await connection.listDevices();
      final recipientDevices = await connection.lookupDevices(
        recipientUsername,
      );
      final participants = <String, DeviceRecord>{
        for (final device in [
          ...ownDevices.devices,
          ...recipientDevices.devices,
        ])
          '${device.username}\n${device.deviceId}': device,
      };
      final message = _messageCipher.encrypt(
        senderUsername: connection.username,
        recipientUsername: recipientUsername,
        text: text,
        trust: trust,
        participantDevices: participants.values.toList(growable: false),
      );
      await connection.sendMessage(message);
      final updated = await _synchronize(connection, trust, localDevice);
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return;
      }
      _messages = List<LocalChatMessage>.unmodifiable(updated);
    } catch (error) {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageError = error;
      }
    } finally {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshMessages() async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null) {
      return;
    }
    final generation = _operationGeneration;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final updated = await _synchronize(connection, trust, localDevice);
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return;
      }
      _messages = List<LocalChatMessage>.unmodifiable(updated);
    } catch (error) {
      if (!_disposed && generation == _operationGeneration) {
        _messageError = error;
      }
    } finally {
      if (!_disposed && generation == _operationGeneration) {
        _messageBusy = false;
        notifyListeners();
      }
    }
  }

  Future<List<LocalChatMessage>> _synchronize(
    AccountConnection connection,
    DeviceTrustSession trust,
    DeviceRecord localDevice,
  ) async {
    var cursor = trust.mailboxCursor;
    final byId = <String, LocalChatMessage>{
      for (final message in trust.messages) message.messageId: message,
    };
    for (var page = 0; page < 20; page += 1) {
      final batch = await connection.syncMessages(afterCursor: cursor);
      if (batch.nextCursor < cursor) {
        throw const FormatException('Mailbox cursor moved backwards.');
      }
      for (final stored in batch.messages) {
        final encrypted = stored.message;
        var local = byId[encrypted.messageId];
        if (local == null) {
          final sender = encrypted.senderDeviceId == localDevice.deviceId
              ? localDevice
              : (await connection.lookupDevices(
                      encrypted.senderUsername,
                      includeRevoked: true,
                    )).devices
                    .where(
                      (device) => device.deviceId == encrypted.senderDeviceId,
                    )
                    .firstOrNull;
          if (sender == null) {
            throw const FormatException('Message sender device was not found.');
          }
          local = _messageCipher.decrypt(
            message: encrypted,
            username: connection.username,
            trust: trust,
            sender: sender,
          );
        }
        byId[encrypted.messageId] = local.withReceipts(
          deliveredAt: stored.deliveredAt,
          readAt: stored.readAt,
        );
        if (encrypted.recipientUsername == connection.username &&
            stored.deliveredAt == null) {
          await connection.markMessageDelivered(encrypted.messageId);
        }
      }
      final previous = cursor;
      cursor = batch.nextCursor;
      if (cursor == previous || batch.messages.length < 100) break;
      if (page == 19) {
        throw const FormatException(
          'Mailbox synchronization exceeded its limit.',
        );
      }
    }
    final now = DateTime.now().toUtc();
    final updated =
        byId.values
            .where((message) => !message.isExpiredAt(now))
            .toList(growable: false)
          ..sort((left, right) {
            final sent = left.sentAt.compareTo(right.sentAt);
            return sent != 0 ? sent : left.messageId.compareTo(right.messageId);
          });
    await trust.saveMailboxState(cursor: cursor, messages: updated);
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration += 1;
    final connection = _connection;
    final trustSession = _trustSession;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    unawaited(_closeState(connection, trustSession).catchError((_) {}));
    super.dispose();
  }
}

Future<void> _closeState(
  AccountConnection? connection,
  DeviceTrustSession? trustSession,
) async {
  Object? failure;
  StackTrace? failureStack;
  try {
    await connection?.close();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    await trustSession?.dispose();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
}
