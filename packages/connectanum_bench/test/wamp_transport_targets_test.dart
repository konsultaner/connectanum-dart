import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  group('resolveWampTransportTargets', () {
    test('prefers dedicated plain WAMP listener over mixed HTTP listener', () {
      final targets = resolveWampTransportTargets([
        const ListenerSettings(
          endpoint: '127.0.0.1:8080',
          authmethods: ['anonymous'],
          protocols: [
            ListenerProtocol.rawsocket,
            ListenerProtocol.http,
            ListenerProtocol.http2,
          ],
        ),
        const ListenerSettings(
          endpoint: '127.0.0.1:8081',
          authmethods: ['anonymous'],
          protocols: [ListenerProtocol.rawsocket, ListenerProtocol.websocket],
          websocket: WebSocketListenerSettings(path: '/wamp'),
        ),
      ]);

      expect(targets[WampTransport.rawsocket]?.host, '127.0.0.1');
      expect(targets[WampTransport.rawsocket]?.port, 8081);
      expect(targets[WampTransport.rawsocket]?.secure, isFalse);
      expect(
        targets[WampTransport.websocket]?.webSocketUri.toString(),
        'ws://127.0.0.1:8081/wamp',
      );
    });

    test('normalizes wildcard hosts and defaults websocket path', () {
      final targets = resolveWampTransportTargets([
        const ListenerSettings(
          endpoint: '0.0.0.0:9090',
          authmethods: ['anonymous'],
          protocols: [ListenerProtocol.websocket],
        ),
      ]);

      final websocket = targets[WampTransport.websocket];
      expect(websocket, isNotNull);
      expect(websocket?.host, '127.0.0.1');
      expect(websocket?.webSocketUri.toString(), 'ws://127.0.0.1:9090/wamp');
    });
  });
}
