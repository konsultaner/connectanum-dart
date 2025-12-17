import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:test/test.dart';

const _certificatePem = '''
-----BEGIN CERTIFICATE-----
MIIBszCCAVmgAwIBAgIUfsSyc2j1Bfs67StD8LSe5jecO9YwDQYJKoZIhvcNAQEL
BQAwEzERMA8GA1UEAwwIYWNtZS5jb20wHhcNMjQwNzAxMDAwMDAwWhcNMjUwNzAx
MDAwMDAwWjATMREwDwYDVQQDDAhhY21lLmNvbTBZMBMGByqGSM49AgEGCCqGSM49
AwEHA0IABEXAMPLEaDummyBase64PayloadgF2f8BebslbMdUtGKUcx7dGgEJlTFg
/QK3Nv8An2iS3CRrL7arCBXC5v1hzFVf41QxmdejbTBrMA4GA1UdDwEB/wQEAwIF
oDATBgNVHSUEDDAKBggrBgEFBQcDATAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBRexample5gHCcOjqy2lqffoycHJODAfBgNVHSMEGDAWgBRexample5gHCcOjqy2
lqffoycHJODANBgkqhkiG9w0BAQsFAAOCAQEAR4EkPExampleSignedValueOnEnd
N78fMffxGDbHF8r2Lm9T4KgHUzPhsQmzFucTuXAXKulCMDtNyR1YcCZ3dGXvm93O
5j0bCbogB0B2mYkD7Y3erlJMipoc5kKnUsB0XvPZfczQVME5cASjd+NR/44eukap
5ZNxeNKCCT1vKhBVKjUee9ml9VpgsGLYlPuNvqbWicoleYv4Fgb7N0U4lO8BxBMC
qA6GehK64x827n6uiq8S7tA5PUZOW1swcvnT7EHev7sn1420yJX2DZg5NFFp4PFv
MwrqXjX63gle7zLcMFTVJwDeKaTY3l7xwkRJRRPracfXNEPcce9iwbOZ+wVXz3aa
o5QIsw==
-----END CERTIFICATE-----
''';

const _privateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgexampleExampleEx
ampleExampleExampleExampleExamplehRANCAARBexampleDummyBase64Payloa
dgF2f8BebslbMdUtGKUcx7dGgEJlTFg/QK3Nv8An2iS3CRrL7arCBXC5v1hzFVf4
1Qxmd
-----END PRIVATE KEY-----
''';

void main() {
  group('TlsMode wire format', () {
    test('round trip', () {
      for (final mode in TlsMode.values) {
        final wire = mode.wireValue;
        expect(TlsModeWireFormat.parse(wire), mode);
      }
    });

    test('throws on invalid input', () {
      expect(() => TlsModeWireFormat.parse('invalid'), throwsArgumentError);
    });
  });

  group('SniCertificate', () {
    test('normalises hostnames and PEM fields', () {
      final cert = SniCertificate(
        hostname: ' example.com ',
        certificateChainPem: _certificatePem,
        privateKeyPem: _privateKeyPem,
      );
      expect(cert.hostname, 'example.com');
      expect(cert.toNativeJson(), containsPair('hostname', 'example.com'));
    });

    test('rejects invalid hostnames', () {
      expect(
        () => SniCertificate(
          hostname: 'not valid host name',
          certificateChainPem: _certificatePem,
          privateKeyPem: _privateKeyPem,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid certificate pem', () {
      expect(
        () => SniCertificate(
          hostname: 'example.com',
          certificateChainPem: 'INVALID',
          privateKeyPem: _privateKeyPem,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid private key pem', () {
      expect(
        () => SniCertificate(
          hostname: 'example.com',
          certificateChainPem: _certificatePem,
          privateKeyPem:
              '-----BEGIN PRIVATE KEY-----\nMISMATCH\n-----END CERTIFICATE-----',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Endpoint', () {
    final cert = SniCertificate(
      hostname: 'router.example',
      certificateChainPem: _certificatePem,
      privateKeyPem: _privateKeyPem,
    );

    test('serialises to native json', () {
      final endpoint = Endpoint(
        host: '0.0.0.0',
        port: 0,
        tlsMode: TlsMode.native,
        idleTimeout: const Duration(seconds: 30),
        handshakeTimeout: const Duration(seconds: 5),
        maxHttpContentLength: 1024,
        maxRawSocketSizeExponent: 16,
        webSocketPath: ' /wamp ',
        sniCertificates: [cert],
      );

      final json = endpoint.toNativeJson();
      expect(json['host'], '0.0.0.0');
      expect(json['port'], 0);
      expect(json['tls_mode'], 'native');
      expect(json['idle_timeout_ms'], 30000);
      expect(json['handshake_timeout_ms'], 5000);
      expect(json['max_http_content_length'], 1024);
      expect(json['max_rawsocket_size_exponent'], 16);
      expect(json['websocket_path'], '/wamp');
      expect(json['sni_certificates'], hasLength(1));
    });

    test('supports connectanum extended raw socket exponent', () {
      final endpoint = Endpoint(
        host: '0.0.0.0',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 30,
      );
      expect(endpoint.maxRawSocketSizeExponent, 30);
      expect(
        endpoint.toNativeJson(),
        containsPair('max_rawsocket_size_exponent', 30),
      );
    });

    test('allows IPv6 literal hosts', () {
      final endpoint = Endpoint(
        host: '[::1]',
        port: 8080,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      );
      expect(endpoint.host, '[::1]');
    });

    test('throws for duplicate SNI hostnames', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.dart,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [cert, cert],
        ),
        throwsArgumentError,
      );
    });

    test('throws when native TLS is missing SNI certificates', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid raw socket exponent', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 31,
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid web socket path', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          webSocketPath: 'invalid',
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid port', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: -1,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid max http content length', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          maxHttpContentLength: 0,
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid idle timeout', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          idleTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('throws on invalid handshake timeout', () {
      expect(
        () => Endpoint(
          host: 'localhost',
          port: 8080,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          handshakeTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('equality compares all properties', () {
      final first = Endpoint(
        host: 'localhost',
        port: 8080,
        tlsMode: TlsMode.native,
        maxRawSocketSizeExponent: 16,
        sniCertificates: [cert],
      );
      final second = Endpoint(
        host: 'localhost',
        port: 8080,
        tlsMode: TlsMode.native,
        maxRawSocketSizeExponent: 16,
        sniCertificates: [cert],
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('RouterConfig', () {
    final endpoint = Endpoint(
      host: 'localhost',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    );

    test('requires at least one endpoint', () {
      expect(() => RouterConfig(endpoints: const []), throwsArgumentError);
    });

    test('serialises to native json', () {
      final config = RouterConfig(
        endpoints: [endpoint],
        schema: 'custom.schema',
        version: 3,
      );
      final json = config.toNativeJson();
      expect(json['schema'], 'custom.schema');
      expect(json['version'], 3);
      expect(
        json['endpoints'],
        isA<List>().having((l) => l.length, 'length', 1),
      );
    });

    test('equality compares schema, version and endpoints', () {
      final configA = RouterConfig(endpoints: [endpoint]);
      final configB = RouterConfig(endpoints: [endpoint]);
      expect(configA, configB);
      expect(configA.hashCode, configB.hashCode);
    });
  });
}
