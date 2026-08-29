import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_app_preferences.dart';
import '../domain/local_chat_group.dart';
import '../domain/local_chat_message.dart';
import '../domain/local_contact_alias.dart';
import '../domain/outbound_chat_message.dart';
import '../infrastructure/attachment_chunk_cache.dart';
import '../infrastructure/attachment_cipher.dart';
import '../infrastructure/call_media.dart';
import '../infrastructure/device_backup_file.dart';
import '../infrastructure/device_vault.dart';
import '../infrastructure/flutter_webrtc_call_media.dart';
import '../infrastructure/message_cipher.dart';
import '../infrastructure/platform_push_registration.dart';
import '../infrastructure/platform_push_token_source.dart';
import '../infrastructure/wamp_account_gateway.dart';
import 'call_controller.dart';

enum WampAppStatus { signedOut, busy, connected, failed }

enum PeerTrustStatus { unverified, verified, changed }

final class PeerDeviceTrust {
  const PeerDeviceTrust({
    required this.device,
    required this.safetyNumber,
    required this.verified,
  });

  final DeviceRecord device;
  final String safetyNumber;
  final bool verified;
}

final class PeerTrustSummary {
  PeerTrustSummary({
    required this.username,
    required Iterable<PeerDeviceTrust> devices,
    required this.previouslyVerified,
  }) : devices = List<PeerDeviceTrust>.unmodifiable(devices);

  final String username;
  final List<PeerDeviceTrust> devices;
  final bool previouslyVerified;

  PeerTrustStatus get status {
    if (devices.isNotEmpty && devices.every((device) => device.verified)) {
      return PeerTrustStatus.verified;
    }
    return previouslyVerified
        ? PeerTrustStatus.changed
        : PeerTrustStatus.unverified;
  }
}

final class OpenedOneTimeMessage {
  OpenedOneTimeMessage._({
    required this.messageId,
    required this.text,
    required Iterable<EncryptedAttachmentDescriptor> attachments,
    required this._scope,
    required this._senderUsername,
  }) : _attachments = attachments.toList(growable: true) {
    this.attachments = UnmodifiableListView<EncryptedAttachmentDescriptor>(
      _attachments,
    );
  }

  final String messageId;
  final String text;
  late final List<EncryptedAttachmentDescriptor> attachments;
  final List<EncryptedAttachmentDescriptor> _attachments;
  final String _scope;
  final String _senderUsername;

  void _invalidate() => _attachments.clear();
}

class WampAppController extends ChangeNotifier {
  WampAppController({
    AccountGateway? gateway,
    DeviceTrustStore? trustStore,
    MessageCipher? messageCipher,
    AttachmentChunkCache? attachmentCache,
    AttachmentCipher? attachmentCipher,
    DeviceBackupFileGateway? backupFiles,
    CallMediaFactory? callMediaFactory,
    PlatformPushTokenSource? platformPushTokenSource,
    this.deviceName = 'This device',
  }) : _gateway = gateway ?? const WampAccountGateway(),
       _trustStore = trustStore ?? EncryptedDeviceVault(),
       _messageCipher = messageCipher ?? MessageCipher(),
       _attachmentCache = attachmentCache ?? createAttachmentChunkCache(),
       _attachmentCipher = attachmentCipher ?? AttachmentCipher(),
       _callMediaFactory =
           callMediaFactory ?? const FlutterWebRtcCallMediaFactory(),
       _backupFiles =
           backupFiles ?? const FileSelectorDeviceBackupFileGateway() {
    _platformPush = PlatformPushRegistrationCoordinator(
      source: platformPushTokenSource,
      onError: _recordPlatformPushError,
    );
  }

  final AccountGateway _gateway;
  final DeviceTrustStore _trustStore;
  final MessageCipher _messageCipher;
  final AttachmentChunkCache _attachmentCache;
  final AttachmentCipher _attachmentCipher;
  final CallMediaFactory _callMediaFactory;
  final DeviceBackupFileGateway _backupFiles;
  late final PlatformPushRegistrationCoordinator _platformPush;
  final String deviceName;
  WampAppStatus _status = WampAppStatus.signedOut;
  AccountConnection? _connection;
  DeviceTrustSession? _trustSession;
  DeviceRecord? _localDevice;
  CallController? _calls;
  Object? _error;
  Object? _messageError;
  Object? _messageExpiryError;
  Object? _profileError;
  Object? _contactError;
  Object? _mcpAccessError;
  Object? _mcpConsentError;
  Object? _preferenceError;
  Object? _platformPushError;
  Object? _backupError;
  List<LocalChatMessage> _messages = const [];
  Timer? _messageExpiryTimer;
  List<LocalContactAlias> _contacts = const [];
  bool _messageBusy = false;
  bool _profileBusy = false;
  bool _contactBusy = false;
  bool _mcpAccessBusy = false;
  bool _mcpConsentBusy = false;
  bool _preferenceBusy = false;
  bool _backupBusy = false;
  LocalAppPreferences _preferences = LocalAppPreferences.defaults;
  StreamSubscription<MailboxWakeup>? _mailboxWakeupSubscription;
  int _pendingMailboxWakeupCursor = 0;
  bool _automaticSyncRunning = false;
  int _operationGeneration = 0;
  Future<void>? _signOutOperation;
  OpenedOneTimeMessage? _openedOneTimeMessage;
  bool _disposed = false;

  WampAppStatus get status => _status;
  bool get isBusy => _status == WampAppStatus.busy || _backupBusy;
  AccountConnection? get connection => _connection;
  DeviceRecord? get localDevice => _localDevice;
  CallController? get calls => _calls;
  String? get safetyNumber => _trustSession?.safetyNumber;
  List<LocalChatMessage> get messages => _messages;
  List<LocalChatGroup> get groups => _trustSession?.groups ?? const [];
  List<LocalContactAlias> get contacts => _contacts;
  OutboundChatMessage? outboundMessageFor(String messageId) => _trustSession
      ?.outbox
      .where((message) => message.envelope.messageId == messageId)
      .firstOrNull;
  bool get messageBusy => _messageBusy;
  bool get profileBusy => _profileBusy;
  bool get contactBusy => _contactBusy;
  bool get mcpAccessBusy => _mcpAccessBusy;
  bool get mcpConsentBusy => _mcpConsentBusy;
  WampAppMcpConsent get mcpConsent =>
      _connection?.mcpConsent ?? WampAppMcpConsent.denied;
  bool get preferenceBusy => _preferenceBusy;
  bool get backupBusy => _backupBusy;
  WampAppThemePreference get themePreference => _preferences.theme;
  String? get preferenceError => switch (_preferenceError) {
    FormatException(:final message) => message,
    _ when _preferenceError != null => 'Could not save local preferences.',
    _ => null,
  };
  String? get platformPushError => _platformPushError == null
      ? null
      : 'Platform push notifications are unavailable.';
  String? get backupError => switch (_backupError) {
    BackupExportException() => 'Could not create the encrypted backup.',
    BackupRestoreException() => 'Could not read the encrypted backup.',
    RemoteBackupException() => _backupError.toString(),
    FormatException(:final message) => message,
    _ when _backupError != null => 'The backup file operation failed.',
    _ => null,
  };
  String? get profileError => switch (_profileError) {
    FormatException(:final message) => message,
    ProfileUpdateException() => _profileError.toString(),
    _ when _profileError != null => 'The profile operation failed.',
    _ => null,
  };
  String? get contactError => switch (_contactError) {
    FormatException(:final message) => message,
    _ when _contactError != null => 'The local contact operation failed.',
    _ => null,
  };
  String? get mcpAccessError => switch (_mcpAccessError) {
    FormatException(:final message) => message,
    McpAccessException() => _mcpAccessError.toString(),
    StateError() => 'MCP access discovery is unavailable.',
    _ when _mcpAccessError != null =>
      'Could not load MCP connection information.',
    _ => null,
  };
  String? get mcpConsentError => switch (_mcpConsentError) {
    FormatException(:final message) => message,
    McpConsentException() => _mcpConsentError.toString(),
    _ when _mcpConsentError != null =>
      'Could not update MCP public-profile access.',
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
    BackupRestoreException() =>
      'Could not restore this backup. Check its account and recovery phrase.',
    RemoteBackupException() => _error.toString(),
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

  WampAppConversationAppearance conversationAppearanceFor(
    String conversationId,
  ) => _preferences.conversationAppearanceFor(conversationId);

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

  Future<bool> setConversationAppearance(
    String conversationId,
    WampAppConversationAppearance appearance,
  ) {
    if (_preferences.conversationAppearanceFor(conversationId) == appearance) {
      return Future<bool>.value(true);
    }
    try {
      return _savePreferences(
        _preferences.withConversationAppearance(conversationId, appearance),
      );
    } on FormatException catch (error) {
      _preferenceError = error;
      if (!_disposed) notifyListeners();
      return Future<bool>.value(false);
    }
  }

  Duration? disappearingMessagesFor(String conversationId) =>
      _preferences.disappearingMessagesFor(conversationId);

  Future<bool> setConversationDisappearingMessages(
    String conversationId,
    Duration? duration,
  ) {
    if (_preferences.disappearingMessagesFor(conversationId) == duration) {
      return Future<bool>.value(true);
    }
    try {
      return _savePreferences(
        _preferences.withConversationDisappearingMessages(
          conversationId,
          duration,
        ),
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
      await _platformPush.updateMutedConversationIds(
        preferences.mutedConversationIds,
      );
      if (!isCurrent()) return false;
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

  Future<bool> exportLocalBackup({required String recoveryPassphrase}) async {
    final trust = _trustSession;
    if (_disposed || isBusy || _messageBusy || trust == null) return false;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(trust, _trustSession);
    _backupBusy = true;
    _backupError = null;
    notifyListeners();
    Uint8List? archive;
    try {
      archive = await trust.exportBackup(
        recoveryPassphrase: recoveryPassphrase,
      );
      if (!isCurrent()) return false;
      final now = DateTime.now().toUtc();
      final date =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      return await _backupFiles.save(
        archive,
        suggestedName: 'wampapp-device-$date.wampbackup',
      );
    } catch (error) {
      if (isCurrent()) _backupError = error;
      return false;
    } finally {
      archive?.fillRange(0, archive.length, 0);
      if (isCurrent()) {
        _backupBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> restoreLocalBackupAndLogin({
    required String serverAddress,
    required String username,
    required String password,
    required String recoveryPassphrase,
  }) async {
    if (_disposed || isBusy || _messageBusy) return;
    _backupBusy = true;
    _backupError = null;
    notifyListeners();
    Uint8List? archive;
    try {
      archive = await _backupFiles.open();
    } catch (error) {
      if (!_disposed) {
        _backupError = error;
        _backupBusy = false;
        notifyListeners();
      }
      return;
    }
    if (archive == null) {
      if (!_disposed) {
        _backupBusy = false;
        notifyListeners();
      }
      return;
    }
    _backupBusy = false;
    try {
      await _run(
        password: password,
        beforeTrustOpen: (connection) => _trustStore.importBackup(
          endpoint: connection.endpoint,
          username: connection.username,
          password: password,
          recoveryPassphrase: recoveryPassphrase,
          archive: archive!,
        ),
        () {
          final endpoint = ServerEndpoint.parse(serverAddress);
          endpoint.requireSecureRegistration();
          return _gateway.login(
            endpoint: endpoint,
            username: username,
            password: password,
          );
        },
      );
    } finally {
      archive.fillRange(0, archive.length, 0);
    }
  }

  Future<bool> uploadRemoteBackup({required String recoveryPassphrase}) async {
    final trust = _trustSession;
    final connection = _connection;
    if (_disposed ||
        isBusy ||
        _messageBusy ||
        trust == null ||
        connection == null) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(trust, _trustSession) &&
        identical(connection, _connection);
    _backupBusy = true;
    _backupError = null;
    notifyListeners();
    Uint8List? archive;
    try {
      archive = await trust.exportBackup(
        recoveryPassphrase: recoveryPassphrase,
      );
      if (!isCurrent()) return false;
      await connection.uploadRemoteBackup(archive);
      return isCurrent();
    } catch (error) {
      if (isCurrent()) _backupError = error;
      return false;
    } finally {
      archive?.fillRange(0, archive.length, 0);
      if (isCurrent()) {
        _backupBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> restoreRemoteBackupAndLogin({
    required String serverAddress,
    required String username,
    required String password,
    required String recoveryPassphrase,
  }) async {
    Uint8List? archive;
    try {
      await _run(
        password: password,
        beforeTrustOpen: (connection) async {
          final remote = await connection.downloadRemoteBackup();
          if (remote == null) {
            throw const RemoteBackupException(RemoteBackupFailureKind.notFound);
          }
          archive = remote.archive;
          await _trustStore.importBackup(
            endpoint: connection.endpoint,
            username: connection.username,
            password: password,
            recoveryPassphrase: recoveryPassphrase,
            archive: archive!,
          );
        },
        () {
          final endpoint = ServerEndpoint.parse(serverAddress);
          endpoint.requireSecureRegistration();
          return _gateway.login(
            endpoint: endpoint,
            username: username,
            password: password,
          );
        },
      );
    } finally {
      archive?.fillRange(0, archive!.length, 0);
    }
  }

  Future<void> signOut() async {
    final activeOperation = _signOutOperation;
    if (activeOperation != null) {
      await activeOperation;
      return;
    }
    final operation = _performSignOut();
    _signOutOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_signOutOperation, operation)) {
        _signOutOperation = null;
      }
    }
  }

  Future<void> _performSignOut() async {
    if (_backupBusy) return;
    _operationGeneration += 1;
    _messageExpiryTimer?.cancel();
    _messageExpiryTimer = null;
    final connection = _connection;
    final trustSession = _trustSession;
    final wakeupSubscription = _mailboxWakeupSubscription;
    final calls = _calls;
    final openedOneTimeMessage = _openedOneTimeMessage;
    final openedOneTimeMessageHasAttachments =
        openedOneTimeMessage?.attachments.isNotEmpty ?? false;
    openedOneTimeMessage?._invalidate();
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _calls = null;
    _mailboxWakeupSubscription = null;
    _pendingMailboxWakeupCursor = 0;
    _automaticSyncRunning = false;
    _openedOneTimeMessage = null;
    _error = null;
    _messageError = null;
    _messageExpiryError = null;
    _profileError = null;
    _contactError = null;
    _mcpAccessError = null;
    _mcpConsentError = null;
    _preferenceError = null;
    _platformPushError = null;
    _backupError = null;
    _messages = const [];
    _contacts = const [];
    _messageBusy = false;
    _profileBusy = false;
    _contactBusy = false;
    _mcpAccessBusy = false;
    _mcpConsentBusy = false;
    _preferenceBusy = false;
    _backupBusy = false;
    _preferences = LocalAppPreferences.defaults;
    _status = WampAppStatus.signedOut;
    if (!_disposed) notifyListeners();
    try {
      await Future.wait<void>([
        _platformPush.clear(),
        if (openedOneTimeMessage != null && openedOneTimeMessageHasAttachments)
          _attachmentCache.removeMessage(
            scope: openedOneTimeMessage._scope,
            messageId: openedOneTimeMessage.messageId,
          ),
      ]);
    } finally {
      await _closeState(connection, trustSession, wakeupSubscription, calls);
    }
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

  Future<WampAppMcpAccessConfiguration?> loadMcpAccessConfiguration() async {
    final connection = _connection;
    if (_disposed || _mcpAccessBusy || connection == null) return null;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection);
    _mcpAccessBusy = true;
    _mcpAccessError = null;
    notifyListeners();
    try {
      final configuration = await connection.getMcpAccessConfiguration();
      return isCurrent() ? configuration : null;
    } catch (error) {
      if (isCurrent()) _mcpAccessError = error;
      return null;
    } finally {
      if (isCurrent()) {
        _mcpAccessBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> setMcpProfileReadAllowed(bool allowed) async {
    final connection = _connection;
    if (_disposed || _mcpConsentBusy || connection == null) return false;
    if (connection.mcpConsent.profileReadAllowed == allowed) return true;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection);
    _mcpConsentBusy = true;
    _mcpConsentError = null;
    notifyListeners();
    try {
      await connection.updateMcpConsent(
        WampAppMcpConsentUpdate(
          expectedRevision: connection.mcpConsent.revision,
          profileReadAllowed: allowed,
        ),
      );
      return isCurrent();
    } catch (error) {
      if (error case McpConsentException(
        kind: McpConsentFailureKind.conflict,
      )) {
        try {
          await connection.refreshMcpConsent();
        } catch (_) {
          // Keep the original conflict as the actionable UI result.
        }
      }
      if (isCurrent()) _mcpConsentError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _mcpConsentBusy = false;
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

  Future<bool> bindContact({
    required String username,
    required String displayName,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    if (_disposed || _contactBusy || connection == null || trust == null) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    _contactBusy = true;
    _contactError = null;
    notifyListeners();
    try {
      final contact = LocalContactAlias(
        username: username,
        displayName: displayName,
        importedAt: DateTime.now().toUtc(),
      );
      if (contact.username == connection.username) {
        throw const FormatException('You cannot add your own account.');
      }
      final profile = await connection.getProfile(contact.username);
      if (!isCurrent()) return false;
      if (profile.username != contact.username) {
        throw const FormatException(
          'The server returned a different contact account.',
        );
      }
      final nextContacts =
          <LocalContactAlias>[
            ..._contacts.where((saved) => saved.username != contact.username),
            contact,
          ]..sort((left, right) {
            final byName = left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            );
            return byName != 0
                ? byName
                : left.username.compareTo(right.username);
          });
      await trust.saveContacts(nextContacts);
      if (!isCurrent()) return false;
      _contacts = trust.contacts;
      return true;
    } catch (error) {
      if (isCurrent()) _contactError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _contactBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> renameContact(String username, String displayName) async {
    final trust = _trustSession;
    if (_disposed || _contactBusy || trust == null) return false;
    final normalized = AccountRegistration.normalizeUsername(username);
    final existing = _contacts
        .where((contact) => contact.username == normalized)
        .firstOrNull;
    if (existing == null) return false;
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(trust, _trustSession);
    _contactBusy = true;
    _contactError = null;
    notifyListeners();
    try {
      final updated = existing.withDisplayName(displayName);
      final nextContacts = _contacts
          .map((contact) => contact.username == normalized ? updated : contact)
          .toList(growable: false);
      await trust.saveContacts(nextContacts);
      if (!isCurrent()) return false;
      _contacts = trust.contacts;
      return true;
    } catch (error) {
      if (isCurrent()) _contactError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _contactBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> removeContact(String username) async {
    final trust = _trustSession;
    if (_disposed || _contactBusy || trust == null) return false;
    final normalized = AccountRegistration.normalizeUsername(username);
    if (!_contacts.any((contact) => contact.username == normalized)) {
      return false;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(trust, _trustSession);
    _contactBusy = true;
    _contactError = null;
    notifyListeners();
    try {
      final nextContacts = _contacts
          .where((contact) => contact.username != normalized)
          .toList(growable: false);
      await trust.saveContacts(nextContacts);
      if (!isCurrent()) return false;
      _contacts = trust.contacts;
      return true;
    } catch (error) {
      if (isCurrent()) _contactError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _contactBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _run(
    Future<AccountConnection> Function() action, {
    required String password,
    Future<void> Function(AccountConnection connection)? beforeTrustOpen,
  }) async {
    if (_disposed || isBusy || _messageBusy) return;
    final generation = ++_operationGeneration;
    _error = null;
    _messageError = null;
    _contactError = null;
    _mcpAccessError = null;
    _mcpConsentError = null;
    _status = WampAppStatus.busy;
    notifyListeners();
    AccountConnection? next;
    DeviceTrustSession? nextTrust;
    DeviceRecord? nextDevice;
    CallController? nextCalls;
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
      await beforeTrustOpen?.call(next);
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
      nextCalls = CallController(
        connection: next,
        trust: nextTrust,
        localDevice: nextDevice,
        mediaFactory: _callMediaFactory,
      );
      await nextCalls.initialize();
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
        await _closeState(next, nextTrust, nextWakeupSubscription, nextCalls);
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
      await _closeState(next, nextTrust, nextWakeupSubscription, nextCalls);
      return;
    }

    final previous = _connection;
    final previousTrust = _trustSession;
    final previousWakeupSubscription = _mailboxWakeupSubscription;
    final previousCalls = _calls;
    _connection = next;
    _trustSession = nextTrust;
    _calls = nextCalls;
    _preferences = nextTrust.preferences;
    _contacts = nextTrust.contacts;
    _localDevice = nextDevice;
    _mailboxWakeupSubscription = nextWakeupSubscription;
    _pendingMailboxWakeupCursor = nextPendingWakeupCursor;
    _automaticSyncRunning = false;
    _replaceMessages(nextMessages);
    _messageError = nextWakeupError;
    _messageExpiryError = null;
    _mcpAccessError = null;
    _mcpConsentError = null;
    _contactError = null;
    _preferenceError = null;
    _platformPushError = null;
    _preferenceBusy = false;
    _contactBusy = false;
    _mcpAccessBusy = false;
    _mcpConsentBusy = false;
    _status = WampAppStatus.connected;
    notifyListeners();
    _startAutomaticSyncIfNeeded();
    await _platformPush.replace(
      deviceId: nextDevice.deviceId,
      register: next.registerPlatformPush,
      unregister: next.unregisterPlatformPush,
      mutedConversationIds: nextTrust.preferences.mutedConversationIds,
    );
    try {
      await _closeState(
        previous,
        previousTrust,
        previousWakeupSubscription,
        previousCalls,
      );
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
        _preferenceBusy ||
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
      final conversationId = directConversationIdFor(recipientUsername);
      final effectiveExpiresAfter =
          expiresAfter ??
          (conversationId == null
              ? null
              : _preferences.disappearingMessagesFor(conversationId));
      if (effectiveExpiresAfter != null &&
          effectiveExpiresAfter <= Duration.zero) {
        throw const FormatException('Message expiry must be positive.');
      }
      final ownDevices = await connection.listDevices();
      final recipientDevices = await connection.lookupDevices(
        recipientUsername,
      );
      if (recipientDevices.devices.isEmpty) {
        final username = AccountRegistration.normalizeUsername(
          recipientUsername,
        );
        throw FormatException('@$username has no active device.');
      }
      _ensurePeerTrustAllowsSending(
        trust,
        recipientUsername,
        recipientDevices.devices,
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
        expiresAt: effectiveExpiresAfter == null
            ? null
            : now.add(effectiveExpiresAfter),
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
      _replaceMessages(_visibleMessages(trust));
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
        _replaceMessages(updated);
        synchronized = true;
      } else {
        _replaceMessages(_visibleMessages(trust));
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
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
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
        _startAutomaticSyncIfNeeded();
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
        _preferenceBusy ||
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
      final effectiveExpiresAfter =
          expiresAfter ?? _preferences.disappearingMessagesFor(groupId);
      if (effectiveExpiresAfter != null &&
          effectiveExpiresAfter <= Duration.zero) {
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
        if (username != connection.username) {
          _ensurePeerTrustAllowsSending(trust, username, directory.devices);
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
        expiresAt: effectiveExpiresAfter == null
            ? null
            : now.add(effectiveExpiresAfter),
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
      _replaceMessages(_visibleMessages(trust));
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
        _replaceMessages(updated);
        synchronized = true;
      } else {
        _replaceMessages(_visibleMessages(trust));
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
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
      }
    }
  }

  Future<PeerTrustSummary?> inspectPeerTrust(String username) async {
    final connection = _connection;
    final trust = _trustSession;
    if (_disposed || connection == null || trust == null) return null;
    final normalized = AccountRegistration.normalizeUsername(username);
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    final directory = normalized == connection.username
        ? await connection.listDevices()
        : await connection.lookupDevices(normalized);
    if (!isCurrent()) return null;
    if (directory.devices.isEmpty) {
      throw FormatException('@$normalized has no active device.');
    }
    return _peerTrustSummary(trust, normalized, directory.devices);
  }

  Future<PeerTrustSummary?> verifyPeerDevice(PeerDeviceTrust expected) async {
    final connection = _connection;
    final trust = _trustSession;
    if (_disposed || connection == null || trust == null) return null;
    final username = AccountRegistration.normalizeUsername(
      expected.device.username,
    );
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    final directory = username == connection.username
        ? await connection.listDevices()
        : await connection.lookupDevices(username);
    if (!isCurrent()) return null;
    final current = directory.devices
        .where((device) => device.deviceId == expected.device.deviceId)
        .firstOrNull;
    if (current == null ||
        trust.safetyNumberFor(current) != expected.safetyNumber) {
      throw const FormatException(
        'That device identity changed before verification completed.',
      );
    }
    await trust.markVerified(current);
    if (!isCurrent()) return null;
    return _peerTrustSummary(trust, username, directory.devices);
  }

  PeerTrustSummary _peerTrustSummary(
    DeviceTrustSession trust,
    String username,
    Iterable<DeviceRecord> devices,
  ) {
    return PeerTrustSummary(
      username: username,
      devices: devices.map(
        (device) => PeerDeviceTrust(
          device: device,
          safetyNumber: trust.safetyNumberFor(device),
          verified: trust.isVerified(device),
        ),
      ),
      previouslyVerified: trust.hasVerifiedContact(username),
    );
  }

  void _ensurePeerTrustAllowsSending(
    DeviceTrustSession trust,
    String username,
    Iterable<DeviceRecord> devices,
  ) {
    final normalized = AccountRegistration.normalizeUsername(username);
    if (!trust.hasVerifiedContact(normalized) ||
        devices.every(trust.isVerified)) {
      return;
    }
    throw FormatException(
      'Encryption identity changed for @$normalized. Review and verify every '
      'active device before sending.',
    );
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
        _replaceMessages(updated);
        synchronized = true;
      } else {
        _replaceMessages(_visibleMessages(trust));
      }
      return true;
    } catch (error) {
      if (isCurrent()) _messageError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
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
        _startAutomaticSyncIfNeeded();
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
      _replaceMessages(_visibleMessages(trust));
      return true;
    } catch (error) {
      if (isCurrent()) _messageError = error;
      return false;
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
        _startAutomaticSyncIfNeeded();
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
      _replaceMessages(updated);
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
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
      }
    }
  }

  Future<OpenedOneTimeMessage?> consumeOneTimeMessage(String messageId) async {
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
    OpenedOneTimeMessage? opened;
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      await _discardOpenedOneTimeMessage();
      final scope = attachmentCacheScope(
        connection.endpoint,
        connection.username,
      );
      final senderUsername = message.peerUsername;
      for (final attachment in message.attachments) {
        await _attachmentCipher.cacheEncryptedChunks(
          scope: scope,
          senderUsername: senderUsername,
          messageId: message.messageId,
          attachment: attachment,
          cache: _attachmentCache,
          fetchChunk: (chunkIndex) => connection.getAttachmentChunk(
            messageId: message.messageId,
            attachmentId: attachment.attachmentId,
            chunkIndex: chunkIndex,
          ),
          isCancelled: () =>
              _disposed ||
              generation != _operationGeneration ||
              connection != _connection ||
              trust != _trustSession,
        );
      }
      final consumption = trust.signOneTimeConsumption(messageId);
      if (consumption.deviceId != localDevice.deviceId) {
        throw StateError('The local device identity changed unexpectedly.');
      }
      await connection.consumeOneTime(consumption);
      opened = OpenedOneTimeMessage._(
        messageId: message.messageId,
        text: message.text,
        attachments: message.attachments,
        scope: scope,
        senderUsername: senderUsername,
      );
      _openedOneTimeMessage = opened;
      final updated = await _synchronize(connection, trust, localDevice);
      if (_disposed ||
          generation != _operationGeneration ||
          connection != _connection ||
          trust != _trustSession) {
        await _discardOpenedOneTimeMessage(only: opened);
        return null;
      }
      _replaceMessages(updated);
      synchronized = true;
      return opened;
    } catch (error) {
      try {
        if (opened != null) {
          await _discardOpenedOneTimeMessage(only: opened);
        } else if (message.attachments.isNotEmpty) {
          await _attachmentCache.removeMessage(
            scope: attachmentCacheScope(
              connection.endpoint,
              connection.username,
            ),
            messageId: message.messageId,
          );
        }
      } catch (_) {
        // Preserve the consumption or synchronization error for the UI.
      }
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
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
      }
    }
  }

  Future<Uint8List?> loadOpenedOneTimeAttachment({
    required OpenedOneTimeMessage message,
    required String attachmentId,
  }) async {
    final connection = _connection;
    final trust = _trustSession;
    final attachment = message.attachments
        .where((candidate) => candidate.attachmentId == attachmentId)
        .firstOrNull;
    if (_disposed ||
        _messageBusy ||
        connection == null ||
        trust == null ||
        !identical(_openedOneTimeMessage, message) ||
        attachment == null) {
      return null;
    }
    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession) &&
        identical(_openedOneTimeMessage, message);
    _messageBusy = true;
    _messageError = null;
    notifyListeners();
    try {
      final opened = await _attachmentCipher.decryptToBytes(
        scope: message._scope,
        senderUsername: message._senderUsername,
        messageId: message.messageId,
        attachment: attachment,
        cache: _attachmentCache,
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
        _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<void> closeOpenedOneTimeMessage(OpenedOneTimeMessage message) async {
    if (!identical(_openedOneTimeMessage, message)) return;
    try {
      await _discardOpenedOneTimeMessage(only: message);
    } catch (error) {
      if (!_disposed) _messageError = error;
    } finally {
      if (!_disposed) {
        _messageBusy = false;
        notifyListeners();
        _startAutomaticSyncIfNeeded();
      }
    }
  }

  Future<void> _discardOpenedOneTimeMessage({
    OpenedOneTimeMessage? only,
  }) async {
    final opened = _openedOneTimeMessage;
    if (opened == null || (only != null && !identical(opened, only))) return;
    _openedOneTimeMessage = null;
    final hasAttachments = opened.attachments.isNotEmpty;
    opened._invalidate();
    if (!hasAttachments) return;
    await _attachmentCache.removeMessage(
      scope: opened._scope,
      messageId: opened.messageId,
    );
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
      _replaceMessages(updated);
      synchronized = true;
    } catch (error) {
      if (!_disposed && generation == _operationGeneration) {
        _messageError = error;
      }
    } finally {
      if (!_disposed && generation == _operationGeneration) {
        _messageBusy = false;
        notifyListeners();
        if (synchronized || trust.mailboxCursor < _pendingMailboxWakeupCursor) {
          _startAutomaticSyncIfNeeded();
        }
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

  void _recordPlatformPushError(Object error) {
    if (_disposed || _connection == null) return;
    _platformPushError = error;
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
        _replaceMessages(updated);
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

  void _replaceMessages(Iterable<LocalChatMessage> messages) {
    _messages = List<LocalChatMessage>.unmodifiable(messages);
    _scheduleMessageExpiry();
  }

  void _scheduleMessageExpiry() {
    _messageExpiryTimer?.cancel();
    _messageExpiryTimer = null;
    if (_disposed || _trustSession == null) return;
    DateTime? nextExpiry;
    for (final message in _messages) {
      final expiresAt = message.expiresAt;
      if (expiresAt != null &&
          (nextExpiry == null || expiresAt.isBefore(nextExpiry))) {
        nextExpiry = expiresAt;
      }
    }
    if (nextExpiry == null) return;
    final now = DateTime.now().toUtc();
    final remaining = nextExpiry.difference(now);
    final delay = remaining.isNegative || remaining == Duration.zero
        ? Duration.zero
        : remaining + const Duration(milliseconds: 1);
    _messageExpiryTimer = Timer(
      delay,
      () => unawaited(_pruneExpiredMessages()),
    );
  }

  void _retryMessageExpiryPrune([
    Duration delay = const Duration(milliseconds: 100),
  ]) {
    _messageExpiryTimer?.cancel();
    if (_disposed || _trustSession == null) {
      _messageExpiryTimer = null;
      return;
    }
    _messageExpiryTimer = Timer(
      delay,
      () => unawaited(_pruneExpiredMessages()),
    );
  }

  Future<void> _pruneExpiredMessages() async {
    _messageExpiryTimer = null;
    final connection = _connection;
    final trust = _trustSession;
    if (_disposed || connection == null || trust == null) return;
    if (_messageBusy) {
      _retryMessageExpiryPrune();
      return;
    }

    final now = DateTime.now().toUtc();
    final retainedMessages = trust.messages
        .where((message) => !message.isExpiredAt(now))
        .toList(growable: false);
    final retainedOutbox = trust.outbox
        .where((message) => !message.localMessage.isExpiredAt(now))
        .toList(growable: false);
    if (retainedMessages.length == trust.messages.length &&
        retainedOutbox.length == trust.outbox.length) {
      _clearMessageExpiryError();
      _replaceMessages(_visibleMessages(trust));
      return;
    }

    final generation = _operationGeneration;
    bool isCurrent() =>
        !_disposed &&
        generation == _operationGeneration &&
        identical(connection, _connection) &&
        identical(trust, _trustSession);
    _messageBusy = true;
    _replaceMessages(_visibleMessages(trust));
    notifyListeners();
    try {
      await trust.saveMailboxState(
        cursor: trust.mailboxCursor,
        messages: retainedMessages,
        outbox: retainedOutbox,
      );
      if (!isCurrent()) return;
      _clearMessageExpiryError();
      _replaceMessages(_visibleMessages(trust));
    } catch (error) {
      if (isCurrent()) {
        _messageError = error;
        _messageExpiryError = error;
        _retryMessageExpiryPrune(const Duration(seconds: 1));
      }
    } finally {
      if (isCurrent()) {
        _messageBusy = false;
        notifyListeners();
        _startAutomaticSyncIfNeeded();
      }
    }
  }

  void _clearMessageExpiryError() {
    if (identical(_messageError, _messageExpiryError)) {
      _messageError = null;
    }
    _messageExpiryError = null;
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
    final consumedOneTimeMessageIds = <String>{};
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
          if (encrypted.attachmentIds.isNotEmpty) {
            consumedOneTimeMessageIds.add(encrypted.messageId);
          }
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
    final activeOpenedMessageId = _openedOneTimeMessage?.messageId;
    final scope = attachmentCacheScope(
      connection.endpoint,
      connection.username,
    );
    for (final messageId in consumedOneTimeMessageIds) {
      if (messageId == activeOpenedMessageId) continue;
      await _attachmentCache.removeMessage(scope: scope, messageId: messageId);
    }
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
    _messageExpiryTimer?.cancel();
    _messageExpiryTimer = null;
    final connection = _connection;
    final trustSession = _trustSession;
    final wakeupSubscription = _mailboxWakeupSubscription;
    final calls = _calls;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _calls = null;
    _mailboxWakeupSubscription = null;
    _pendingMailboxWakeupCursor = 0;
    _automaticSyncRunning = false;
    _openedOneTimeMessage?._invalidate();
    _openedOneTimeMessage = null;
    unawaited(
      Future.wait<void>([
        _platformPush.dispose().then(
          (_) =>
              _closeState(connection, trustSession, wakeupSubscription, calls),
        ),
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
  CallController? calls,
]) async {
  Object? failure;
  StackTrace? failureStack;
  try {
    await calls?.close();
    calls?.dispose();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
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
