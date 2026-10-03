@TestOn('vm')
library;

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_client/src/transport/socket/socket_transport.dart'
    as socket;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

Router _router(ListenerProtocol protocol, String role) {
  final settings = RouterSettings(
    realms: [
      RealmSettings(
        name: 'consumer',
        auth: RealmAuthSettings(
          methods: const ['anonymous'],
          methodOptions: {
            'anonymous': {'authrole': role},
          },
        ),
        roles: const [],
        limits: const RealmLimitSettings(),
      ),
    ],
    listeners: [
      ListenerSettings(
        type: listenerProtocolToString(protocol),
        endpoint: '127.0.0.1:0',
        options: const {},
        protocols: [protocol],
        websocket: protocol == ListenerProtocol.websocket
            ? const WebSocketListenerSettings(path: '/ws')
            : null,
        authmethods: const ['anonymous'],
      ),
    ],
    workerPool: const WorkerPoolSettings(minWorkers: 1),
  );
  return Router(
    RouterConfig(
      endpoints: settings.listeners.map(Endpoint.fromListenerSettings).toList(),
    ),
    settings: settings,
  );
}

Future<void> _connect(RouterBinding binding, String role) async {
  final listener = binding.listeners.single;
  final transport =
      listener.settings!.protocols.single == ListenerProtocol.websocket
      ? client.WebSocketTransport.withJsonSerializer(
          'ws://127.0.0.1:${listener.port}/ws',
        )
      : socket.SocketTransport(
          '127.0.0.1',
          listener.port,
          json.Serializer(),
          SocketHelper.serializationJson,
        );
  final consumer = client.Client(realm: 'consumer', transport: transport);
  try {
    final session = await consumer.connect().first.timeout(
      const Duration(seconds: 5),
    );
    expect(session.authRole, role);
    await session.close();
  } finally {
    await consumer.disconnect();
  }
}

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  test(
    'deferred router keeps its own configuration and sibling survives restart',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      final routerA = _router(ListenerProtocol.websocket, 'customer-a');
      final a = routerA.start(runtime, activateListeners: false);
      addTearDown(a.dispose);
      final b = _router(
        ListenerProtocol.rawsocket,
        'customer-b',
      ).start(runtime);
      addTearDown(b.dispose);
      a.activateListeners();
      expect(
        a.listeners.single.listenerId,
        isNot(b.listeners.single.listenerId),
      );
      expect(a.listeners.single.port, isNot(b.listeners.single.port));
      await _connect(a, 'customer-a');
      await _connect(b, 'customer-b');
      expect(a.reloadTls(), 1);
      expect(b.reloadTls(), 1);
      expect(runtime.reloadTls(), 0);
      await _connect(a, 'customer-a');
      await _connect(b, 'customer-b');
      await a.dispose();
      expect(a.activateListeners, throwsStateError);
      expect(a.reloadTls, throwsStateError);
      await _connect(b, 'customer-b');
      final restarted = routerA.start(runtime);
      addTearDown(restarted.dispose);
      await _connect(restarted, 'customer-a');
      await _connect(b, 'customer-b');
    },
    skip: nativeLib == null ? 'Native transport library unavailable' : false,
  );
}
