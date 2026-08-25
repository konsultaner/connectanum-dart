import 'dart:async';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';
import 'push_subscription_store.dart';

enum PlatformPushDeliveryResult { accepted, invalidToken, retryableFailure }

enum PlatformPushDispatchFailure {
  subscriptionLookup,
  delivery,
  tokenRetirement,
}

abstract interface class PlatformPushGateway {
  Future<PlatformPushDeliveryResult> deliver({
    required String provider,
    required String token,
    required int cursor,
  });
}

final class PlatformPushService {
  const PlatformPushService({required this.accounts, required this.store});

  final AccountStore accounts;
  final PlatformPushSubscriptionStore store;

  Future<PlatformPushSubscriptionReceipt> register(
    String username,
    PlatformPushSubscriptionRequest request,
  ) async {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final devices = await accounts.listDevices(
      normalizedUsername,
      includeRevoked: true,
    );
    final device = devices
        .where((item) => item.deviceId == request.deviceId)
        .firstOrNull;
    if (device == null) throw DeviceNotFound(request.deviceId);
    if (device.isRevoked) throw DeviceRevoked(request.deviceId);
    return (await store.upsert(normalizedUsername, request)).receipt;
  }

  Future<bool> unregister(
    String username,
    PlatformPushSubscriptionKey key,
  ) async {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final devices = await accounts.listDevices(
      normalizedUsername,
      includeRevoked: true,
    );
    final device = devices
        .where((item) => item.deviceId == key.deviceId)
        .firstOrNull;
    if (device == null) throw DeviceNotFound(key.deviceId);
    return store.remove(normalizedUsername, key);
  }

  Future<void> deviceRevoked(String username, String deviceId) async {
    await store.removeDevice(username, deviceId);
  }

  Future<List<StoredPlatformPushSubscription>> activeSubscriptions(
    Iterable<String> usernames,
  ) async {
    final normalized = usernames
        .map(AccountRegistration.normalizeUsername)
        .toSet();
    final active = await accounts.listActiveDeviceSnapshot(normalized);
    final activeKeys = <String>{
      for (final entry in active.entries)
        for (final device in entry.value) '${entry.key}\n${device.deviceId}',
    };
    final subscriptions = await store.listForUsernames(normalized);
    final result = <StoredPlatformPushSubscription>[];
    for (final subscription in subscriptions) {
      if (activeKeys.contains(
        '${subscription.username}\n${subscription.deviceId}',
      )) {
        result.add(subscription);
      } else {
        await store.removeIfCurrent(subscription);
      }
    }
    return List<StoredPlatformPushSubscription>.unmodifiable(result);
  }
}

final class PlatformPushDispatcher {
  PlatformPushDispatcher({
    required this.service,
    required this.gateway,
    this.maxPendingAccounts = 10000,
    this.deliveryTimeout = const Duration(seconds: 10),
    this.onBackgroundFailure,
  }) {
    if (maxPendingAccounts <= 0) {
      throw ArgumentError.value(maxPendingAccounts, 'maxPendingAccounts');
    }
    if (deliveryTimeout <= Duration.zero) {
      throw ArgumentError.value(deliveryTimeout, 'deliveryTimeout');
    }
  }

  final PlatformPushService service;
  final PlatformPushGateway gateway;
  final int maxPendingAccounts;
  final Duration deliveryTimeout;
  final void Function(PlatformPushDispatchFailure failure)? onBackgroundFailure;
  final Map<String, int> _pending = <String, int>{};
  Future<void>? _drainFuture;
  bool _closed = false;

  void enqueue(int cursor, Iterable<String> usernames) {
    if (_closed || cursor <= 0) return;
    for (final value in usernames) {
      final username = AccountRegistration.normalizeUsername(value);
      if (username.isEmpty) continue;
      final previous = _pending[username];
      if (previous != null || _pending.length < maxPendingAccounts) {
        if (previous == null || cursor > previous) _pending[username] = cursor;
      }
    }
    _drainFuture ??= _drain();
  }

  Future<void> close() async {
    _closed = true;
    await _drainFuture;
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final batch = Map<String, int>.from(_pending);
        _pending.clear();
        List<StoredPlatformPushSubscription> subscriptions;
        try {
          subscriptions = await service.activeSubscriptions(batch.keys);
        } catch (_) {
          onBackgroundFailure?.call(
            PlatformPushDispatchFailure.subscriptionLookup,
          );
          continue;
        }
        for (final subscription in subscriptions) {
          final cursor = batch[subscription.username];
          if (cursor == null) continue;
          PlatformPushDeliveryResult result;
          try {
            result = await gateway
                .deliver(
                  provider: subscription.provider,
                  token: subscription.token,
                  cursor: cursor,
                )
                .timeout(deliveryTimeout);
          } catch (_) {
            onBackgroundFailure?.call(PlatformPushDispatchFailure.delivery);
            continue;
          }
          if (result == PlatformPushDeliveryResult.retryableFailure) {
            onBackgroundFailure?.call(PlatformPushDispatchFailure.delivery);
          } else if (result == PlatformPushDeliveryResult.invalidToken) {
            try {
              await service.store.removeIfCurrent(subscription);
            } catch (_) {
              onBackgroundFailure?.call(
                PlatformPushDispatchFailure.tokenRetirement,
              );
            }
          }
        }
      }
    } finally {
      _drainFuture = null;
      if (!_closed && _pending.isNotEmpty) _drainFuture = _drain();
    }
  }
}
