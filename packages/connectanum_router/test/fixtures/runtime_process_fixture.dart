import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  final runtime = NativeTransportRuntime(libraryPath: args[0])..start();
  final settings = RouterSettings(
    realms: const [
      RealmSettings(
        name: 'consumer',
        auth: RealmAuthSettings(methods: ['anonymous']),
        roles: [],
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
    workerPool: const WorkerPoolSettings(minWorkers: 1),
    internalRealms: [
      if (args[1] == 'bootstrap-startup')
        InternalRealmSettings(name: 'consumer', services: {'metrics'}),
    ],
    metrics: args[1] == 'bootstrap-startup'
        ? const MetricsSettings(
            openMetrics: OpenMetricsSettings(
              enabled: true,
              listen: '127.0.0.1:0',
              realm: 'consumer',
            ),
          )
        : null,
  );
  final router = Router(
    RouterConfig(
      endpoints: settings.listeners.map(Endpoint.fromListenerSettings).toList(),
    ),
    settings: settings,
  );
  final binding = router.start(runtime);
  final port = binding.listeners.first.port;
  if (args[1] == 'bootstrap-startup') {
    await binding.dispose();
    if (binding.internalSessionForRealm('consumer') != null) {
      throw StateError('Bootstrap published a session during disposal');
    }
    runtime.shutdown();
    runtime.dispose();
    print(jsonEncode({'ready': true, 'pid': pid, 'port': port}));
    print('cleanup completed');
    return;
  }
  if (args[1] == 'cleanup-failure') {
    final first = await binding.createInternalSession(realmUri: 'consumer');
    await binding.createInternalSession(realmUri: 'consumer');
    final registered = await first.register('app.shutdown');
    final source = StreamController<core.Invocation>(
      onCancel: () => throw StateError('expected cleanup failure'),
    );
    registered.invocationStream = source.stream;
    registered.onInvoke((_) {});
    final disposing = binding.dispose();
    if (!identical(disposing, binding.dispose())) {
      throw StateError('Concurrent disposal did not share failure');
    }
    try {
      await disposing;
      throw StateError('Cleanup failure was not reported');
    } catch (error) {
      if (error is! StateError || error.message != 'expected cleanup failure') {
        rethrow;
      }
    }
    await source.close();
    runtime.shutdown();
    runtime.dispose();
    print(jsonEncode({'ready': true, 'pid': pid, 'port': port}));
    print('cleanup completed');
    return;
  }
  if (args[1] == 'internal-startup' || args[1] == 'internal-spawn') {
    var cancelled = 0;
    final created = <RouterSession>[];
    final creations = List.generate(
      16,
      (_) => binding
          .createInternalSession(realmUri: 'consumer')
          .then<void>(
            created.add,
            onError: (Object error) {
              if (error is! StateError ||
                  error.message != 'Router binding is disposed') {
                throw error;
              }
              cancelled++;
            },
          ),
    );
    if (args[1] == 'internal-spawn') {
      // Exercise later scheduling turns, including isolates already spawning.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // Begin teardown while the session IDs and isolates are still in flight.
    final disposing = binding.dispose();
    if (!identical(disposing, binding.dispose())) {
      throw StateError('Concurrent disposal did not share completion');
    }
    await disposing;
    await Future.wait(creations);
    if (cancelled + created.length != 16 ||
        (args[1] == 'internal-startup' && cancelled != 16)) {
      throw StateError('Startup was not accounted for');
    }
    for (final session in created) {
      try {
        await session.register('app.after_shutdown');
        throw StateError('Session survived binding disposal');
      } catch (error) {
        if (error is! StateError ||
            error.message != 'Router session is closed') {
          rethrow;
        }
      }
    }
    try {
      await binding.createInternalSession(realmUri: 'consumer');
      throw StateError('Disposed binding accepted a new session');
    } catch (error) {
      if (error is! StateError ||
          error.message != 'Router binding is disposed') {
        rethrow;
      }
    }
    runtime.shutdown();
    runtime.dispose();
    print(jsonEncode({'ready': true, 'pid': pid, 'port': port}));
    print('cleanup completed');
    return;
  }
  final consumer = client.Client(
    realm: 'consumer',
    transport: client.WebSocketTransport.withJsonSerializer(
      'ws://127.0.0.1:$port/ws',
    ),
  );
  try {
    final session = await consumer.connect().first.timeout(
      const Duration(seconds: 5),
    );
    if (session.authRole != 'anonymous') {
      throw StateError('Authentication failed');
    }
    if (args[1] == 'active-client') {
      await binding.dispose();
      await session.onDisconnect.timeout(const Duration(seconds: 5));
    } else {
      await session.close();
    }
    await consumer.disconnect();
    print(jsonEncode({'ready': true, 'pid': pid, 'port': port}));
    if (args[1] == 'hold') {
      await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
    }
  } finally {
    await consumer.disconnect();
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
  print('cleanup completed');
  // Returning from main must exit naturally; do not call exit(0).
}
