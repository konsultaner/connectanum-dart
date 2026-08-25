import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_app_preferences.dart';
import '../domain/local_chat_group.dart';
import '../domain/local_chat_message.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/attachment_chunk_cache.dart';
import '../infrastructure/attachment_cipher.dart';
import '../infrastructure/device_vault.dart';
import '../infrastructure/message_cipher.dart';
import '../infrastructure/wamp_account_gateway.dart';

enum WampAppStatus { signedOut, busy, connected, failed }

class WampAppController extends ChangeNotifier {
  WampAppController({
    AccountGateway? gateway,
    DeviceTrustStore? trustStore,
    MessageCipher? messageCipher,
    AttachmentChunkCache? attachmentCache,
    AttachmentCipher? attachmentCipher,
    this.deviceName = 'This device',
  }) : _gateway = gateway ?? const WampAccountGateway(),
       _trustStore = trustStore ?? EncryptedDeviceVault(),
       _messageCipher = messageCipher ?? MessageCipher(),
       _attachmentCache = attachmentCache ?? createAttachmentChunkCache(),
       _attachmentCipher = attachmentCipher ?? AttachmentCipher();

  final AccountGateway _gateway;
  final DeviceTrustStore _trustStore;
  final MessageCipher _messageCipher;
  final AttachmentChunkCache _attachmentCache;
  final AttachmentCipher _attachmentCipher;
  final String deviceName;
  WampAppStatus _status = WampAppStatus.signedOut;
  AccountConnection? _connection;
  DeviceTrustSession? _trustSession;
  DeviceRecord? _localDevice;
  Object? _error;
  Object? _messageError;
  Object? _profileError;
  Object? _preferenceError;
  List<LocalChatMessage> _messages = const [];
  bool _messageBusy = false;
  bool _profileBusy = false;
  bool _preferenceBusy = false;
  LocalAppPreferences _preferences = LocalAppPreferences.defaults;
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
  OutboundChatMessage? outboundMessageFor(String messageId) => _trustSession
      ?.outbox
      .where((message) => message.envelope.messageId == messageId)
      .firstOrNull;
  bool get messageBusy => _messageBusy;
  bool get profileBusy => _profileBusy;
  bool get preferenceBusy => _preferenceBusy;
  WampAppThemePreference get themePreference => _preferences.theme;
  String? get preferenceError => switch (_preferenceError) {
    FormatException(:final message) => message,
    _ when _preferenceError != null => 'Could not save local preferences.',
    _ => null,
  };
  String? get profileError => switch (_profileError) {
    FormatException(:final message) => message,
    ProfileUpdateException() => _profileError.toString(),
    _ when _profileError != null => 'The profile operation failed.',
    _ => null,
  };
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

  String? directConversationIdFor(String recipientUsername) {
    final username = _connection?.username;
    if (username == null) return null;
    try {
      return MessageCipher.directConversationId(username, recipientUsername);
    } on FormatException {
      return null;
    }
  }

  bool isConversationMuted(String conversationId) =>
      _preferences.isMuted(conversationId);

  bool shouldPresentNotificationFor(LocalChatMessage message) =>
      _connection != null &&
      !message.outgoing &&
      !_preferences.isMuted(message.conversationId);

  Future<bool> setThemePreference(WampAppThemePreference theme) {
    if (_preferences.theme == theme) return Future<bool>.value(true);
    return _savePreferences(_preferences.withTheme(theme));
  }

  Future<bool> setConversationMuted(String conversationId, bool muted) {
    if (_preferences.isMuted(conversationId) == muted) {
      return Future<bool>.value(true);
    }
    try {
      return _savePreferences(
        _preferences.withConversationMuted(conversationId, muted),
      );
    } on FormatException catch (error) {
      _preferenceError = error;
      if (!_disposed) notifyListeners();
      return Future<bool>.value(false);
    }
  }

  Future<bool> _savePreferences(LocalAppPreferences preferences) async {
    final trust = _trustSession;
    if (_disposed || _preferenceBusy || trust == null) return false;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(trust, _trustSession);
    _preferenceBusy = true;
    _preferenceError = null;
    notifyListeners();
    try {
      await trust.savePreferences(preferences);
      if (!isCurrent()) return false;
      _preferences = preferences;
      return true;
    } catch (error) {
      if (isCurrent()) _preferenceError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _preferenceBusy = false;
        notifyListeners();
      }
    }
  }

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
    _profileError = null;
    _preferenceError = null;
    _messages = const [];
    _messageBusy = false;
    _profileBusy = false;
    _preferenceBusy = false;
    _preferences = LocalAppPreferences.defaults;
    _status = WampAppStatus.signedOut;
    if (!_disposed) notifyListeners();
    await _closeState(connection, trustSession, wakeupSubscription);
  }

  Future<bool> updateProfile(AccountProfileUpdate update) async {
    final connection = _connection;
    if (_disposed || _profileBusy || connection == null) return false;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection);
    _profileBusy = true;
    _profileError = null;
    notifyListeners();
    try {
      await connection.updateProfile(update);
      return isCurrent();
    } catch (error) {
      if (error case ProfileUpdateException(
        kind: ProfileUpdateFailureKind.conflict,
      )) {
        try {
          await connection.refreshProfile();
        } catch (_) {
          // Keep the original conflict as the actionable UI result.
        }
      }
      if (isCurrent()) _profileError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _profileBusy = false;
        notifyListeners();
      }
    }
  }

  Future<AccountProfile?> lookupProfile(String username) async {
    final connection = _connection;
    if (_disposed || _profileBusy || connection == null) return null;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection);
    _profileBusy = true;
    _profileError = null;
    notifyListeners();
    try {
      final profile = await connection.getProfile(username);
      return isCurrent() ? profile : null;
    } catch (error) {
      if (isCurrent()) _profileError = error;
      return null;
    } finally {
      if (isCurrent()) {
        _profileBusy = false;
        notifyListeners();
      }
    }
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
      bool pendingConnectionIsCurrent() =>
          !_disposed && generation == _operationGeneration;
      nextMessages = await _synchronize(next, nextTrust, nextDevice);
      var acceptedRecoveredMessage = false;
      final recoverable = nextTrust.outbox
          .where(
            (message) =>
                message.state == OutboundMessageState.queued ||
                message.state == OutboundMessageState.retryable,
          )
          .map((message) => message.envelope.messageId)
          .toList(growable: false);
      for (final messageId in recoverable) {
        if (!pendingConnectionIsCurrent()) break;
        acceptedRecoveredMessage =
            await _attemptOutboxMessage(
              connection: next,
              trust: nextTrust,
              messageId: messageId,
              isCurrent: pendingConnectionIsCurrent,
            ) ||
            acceptedRecoveredMessage;
      }
      if (acceptedRecoveredMessage && pendingConnectionIsCurrent()) {
        nextMessages = await _synchronize(next, nextTrust, nextDevice);
      } else {
        nextMessages = _visibleMessages(nextTrust);
      }
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
    _preferences = nextTrust.preferences;
    _localDevice = nextDevice;
    _mailboxWakeupSubscription = nextWakeupSubscription;
    _pendingMailboxWakeupCursor = nextPendingWakeupCursor;
    _automaticSyncRunning = false;
    _messages = List<LocalChatMessage>.unmodifiable(nextMessages);
    _messageError = nextWakeupError;
    _preferenceError = null;
    _preferenceBusy = false;
    _status = WampAppStatus.connected;
    notifyListeners();
    _startAutomaticSyncIfNeeded();
    try {
      await _closeState(previous, previousTrust, previousWakeupSubscription);
    } catch (_) {
      // The replacement connection remains valid even if stale cleanup fails.
    }
  }

  Future<bool> sendMessage({
    required String recipientUsername,
    required String text,
    bool oneTime = false,
    Duration? expiresAfter,
    List<AttachmentPlaintextSource> attachmentSources = const [],
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    var enqueued = false;
    var synchronized = false;
    String? stagedAttachmentMessageId;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      if (expiresAfter != null && expiresAfter <= Duration.zero) {
        throw const FormatException('Message expiry must be positive.');
      }
      if (oneTime && attachmentSources.isNotEmpty) {
        throw const FormatException(
          'View-once attachments are not supported yet.',
        );
      }
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
      if (!isCurrent()) return false;
      final now = DateTime.now().toUtc();
      final messageId = _messageCipher.newMessageId();
      final attachments = attachmentSources.isEmpty
          ? const <EncryptedAttachmentDescriptor>[]
          : await _attachmentCipher.encryptSources(
              scope: attachmentCacheScope(
                connection.endpoint,
                connection.username,
              ),
              senderUsername: connection.username,
              messageId: messageId,
              sources: attachmentSources,
              cache: _attachmentCache,
              isCancelled: () => !isCurrent(),
            );
      if (attachments.isNotEmpty) stagedAttachmentMessageId = messageId;
      if (!isCurrent()) {
        if (stagedAttachmentMessageId != null) {
          await _attachmentCache.removeMessage(
            scope: attachmentCacheScope(
              connection.endpoint,
              connection.username,
            ),
            messageId: stagedAttachmentMessageId,
          );
        }
        return false;
      }
      final envelope = _messageCipher.encrypt(
        senderUsername: connection.username,
        recipientUsername: recipientUsername,
        text: text,
        trust: trust,
        participantDevices: participants.values.toList(growable: false),
        now: now,
        expiresAt: expiresAfter == null ? null : now.add(expiresAfter),
        oneTime: oneTime,
        messageId: messageId,
        attachments: attachments,
      );
      final pending = OutboundChatMessage(
        envelope: envelope,
        localMessage: LocalChatMessage(
          messageId: envelope.messageId,
          conversationId: envelope.conversationId,
          peerUsername: envelope.recipientUsername!,
          text: text,
          sentAt: envelope.createdAt,
          outgoing: true,
          oneTime: envelope.oneTime,
          expiresAt: envelope.expiresAt,
          attachments: attachments,
        ),
        state: OutboundMessageState.queued,
        attemptCount: 0,
      );
      await _appendOutboxMessage(trust, pending);
      enqueued = true;
      if (!isCurrent()) return true;
      _messages = List<LocalChatMessage>.unmodifiable(_visibleMessages(trust));
      notifyListeners();

      final accepted = await _attemptOutboxMessage(
        connection: connection,
        trust: trust,
        messageId: envelope.messageId,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return true;
      if (accepted) {
        final updated = await _synchronize(connection, trust, localDevice);
        if (!isCurrent()) return true;
        _messages = List<LocalChatMessage>.unmodifiable(updated);
        synchronized = true;
      } else {
        _messages = List<LocalChatMessage>.unmodifiable(
          _visibleMessages(trust),
        );
      }
      return true;
    } catch (error) {
      if (!enqueued && stagedAttachmentMessageId != null) {
        try {
          await _attachmentCache.removeMessage(
            scope: attachmentCacheScope(
              connection.endpoint,
              connection.username,
            ),
            messageId: stagedAttachmentMessageId,
          );
        } catch (_) {
          // Preserve the staging or encryption failure for the UI.
        }
      }
      if (isCurrent()) _messageError = error;
      return enqueued;
    } finally {
      if (isCurrent()) {
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

  Future<bool> sendGroupMessage({
    required String groupId,
    required String text,
    Duration? expiresAfter,
    List<AttachmentPlaintextSource> attachmentSources = const [],
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
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    var enqueued = false;
    var synchronized = false;
    String? stagedAttachmentMessageId;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      if (expiresAfter != null && expiresAfter <= Duration.zero) {
        throw const FormatException('Message expiry must be positive.');
      }
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
      if (!isCurrent()) return false;
      final now = DateTime.now().toUtc();
      final messageId = _messageCipher.newMessageId();
      final attachments = attachmentSources.isEmpty
          ? const <EncryptedAttachmentDescriptor>[]
          : await _attachmentCipher.encryptSources(
              scope: attachmentCacheScope(
                connection.endpoint,
                connection.username,
              ),
              senderUsername: connection.username,
              messageId: messageId,
              sources: attachmentSources,
              cache: _attachmentCache,
              isCancelled: () => !isCurrent(),
            );
      if (attachments.isNotEmpty) stagedAttachmentMessageId = messageId;
      if (!isCurrent()) {
        if (stagedAttachmentMessageId != null) {
          await _attachmentCache.removeMessage(
            scope: attachmentCacheScope(
              connection.endpoint,
              connection.username,
            ),
            messageId: stagedAttachmentMessageId,
          );
        }
        return false;
      }
      final envelope = _messageCipher.encryptGroup(
        senderUsername: connection.username,
        group: group,
        text: text,
        trust: trust,
        participantDevices: participants.values.toList(growable: false),
        now: now,
        expiresAt: expiresAfter == null ? null : now.add(expiresAfter),
        messageId: messageId,
        attachments: attachments,
      );
      final pending = OutboundChatMessage(
        envelope: envelope,
        localMessage: LocalChatMessage(
          messageId: envelope.messageId,
          conversationId: envelope.conversationId,
          peerUsername: envelope.senderUsername,
          text: text,
          sentAt: envelope.createdAt,
          outgoing: true,
          expiresAt: envelope.expiresAt,
          groupTitle: group.title,
          participantUsernames: group.memberUsernames,
          groupCreatedBy: group.createdBy,
          groupCreatedAt: group.createdAt,
          attachments: attachments,
        ),
        state: OutboundMessageState.queued,
        attemptCount: 0,
      );
      await _appendOutboxMessage(trust, pending);
      enqueued = true;
      if (!isCurrent()) return true;
      _messages = List<LocalChatMessage>.unmodifiable(_visibleMessages(trust));
      notifyListeners();

      final accepted = await _attemptOutboxMessage(
        connection: connection,
        trust: trust,
        messageId: envelope.messageId,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return true;
      if (accepted) {
        final updated = await _synchronize(connection, trust, localDevice);
        if (!isCurrent()) return true;
        _messages = List<LocalChatMessage>.unmodifiable(updated);
        synchronized = true;
      } else {
        _messages = List<LocalChatMessage>.unmodifiable(
          _visibleMessages(trust),
        );
      }
      return true;
    } catch (error) {
      if (!enqueued && stagedAttachmentMessageId != null) {
        try {
          await _attachmentCache.removeMessage(
            scope: attachmentCacheScope(
              connection.endpoint,
              connection.username,
            ),
            messageId: stagedAttachmentMessageId,
          );
        } catch (_) {
          // Preserve the staging or encryption failure for the UI.
        }
      }
      if (isCurrent()) _messageError = error;
      return enqueued;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<bool> retryMessage(String messageId) async {
    final connection = _connection;
    final trust = _trustSession;
    final localDevice = _localDevice;
    final pending = outboundMessageFor(messageId);
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        localDevice == null ||
        pending == null ||
        !pending.canRetry) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    var synchronized = false;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final accepted = await _attemptOutboxMessage(
        connection: connection,
        trust: trust,
        messageId: messageId,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return true;
      if (accepted) {
        final updated = await _synchronize(connection, trust, localDevice);
        if (!isCurrent()) return true;
        _messages = List<LocalChatMessage>.unmodifiable(updated);
        synchronized = true;
      } else {
        _messages = List<LocalChatMessage>.unmodifiable(
          _visibleMessages(trust),
        );
      }
      return true;
    } catch (error) {
      if (isCurrent()) _messageError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized) _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<Uint8List?> loadAttachment({
    required String messageId,
    required String attachmentId,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    final message = _messages
        .where((candidate) => candidate.messageId == messageId)
        .firstOrNull;
    final attachment = message?.attachments
        .where((candidate) => candidate.attachmentId == attachmentId)
        .firstOrNull;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        message == null ||
        attachment == null) {
      return null;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final senderUsername = message.outgoing
          ? connection.username
          : message.peerUsername;
      final opened = await _attachmentCipher.decryptToBytes(
        scope: attachmentCacheScope(connection.endpoint, connection.username),
        senderUsername: senderUsername,
        messageId: message.messageId,
        attachment: attachment,
        cache: _attachmentCache,
        fetchChunk: (chunkIndex) => connection.getAttachmentChunk(
          messageId: message.messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: chunkIndex,
        ),
        isCancelled: () => !isCurrent(),
      );
      if (!isCurrent()) {
        opened.fillRange(0, opened.length, 0);
        return null;
      }
      return opened;
    } catch (error) {
      if (isCurrent()) _messageError = error;
      return null;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> discardOutboundMessage(String messageId) async {
    final connection = _connection;
    final trust = _trustSession;
    final pending = outboundMessageFor(messageId);
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        pending == null ||
        !pending.canDiscard) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      await _removeOutboxMessage(trust, messageId);
      if (pending.localMessage.attachments.isNotEmpty) {
        await _attachmentCache.removeMessage(
          scope: attachmentCacheScope(connection.endpoint, connection.username),
          messageId: messageId,
        );
      }
      if (!isCurrent()) return true;
      _messages = List<LocalChatMessage>.unmodifiable(_visibleMessages(trust));
      return true;
    } catch (error) {
      if (isCurrent()) _messageError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
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

  Future<void> _appendOutboxMessage(
    DeviceTrustSession trust,
    OutboundChatMessage message,
  ) {
    if (trust.outbox.any(
      (existing) => existing.envelope.messageId == message.envelope.messageId,
    )) {
      throw const FormatException('The outbound message already exists.');
    }
    return trust.saveMailboxState(
      cursor: trust.mailboxCursor,
      messages: trust.messages,
      outbox: [...trust.outbox, message],
    );
  }

  Future<void> _replaceOutboxMessage(
    DeviceTrustSession trust,
    OutboundChatMessage replacement,
  ) {
    final index = trust.outbox.indexWhere(
      (message) => message.envelope.messageId == replacement.envelope.messageId,
    );
    if (index < 0) {
      throw StateError('The outbound message is no longer available.');
    }
    final updated = List<OutboundChatMessage>.of(trust.outbox);
    updated[index] = replacement;
    return trust.saveMailboxState(
      cursor: trust.mailboxCursor,
      messages: trust.messages,
      outbox: updated,
    );
  }

  Future<void> _removeOutboxMessage(
    DeviceTrustSession trust,
    String messageId,
  ) {
    final updated = trust.outbox
        .where((message) => message.envelope.messageId != messageId)
        .toList(growable: false);
    if (updated.length == trust.outbox.length) {
      throw StateError('The outbound message is no longer available.');
    }
    return trust.saveMailboxState(
      cursor: trust.mailboxCursor,
      messages: trust.messages,
      outbox: updated,
    );
  }

  Future<bool> _attemptOutboxMessage({
    required AccountConnection connection,
    required DeviceTrustSession trust,
    required String messageId,
    required bool Function() isCurrent,
  }) async {
    final pending = trust.outbox
        .where((message) => message.envelope.messageId == messageId)
        .firstOrNull;
    if (pending == null ||
        (pending.state != OutboundMessageState.queued &&
            pending.state != OutboundMessageState.retryable)) {
      return false;
    }
    if (pending.attemptCount >= OutboundChatMessage.maxAttemptCount) {
      await _replaceOutboxMessage(
        trust,
        pending.withFailure(OutboundMessageState.rejected),
      );
      return false;
    }
    final attempted = pending.withAttempt(DateTime.now().toUtc());
    await _replaceOutboxMessage(trust, attempted);
    if (!isCurrent()) return false;

    MessageSendReceipt receipt;
    try {
      await _uploadAttachments(
        connection: connection,
        pending: attempted,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return false;
      receipt = await connection.sendMessage(attempted.envelope);
    } catch (error) {
      if (!isCurrent()) return false;
      await _replaceOutboxMessage(
        trust,
        attempted.withFailure(_outboundFailureState(error)),
      );
      return false;
    }
    if (!isCurrent()) return false;
    await _replaceOutboxMessage(trust, attempted.withAccepted(receipt));
    return true;
  }

  Future<void> _uploadAttachments({
    required AccountConnection connection,
    required OutboundChatMessage pending,
    required bool Function() isCurrent,
  }) async {
    if (pending.localMessage.attachments.isEmpty) return;
    final scope = attachmentCacheScope(
      connection.endpoint,
      connection.username,
    );
    for (final attachment in pending.localMessage.attachments) {
      if (!isCurrent()) throw const AttachmentTransferCancelled();
      final status = await connection.attachmentUploadStatus(
        messageId: pending.envelope.messageId,
        attachmentId: attachment.attachmentId,
        chunkCount: attachment.chunkCount,
      );
      if (status.messageId != pending.envelope.messageId ||
          status.attachmentId != attachment.attachmentId ||
          status.chunkCount != attachment.chunkCount) {
        throw const FormatException('Attachment upload status conflicts.');
      }
      final received = status.receivedChunks.toSet();
      for (
        var chunkIndex = 0;
        chunkIndex < attachment.chunkCount;
        chunkIndex++
      ) {
        if (received.contains(chunkIndex)) continue;
        if (!isCurrent()) throw const AttachmentTransferCancelled();
        final chunk = await _attachmentCache.get(
          scope: scope,
          senderUsername: connection.username,
          messageId: pending.envelope.messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: chunkIndex,
          chunkCount: attachment.chunkCount,
        );
        if (chunk == null) throw const AttachmentCacheMiss();
        final receipt = await connection.putAttachmentChunk(chunk);
        received.add(chunkIndex);
        if (receipt.messageId != pending.envelope.messageId ||
            receipt.attachmentId != attachment.attachmentId ||
            receipt.chunkIndex != chunkIndex ||
            receipt.ciphertextSha256 != chunk.ciphertextSha256 ||
            receipt.complete != (received.length == attachment.chunkCount)) {
          throw const FormatException('Attachment upload receipt conflicts.');
        }
      }
      if (received.length != attachment.chunkCount) {
        throw const FormatException('Attachment upload did not complete.');
      }
    }
  }

  OutboundMessageState _outboundFailureState(Object error) {
    if (error case MessageSendException(:final kind)) {
      return switch (kind) {
        MessageSendFailureKind.retryable => OutboundMessageState.retryable,
        MessageSendFailureKind.rejected => OutboundMessageState.rejected,
        MessageSendFailureKind.conflict => OutboundMessageState.conflict,
      };
    }
    if (error is AttachmentCacheConflict) {
      return OutboundMessageState.conflict;
    }
    if (error is AttachmentCacheMiss) {
      return OutboundMessageState.rejected;
    }
    if (error case AttachmentTransferException(:final kind)) {
      return switch (kind) {
        AttachmentTransferFailureKind.conflict => OutboundMessageState.conflict,
        AttachmentTransferFailureKind.rejected ||
        AttachmentTransferFailureKind.quotaExceeded =>
          OutboundMessageState.rejected,
        AttachmentTransferFailureKind.retryable ||
        AttachmentTransferFailureKind.notFound ||
        AttachmentTransferFailureKind.incomplete =>
          OutboundMessageState.retryable,
      };
    }
    return OutboundMessageState.retryable;
  }

  List<LocalChatMessage> _visibleMessages(DeviceTrustSession trust) {
    final now = DateTime.now().toUtc();
    final byId = <String, LocalChatMessage>{
      for (final message in trust.messages)
        if (!message.isExpiredAt(now)) message.messageId: message,
    };
    for (final pending in trust.outbox) {
      final message = pending.localMessage;
      if (!message.isExpiredAt(now)) {
        byId.putIfAbsent(message.messageId, () => message);
      }
    }
    final visible = byId.values.toList(growable: false)
      ..sort((left, right) {
        final sent = left.sentAt.compareTo(right.sentAt);
        return sent != 0 ? sent : left.messageId.compareTo(right.messageId);
      });
    return visible;
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
    final outboxById = <String, OutboundChatMessage>{
      for (final message in trust.outbox) message.envelope.messageId: message,
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
          outboxById.remove(encrypted.messageId);
          continue;
        }

        final pending = outboxById[encrypted.messageId];
        if (pending != null && !pending.matchesEnvelope(encrypted)) {
          outboxById[encrypted.messageId] = pending.withFailure(
            OutboundMessageState.conflict,
          );
          continue;
        }

        var local = pending?.localMessage ?? byId[encrypted.messageId];
        if (pending != null) outboxById.remove(encrypted.messageId);
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
    final remainingOutbox =
        outboxById.values
            .where((message) => !message.localMessage.isExpiredAt(now))
            .where(
              (message) =>
                  message.state != OutboundMessageState.accepted ||
                  message.acceptedCursor! > cursor,
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.envelope.createdAt.compareTo(right.envelope.createdAt),
          );
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
      outbox: remainingOutbox,
    );
    return _visibleMessages(trust);
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
      Future.wait<void>([
        _closeState(connection, trustSession, wakeupSubscription),
        _attachmentCache.dispose(),
        _attachmentCipher.dispose(),
      ]).then<void>((_) {}).catchError((_) {}),
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
