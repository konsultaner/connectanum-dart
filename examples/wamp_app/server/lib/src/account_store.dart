import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    Map<String, DeviceRecord> devices = const {},
  }) : devices = Map<String, DeviceRecord>.unmodifiable(devices);

  final String username;
  final String displayName;
  final String storedKey;
  final String serverKey;
  final String salt;
  final int iterations;
  final int memoryKiB;
  final String kdf;
  final DateTime createdAt;
  final Map<String, DeviceRecord> devices;

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
    devices: value,
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
}

class AccountAlreadyExists implements Exception {
  const AccountAlreadyExists(this.username);

  final String username;

  @override
  String toString() => 'Account $username already exists.';
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
