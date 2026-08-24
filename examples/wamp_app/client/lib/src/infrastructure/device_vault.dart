import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectanum_core/authentication.dart';
import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_chat_message.dart';
import 'local_device_identity.dart';
import 'vault_storage.dart';

abstract interface class DeviceTrustStore {
  Future<DeviceTrustSession> openOrCreate({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String deviceName,
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
  Future<void> saveMailboxState({
    required int cursor,
    required List<LocalChatMessage> messages,
  });
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
  }) : _encryptionKey = Uint8List.fromList(encryptionKey),
       _verifications = Map<String, _ContactVerification>.of(verifications),
       _messages = List<LocalChatMessage>.of(messages);

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
  }) async {
    _ensureActive();
    if (cursor < _mailboxCursor || cursor < 0 || messages.length > 5000) {
      throw const FormatException('Local mailbox state is invalid.');
    }
    for (final message in messages) {
      message.validate();
    }
    _mailboxCursor = cursor;
    _messages
      ..clear()
      ..addAll(messages);
    await persist();
  }

  Future<void> persist() {
    _ensureActive();
    return _serializeWrite(() async {
      final plaintext = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': EncryptedDeviceVault._schema,
            'endpoint': endpointBinding,
            'username': username,
            'identity': identity.toJson(),
            'verifications': _verifications.map(
              (key, value) => MapEntry(key, value.toJson()),
            ),
            'mailbox': {
              'cursor': _mailboxCursor,
              'messages': _messages
                  .map((message) => message.toJson())
                  .toList(growable: false),
            },
          }),
        ),
      );
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
        await storage.write(storageKey, envelope);
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    });
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
