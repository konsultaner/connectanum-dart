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
  Future<void> _lifecycleTail = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  bool get hasActiveBinding => _binding != null;

  Future<void> replace({
    required String deviceId,
    required RegisterPlatformPush register,
    required UnregisterPlatformPush unregister,
  }) {
    if (_disposed) return Future<void>.value();
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
    );
    _binding = binding;
    binding.start();
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
  });

  final PlatformPushTokenSession session;
  final String deviceId;
  final RegisterPlatformPush register;
  final UnregisterPlatformPush unregister;
  final void Function(Object error) onError;
  StreamSubscription<PlatformPushToken>? _subscription;
  PlatformPushSubscriptionKey? _registeredKey;
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
    _registrationTail = _registrationTail.then((_) => _register(token));
  }

  Future<void> _register(PlatformPushToken token) async {
    if (!_active) return;
    try {
      token.validate();
      final request = PlatformPushSubscriptionRequest(
        deviceId: deviceId,
        provider: token.provider,
        token: token.token,
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
