import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_chat_group.dart';
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
  StreamSubscription<MailboxWakeup>? _mailboxWakeupSubscription;
  int _pendingMailboxWakeupCursor = 0;
  bool _automaticSyncRunning = false;
  int _operationGeneration = 0;
  bool _disposed = false;

  WampAppStatus get status => _status;
  bool get isBusy => _status == WampAppStatus.busy;
  AccountConnection? get connection => _connection;
  DeviceRecord? get localDevice => _localDevice;
  String? get safetyNumber => _trustSession?.safetyNumber;
  List<LocalChatMessage> get messages => _messages;
  List<LocalChatGroup> get groups => _trustSession?.groups ?? const [];
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
    final wakeupSubscription = _mailboxWakeupSubscription;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _mailboxWakeupSubscription = null;
    _pendingMailboxWakeupCursor = 0;
    _automaticSyncRunning = false;
    _error = null;
    _messageError = null;
    _messages = const [];
    _messageBusy = false;
    _status = WampAppStatus.signedOut;
    if (!_disposed) notifyListeners();
    await _closeState(connection, trustSession, wakeupSubscription);
  }

  Future<void> _run(
    Future<AccountConnection> Function() action, {
    required String password,
  }) async {
    if (_disposed || isBusy || _messageBusy) return;
    final generation = ++_operationGeneration;
    _error = null;
    _messageError = null;
    _status = WampAppStatus.busy;
    notifyListeners();
    AccountConnection? next;
    DeviceTrustSession? nextTrust;
    DeviceRecord? nextDevice;
    List<LocalChatMessage>? nextMessages;
    StreamSubscription<MailboxWakeup>? nextWakeupSubscription;
    var nextPendingWakeupCursor = 0;
    Object? nextWakeupError;
    try {
      next = await action();
      nextPendingWakeupCursor = next.latestMailboxWakeupCursor;
      nextWakeupError = next.latestMailboxWakeupError;
      nextWakeupSubscription = next.mailboxWakeups.listen(
        (wakeup) {
          if (wakeup.cursor > nextPendingWakeupCursor) {
            nextPendingWakeupCursor = wakeup.cursor;
          }
          if (identical(next, _connection)) {
            _recordMailboxWakeup(wakeup);
          }
        },
        onError: (Object error) {
          nextWakeupError ??= error;
          if (identical(next, _connection)) {
            _recordMailboxWakeupError(error);
          }
        },
      );
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
        await _closeState(next, nextTrust, nextWakeupSubscription);
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
      await _closeState(next, nextTrust, nextWakeupSubscription);
      return;
    }

    final previous = _connection;
    final previousTrust = _trustSession;
    final previousWakeupSubscription = _mailboxWakeupSubscription;
    _connection = next;
    _trustSession = nextTrust;
    _localDevice = nextDevice;
    _mailboxWakeupSubscription = nextWakeupSubscription;
    _pendingMailboxWakeupCursor = nextPendingWakeupCursor;
    _automaticSyncRunning = false;
    _messages = List<LocalChatMessage>.unmodifiable(nextMessages);
    _messageError = nextWakeupError;
    _status = WampAppStatus.connected;
    notifyListeners();
    _startAutomaticSyncIfNeeded();
    try {
      await _closeState(previous, previousTrust, previousWakeupSubscription);
    } catch (_) {
      // The replacement connection remains valid even if stale cleanup fails.
    }
  }

  Future<void> sendMessage({
    required String recipientUsername,
    required String text,
    bool oneTime = false,
    Duration? expiresAfter,
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
    var synchronized = false;
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
      if (expiresAfter != null && expiresAfter <= Duration.zero) {
        throw const FormatException('Message expiry must be positive.');
      }
      final now = DateTime.now().toUtc();
      final message = _messageCipher.encrypt(
        senderUsername: connection.username,
        recipientUsername: recipientUsername,
        text: text,
        trust: trust,
        participantDevices: participants.values.toList(growable: false),
        now: now,
        expiresAt: expiresAfter == null ? null : now.add(expiresAfter),
        oneTime: oneTime,
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
      synchronized = true;
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
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<LocalChatGroup?> createGroup({
    required String title,
    required Iterable<String> memberUsernames,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    if (_disposed || _messageBusy || connection == null || trust == null) {
      return null;
    }
    final generation = _operationGeneration;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final members = <String>{
        connection.username,
        ...memberUsernames.map(AccountRegistration.normalizeUsername),
      }.toList(growable: false)..sort();
      if (members.length < 2) {
        throw const FormatException('A group needs at least two members.');
      }
      if (trust.groups.length >= LocalChatGroup.maxGroups) {
        throw const FormatException('The local group limit has been reached.');
      }
      for (final username in members) {
        final directory = username == connection.username
            ? await connection.listDevices()
            : await connection.lookupDevices(username);
        if (directory.devices.isEmpty) {
          throw FormatException('@$username has no active device.');
        }
      }
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return null;
      }
      final group = LocalChatGroup(
        conversationId: _messageCipher.newGroupConversationId(),
        title: title,
        memberUsernames: members,
        createdBy: connection.username,
        createdAt: DateTime.now().toUtc(),
      );
      await trust.saveMailboxState(
        cursor: trust.mailboxCursor,
        messages: trust.messages,
        groups: [...trust.groups, group],
      );
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return null;
      }
      return group;
    } catch (error) {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageError = error;
      }
      return null;
    } finally {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> sendGroupMessage({
    required String groupId,
    required String text,
    Duration? expiresAfter,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    final group = trust?.groups
        .where((candidate) => candidate.conversationId == groupId)
        .firstOrNull;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null ||
        group == null) {
      return;
    }
    final generation = _operationGeneration;
    var synchronized = false;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final participants = <String, DeviceRecord>{};
      for (final username in group.memberUsernames) {
        final directory = username == connection.username
            ? await connection.listDevices()
            : await connection.lookupDevices(username);
        if (directory.devices.isEmpty) {
          throw FormatException('@$username has no active device.');
        }
        for (final device in directory.devices) {
          participants['${device.username}\n${device.deviceId}'] = device;
        }
      }
      if (expiresAfter != null && expiresAfter <= Duration.zero) {
        throw const FormatException('Message expiry must be positive.');
      }
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return;
      }
      final now = DateTime.now().toUtc();
      final message = _messageCipher.encryptGroup(
        senderUsername: connection.username,
        group: group,
        text: text,
        trust: trust,
        participantDevices: participants.values.toList(growable: false),
        now: now,
        expiresAt: expiresAfter == null ? null : now.add(expiresAfter),
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
      synchronized = true;
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
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<void> markMessageRead(String messageId) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    final message = _messages
        .where((candidate) => candidate.messageId == messageId)
        .firstOrNull;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null ||
        message == null ||
        message.outgoing ||
        message.oneTime ||
        message.readAt != null) {
      return;
    }
    final generation = _operationGeneration;
    var synchronized = false;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      await connection.markMessageDelivered(messageId, read: true);
      final updated = await _synchronize(connection, trust, localDevice);
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return;
      }
      _messages = List<LocalChatMessage>.unmodifiable(updated);
      synchronized = true;
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
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<String?> consumeOneTimeMessage(String messageId) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    final message = _messages
        .where((candidate) => candidate.messageId == messageId)
        .firstOrNull;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null ||
        message == null ||
        message.outgoing ||
        !message.oneTime) {
      return null;
    }
    final generation = _operationGeneration;
    var synchronized = false;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final consumption = trust.signOneTimeConsumption(messageId);
      if (consumption.deviceId != localDevice.deviceId) {
        throw StateError('The local device identity changed unexpectedly.');
      }
      await connection.consumeOneTime(consumption);
      final updated = await _synchronize(connection, trust, localDevice);
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        return null;
      }
      _messages = List<LocalChatMessage>.unmodifiable(updated);
      synchronized = true;
      return message.text;
    } catch (error) {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageError = error;
      }
      return null;
    } finally {
      if (!_disposed &&
          generation == _operationGeneration &&
          connection == _connection) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized) _startAutomaticSyncIfNeeded();
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
    var synchronized = false;
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
      synchronized = true;
    } catch (error) {
      if (!_disposed && generation == _operationGeneration) {
        _messageError = error;
      }
    } finally {
      if (!_disposed && generation == _operationGeneration) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  void _recordMailboxWakeup(MailboxWakeup wakeup) {
    if (_disposed || wakeup.cursor <= 0) return;
    if (wakeup.cursor > _pendingMailboxWakeupCursor) {
      _pendingMailboxWakeupCursor = wakeup.cursor;
    }
    _startAutomaticSyncIfNeeded();
  }

  void _recordMailboxWakeupError(Object error) {
    if (_disposed || _connection == null) return;
    _messageError = error;
    notifyListeners();
  }

  void _startAutomaticSyncIfNeeded() {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    if (_disposed ||
        _automaticSyncRunning ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null ||
        trust.mailboxCursor >= _pendingMailboxWakeupCursor) {
      return;
    }
    final generation = _operationGeneration;
    _automaticSyncRunning = true;
    unawaited(_drainAutomaticSync(connection, trust, localDevice, generation));
  }

  Future<void> _drainAutomaticSync(
    AccountConnection connection,
    DeviceTrustSession trust,
    DeviceRecord localDevice,
    int generation,
  ) async {
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      while (!_disposed &&
          generation == _operationGeneration &&
          identical(connection, _connection) &&
          identical(trust, _trustSession) &&
          trust.mailboxCursor < _pendingMailboxWakeupCursor) {
        final targetCursor = _pendingMailboxWakeupCursor;
        final updated = await _synchronize(connection, trust, localDevice);
        if (_disposed ||
            generation != _operationGeneration ||
            !identical(connection, _connection) ||
            !identical(trust, _trustSession)) {
          return;
        }
        _messages = List<LocalChatMessage>.unmodifiable(updated);
        if (trust.mailboxCursor < targetCursor) {
          throw const FormatException(
            'Mailbox synchronization did not reach its wakeup cursor.',
          );
        }
      }
    } catch (error) {
      if (!_disposed &&
          generation == _operationGeneration &&
          identical(connection, _connection)) {
        _messageError = error;
      }
    } finally {
      if (!_disposed &&
          generation == _operationGeneration &&
          identical(connection, _connection)) {
        _messageBusy = false;
        _automaticSyncRunning = false;
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
    final groupsById = <String, LocalChatGroup>{
      for (final group in trust.groups) group.conversationId: group,
    };
    for (var page = 0; page < 20; page += 1) {
      final batch = await connection.syncMessages(afterCursor: cursor);
      if (batch.nextCursor < cursor) {
        throw const FormatException('Mailbox cursor moved backwards.');
      }
      for (final stored in batch.messages) {
        final encrypted = stored.message;
        final recipientState = stored.recipientStateFor(connection.username);
        if (!encrypted.isGroup &&
            encrypted.oneTime &&
            encrypted.recipientUsername == connection.username &&
            recipientState?.consumedAt != null) {
          byId.remove(encrypted.messageId);
          continue;
        }
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
        if (encrypted.isGroup != local.isGroup) {
          throw const FormatException('Local conversation metadata conflicts.');
        }
        if (local.group case final group?) {
          final known = groupsById[group.conversationId];
          if (known != null && !known.hasSameDefinition(group)) {
            throw const FormatException('Group metadata conflicts.');
          }
          groupsById[group.conversationId] = group;
        }
        byId[encrypted.messageId] = local.withReceipts(
          deliveredAt: stored.deliveredAtFor(connection.username),
          readAt: stored.readAtFor(connection.username),
        );
        if (encrypted.recipientUsernames.contains(connection.username) &&
            recipientState?.deliveredAt == null) {
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
    final groups = groupsById.values.toList(growable: false)
      ..sort((left, right) {
        final created = left.createdAt.compareTo(right.createdAt);
        return created != 0
            ? created
            : left.conversationId.compareTo(right.conversationId);
      });
    await trust.saveMailboxState(
      cursor: cursor,
      messages: updated,
      groups: groups,
    );
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration += 1;
    final connection = _connection;
    final trustSession = _trustSession;
    final wakeupSubscription = _mailboxWakeupSubscription;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _mailboxWakeupSubscription = null;
    _pendingMailboxWakeupCursor = 0;
    _automaticSyncRunning = false;
    unawaited(
      _closeState(
        connection,
        trustSession,
        wakeupSubscription,
      ).catchError((_) {}),
    );
    super.dispose();
  }
}

Future<void> _closeState(
  AccountConnection? connection,
  DeviceTrustSession? trustSession, [
  StreamSubscription<MailboxWakeup>? wakeupSubscription,
]) async {
  Object? failure;
  StackTrace? failureStack;
  try {
    await wakeupSubscription?.cancel();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
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
