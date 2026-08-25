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
  Set<String> get providers;

  Future<PlatformPushDeliveryResult> deliver({
    required String provider,
    required String token,
    required int cursor,
    bool present = false,
  });

  Future<void> close();
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
    this.maxPendingPresentationConversationsPerAccount = 64,
    this.deliveryTimeout = const Duration(seconds: 10),
    this.onBackgroundFailure,
  }) {
    if (maxPendingAccounts <= 0) {
      throw ArgumentError.value(maxPendingAccounts, 'maxPendingAccounts');
    }
    if (maxPendingPresentationConversationsPerAccount <= 0) {
      throw ArgumentError.value(
        maxPendingPresentationConversationsPerAccount,
        'maxPendingPresentationConversationsPerAccount',
      );
    }
    if (deliveryTimeout <= Duration.zero) {
      throw ArgumentError.value(deliveryTimeout, 'deliveryTimeout');
    }
  }

  final PlatformPushService service;
  final PlatformPushGateway gateway;
  final int maxPendingAccounts;
  final int maxPendingPresentationConversationsPerAccount;
  final Duration deliveryTimeout;
  final void Function(PlatformPushDispatchFailure failure)? onBackgroundFailure;
  final Map<String, _PendingPlatformPush> _pending =
      <String, _PendingPlatformPush>{};
  Future<void>? _drainFuture;
  bool _closed = false;

  void enqueue(
    int cursor,
    Iterable<String> usernames, {
    String? presentationConversationId,
    Iterable<String> presentationUsernames = const [],
  }) {
    if (_closed || cursor <= 0) return;
    final canPresent =
        presentationConversationId != null &&
        presentationConversationId.isNotEmpty &&
        presentationConversationId.length <=
            PlatformPushSubscriptionRequest.maxConversationIdLength;
    final normalizedPresentationUsernames = canPresent
        ? presentationUsernames
              .map(AccountRegistration.normalizeUsername)
              .toSet()
        : const <String>{};
    for (final value in usernames) {
      final username = AccountRegistration.normalizeUsername(value);
      if (username.isEmpty) continue;
      var pending = _pending[username];
      if (pending == null && _pending.length < maxPendingAccounts) {
        pending = _PendingPlatformPush(cursor);
        _pending[username] = pending;
      }
      if (pending != null) {
        if (cursor > pending.cursor) pending.cursor = cursor;
        if (canPresent && normalizedPresentationUsernames.contains(username)) {
          pending.addPresentationConversation(
            presentationConversationId,
            maxPendingPresentationConversationsPerAccount,
          );
        }
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
        final batch = Map<String, _PendingPlatformPush>.from(_pending);
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
          final pending = batch[subscription.username];
          if (pending == null) continue;
          final muted = subscription.mutedConversationIds.toSet();
          final present = pending.presentationConversationIds.any(
            (conversationId) => !muted.contains(conversationId),
          );
          PlatformPushDeliveryResult result;
          try {
            result = await gateway
                .deliver(
                  provider: subscription.provider,
                  token: subscription.token,
                  cursor: pending.cursor,
                  present: present,
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

final class _PendingPlatformPush {
  _PendingPlatformPush(this.cursor);

  int cursor;
  final Set<String> presentationConversationIds = <String>{};

  void addPresentationConversation(String conversationId, int maximum) {
    if (presentationConversationIds.length >= maximum) return;
    presentationConversationIds.add(conversationId);
  }
}
