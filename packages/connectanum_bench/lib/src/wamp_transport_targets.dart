import 'package:connectanum_router/connectanum_router.dart';

import 'wamp_workload_runner.dart';

class WampTransportTarget {
  const WampTransportTarget({
    required this.transport,
    required this.host,
    required this.port,
    required this.secure,
    this.webSocketPath,
  });

  final WampTransport transport;
  final String host;
  final int port;
  final bool secure;
  final String? webSocketPath;

  Uri get webSocketUri {
    if (transport != WampTransport.websocket) {
      throw StateError('webSocketUri is only available for websocket targets');
    }
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: host,
      port: port,
      path: webSocketPath ?? '/wamp',
    );
  }
}

Map<WampTransport, WampTransportTarget> resolveWampTransportTargets(
  Iterable<ListenerSettings> listeners,
) {
  final bestTargets = <WampTransport, _ScoredTarget>{};
  for (final listener in listeners) {
    final endpoint = Endpoint.fromListenerSettings(listener);
    final secure = endpoint.tlsMode != TlsMode.disabled;
    final host = _benchClientHost(endpoint.host);
    final path = endpoint.webSocketPath ?? '/wamp';
    final score = _targetScore(listener, secure: secure);
    for (final protocol in listener.protocols) {
      switch (protocol) {
        case ListenerProtocol.rawsocket:
          _recordTarget(
            bestTargets,
            WampTransport.rawsocket,
            WampTransportTarget(
              transport: WampTransport.rawsocket,
              host: host,
              port: endpoint.port,
              secure: secure,
            ),
            score,
          );
          break;
        case ListenerProtocol.websocket:
          _recordTarget(
            bestTargets,
            WampTransport.websocket,
            WampTransportTarget(
              transport: WampTransport.websocket,
              host: host,
              port: endpoint.port,
              secure: secure,
              webSocketPath: path,
            ),
            score,
          );
          break;
        case ListenerProtocol.http:
        case ListenerProtocol.http2:
        case ListenerProtocol.http3:
          break;
      }
    }
  }
  return Map<WampTransport, WampTransportTarget>.unmodifiable(
    bestTargets.map(
      (transport, scored) => MapEntry<WampTransport, WampTransportTarget>(
        transport,
        scored.target,
      ),
    ),
  );
}

void _recordTarget(
  Map<WampTransport, _ScoredTarget> bestTargets,
  WampTransport transport,
  WampTransportTarget target,
  int score,
) {
  final current = bestTargets[transport];
  if (current == null || score > current.score) {
    bestTargets[transport] = _ScoredTarget(target: target, score: score);
  }
}

int _targetScore(ListenerSettings listener, {required bool secure}) {
  final protocols = listener.protocols;
  final hasHttp = protocols.any((protocol) => protocol.isHttp);
  var score = 0;
  if (!hasHttp) {
    score += 100;
  }
  if (!secure) {
    score += 10;
  }
  return score;
}

String _benchClientHost(String host) {
  final normalized = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  switch (normalized) {
    case '0.0.0.0':
      return '127.0.0.1';
    case '::':
      return '::1';
    default:
      return normalized;
  }
}

class _ScoredTarget {
  const _ScoredTarget({required this.target, required this.score});

  final WampTransportTarget target;
  final int score;
}
