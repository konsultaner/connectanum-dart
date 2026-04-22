@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final nativeSkipReason = !(Platform.isLinux || Platform.isMacOS)
      ? 'Bench router native startup regression only runs on Linux and macOS.'
      : nativeLib == null
      ? 'Native transport library missing; build native transport first.'
      : null;

  group('bench router config', () {
    test('loads through router validation with shared TLS SNI hosts', () async {
      final routerConfigPath = _resolveBenchRouterConfig();
      final settings = await RouterConfigLoaderIo.fromFile(routerConfigPath);
      final endpoints = settings.listeners
          .map(Endpoint.fromListenerSettings)
          .toList(growable: false);

      final sniHosts = endpoints
          .expand((endpoint) => endpoint.sniCertificates)
          .map((certificate) => certificate.hostname)
          .toList(growable: false);

      expect(sniHosts.where((host) => host == 'localhost'), hasLength(2));
      expect(
        () => Router(RouterConfig(endpoints: endpoints), settings: settings),
        returnsNormally,
      );
    });

    test(
      'starts through the native runtime with ephemeral listener ports',
      () async {
        final routerConfigPath = _resolveBenchRouterConfig();
        final settings = await RouterConfigLoaderIo.fromFile(routerConfigPath);
        final ephemeralSettings = await _settingsWithFreePorts(settings);
        final endpoints = ephemeralSettings.listeners
            .map(Endpoint.fromListenerSettings)
            .toList(growable: false);
        final router = Router(
          RouterConfig(endpoints: endpoints),
          settings: ephemeralSettings,
        );
        final runtime = NativeTransportRuntime(libraryPath: nativeLib!)
          ..start();
        RouterBinding? binding;

        addTearDown(() async {
          await binding?.dispose();
          runtime.shutdown();
        });

        binding = router.start(runtime);

        expect(
          binding.listeners,
          hasLength(ephemeralSettings.listeners.length),
        );
        for (final listener in binding.listeners) {
          expect(listener.port, greaterThan(0));
        }
      },
      skip: nativeSkipReason,
    );
  });
}

String _resolveBenchRouterConfig() {
  final candidates = [
    File('native/bench/bench_router.json'),
    File('../../native/bench/bench_router.json'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  throw StateError(
    'Failed to locate native/bench/bench_router.json from ${Directory.current.path}.',
  );
}

Future<RouterSettings> _settingsWithFreePorts(RouterSettings settings) async {
  final sockets = <ServerSocket>[];
  try {
    final reservedPorts = <int>[];
    final http3Ports = <int?>[];
    for (final listener in settings.listeners) {
      final listenerSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      sockets.add(listenerSocket);
      reservedPorts.add(listenerSocket.port);

      final http3 = listener.http?.http3;
      if (http3 != null && http3.enabled) {
        final http3Socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        sockets.add(http3Socket);
        http3Ports.add(http3Socket.port);
      } else {
        http3Ports.add(null);
      }
    }

    final listeners = <ListenerSettings>[];
    for (var i = 0; i < settings.listeners.length; i++) {
      listeners.add(
        _listenerWithReservedPorts(
          settings.listeners[i],
          listenerPort: reservedPorts[i],
          http3Port: http3Ports[i],
        ),
      );
    }
    return settings.copyWith(listeners: listeners);
  } finally {
    for (final socket in sockets) {
      await socket.close();
    }
  }
}

ListenerSettings _listenerWithReservedPorts(
  ListenerSettings listener, {
  required int listenerPort,
  required int? http3Port,
}) {
  final separatorIndex = listener.endpoint.lastIndexOf(':');
  if (separatorIndex < 0) {
    throw StateError(
      'Listener endpoint "${listener.endpoint}" is missing a port.',
    );
  }
  final host = listener.endpoint.substring(0, separatorIndex);
  final http = listener.http;
  return ListenerSettings(
    type: listener.type,
    endpoint: '$host:$listenerPort',
    authmethods: listener.authmethods,
    sessionProfile: listener.sessionProfile,
    path: listener.path,
    tls: listener.tls,
    options: listener.options,
    protocols: listener.protocols,
    rawsocket: listener.rawsocket,
    websocket: listener.websocket,
    http: http == null
        ? null
        : HttpListenerSettings(
            alpn: http.alpn,
            http3: http.http3 == null
                ? null
                : Http3Settings(enabled: http.http3!.enabled, port: http3Port),
            sessionProfile: http.sessionProfile,
            routes: http.routes,
            options: http.options,
          ),
  );
}

String? _resolveNativeLib() {
  final envPath = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (envPath != null && File(envPath).existsSync()) {
    return envPath;
  }

  final libraryName = switch (Platform.operatingSystem) {
    'linux' => 'libct_ffi.so',
    'macos' => 'libct_ffi.dylib',
    'windows' => 'ct_ffi.dll',
    _ => 'libct_ffi.so',
  };

  final candidates = [
    File('native/transport/target/ffi-test/release/$libraryName'),
    File('native/transport/target/release/$libraryName'),
    File('../../native/transport/target/ffi-test/release/$libraryName'),
    File('../../native/transport/target/release/$libraryName'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}
