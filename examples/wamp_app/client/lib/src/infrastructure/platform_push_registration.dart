import 'dart:async';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'platform_push_token_source.dart';

typedef RegisterPlatformPush = Future<PlatformPushSubscriptionReceipt> Function(
  PlatformPushSubscriptionRequest request,
);
typedef UnregisterPlatformPush = Future<bool> Function(
  PlatformPushSubscriptionKey key,
);

final class PlatformPushRegistrationCoordinator {
  PlatformPushRegistrationCoordinator({
    PlatformPushTokenSource? source,
    this.onError,
  }) : _source = source ?? const DisabledPlatformPushTokenSource();

  final PlatformPushTokenSource _source;
  final void Function(Object error)? onError;
  _PlatformPushBinding? _binding;
  List<String> _mutedConversationIds = const [];
  Future<void> _lifecycleTail = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  bool get hasActiveBinding => _binding != null;

  Future<void> replace({
    required String deviceId,
    required RegisterPlatformPush register,
    required UnregisterPlatformPush unregister,
    Iterable<String> mutedConversationIds = const [],
  }) {
    if (_disposed) return Future<void>.value();
    _mutedConversationIds = _normalizeMutedConversationIds(
      mutedConversationIds,
    );
    final generation = ++_generation;
    return _enqueueLifecycle(
      () => _replace(
        generation: generation,
        deviceId: deviceId,
        register: register,
        unregister: unregister,
      ),
    );
  }

  Future<void> _replace({
    required int generation,
    required String deviceId,
    required RegisterPlatformPush register,
    required UnregisterPlatformPush unregister,
  }) async {
    if (_disposed || generation != _generation) return;
    await _closeCurrentBinding();
    if (_disposed || generation != _generation) return;

    PlatformPushTokenSession? session;
    try {
      session = await _source.open();
    } catch (error) {
      if (!_disposed && generation == _generation) _report(error);
      return;
    }
    if (session == null) return;
    if (_disposed || generation != _generation) {
      await _closeSession(session);
      return;
    }

    final binding = _PlatformPushBinding(
      session: session,
      deviceId: deviceId,
      register: register,
      unregister: unregister,
      onError: _report,
      mutedConversationIds: _mutedConversationIds,
    );
    _binding = binding;
    binding.start();
  }

  Future<void> updateMutedConversationIds(Iterable<String> values) {
    if (_disposed) return Future<void>.value();
    final normalized = _normalizeMutedConversationIds(values);
    if (_listsEqual(_mutedConversationIds, normalized)) {
      return Future<void>.value();
    }
    _mutedConversationIds = normalized;
    return _enqueueLifecycle(() async {
      if (_disposed || !_listsEqual(_mutedConversationIds, normalized)) return;
      await _binding?.updateMutedConversationIds(normalized);
    });
  }

  Future<void> clear() async {
    if (_disposed) return;
    _generation += 1;
    await _enqueueLifecycle(_closeCurrentBinding);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _enqueueLifecycle(() async {
      await _closeCurrentBinding();
      try {
        await _source.dispose();
      } catch (error) {
        _report(error);
      }
    });
  }

  Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final result = _lifecycleTail.then((_) => operation());
    _lifecycleTail = result.catchError((Object error) => _report(error));
    return result;
  }

  Future<void> _closeCurrentBinding() async {
    final binding = _binding;
    _binding = null;
    if (binding == null) return;
    try {
      await binding.close();
    } catch (error) {
      _report(error);
    }
  }

  Future<void> _closeSession(PlatformPushTokenSession session) async {
    try {
      await session.close();
    } catch (error) {
      _report(error);
    }
  }

  void _report(Object error) => onError?.call(error);
}

final class _PlatformPushBinding {
  _PlatformPushBinding({
    required this.session,
    required this.deviceId,
    required this.register,
    required this.unregister,
    required this.onError,
    required this._mutedConversationIds,
  });

  final PlatformPushTokenSession session;
  final String deviceId;
  final RegisterPlatformPush register;
  final UnregisterPlatformPush unregister;
  final void Function(Object error) onError;
  StreamSubscription<PlatformPushToken>? _subscription;
  PlatformPushSubscriptionKey? _registeredKey;
  PlatformPushToken? _latestToken;
  List<String> _mutedConversationIds;
  Future<void> _registrationTail = Future<void>.value();
  bool _active = true;

  void start() {
    _subscription = session.tokens.listen(
      _enqueue,
      onError: (Object error) {
        if (_active) onError(error);
      },
    );
  }

  void _enqueue(PlatformPushToken token) {
    if (!_active) return;
    _latestToken = token;
    _registrationTail = _registrationTail.then((_) => _register(token));
  }

  Future<void> updateMutedConversationIds(List<String> values) {
    if (!_active || _listsEqual(_mutedConversationIds, values)) {
      return Future<void>.value();
    }
    _mutedConversationIds = values;
    final token = _latestToken;
    if (token == null) return Future<void>.value();
    final registration = _registrationTail.then((_) => _register(token));
    _registrationTail = registration;
    return registration;
  }

  Future<void> _register(PlatformPushToken token) async {
    if (!_active) return;
    try {
      token.validate();
      final request = PlatformPushSubscriptionRequest(
        deviceId: deviceId,
        provider: token.provider,
        token: token.token,
        mutedConversationIds: _mutedConversationIds,
      );
      final receipt = await register(request);
      final nextKey = PlatformPushSubscriptionKey(
        deviceId: request.deviceId,
        provider: request.provider,
      );
      if (receipt.deviceId != nextKey.deviceId ||
          receipt.provider != nextKey.provider) {
        await _remove(nextKey);
        throw const FormatException(
          'The server returned a conflicting push registration receipt.',
        );
      }
      if (!_active) {
        await _remove(nextKey);
        return;
      }
      final previousKey = _registeredKey;
      _registeredKey = nextKey;
      if (previousKey != null &&
          (previousKey.deviceId != nextKey.deviceId ||
              previousKey.provider != nextKey.provider)) {
        await _remove(previousKey);
      }
    } catch (error) {
      onError(error);
    }
  }

  Future<void> close() async {
    if (!_active) return;
    _active = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) await subscription.cancel();
    await session.close();
    await _registrationTail;
    final registeredKey = _registeredKey;
    _registeredKey = null;
    if (registeredKey != null) await _remove(registeredKey);
  }

  Future<void> _remove(PlatformPushSubscriptionKey key) async {
    try {
      await unregister(key);
    } catch (error) {
      onError(error);
    }
  }
}

List<String> _normalizeMutedConversationIds(Iterable<String> values) {
  final result = values.toList(growable: false);
  if (result.length > PlatformPushSubscriptionRequest.maxMutedConversations) {
    throw const FormatException('Too many muted conversations are registered.');
  }
  final unique = result.toSet();
  if (unique.length != result.length) {
    throw const FormatException(
      'Muted conversation identifiers must be unique.',
    );
  }
  for (final conversationId in result) {
    if (conversationId.isEmpty ||
        conversationId.length >
            PlatformPushSubscriptionRequest.maxConversationIdLength) {
      throw const FormatException(
        'A muted conversation identifier is invalid.',
      );
    }
  }
  result.sort();
  return List<String>.unmodifiable(result);
}

bool _listsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
