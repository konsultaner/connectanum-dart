@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_router/connectanum_router.dart' hide Invocation;
import 'package:test/test.dart';

class _LegacyRuntime extends NativeRuntime {
  int globalApplies = 0;
  int globalReloads = 0;
  int legacyListens = 0;
  int nextId = 1;
  final closed = <int>[];

  @override
  void applyRouterConfig(Uint8List config) => globalApplies++;
  @override
  int reloadTls() => ++globalReloads;
  @override
  int listen(String host, int port, {int backlog = 128}) {
    legacyListens++;
    return nextId++;
  }

  @override
  int getLocalPort(int listenerId) => 10000 + listenerId;
  @override
  int getHttp3Port(int listenerId) => 0;
  @override
  void closeListener(int listenerId) => closed.add(listenerId);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected runtime operation: ${invocation.memberName}',
  );
}

class _ScopedRuntime extends _LegacyRuntime
    implements NativeRuntimeWithRouterConfiguration {
  @override
  bool supportsRouterConfiguration = true;
  final opened = <(Uint8List, int)>[];
  final reloads = <(Uint8List, List<int>)>[];
  bool failReload = false;

  @override
  int listenRouterEndpoint(Uint8List config, int index, {int backlog = 128}) {
    opened.add((config, index));
    return nextId++;
  }

  @override
  int reloadRouterTls(Uint8List config, List<int> ids) {
    reloads.add((config, ids));
    if (failReload) throw StateError('Rejected TLS identity');
    return ids.length;
  }
}

Router _router() => Router(
  RouterConfig(
    endpoints: [
      Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      ),
    ],
  ),
);

void main() {
  test(
    'scoped bindings never change the global default and reload only their IDs',
    () async {
      final runtime = _ScopedRuntime();
      final a = _router().start(runtime, activateListeners: false);
      final b = _router().start(runtime);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.reloadTls, throwsStateError);
      a.activateListeners();
      a.activateListeners();
      expect(runtime.globalApplies, 0);
      expect(runtime.legacyListens, 0);
      expect(runtime.opened.map((entry) => entry.$2), [0, 0]);
      expect(a.reloadTls(), 1);
      expect(runtime.reloads.single.$2, [a.listeners.single.listenerId]);
      expect(
        runtime.reloads.single.$2,
        isNot(contains(b.listeners.single.listenerId)),
      );
      expect(runtime.globalReloads, 0);
      await a.dispose();
      expect(a.reloadTls, throwsStateError);
      expect(a.activateListeners, throwsStateError);
    },
  );

  test('legacy capability fallback never performs a global TLS reload', () {
    for (final runtime in [
      _LegacyRuntime(),
      _ScopedRuntime()..supportsRouterConfiguration = false,
    ]) {
      final binding = _router().start(runtime);
      addTearDown(binding.dispose);
      expect(runtime.globalApplies, 1);
      expect(runtime.legacyListens, 1);
      expect(binding.reloadTls, throwsUnsupportedError);
      expect(runtime.globalReloads, 0);
    }
  });

  test('reload retains an immutable snapshot only after native acceptance', () {
    final runtime = _ScopedRuntime();
    final binding = _router().start(runtime);
    addTearDown(binding.dispose);
    final original = binding.configJson;
    expect(() => original[0] = 0, throwsUnsupportedError);
    final replacement =
        jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    replacement['endpoints'][0]['max_rawsocket_size_exponent'] = 17;
    final expected = jsonEncode(replacement);
    final changed = Uint8List.fromList(utf8.encode(expected));
    runtime.failReload = true;
    expect(() => binding.reloadTls(configuration: changed), throwsStateError);
    expect(binding.configJson, same(original));
    runtime.failReload = false;
    expect(binding.reloadTls(configuration: changed), 1);
    changed[0] = 0;
    expect(utf8.decode(binding.configJson), expected);
    expect(binding.reloadTls(), 1);
    expect(utf8.decode(runtime.reloads.last.$1), expected);
  });
}
