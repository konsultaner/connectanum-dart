part of '../router_instance.dart';

/// Describes a listener bound by the native runtime, including the endpoint
/// configuration and the port it ultimately bound to.
class RouterListener {
  const RouterListener({
    required this.listenerId,
    required this.endpoint,
    required this.port,
  });

  final int listenerId;
  final Endpoint endpoint;
  final int port;
}

/// Message wrapper that keeps track of which listener and connection produced
/// the incoming payload so routing logic can make decisions later on.
class RouterMessage {
  RouterMessage(this.listener, this.connectionId, this.message);

  final RouterListener listener;
  final int connectionId;
  final NativeIncomingMessage message;
}

/// Tracks the listener that owns an open connection. Additional per-connection
/// state can be attached here in the future without leaking outside of this
/// library.
class _ConnectionState {
  _ConnectionState(this.listener);

  final RouterListener listener;
}
