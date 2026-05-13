import 'dart:io';

import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_client_auth.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:test/test.dart';

void main() {
  group('endpointFromListenerSettings', () {
    test('parses host/port and defaults', () {
      final settings = ListenerSettings(
        type: 'rawsocket',
        endpoint: '127.0.0.1:8080',
        options: const {},
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.host, '127.0.0.1');
      expect(endpoint.port, 8080);
      expect(endpoint.tlsMode, TlsMode.disabled);
      expect(endpoint.maxRawSocketSizeExponent, 16);
    });

    test('resolves tls native and SNI from files', () async {
      final certFile = await _writeTemp(
        'cert.pem',
        '-----BEGIN CERTIFICATE-----\nCERT\n-----END CERTIFICATE-----\n',
      );
      final keyFile = await _writeTemp(
        'key.pem',
        '-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----\n',
      );

      final settings = ListenerSettings(
        type: 'rawsocket',
        endpoint: 'localhost:8443',
        tls: {
          'mode': 'native',
          'sni_certificates': [
            {
              'hostname': 'localhost',
              'certificate_chain_file': certFile.path,
              'private_key_file': keyFile.path,
            },
          ],
        },
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.tlsMode, TlsMode.native);
      expect(endpoint.sniCertificates, hasLength(1));
      expect(endpoint.sniCertificates.first.hostname, 'localhost');
      expect(
        endpoint.sniCertificates.first.certificateChainPem,
        contains('CERT'),
      );
      expect(endpoint.sniCertificates.first.privateKeyPem, contains('KEY'));
    });

    test('resolves client auth from files', () async {
      final certFile = await _writeTemp(
        'cert.pem',
        '-----BEGIN CERTIFICATE-----\nCERT\n-----END CERTIFICATE-----\n',
      );
      final keyFile = await _writeTemp(
        'key.pem',
        '-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----\n',
      );
      final caFile = await _writeTemp(
        'ca.pem',
        '-----BEGIN CERTIFICATE-----\nCA_CERT\n-----END CERTIFICATE-----\n',
      );

      final settings = ListenerSettings(
        type: 'rawsocket',
        endpoint: 'localhost:8443',
        tls: {
          'mode': 'native',
          'sni_certificates': [
            {
              'hostname': 'localhost',
              'certificate_chain_file': certFile.path,
              'private_key_file': keyFile.path,
            },
          ],
          'client_auth': {
            'mode': 'required',
            'ca_certificates_file': caFile.path,
          },
        },
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.clientAuth, isNotNull);
      expect(endpoint.clientAuth!.mode, TlsClientAuthMode.required);
      expect(endpoint.clientAuth!.caCertificatesPem, contains('CA_CERT'));
    });

    test('parses timeouts and rawsocket size overrides', () {
      final settings = ListenerSettings(
        type: 'rawsocket',
        endpoint: '0.0.0.0:0',
        options: const {
          'max_rawsocket_size_exponent': 18,
          'idle_timeout_ms': 1500,
          'heartbeat_interval_ms': 1000,
          'heartbeat_timeout_ms': 3000,
          'handshake_timeout_ms': '2500',
          'max_http_content_length': 4096,
        },
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.maxRawSocketSizeExponent, 18);
      expect(endpoint.idleTimeout, const Duration(milliseconds: 1500));
      expect(endpoint.heartbeatInterval, const Duration(milliseconds: 1000));
      expect(endpoint.heartbeatTimeout, const Duration(milliseconds: 3000));
      expect(endpoint.handshakeTimeout, const Duration(milliseconds: 2500));
      expect(endpoint.maxHttpContentLength, 4096);
    });

    test('prefers rawsocket max exponent from rawsocket block', () {
      final settings = ListenerSettings(
        endpoint: '0.0.0.0:0',
        options: const {'max_rawsocket_size_exponent': 18},
        rawsocket: const RawSocketListenerSettings(maxFrameExponent: 20),
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.maxRawSocketSizeExponent, 20);
    });

    test('prefers websocket path from websocket block', () {
      final settings = ListenerSettings(
        endpoint: '0.0.0.0:0',
        path: '/legacy',
        websocket: const WebSocketListenerSettings(
          path: '/ws',
          subprotocols: [],
          serializerFallback: null,
          options: {},
        ),
      );

      final endpoint = Endpoint.fromListenerSettings(settings);

      expect(endpoint.webSocketPath, '/ws');
    });
  });
}

Future<File> _writeTemp(String name, String contents) async {
  final dir = await Directory.systemTemp.createTemp('resolver_test_');
  final file = File('${dir.path}/$name');
  return file.writeAsString(contents);
}
