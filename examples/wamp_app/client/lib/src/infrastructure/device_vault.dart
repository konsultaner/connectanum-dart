import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/authentication.dart';
import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_app_preferences.dart';
import '../domain/local_chat_group.dart';
import '../domain/local_chat_message.dart';
import '../domain/outbound_chat_message.dart';
import 'local_device_identity.dart';
import 'vault_storage.dart';

abstract final class WampAppBackupLimits {
  static const maximumArchiveBytes = 12 * 1024 * 1024;
}

abstract interface class DeviceTrustStore {
  Future<DeviceTrustSession> openOrCreate({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String deviceName,
  });

  Future<void> importBackup({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String recoveryPassphrase,
    required Uint8List archive,
  });
}

abstract interface class DeviceTrustSession {
  DeviceEnrollment get enrollment;
  String get deviceId;
  String get safetyNumber;
  String safetyNumberFor(DeviceRecord contact);
  bool isVerified(DeviceRecord contact);
  Future<void> markVerified(DeviceRecord contact);
  WrappedConversationKey wrapConversationKey({
    required String conversationId,
    required DeviceRecord recipient,
    required Uint8List conversationKey,
  });
  OneTimeMessageConsumption signOneTimeConsumption(String messageId);
  Uint8List unwrapConversationKey({
    required WrappedConversationKey envelope,
    required DeviceRecord sender,
    bool allowRevokedSender = false,
  });
  int get mailboxCursor;
  List<LocalChatMessage> get messages;
  List<LocalChatGroup> get groups;
  List<OutboundChatMessage> get outbox;
  LocalAppPreferences get preferences;
  Future<Uint8List> exportBackup({required String recoveryPassphrase});
  Future<void> saveMailboxState({
    required int cursor,
    required List<LocalChatMessage> messages,
    List<LocalChatGroup>? groups,
    List<OutboundChatMessage>? outbox,
  });
  Future<void> savePreferences(LocalAppPreferences preferences);
  Future<void> dispose();
}

abstract interface class VaultKeyDeriver {
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  });
}

final class ScramVaultKeyDeriver implements VaultKeyDeriver {
  const ScramVaultKeyDeriver();

  @override
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  }) {
    return ScramAuthentication.deriveSaltedPasswordAsync(
      secret: password,
      salt: salt,
      kdf: ScramAuthentication.kdfArgon,
      iterations: iterations,
      memory: memoryKiB,
      timeout: timeout,
    );
  }
}

final class EncryptedDeviceVault implements DeviceTrustStore {
  EncryptedDeviceVault({
    VaultStorage? storage,
    this.keyDeriver = const ScramVaultKeyDeriver(),
    this.iterations = 3,
    this.memoryKiB = 65536,
    this.derivationTimeout = const Duration(seconds: 75),
    Random? random,
  }) : storage = storage ?? SharedPreferencesVaultStorage(),
       _random = random ?? Random.secure();

  static const _schema = 1;
  static const _cipher = 'xsalsa20-poly1305-secretbox';
  static const _maximumEnvelopeBytes = 8 * 1024 * 1024;
  static const _backupSchema = 1;
  static const _backupFormat = 'wamp-app-device-backup';
  static const _minimumBackupMemoryKiB = 8192;
  static const _maximumBackupMemoryKiB = 262144;
  static const _maximumBackupIterations = 16;

  final VaultStorage storage;
  final VaultKeyDeriver keyDeriver;
  final int iterations;
  final int memoryKiB;
  final Duration derivationTimeout;
  final Random _random;
  Future<void> _openTail = Future<void>.value();

  @override
  Future<DeviceTrustSession> openOrCreate({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String deviceName,
  }) {
    return _serializeOpen(() async {
      final normalizedUsername = AccountRegistration.normalizeUsername(
        username,
      );
      if (normalizedUsername.isEmpty || password.isEmpty) {
        throw const VaultUnlockException();
      }
      final endpointBinding = endpoint.websocketUri.toString();
      final storageKey = _storageKey(endpointBinding, normalizedUsername);
      final stored = await storage.read(storageKey);
      if (stored == null) {
        return _create(
          endpointBinding: endpointBinding,
          username: normalizedUsername,
          password: password,
          deviceName: deviceName,
          storageKey: storageKey,
        );
      }
      return _unlock(
        stored: stored,
        endpointBinding: endpointBinding,
        username: normalizedUsername,
        password: password,
        storageKey: storageKey,
      );
    });
  }

  @override
  Future<void> importBackup({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String recoveryPassphrase,
    required Uint8List archive,
  }) {
    return _serializeOpen(() async {
      final normalizedUsername = AccountRegistration.normalizeUsername(
        username,
      );
      if (normalizedUsername.isEmpty || password.isEmpty) {
        throw const BackupRestoreException();
      }
      final endpointBinding = endpoint.websocketUri.toString();
      final plaintext = await _decryptBackup(
        archive,
        recoveryPassphrase: recoveryPassphrase,
      );
      Uint8List? localKey;
      LocalDeviceIdentity? identity;
      try {
        final document = jsonDecode(utf8.decode(plaintext));
        if (document is! Map<String, dynamic> ||
            document['schema'] != _schema ||
            document['endpoint'] != endpointBinding ||
            document['username'] != normalizedUsername ||
            document['identity'] is! Map<String, dynamic>) {
          throw const BackupRestoreException();
        }
        identity = LocalDeviceIdentity.fromJson(
          document['identity'] as Map<String, dynamic>,
        );
        final verifications = _readVerifications(document['verifications']);
        final mailbox = _readMailbox(document['mailbox']);
        final groups = _readGroups(document['groups']);
        final outbox = _readOutbox(document['outbox'], mailbox.$2);
        final preferences = LocalAppPreferences.fromJson(
          document['preferences'],
        );
        final saltBytes = Uint8List.fromList(
          List<int>.generate(16, (_) => _random.nextInt(256)),
        );
        final salt = base64.encode(saltBytes);
        saltBytes.fillRange(0, saltBytes.length, 0);
        localKey = await _derive(password, salt);
        final session = _UnlockedDeviceVault(
          storage: storage,
          storageKey: _storageKey(endpointBinding, normalizedUsername),
          endpointBinding: endpointBinding,
          username: normalizedUsername,
          salt: salt,
          iterations: iterations,
          memoryKiB: memoryKiB,
          encryptionKey: localKey,
          identity: identity,
          verifications: verifications,
          mailboxCursor: mailbox.$1,
          messages: mailbox.$2,
          groups: groups,
          outbox: outbox,
          preferences: preferences,
          backupEncoder: _encryptBackup,
        );
        identity = null;
        try {
          await session.persist();
        } finally {
          await session.dispose();
        }
      } catch (error) {
        identity?.dispose();
        if (error is BackupRestoreException) rethrow;
        throw const BackupRestoreException();
      } finally {
        localKey?.fillRange(0, localKey.length, 0);
        plaintext.fillRange(0, plaintext.length, 0);
      }
    });
  }

  Future<DeviceTrustSession> _create({
    required String endpointBinding,
    required String username,
    required String password,
    required String deviceName,
    required String storageKey,
  }) async {
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final salt = base64.encode(saltBytes);
    saltBytes.fillRange(0, saltBytes.length, 0);
    final key = await _derive(password, salt);
    LocalDeviceIdentity? identity;
    try {
      identity = LocalDeviceIdentity.generate(deviceName: deviceName);
      final session = _UnlockedDeviceVault(
        storage: storage,
        storageKey: storageKey,
        endpointBinding: endpointBinding,
        username: username,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        encryptionKey: key,
        identity: identity,
        verifications: const {},
        mailboxCursor: 0,
        messages: const [],
        groups: const [],
        outbox: const [],
        preferences: LocalAppPreferences.defaults,
        backupEncoder: _encryptBackup,
      );
      identity = null;
      try {
        await session.persist();
        return session;
      } catch (_) {
        await session.dispose();
        rethrow;
      }
    } finally {
      key.fillRange(0, key.length, 0);
      identity?.dispose();
    }
  }

  Future<DeviceTrustSession> _unlock({
    required String stored,
    required String endpointBinding,
    required String username,
    required String password,
    required String storageKey,
  }) async {
    Uint8List? key;
    Uint8List? plaintext;
    LocalDeviceIdentity? identity;
    try {
      if (utf8.encode(stored).length > _maximumEnvelopeBytes) {
        throw const FormatException('Encrypted vault is too large.');
      }
      final envelope = jsonDecode(stored);
      if (envelope is! Map<String, dynamic> ||
          envelope['schema'] != _schema ||
          envelope['kdf'] != ScramAuthentication.kdfArgon ||
          envelope['iterations'] != iterations ||
          envelope['memory_kib'] != memoryKiB ||
          envelope['cipher'] != _cipher) {
        throw const FormatException('Encrypted vault settings are invalid.');
      }
      final salt = _readSalt(envelope['salt']);
      final ciphertext = _decodeCiphertext(envelope['ciphertext']);
      key = await _derive(password, salt);
      final box = SecretBox(key);
      plaintext = box.decrypt(EncryptedMessage.fromList(ciphertext));
      final document = jsonDecode(utf8.decode(plaintext));
      if (document is! Map<String, dynamic> ||
          document['schema'] != _schema ||
          document['endpoint'] != endpointBinding ||
          document['username'] != username ||
          document['identity'] is! Map<String, dynamic>) {
        throw const FormatException('Encrypted vault binding is invalid.');
      }
      identity = LocalDeviceIdentity.fromJson(
        document['identity'] as Map<String, dynamic>,
      );
      final verifications = _readVerifications(document['verifications']);
      final mailbox = _readMailbox(document['mailbox']);
      final groups = _readGroups(document['groups']);
      final outbox = _readOutbox(document['outbox'], mailbox.$2);
      final preferences = LocalAppPreferences.fromJson(document['preferences']);
      final session = _UnlockedDeviceVault(
        storage: storage,
        storageKey: storageKey,
        endpointBinding: endpointBinding,
        username: username,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        encryptionKey: key,
        identity: identity,
        verifications: verifications,
        mailboxCursor: mailbox.$1,
        messages: mailbox.$2,
        groups: groups,
        outbox: outbox,
        preferences: preferences,
        backupEncoder: _encryptBackup,
      );
      identity = null;
      return session;
    } catch (_) {
      identity?.dispose();
      throw const VaultUnlockException();
    } finally {
      key?.fillRange(0, key.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<Uint8List> _derive(String password, String salt) async {
    final key = await keyDeriver.derive(
      password: password,
      salt: salt,
      iterations: iterations,
      memoryKiB: memoryKiB,
      timeout: derivationTimeout,
    );
    if (key.length != SecretBox.keyLength) {
      key.fillRange(0, key.length, 0);
      throw const VaultUnlockException();
    }
    return key;
  }

  Future<Uint8List> _encryptBackup(
    Uint8List plaintext,
    String recoveryPassphrase,
  ) async {
    _validateRecoveryPassphrase(recoveryPassphrase, exporting: true);
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final salt = base64.encode(saltBytes);
    saltBytes.fillRange(0, saltBytes.length, 0);
    Uint8List? key;
    try {
      _validateBackupKdf(iterations, memoryKiB);
      key = await _deriveBackupKey(
        recoveryPassphrase,
        salt,
        backupIterations: iterations,
        backupMemoryKiB: memoryKiB,
      );
      final ciphertext = SecretBox(key).encrypt(plaintext).asTypedList;
      final encoded = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': _backupFormat,
            'schema': _backupSchema,
            'kdf': ScramAuthentication.kdfArgon,
            'iterations': iterations,
            'memory_kib': memoryKiB,
            'salt': salt,
            'cipher': _cipher,
            'content': 'device-state',
            'media': 'descriptors-only',
            'ciphertext': _encode(ciphertext),
          }),
        ),
      );
      if (encoded.length > WampAppBackupLimits.maximumArchiveBytes) {
        encoded.fillRange(0, encoded.length, 0);
        throw const BackupExportException();
      }
      return encoded;
    } catch (error) {
      if (error is BackupExportException) rethrow;
      throw const BackupExportException();
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }

  Future<Uint8List> _decryptBackup(
    Uint8List archive, {
    required String recoveryPassphrase,
  }) async {
    _validateRecoveryPassphrase(recoveryPassphrase, exporting: false);
    Uint8List? key;
    try {
      if (archive.isEmpty ||
          archive.length > WampAppBackupLimits.maximumArchiveBytes) {
        throw const BackupRestoreException();
      }
      final envelope = jsonDecode(utf8.decode(archive));
      if (envelope is! Map<String, dynamic> ||
          envelope['format'] != _backupFormat ||
          envelope['schema'] != _backupSchema ||
          envelope['kdf'] != ScramAuthentication.kdfArgon ||
          envelope['cipher'] != _cipher ||
          envelope['content'] != 'device-state' ||
          envelope['media'] != 'descriptors-only') {
        throw const BackupRestoreException();
      }
      final backupIterations = envelope['iterations'];
      final backupMemoryKiB = envelope['memory_kib'];
      if (backupIterations is! int || backupMemoryKiB is! int) {
        throw const BackupRestoreException();
      }
      _validateBackupKdf(backupIterations, backupMemoryKiB);
      final salt = _readSalt(envelope['salt']);
      final ciphertext = _decodeCiphertext(envelope['ciphertext']);
      key = await _deriveBackupKey(
        recoveryPassphrase,
        salt,
        backupIterations: backupIterations,
        backupMemoryKiB: backupMemoryKiB,
      );
      final plaintext = SecretBox(key)
          .decrypt(EncryptedMessage.fromList(ciphertext));
      if (plaintext.length > _maximumEnvelopeBytes) {
        plaintext.fillRange(0, plaintext.length, 0);
        throw const BackupRestoreException();
      }
      return plaintext;
    } catch (error) {
      if (error is BackupRestoreException) rethrow;
      throw const BackupRestoreException();
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }

  Future<Uint8List> _deriveBackupKey(
    String passphrase,
    String salt, {
    required int backupIterations,
    required int backupMemoryKiB,
  }) async {
    final key = await keyDeriver.derive(
      password: passphrase,
      salt: salt,
      iterations: backupIterations,
      memoryKiB: backupMemoryKiB,
      timeout: derivationTimeout,
    );
    if (key.length != SecretBox.keyLength) {
      key.fillRange(0, key.length, 0);
      throw const BackupRestoreException();
    }
    return key;
  }

  static void _validateBackupKdf(int iterations, int memoryKiB) {
    if (iterations < 1 ||
        iterations > _maximumBackupIterations ||
        memoryKiB < _minimumBackupMemoryKiB ||
        memoryKiB > _maximumBackupMemoryKiB) {
      throw const BackupRestoreException();
    }
  }

  static void _validateRecoveryPassphrase(
    String passphrase, {
    required bool exporting,
  }) {
    final encoded = utf8.encode(passphrase);
    final valid = encoded.length >= 16 && encoded.length <= 1024;
    encoded.fillRange(0, encoded.length, 0);
    if (valid) return;
    if (exporting) throw const BackupExportException();
    throw const BackupRestoreException();
  }

  Future<T> _serializeOpen<T>(Future<T> Function() action) async {
    final previous = _openTail;
    final release = Completer<void>();
    _openTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}

final class _UnlockedDeviceVault implements DeviceTrustSession {
  _UnlockedDeviceVault({
    required this.storage,
    required this.storageKey,
    required this.endpointBinding,
    required this.username,
    required this.salt,
    required this.iterations,
    required this.memoryKiB,
    required Uint8List encryptionKey,
    required this.identity,
    required Map<String, _ContactVerification> verifications,
    required this._mailboxCursor,
    required List<LocalChatMessage> messages,
    required List<LocalChatGroup> groups,
    required List<OutboundChatMessage> outbox,
    required this._preferences,
    required this.backupEncoder,
  }) : _encryptionKey = Uint8List.fromList(encryptionKey),
       _verifications = Map<String, _ContactVerification>.of(verifications),
       _messages = List<LocalChatMessage>.of(messages),
       _groups = List<LocalChatGroup>.of(groups),
       _outbox = List<OutboundChatMessage>.of(outbox);

  final VaultStorage storage;
  final String storageKey;
  final String endpointBinding;
  final String username;
  final String salt;
  final int iterations;
  final int memoryKiB;
  final Uint8List _encryptionKey;
  final LocalDeviceIdentity identity;
  final Map<String, _ContactVerification> _verifications;
  int _mailboxCursor;
  final List<LocalChatMessage> _messages;
  final List<LocalChatGroup> _groups;
  final List<OutboundChatMessage> _outbox;
  LocalAppPreferences _preferences;
  final Future<Uint8List> Function(Uint8List plaintext, String passphrase)
  backupEncoder;
  Future<void> _writeTail = Future<void>.value();
  bool _disposed = false;
  bool _closing = false;

  @override
  DeviceEnrollment get enrollment {
    _ensureActive();
    return identity.enrollment(username);
  }

  @override
  String get deviceId {
    _ensureActive();
    return identity.deviceId;
  }

  @override
  String get safetyNumber {
    _ensureActive();
    return identity.ownSafetyNumber;
  }

  @override
  int get mailboxCursor {
    _ensureActive();
    return _mailboxCursor;
  }

  @override
  List<LocalChatMessage> get messages {
    _ensureActive();
    return List<LocalChatMessage>.unmodifiable(_messages);
  }

  @override
  List<LocalChatGroup> get groups {
    _ensureActive();
    return List<LocalChatGroup>.unmodifiable(_groups);
  }

  @override
  List<OutboundChatMessage> get outbox {
    _ensureActive();
    return List<OutboundChatMessage>.unmodifiable(_outbox);
  }

  @override
  LocalAppPreferences get preferences {
    _ensureActive();
    return _preferences;
  }

  @override
  Future<Uint8List> exportBackup({required String recoveryPassphrase}) {
    _ensureActive();
    return _serializeWrite(() async {
      final plaintext = _snapshotPlaintext(_preferences);
      try {
        return await backupEncoder(plaintext, recoveryPassphrase);
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    });
  }

  @override
  String safetyNumberFor(DeviceRecord contact) {
    _ensureActive();
    return identity.safetyNumberFor(username: username, contact: contact);
  }

  @override
  bool isVerified(DeviceRecord contact) {
    _ensureActive();
    if (contact.isRevoked) return false;
    final stored = _verifications[_verificationKey(contact)];
    return stored?.safetyNumber == safetyNumberFor(contact);
  }

  @override
  Future<void> markVerified(DeviceRecord contact) async {
    _ensureActive();
    if (contact.isRevoked) {
      throw const FormatException('Cannot verify a revoked device.');
    }
    _verifications[_verificationKey(contact)] = _ContactVerification(
      safetyNumber: safetyNumberFor(contact),
      verifiedAt: DateTime.now().toUtc(),
    );
    await persist();
  }

  @override
  WrappedConversationKey wrapConversationKey({
    required String conversationId,
    required DeviceRecord recipient,
    required Uint8List conversationKey,
  }) {
    _ensureActive();
    return identity.wrapConversationKey(
      username: username,
      conversationId: conversationId,
      recipient: recipient,
      conversationKey: conversationKey,
    );
  }

  @override
  OneTimeMessageConsumption signOneTimeConsumption(String messageId) {
    _ensureActive();
    return identity.signOneTimeConsumption(
      username: username,
      messageId: messageId,
    );
  }

  @override
  Uint8List unwrapConversationKey({
    required WrappedConversationKey envelope,
    required DeviceRecord sender,
    bool allowRevokedSender = false,
  }) {
    _ensureActive();
    return identity.unwrapConversationKey(
      username: username,
      envelope: envelope,
      sender: sender,
      allowRevokedSender: allowRevokedSender,
    );
  }

  @override
  Future<void> saveMailboxState({
    required int cursor,
    required List<LocalChatMessage> messages,
    List<LocalChatGroup>? groups,
    List<OutboundChatMessage>? outbox,
  }) async {
    _ensureActive();
    if (cursor < _mailboxCursor || cursor < 0 || messages.length > 5000) {
      throw const FormatException('Local mailbox state is invalid.');
    }
    for (final message in messages) {
      message.validate();
    }
    final nextGroups = groups ?? _groups;
    final nextOutbox = outbox ?? _outbox;
    _validateGroups(nextGroups);
    _validateOutbox(nextOutbox, messages);
    _mailboxCursor = cursor;
    _messages
      ..clear()
      ..addAll(messages);
    if (groups != null) {
      _groups
        ..clear()
        ..addAll(groups);
    }
    if (outbox != null) {
      _outbox
        ..clear()
        ..addAll(outbox);
    }
    await persist();
  }

  @override
  Future<void> savePreferences(LocalAppPreferences preferences) {
    _ensureActive();
    return _serializeWrite(() async {
      await _writeSnapshot(preferences);
      _preferences = preferences;
    });
  }

  Future<void> persist() {
    _ensureActive();
    return _serializeWrite(() => _writeSnapshot(_preferences));
  }

  Future<void> _writeSnapshot(LocalAppPreferences preferences) async {
    final plaintext = _snapshotPlaintext(preferences);
    final box = SecretBox(_encryptionKey);
    try {
      final ciphertext = box.encrypt(plaintext).asTypedList;
      final envelope = jsonEncode({
        'schema': EncryptedDeviceVault._schema,
        'kdf': ScramAuthentication.kdfArgon,
        'iterations': iterations,
        'memory_kib': memoryKiB,
        'salt': salt,
        'cipher': EncryptedDeviceVault._cipher,
        'ciphertext': _encode(ciphertext),
      });
      if (utf8.encode(envelope).length >
          EncryptedDeviceVault._maximumEnvelopeBytes) {
        throw const FormatException('Encrypted vault is too large.');
      }
      await storage.write(storageKey, envelope);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Uint8List _snapshotPlaintext(LocalAppPreferences preferences) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': EncryptedDeviceVault._schema,
          'endpoint': endpointBinding,
          'username': username,
          'identity': identity.toJson(),
          'verifications': _verifications.map(
            (key, value) => MapEntry(key, value.toJson()),
          ),
          'groups': _groups
              .map((group) => group.toJson())
              .toList(growable: false),
          'outbox': _outbox
              .map((message) => message.toJson())
              .toList(growable: false),
          'preferences': preferences.toJson(),
          'mailbox': {
            'cursor': _mailboxCursor,
            'messages': _messages
                .map((message) => message.toJson())
                .toList(growable: false),
          },
        }),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed || _closing) return;
    _closing = true;
    try {
      await _writeTail;
    } finally {
      _disposed = true;
      identity.dispose();
      _encryptionKey.fillRange(0, _encryptionKey.length, 0);
      _verifications.clear();
      _messages.clear();
      _groups.clear();
      _outbox.clear();
    }
  }

  Future<T> _serializeWrite<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final release = Completer<void>();
    _writeTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  void _ensureActive() {
    if (_disposed || _closing) {
      throw StateError('Encrypted device vault is closed.');
    }
  }
}

final class _ContactVerification {
  const _ContactVerification({
    required this.safetyNumber,
    required this.verifiedAt,
  });

  final String safetyNumber;
  final DateTime verifiedAt;

  Map<String, dynamic> toJson() => {
    'safety_number': safetyNumber,
    'verified_at': verifiedAt.toIso8601String(),
  };

  factory _ContactVerification.fromJson(Map<String, dynamic> value) {
    final safetyNumber = value['safety_number'];
    final verifiedAt = DateTime.tryParse(value['verified_at'] as String? ?? '');
    if (safetyNumber is! String ||
        safetyNumber.isEmpty ||
        verifiedAt == null ||
        !verifiedAt.isUtc) {
      throw const FormatException('Contact verification is invalid.');
    }
    return _ContactVerification(
      safetyNumber: safetyNumber,
      verifiedAt: verifiedAt,
    );
  }
}

final class VaultUnlockException implements Exception {
  const VaultUnlockException();

  @override
  String toString() => 'Could not unlock encrypted device storage.';
}

final class BackupExportException implements Exception {
  const BackupExportException();

  @override
  String toString() => 'Could not create the encrypted device backup.';
}

final class BackupRestoreException implements Exception {
  const BackupRestoreException();

  @override
  String toString() => 'Could not restore the encrypted device backup.';
}

(int, List<LocalChatMessage>) _readMailbox(Object? value) {
  if (value == null) return (0, const []);
  if (value is! Map<String, dynamic> ||
      value['cursor'] is! int ||
      (value['cursor'] as int) < 0 ||
      value['messages'] is! List) {
    throw const FormatException('Encrypted mailbox state is invalid.');
  }
  final rawMessages = value['messages'] as List;
  if (rawMessages.length > 5000) {
    throw const FormatException('Encrypted mailbox state is too large.');
  }
  final messages = rawMessages
      .map((raw) {
        if (raw is! Map) {
          throw const FormatException('Encrypted mailbox entry is invalid.');
        }
        return LocalChatMessage.fromJson(Map<String, dynamic>.from(raw));
      })
      .toList(growable: false);
  final ids = <String>{};
  for (final message in messages) {
    if (!ids.add(message.messageId)) {
      throw const FormatException(
        'Encrypted mailbox contains duplicate messages.',
      );
    }
  }
  return (value['cursor'] as int, messages);
}

List<OutboundChatMessage> _readOutbox(
  Object? value,
  List<LocalChatMessage> messages,
) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Encrypted outbox state is invalid.');
  }
  final outbox = value
      .map((raw) {
        if (raw is! Map) {
          throw const FormatException('Encrypted outbox entry is invalid.');
        }
        return OutboundChatMessage.fromJson(Map<String, dynamic>.from(raw));
      })
      .toList(growable: false);
  _validateOutbox(outbox, messages);
  return outbox;
}

void _validateOutbox(
  List<OutboundChatMessage> outbox,
  List<LocalChatMessage> messages,
) {
  if (outbox.length > OutboundChatMessage.maxEntries) {
    throw const FormatException('Encrypted outbox state is too large.');
  }
  final ids = messages.map((message) => message.messageId).toSet();
  for (final message in outbox) {
    message.validate();
    if (!ids.add(message.envelope.messageId)) {
      throw const FormatException(
        'Encrypted mailbox and outbox contain duplicate messages.',
      );
    }
  }
}

List<LocalChatGroup> _readGroups(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Encrypted group state is invalid.');
  }
  final groups = value
      .map((raw) {
        if (raw is! Map) {
          throw const FormatException('Encrypted group entry is invalid.');
        }
        return LocalChatGroup.fromJson(Map<String, dynamic>.from(raw));
      })
      .toList(growable: false);
  _validateGroups(groups);
  return groups;
}

void _validateGroups(List<LocalChatGroup> groups) {
  if (groups.length > LocalChatGroup.maxGroups) {
    throw const FormatException('Encrypted group state is too large.');
  }
  final ids = <String>{};
  for (final group in groups) {
    group.validate();
    if (!ids.add(group.conversationId)) {
      throw const FormatException('Encrypted group state contains duplicates.');
    }
  }
}

Map<String, _ContactVerification> _readVerifications(Object? value) {
  if (value == null) return {};
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Contact verifications must be a map.');
  }
  return value.map((key, raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Contact verification entry is invalid.');
    }
    return MapEntry(key, _ContactVerification.fromJson(raw));
  });
}

String _verificationKey(DeviceRecord contact) =>
    '${contact.username}:${contact.deviceId}';

String _storageKey(String endpoint, String username) {
  final digest = sha256.convert(
    utf8.encode('wampapp-vault-storage-v1\n$endpoint\n$username'),
  );
  return 'wampapp.vault.${base64Url.encode(digest.bytes).replaceAll('=', '')}';
}

String _readSalt(Object? value) {
  if (value is! String) throw const FormatException('Vault salt is invalid.');
  try {
    final bytes = base64.decode(value);
    if (bytes.length != 16 || base64.encode(bytes) != value) {
      throw const FormatException();
    }
    return value;
  } on FormatException {
    throw const FormatException('Vault salt is invalid.');
  }
}

Uint8List _decodeCiphertext(Object? value) {
  if (value is! String || value.isEmpty || value.contains('=')) {
    throw const FormatException('Vault ciphertext is invalid.');
  }
  try {
    final bytes = base64Url.decode(
      value.padRight((value.length + 3) ~/ 4 * 4, '='),
    );
    if (bytes.length < EncryptedMessage.nonceLength + SecretBox.macBytes ||
        bytes.length > EncryptedDeviceVault._maximumEnvelopeBytes ||
        _encode(bytes) != value) {
      throw const FormatException();
    }
    return bytes;
  } on FormatException {
    throw const FormatException('Vault ciphertext is invalid.');
  }
}

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');
