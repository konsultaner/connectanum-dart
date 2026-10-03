@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  test(
    'WebSocket and health port-zero listeners remain separate and usable',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      final settings = RouterSettings(
        realms: const [
          RealmSettings(
            name: 'consumer',
            auth: RealmAuthSettings(
              methods: ['anonymous'],
              methodOptions: {
                'anonymous': {'authrole': 'customer'},
              },
            ),
            roles: [],
            limits: RealmLimitSettings(),
          ),
          RealmSettings(
            name: 'connectanum.metrics',
            auth: RealmAuthSettings(methods: ['anonymous']),
            roles: [
              RoleSettings(
                name: 'metrics',
                permissions: [
                  PermissionSettings(
                    uri: '',
                    matchPolicy: PermissionMatchPolicy.prefix,
                    allow: ['call', 'register', 'unregister'],
                  ),
                ],
              ),
            ],
            limits: RealmLimitSettings(),
          ),
        ],
        listeners: const [
          ListenerSettings(
            type: 'websocket',
            endpoint: '127.0.0.1:0',
            options: {},
            protocols: [ListenerProtocol.websocket],
            websocket: WebSocketListenerSettings(path: '/ws'),
            authmethods: ['anonymous'],
          ),
        ],
        internalRealms: [
          InternalRealmSettings(
            name: 'connectanum.metrics',
            authId: 'metrics-daemon',
            authRole: 'metrics',
            services: {'metrics'},
          ),
        ],
        metrics: const MetricsSettings(
          openMetrics: OpenMetricsSettings(
            enabled: true,
            listen: '127.0.0.1:0',
            realm: 'connectanum.metrics',
          ),
        ),
        workerPool: const WorkerPoolSettings(minWorkers: 1),
      ).withOpenMetricsHttpRoutes();
      final router = Router(
        RouterConfig(
          endpoints: settings.listeners
              .map(Endpoint.fromListenerSettings)
              .toList(),
        ),
        settings: settings,
      );
      final nativeConfig =
          jsonDecode(utf8.decode(router.buildNativeConfigJson())) as Map;
      expect(nativeConfig['endpoints'][0]['protocols'], ['websocket']);
      expect(nativeConfig['endpoints'][0]['http_routes'], isNull);
      expect(nativeConfig['endpoints'][1]['protocols'], ['http', 'http2']);
      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await binding.ensureInternalServicesReady();
      final ws = binding.listeners.first;
      final metrics = binding.listeners.last;
      expect(ws.port, isNonZero);
      expect(metrics.port, isNot(ws.port));
      expect(ws.settings!.protocols, [ListenerProtocol.websocket]);
      expect(
        metrics.settings!.options['connectanum_open_metrics_listener'],
        true,
      );
      expect(binding.reloadTls(), 2);

      final consumer = client.Client(
        realm: 'consumer',
        transport: client.WebSocketTransport.withJsonSerializer(
          'ws://127.0.0.1:${ws.port}/ws',
        ),
      );
      addTearDown(consumer.disconnect);
      final session = await consumer.connect().first.timeout(
        const Duration(seconds: 10),
      );
      expect(session.authRole, 'customer');

      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      for (final path in ['/healthz', '/health', '/metrics']) {
        final response = await (await http.getUrl(
          Uri.parse('http://127.0.0.1:${metrics.port}$path'),
        )).close().timeout(const Duration(seconds: 5));
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        expect(body, isNotEmpty);
      }
      // The health route must not migrate to the WAMP listener.
      var misplacedHealth = false;
      try {
        final misplaced = await (await http.getUrl(
          Uri.parse('http://127.0.0.1:${ws.port}/healthz'),
        )).close().timeout(const Duration(seconds: 5));
        misplacedHealth = misplaced.statusCode == 200;
        await misplaced.drain<void>();
      } on HttpException {
        // A WebSocket-only endpoint rejects non-upgrade HTTP by closing the socket.
      }
      expect(misplacedHealth, isFalse);
      await session.close();
    },
    skip: nativeLib == null ? 'Native transport library unavailable' : false,
  );
}
