@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  group('bench router config', () {
    test(
      'loads through router validation with distinct TLS SNI hosts',
      () async {
        final routerConfigPath = _resolveBenchRouterConfig();
        final settings = await RouterConfigLoaderIo.fromFile(routerConfigPath);
        final endpoints = settings.listeners
            .map(Endpoint.fromListenerSettings)
            .toList(growable: false);

        final sniHosts = endpoints
            .expand((endpoint) => endpoint.sniCertificates)
            .map((certificate) => certificate.hostname)
            .toSet();

        expect(
          sniHosts.length,
          endpoints.expand((endpoint) => endpoint.sniCertificates).length,
        );
        expect(
          () => Router(RouterConfig(endpoints: endpoints), settings: settings),
          returnsNormally,
        );
      },
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
