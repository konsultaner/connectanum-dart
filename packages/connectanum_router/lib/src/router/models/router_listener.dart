import 'endpoint.dart';
import '../config/router_settings.dart';

/// Describes a native listener that the router bound to a specific port.
class RouterListener {
  const RouterListener({
    required this.listenerId,
    required this.endpoint,
    required this.port,
    required this.http3Port,
    this.settings,
  });

  final int listenerId;
  final Endpoint endpoint;
  final int port;
  final int http3Port;
  final ListenerSettings? settings;

  /// TODO(protocol-negotiation): surface negotiated protocol stats/metrics once
  /// the native runtime reports them (e.g., active http/websocket counts).
}
