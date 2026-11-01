import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';

/// Transport-owned context. Client IDs identify connections, not principals.
final class MqttPeerContext {
  const MqttPeerContext({
    required this.realm,
    required this.clientId,
    required this.version,
    required this.cancellation,
    this.connectionId,
  });

  final String realm;
  final String clientId;
  final MqttVersion version;
  final int? connectionId;
  final MqttGatewayCancellation cancellation;
}

/// Cancellation with removable listeners: completed messages must not leave a
/// continuation on a connection-lifetime Future until that connection closes.
final class MqttGatewayCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;
  int get listenerCount => _listeners.length;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  Future<T> waitFor<T>(
    Future<T> work, {
    MqttGatewayCancellation? other,
    Duration? timeout,
  }) {
    final result = Completer<T>();
    final tokens = [this, ?other];
    Timer? timer;
    late void Function() cancelled;
    void finish({T? value, Object? error, StackTrace? stack}) {
      if (result.isCompleted) return;
      for (final token in tokens) {
        token._listeners.remove(cancelled);
      }
      timer?.cancel();
      if (error != null) {
        result.completeError(error, stack);
      } else {
        result.complete(value as T);
      }
    }

    cancelled = () => finish(error: StateError('MQTT gateway work cancelled'));
    for (final token in tokens) {
      if (token._cancelled) {
        cancelled();
        break;
      }
      token._listeners.add(cancelled);
    }
    if (!result.isCompleted && timeout != null) {
      timer = Timer(
        timeout,
        () => finish(error: TimeoutException('MQTT gateway work timed out')),
      );
    }
    work.then<void>(
      (value) => finish(value: value),
      onError: (Object error, StackTrace stack) =>
          finish(error: error, stack: stack),
    );
    return result.future;
  }
}

/// Optional realm boundary installed by an explicitly configured gateway.
///
/// A policy must observe [MqttPeerContext.cancellation] during external work.
/// Closing a policy denies subsequent work until a replacement is installed;
/// the broker never silently falls back to anonymous delivery for that realm.
abstract interface class MqttBrokerGatewayPolicy {
  bool get isClosed;

  Future<bool> publish(MqttPeerContext peer, MqttPublish publication);

  Future<bool> subscribe(MqttPeerContext peer, String filter);

  Future<bool> receive(MqttPeerContext peer, String topic);
}

/// A validated, explicitly authorized application publication for MQTT peers.
final class MqttGatewayPublication {
  const MqttGatewayPublication({required this.topic, required this.payload});

  final String topic;
  final Uint8List payload;
}
