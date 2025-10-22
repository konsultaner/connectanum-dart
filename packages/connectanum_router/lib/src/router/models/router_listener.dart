import 'endpoint.dart';

/// Describes a native listener that the router bound to a specific port.
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
