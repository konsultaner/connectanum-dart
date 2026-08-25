import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class StoredPlatformPushSubscription {
  StoredPlatformPushSubscription({
    required String username,
    required this.deviceId,
    required String provider,
    required this.token,
    required DateTime registeredAt,
    required DateTime updatedAt,
  }) : username = AccountRegistration.normalizeUsername(username),
       provider = provider.trim().toLowerCase(),
       registeredAt = registeredAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    validate();
  }

  final String username;
  final String deviceId;
  final String provider;
  final String token;
  final DateTime registeredAt;
  final DateTime updatedAt;

  String get key => '$username\n$deviceId\n$provider';

  void validate() {
    if (username.isEmpty) {
      throw const FormatException('Push subscription username is required.');
    }
    PlatformPushSubscriptionRequest(
      deviceId: deviceId,
      provider: provider,
      token: token,
    ).validate();
    if (updatedAt.isBefore(registeredAt)) {
      throw const FormatException('Push update predates registration.');
    }
  }

  PlatformPushSubscriptionReceipt get receipt =>
      PlatformPushSubscriptionReceipt(
        deviceId: deviceId,
        provider: provider,
        registeredAt: registeredAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() {
    validate();
    return {
      'username': username,
      'device_id': deviceId,
      'provider': provider,
      'token': token,
      'registered_at': registeredAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory StoredPlatformPushSubscription.fromJson(Map<String, dynamic> value) {
    return StoredPlatformPushSubscription(
      username: _string(value['username'], 'username'),
      deviceId: _string(value['device_id'], 'device_id'),
      provider: _string(value['provider'], 'provider'),
      token: _string(value['token'], 'token'),
      registeredAt: _utcDate(value['registered_at'], 'registered_at'),
      updatedAt: _utcDate(value['updated_at'], 'updated_at'),
    );
  }
}

final class PushSubscriptionLimitExceeded implements Exception {
  const PushSubscriptionLimitExceeded();
}

final class PlatformPushSubscriptionStore {
  PlatformPushSubscriptionStore(
    String path, {
    this.maxSubscriptionsPerAccount = 32,
  }) : file = File(path) {
    if (maxSubscriptionsPerAccount <= 0 || maxSubscriptionsPerAccount > 256) {
      throw ArgumentError.value(
        maxSubscriptionsPerAccount,
        'maxSubscriptionsPerAccount',
      );
    }
  }

  final File file;
  final int maxSubscriptionsPerAccount;
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(const <StoredPlatformPushSubscription>[]);
        }
      });
    }
    await _restrictPermissions(file);
  }

  Future<StoredPlatformPushSubscription> upsert(
    String username,
    PlatformPushSubscriptionRequest request, {
    DateTime? now,
  }) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    request.validate();
    return _serializeWrite(() async {
      final subscriptions = await _readDocument();
      final key =
          '$normalizedUsername\n${request.deviceId}\n${request.provider}';
      final existingIndex = subscriptions.indexWhere((item) => item.key == key);
      final existing = existingIndex < 0 ? null : subscriptions[existingIndex];
      if (existing != null && existing.token == request.token) return existing;

      subscriptions.removeWhere(
        (item) =>
            item.provider == request.provider && item.token == request.token,
      );
      final accountCount = subscriptions
          .where(
            (item) => item.username == normalizedUsername && item.key != key,
          )
          .length;
      if (existing == null && accountCount >= maxSubscriptionsPerAccount) {
        throw const PushSubscriptionLimitExceeded();
      }
      subscriptions.removeWhere((item) => item.key == key);
      final timestamp = (now ?? DateTime.now()).toUtc();
      final updatedAt =
          existing != null && timestamp.isBefore(existing.registeredAt)
          ? existing.registeredAt
          : timestamp;
      final replacement = StoredPlatformPushSubscription(
        username: normalizedUsername,
        deviceId: request.deviceId,
        provider: request.provider,
        token: request.token,
        registeredAt: existing?.registeredAt ?? timestamp,
        updatedAt: updatedAt,
      );
      subscriptions.add(replacement);
      await _writeDocument(subscriptions);
      return replacement;
    });
  }

  Future<bool> remove(String username, PlatformPushSubscriptionKey key) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    key.validate();
    return _serializeWrite(() async {
      final subscriptions = await _readDocument();
      final before = subscriptions.length;
      subscriptions.removeWhere(
        (item) =>
            item.username == normalizedUsername &&
            item.deviceId == key.deviceId &&
            item.provider == key.provider,
      );
      if (subscriptions.length == before) return false;
      await _writeDocument(subscriptions);
      return true;
    });
  }

  Future<bool> removeIfCurrent(StoredPlatformPushSubscription expected) {
    return _serializeWrite(() async {
      final subscriptions = await _readDocument();
      final before = subscriptions.length;
      subscriptions.removeWhere(
        (item) => item.key == expected.key && item.token == expected.token,
      );
      if (subscriptions.length == before) return false;
      await _writeDocument(subscriptions);
      return true;
    });
  }

  Future<int> removeDevice(String username, String deviceId) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    return _serializeWrite(() async {
      final subscriptions = await _readDocument();
      final before = subscriptions.length;
      subscriptions.removeWhere(
        (item) =>
            item.username == normalizedUsername && item.deviceId == deviceId,
      );
      final removed = before - subscriptions.length;
      if (removed > 0) await _writeDocument(subscriptions);
      return removed;
    });
  }

  Future<List<StoredPlatformPushSubscription>> listForUsernames(
    Iterable<String> usernames,
  ) async {
    final allowed = usernames
        .map(AccountRegistration.normalizeUsername)
        .toSet();
    final subscriptions = await _serializeWrite(_readDocument);
    final selected =
        subscriptions.where((item) => allowed.contains(item.username)).toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    return List<StoredPlatformPushSubscription>.unmodifiable(selected);
  }

  Future<List<StoredPlatformPushSubscription>> _readDocument() async {
    if (!await file.exists()) return <StoredPlatformPushSubscription>[];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Unsupported push subscription schema.');
    }
    final raw = decoded['subscriptions'];
    if (raw is! List<dynamic>) {
      throw const FormatException('Push subscriptions must be a list.');
    }
    final result = <StoredPlatformPushSubscription>[];
    final keys = <String>{};
    final tokens = <String>{};
    for (final value in raw) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Push subscription entry must be a map.');
      }
      final subscription = StoredPlatformPushSubscription.fromJson(value);
      if (!keys.add(subscription.key) ||
          !tokens.add('${subscription.provider}\n${subscription.token}')) {
        throw const FormatException('Push subscriptions contain duplicates.');
      }
      result.add(subscription);
    }
    return result;
  }

  Future<void> _writeDocument(
    List<StoredPlatformPushSubscription> subscriptions,
  ) async {
    final sorted = subscriptions.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final document = jsonEncode({
      'schema': 1,
      'subscriptions': sorted.map((item) => item.toJson()).toList(),
    });
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(document, flush: true);
      await _restrictPermissions(temporary);
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

Future<void> _restrictPermissions(File target) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', target.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not restrict push subscription store permissions',
      target.path,
    );
  }
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

DateTime _utcDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be a UTC ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be a UTC ISO-8601 string.');
  }
  return parsed;
}
