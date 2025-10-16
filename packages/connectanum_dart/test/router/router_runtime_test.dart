import 'dart:typed_data';

import 'package:connectanum_dart/src/native/runtime.dart';
import 'package:connectanum_dart/src/router/models/endpoint.dart';
import 'package:connectanum_dart/src/router/models/router_config.dart';
import 'package:connectanum_dart/src/router/models/tls_mode.dart';
import 'package:connectanum_dart/src/router/router_instance.dart';
import 'package:test/test.dart';

class _FakeRuntime implements NativeRuntime {
  final List<String> listenCalls = [];
  Uint8List? appliedConfig;
  final Map<int, int> _ports = {};
  int _nextId = 1;

  @override
  void applyRouterConfig(Uint8List config) {
    appliedConfig = config;
  }

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextId++;
    listenCalls.add('$host:$port:$backlog');
    _ports[id] = port == 0 ? 5000 + id : port;
    return id;
  }

  @override
  int pollConnection(int listenerId) => 0;

  @override
  void shutdown() {}

  @override
  void start() {}
}

class _UnsupportedConfigRuntime extends _FakeRuntime {
  @override
  void applyRouterConfig(Uint8List config) {
    throw UnsupportedError('no-op');
  }
}

void main() {
  group('Router start', () {
    test('binds endpoints to runtime and applies config', () {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      expect(runtime.appliedConfig, isNotNull);
      expect(runtime.listenCalls, ['127.0.0.1:0:128']);
      expect(binding.listeners, hasLength(1));
      final listener = binding.listeners.single;
      expect(listener.listenerId, 1);
      expect(listener.port, greaterThan(0));
    });

    test('continues when runtime does not support config application', () {
      final runtime = _UnsupportedConfigRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '0.0.0.0',
              port: 8080,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      expect(binding.listeners, hasLength(1));
      expect(runtime.listenCalls, ['0.0.0.0:8080:128']);
    });
  });
}
