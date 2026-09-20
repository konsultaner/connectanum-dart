import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  test('valid IPv6 listener resolves without substring range errors', () {
    const listeners = [
      ListenerSettings(
        endpoint: '[2001:db8::8]:9090',
        authmethods: ['anonymous'],
        protocols: [ListenerProtocol.rawsocket, ListenerProtocol.websocket],
      ),
    ];
    expect(() => resolveWampTransportTargets(listeners), returnsNormally);
    final targets = resolveWampTransportTargets(listeners);
    for (final transport in WampTransport.values) {
      expect(targets[transport]?.host, '2001:db8::8');
      expect(targets[transport]?.port, 9090);
    }
  });
  for (final secure in [false, true]) {
    for (final reversed in [false, true]) {
      test('equal rank preserves configuration order ($secure/$reversed)', () {
        final listeners = [
          _listener(8081, secure: secure),
          _listener(8082, secure: secure),
        ];
        final targets = resolveWampTransportTargets(
          reversed ? listeners.reversed : listeners,
          secureOnly: secure,
        );
        for (final transport in WampTransport.values) {
          expect(targets[transport]?.port, reversed ? 8082 : 8081);
          expect(targets[transport]?.secure, secure);
        }
        expect(
          () => targets[WampTransport.websocket]!.webSocketUri,
          returnsNormally,
        );
        expect(
          targets[WampTransport.websocket]!.webSocketUri.toString(),
          '${secure ? 'wss' : 'ws'}://127.0.0.1:${reversed ? 8082 : 8081}/wamp',
        );
      });
    }
  }
  for (final reversed in [false, true]) {
    test(
      'default selection prefers cleartext at otherwise equal rank ($reversed)',
      () {
        final listeners = [
          _listener(8443, secure: true),
          _listener(8080, secure: false),
        ];
        final ordered = reversed ? listeners.reversed : listeners;
        final defaults = resolveWampTransportTargets(ordered);
        final secure = resolveWampTransportTargets(ordered, secureOnly: true);
        for (final transport in WampTransport.values) {
          expect(defaults[transport]?.port, 8080);
          expect(defaults[transport]?.secure, isFalse);
          expect(secure[transport]?.port, 8443);
          expect(secure[transport]?.secure, isTrue);
        }
      },
    );
    test('dedicated TLS outranks mixed cleartext ($reversed)', () {
      final listeners = [
        _listener(8443, secure: true),
        _listener(8080, secure: false, mixed: true),
      ];
      final targets = resolveWampTransportTargets(
        reversed ? listeners.reversed : listeners,
      );
      for (final transport in WampTransport.values) {
        expect(targets[transport]?.port, 8443);
        expect(targets[transport]?.secure, isTrue);
      }
    });
  }
}

ListenerSettings _listener(
  int port, {
  required bool secure,
  bool mixed = false,
}) => ListenerSettings(
  endpoint: '127.0.0.1:$port',
  authmethods: const ['anonymous'],
  protocols: [
    ListenerProtocol.rawsocket,
    ListenerProtocol.websocket,
    if (mixed) ListenerProtocol.http,
  ],
  tls: {
    'mode': secure ? 'native' : 'disabled',
    if (secure)
      'sni_certificates': [
        {
          'hostname': 'localhost',
          'certificate_chain_pem':
              '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----',
          'private_key_pem':
              '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----',
        },
      ],
  },
);
