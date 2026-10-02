import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  for (final transport in WampTransport.values) {
    for (final secure in [false, true]) {
      test('$transport secure=$secure round-trips every endpoint field', () {
        final json = <String, Object?>{
          'transport': transport.name,
          'host': '2001:db8::4',
          'port': 8443,
          'secure': secure,
          if (transport == WampTransport.websocket)
            'web_socket_path': '/agent tools',
        };
        final target = WampTransportTarget.fromJson(json);
        expect(target.transport, transport);
        expect(target.host, '2001:db8::4');
        expect(target.port, 8443);
        expect(target.secure, secure);
        expect(target.toJson(), json);
        if (transport == WampTransport.websocket) {
          expect(
            target.webSocketUri.toString(),
            '${secure ? 'wss' : 'ws'}://[2001:db8::4]:8443/agent%20tools',
          );
        } else {
          expect(() => target.webSocketUri, throwsStateError);
        }
      });

      test('$transport selects only the requested security map ($secure)', () {
        final clear = WampTransportTarget(
          transport: transport,
          host: 'clear.example',
          port: 8080,
          secure: false,
        );
        final tls = WampTransportTarget(
          transport: transport,
          host: 'secure.example',
          port: 8443,
          secure: true,
        );
        final scenario = _scenario(transport, secure);
        expect(
          resolveWampTransportTargetForScenario(
            scenario: scenario,
            wampTargets: {transport: clear},
            secureWampTargets: {transport: tls},
          ),
          same(secure ? tls : clear),
        );
        expect(
          () => resolveWampTransportTargetForScenario(
            scenario: scenario,
            wampTargets: secure ? {transport: clear} : {},
            secureWampTargets: secure ? {} : {transport: tls},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'No ${secure ? 'secure ' : ''}bench listener configured for WAMP transport ${transport.name}',
            ),
          ),
        );
      });
    }
  }

  test('missing optional JSON fields keep the legacy RawSocket defaults', () {
    final target = WampTransportTarget.fromJson({
      'host': 'localhost',
      'port': 8080,
    });
    expect(target.transport, WampTransport.rawsocket);
    expect(target.secure, isFalse);
    expect(target.webSocketPath, isNull);
    expect(target.toJson(), {
      'transport': 'rawsocket',
      'host': 'localhost',
      'port': 8080,
      'secure': false,
    });
  });

  test('websocket default path is independent of input and output maps', () {
    final json = <String, Object?>{
      'transport': 'ws',
      'host': 'localhost',
      'port': 8080,
    };
    final target = WampTransportTarget.fromJson(json);
    json['host'] = 'changed';
    target.toJson()['host'] = 'also-changed';
    expect(target.webSocketUri.toString(), 'ws://localhost:8080/wamp');
    expect(target.toJson(), {
      'transport': 'websocket',
      'host': 'localhost',
      'port': 8080,
      'secure': false,
    });
  });

  for (final field in ['host', 'port']) {
    for (final invalid in [null, true, <String>[]]) {
      test('rejects $field=$invalid instead of creating a partial target', () {
        expect(
          () => WampTransportTarget.fromJson({
            'host': 'localhost',
            'port': 8080,
            field: invalid,
          }),
          throwsFormatException,
        );
      });
    }
  }
  for (final transport in ['http', 'quic', 42]) {
    test('rejects unknown transport $transport', () {
      expect(
        () => WampTransportTarget.fromJson({
          'host': 'localhost',
          'port': 8080,
          'transport': transport,
        }),
        throwsFormatException,
      );
    });
  }

  for (final (endpoint, expectedHost) in [
    ('[::]:9090', '::1'),
    ('[2001:db8::4]:9090', '2001:db8::4'),
    ('localhost:9090', 'localhost'),
  ]) {
    test(
      'normalizes $endpoint without changing its port or websocket path',
      () {
        final targets = resolveWampTransportTargets([
          ListenerSettings(
            endpoint: endpoint,
            authmethods: const ['anonymous'],
            protocols: const [ListenerProtocol.websocket],
            websocket: const WebSocketListenerSettings(path: '/custom'),
          ),
          const ListenerSettings(
            endpoint: 'localhost:9999',
            authmethods: ['anonymous'],
            protocols: [
              ListenerProtocol.http,
              ListenerProtocol.http2,
              ListenerProtocol.http3,
            ],
          ),
        ]);
        expect(targets.keys, [WampTransport.websocket]);
        final target = targets[WampTransport.websocket]!;
        expect(target.host, expectedHost);
        expect(target.port, 9090);
        expect(target.webSocketPath, '/custom');
        expect(target.webSocketUri.host, expectedHost);
        expect(() => targets.clear(), throwsUnsupportedError);
      },
    );
  }
}

WampScenario _scenario(WampTransport transport, bool secure) => WampScenario(
  transport: transport,
  secureTransport: secure,
  serializer: WampSerializer.json,
  mode: WampMode.rpc,
  uri: 'bench.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 16,
);
