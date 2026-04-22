import 'dart:convert';

import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

const _certificatePem =
    '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
const _privateKeyPem =
    '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----';

SniCertificate _cert(String host) => SniCertificate(
  hostname: host,
  certificateChainPem: _certificatePem,
  privateKeyPem: _privateKeyPem,
);

void main() {
  group('Router buildNativeConfigJson', () {
    test('encodes schema, version and endpoints', () {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.native,
        maxRawSocketSizeExponent: 16,
        sniCertificates: [_cert('example.com')],
      );
      final router = Router(RouterConfig(endpoints: [endpoint]));

      final bytes = router.buildNativeConfigJson();
      final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['schema'], RouterConfig.defaultSchema);
      expect(map['version'], RouterConfig.defaultVersion);
      final endpointsJson = map['endpoints'] as List;
      expect(endpointsJson, hasLength(1));
      expect((endpointsJson.first as Map)['host'], '127.0.0.1');
    });

    test('throws when using unsupported dart TLS mode', () {
      final endpoints = [
        Endpoint(
          host: '0.0.0.0',
          port: 0,
          tlsMode: TlsMode.dart,
          maxRawSocketSizeExponent: 16,
        ),
      ];
      expect(
        () => Router(RouterConfig(endpoints: endpoints)),
        throwsArgumentError,
      );
    });

    test('allows duplicate SNI host across distinct endpoints', () {
      final cert = _cert('example.com');
      final endpoints = [
        Endpoint(
          host: '0.0.0.0',
          port: 8080,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [cert],
        ),
        Endpoint(
          host: '0.0.0.1',
          port: 8081,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [cert],
        ),
      ];
      expect(() => Router(RouterConfig(endpoints: endpoints)), returnsNormally);
    });
  });
}
