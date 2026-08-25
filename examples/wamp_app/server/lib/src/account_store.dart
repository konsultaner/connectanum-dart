import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

class StoredAccount {
  StoredAccount({
    required this.username,
    required this.displayName,
    required this.storedKey,
    required this.serverKey,
    required this.salt,
    required this.iterations,
    required this.memoryKiB,
    required this.kdf,
    required this.createdAt,
    this.profileStatus = '',
    this.profileRevision = 0,
    DateTime? profileUpdatedAt,
    Uint8List? profileAvatarBytes,
    this.profileAvatarContentType,
    Map<String, DeviceRecord> devices = const {},
  }) : profileUpdatedAt = (profileUpdatedAt ?? createdAt).toUtc(),
       profileAvatarBytes = profileAvatarBytes == null
           ? null
           : Uint8List.fromList(profileAvatarBytes),
       devices = Map<String, DeviceRecord>.unmodifiable(devices) {
    profile.validate();
  }

  final String username;
  final String displayName;
  final String storedKey;
  final String serverKey;
  final String salt;
  final int iterations;
  final int memoryKiB;
  final String kdf;
  final DateTime createdAt;
  final String profileStatus;
  final int profileRevision;
  final DateTime profileUpdatedAt;
  final Uint8List? profileAvatarBytes;
  final String? profileAvatarContentType;
  final Map<String, DeviceRecord> devices;

  String? get _encodedProfileAvatar => switch (profileAvatarBytes) {
    final bytes? => base64.encode(bytes),
    null => null,
  };

  AccountProfile get profile => AccountProfile(
    username: username,
    displayName: displayName,
    status: profileStatus,
    revision: profileRevision,
    updatedAt: profileUpdatedAt,
    avatarBytes: profileAvatarBytes,
    avatarContentType: profileAvatarContentType,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'stored_key': storedKey,
    'server_key': serverKey,
    'salt': salt,
    'iterations': iterations,
    'memory_kib': memoryKiB,
    'kdf': kdf,
    'created_at': createdAt.toUtc().toIso8601String(),
    'profile_status': profileStatus,
    'profile_revision': profileRevision,
    'profile_updated_at': profileUpdatedAt.toIso8601String(),
    'profile_avatar': ?_encodedProfileAvatar,
    'profile_avatar_content_type': ?profileAvatarContentType,
    'devices': devices.map(
      (deviceId, device) => MapEntry(deviceId, device.toWampKeywords()),
    ),
  };

  StoredAccount withDevices(Map<String, DeviceRecord> value) => StoredAccount(
    username: username,
    displayName: displayName,
    storedKey: storedKey,
    serverKey: serverKey,
    salt: salt,
    iterations: iterations,
    memoryKiB: memoryKiB,
    kdf: kdf,
    createdAt: createdAt,
    profileStatus: profileStatus,
    profileRevision: profileRevision,
    profileUpdatedAt: profileUpdatedAt,
    profileAvatarBytes: profileAvatarBytes,
    profileAvatarContentType: profileAvatarContentType,
    devices: value,
  );

  StoredAccount withProfile(
    AccountProfileUpdate update, {
    required DateTime updatedAt,
  }) => StoredAccount(
    username: username,
    displayName: update.displayName,
    storedKey: storedKey,
    serverKey: serverKey,
    salt: salt,
    iterations: iterations,
    memoryKiB: memoryKiB,
    kdf: kdf,
    createdAt: createdAt,
    profileStatus: update.status,
    profileRevision: profileRevision + 1,
    profileUpdatedAt: updatedAt,
    profileAvatarBytes: switch (update.avatarAction) {
      ProfileAvatarAction.keep => profileAvatarBytes,
      ProfileAvatarAction.set => update.avatarBytes,
      ProfileAvatarAction.remove => null,
    },
    profileAvatarContentType: switch (update.avatarAction) {
      ProfileAvatarAction.keep => profileAvatarContentType,
      ProfileAvatarAction.set => update.avatarContentType,
      ProfileAvatarAction.remove => null,
    },
    devices: devices,
  );

  factory StoredAccount.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (json case {
      'username': final String username,
      'display_name': final String displayName,
      'stored_key': final String storedKey,
      'server_key': final String serverKey,
      'salt': final String salt,
      'iterations': final int iterations,
      'memory_kib': final int memoryKiB,
      'kdf': final String kdf,
    } when createdAt != null) {
      final profileStatus = _readOptionalString(
        json['profile_status'],
        'profile_status',
      );
      final profileRevision = _readOptionalInt(
        json['profile_revision'],
        'profile_revision',
      );
      final profileUpdatedAt = _readOptionalDateTime(
        json['profile_updated_at'],
        'profile_updated_at',
      );
      final profileAvatarBytes = _readOptionalAvatar(json['profile_avatar']);
      final profileAvatarContentType = _readOptionalString(
        json['profile_avatar_content_type'],
        'profile_avatar_content_type',
      );
      final devices = _readDevices(json['devices'], username);
      return StoredAccount(
        username: username,
        displayName: displayName,
        storedKey: storedKey,
        serverKey: serverKey,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        kdf: kdf,
        createdAt: createdAt.toUtc(),
        profileStatus: profileStatus ?? '',
        profileRevision: profileRevision ?? 0,
        profileUpdatedAt: profileUpdatedAt ?? createdAt,
        profileAvatarBytes: profileAvatarBytes,
        profileAvatarContentType: profileAvatarContentType,
        devices: devices,
      );
    }
    throw const FormatException('Account store contains an invalid account.');
  }

  static Map<String, DeviceRecord> _readDevices(
    Object? value,
    String username,
  ) {
    if (value == null) return const {};
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Account devices must be a map.');
    }
    return value.map((deviceId, rawDevice) {
      if (rawDevice is! Map<String, dynamic>) {
        throw const FormatException('Account device entry must be a map.');
      }
      final device = DeviceRecord.fromWampKeywords(rawDevice);
      if (deviceId != device.deviceId || device.username != username) {
        throw const FormatException(
          'Account device key or username does not match its record.',
        );
      }
      return MapEntry(deviceId, device);
    });
  }

  static String? _readOptionalString(Object? value, String field) {
    if (value == null || value is String) return value as String?;
    throw FormatException('$field must be a string.');
  }

  static int? _readOptionalInt(Object? value, String field) {
    if (value == null || value is int) return value as int?;
    throw FormatException('$field must be an integer.');
  }

  static DateTime? _readOptionalDateTime(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$field must be a string.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$field must be a date-time.');
    return parsed.toUtc();
  }

  static Uint8List? _readOptionalAvatar(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('profile_avatar must be base64 text.');
    }
    final maximumEncodedLength =
        ((AccountProfileLimits.maxAvatarBytes + 2) ~/ 3) * 4;
    if (value.length > maximumEncodedLength) {
      throw const FormatException('Stored profile avatar is too large.');
    }
    try {
      final decoded = base64.decode(value);
      if (decoded.length > AccountProfileLimits.maxAvatarBytes) {
        throw const FormatException('Stored profile avatar is too large.');
      }
      return decoded;
    } on FormatException {
      throw const FormatException('Stored profile avatar is invalid.');
    }
  }
}

class AccountAlreadyExists implements Exception {
  const AccountAlreadyExists(this.username);

  final String username;

  @override
  String toString() => 'Account $username already exists.';
}

class ProfileNotFound implements Exception {
  const ProfileNotFound(this.username);

  final String username;
}

class ProfileConflict implements Exception {
  const ProfileConflict(this.currentRevision);

  final int currentRevision;
}

class DeviceConflict implements Exception {
  const DeviceConflict(this.deviceId);

  final String deviceId;
}

class DeviceNotFound implements Exception {
  const DeviceNotFound(this.deviceId);

  final String deviceId;
}

class DeviceRevoked implements Exception {
  const DeviceRevoked(this.deviceId);

  final String deviceId;
}

class DeviceLimitExceeded implements Exception {
  const DeviceLimitExceeded();
}

class AccountStore {
  AccountStore(String path) : file = File(path);

  static const maxDevicesPerAccount = 64;

  final File file;
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(const <String, StoredAccount>{});
        }
      });
    }
  }

  Future<StoredAccount?> find(String username) async {
    final accounts = await _readDocument();
    return accounts[username];
  }

  Future<void> create(StoredAccount account) {
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      if (accounts.containsKey(account.username)) {
        throw AccountAlreadyExists(account.username);
      }
      await _writeDocument({...accounts, account.username: account});
    });
  }

  Future<AccountProfile> getProfile(String username) async {
    final normalized = AccountRegistration.normalizeUsername(username);
    final account = await find(normalized);
    if (account == null) throw ProfileNotFound(normalized);
    return account.profile;
  }

  Future<AccountProfile> updateProfile(
    String username,
    AccountProfileUpdate update, {
    DateTime? now,
  }) {
    update.validate();
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      final normalized = AccountRegistration.normalizeUsername(username);
      final account = accounts[normalized];
      if (account == null) throw ProfileNotFound(normalized);
      if (account.profileRevision != update.expectedRevision ||
          account.profileRevision >= AccountProfileLimits.maxRevision) {
        throw ProfileConflict(account.profileRevision);
      }
      final observedAt = (now ?? DateTime.now()).toUtc();
      final updatedAt = observedAt.isBefore(account.profileUpdatedAt)
          ? account.profileUpdatedAt
          : observedAt;
      final updated = account.withProfile(update, updatedAt: updatedAt);
      await _writeDocument({...accounts, normalized: updated});
      return updated.profile;
    });
  }

  Future<DeviceRecord> enrollDevice(
    String username,
    DeviceEnrollment enrollment, {
    DateTime? now,
  }) {
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      final account = accounts[username];
      if (account == null) throw StateError('Account no longer exists.');
      final observedAt = (now ?? DateTime.now()).toUtc();
      final existing = account.devices[enrollment.deviceId];
      if (existing != null) {
        if (existing.isRevoked) throw DeviceRevoked(enrollment.deviceId);
        if (!_sameEnrollment(existing.enrollment, enrollment)) {
          throw DeviceConflict(enrollment.deviceId);
        }
        final lastSeenAt = observedAt.isBefore(existing.lastSeenAt)
            ? existing.lastSeenAt
            : observedAt;
        final refreshed = DeviceRecord(
          username: username,
          enrollment: existing.enrollment,
          enrolledAt: existing.enrolledAt,
          lastSeenAt: lastSeenAt,
        );
        await _replaceAccountDevice(accounts, account, refreshed);
        return refreshed;
      }
      if (account.devices.length >= maxDevicesPerAccount) {
        throw const DeviceLimitExceeded();
      }
      final device = DeviceRecord(
        username: username,
        enrollment: enrollment,
        enrolledAt: observedAt,
        lastSeenAt: observedAt,
      );
      await _replaceAccountDevice(accounts, account, device);
      return device;
    });
  }

  Future<List<DeviceRecord>> listDevices(
    String username, {
    bool includeRevoked = false,
  }) async {
    final account = await find(username);
    if (account == null) throw StateError('Account no longer exists.');
    final devices =
        account.devices.values
            .where((device) => includeRevoked || !device.isRevoked)
            .toList()
          ..sort((left, right) => left.enrolledAt.compareTo(right.enrolledAt));
    return List<DeviceRecord>.unmodifiable(devices);
  }

  Future<Map<String, List<DeviceRecord>>> listActiveDeviceSnapshot(
    Iterable<String> usernames,
  ) {
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      final result = <String, List<DeviceRecord>>{};
      for (final value in usernames) {
        final username = AccountRegistration.normalizeUsername(value);
        final account = accounts[username];
        if (account == null) throw StateError('Account no longer exists.');
        final devices =
            account.devices.values.where((device) => !device.isRevoked).toList()
              ..sort(
                (left, right) => left.enrolledAt.compareTo(right.enrolledAt),
              );
        result[username] = List<DeviceRecord>.unmodifiable(devices);
      }
      return Map<String, List<DeviceRecord>>.unmodifiable(result);
    });
  }

  Future<DeviceRecord> revokeDevice(
    String username,
    String deviceId, {
    DateTime? now,
  }) {
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      final account = accounts[username];
      if (account == null) throw StateError('Account no longer exists.');
      final existing = account.devices[deviceId];
      if (existing == null) throw DeviceNotFound(deviceId);
      if (existing.isRevoked) return existing;
      final requestedRevocation = (now ?? DateTime.now()).toUtc();
      final revokedAt = requestedRevocation.isBefore(existing.enrolledAt)
          ? existing.enrolledAt
          : requestedRevocation;
      final revoked = DeviceRecord(
        username: username,
        enrollment: existing.enrollment,
        enrolledAt: existing.enrolledAt,
        lastSeenAt: existing.lastSeenAt,
        revokedAt: revokedAt,
      );
      await _replaceAccountDevice(accounts, account, revoked);
      return revoked;
    });
  }

  Future<void> _replaceAccountDevice(
    Map<String, StoredAccount> accounts,
    StoredAccount account,
    DeviceRecord device,
  ) {
    return _writeDocument({
      ...accounts,
      account.username: account.withDevices({
        ...account.devices,
        device.deviceId: device,
      }),
    });
  }

  Future<Map<String, StoredAccount>> _readDocument() async {
    if (!await file.exists()) return <String, StoredAccount>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Unsupported account store schema.');
    }
    final rawAccounts = decoded['accounts'];
    if (rawAccounts is! Map<String, dynamic>) {
      throw const FormatException('Account store accounts must be a map.');
    }
    return rawAccounts.map((username, value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Account store entry must be a map.');
      }
      final account = StoredAccount.fromJson(value);
      if (username != account.username) {
        throw const FormatException(
          'Account store key does not match username.',
        );
      }
      return MapEntry(username, account);
    });
  }

  Future<void> _writeDocument(Map<String, StoredAccount> accounts) async {
    final document = jsonEncode({
      'schema': 1,
      'accounts': accounts.map(
        (username, account) => MapEntry(username, account.toJson()),
      ),
    });
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(document, flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', temporary.path]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Could not restrict account store permissions',
            temporary.path,
          );
        }
      }
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
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
}

bool _sameEnrollment(DeviceEnrollment left, DeviceEnrollment right) {
  return left.deviceId == right.deviceId &&
      left.deviceName == right.deviceName &&
      left.signingPublicKey == right.signingPublicKey &&
      left.exchangePublicKey == right.exchangePublicKey &&
      left.attestation == right.attestation &&
      left.createdAt == right.createdAt;
}
