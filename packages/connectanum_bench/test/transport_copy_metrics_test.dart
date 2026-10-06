import 'package:connectanum_bench/src/transport_copy_metrics.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  group('mergeRouterTransportCopyMetrics', () {
    for (final boundaries in [
      null,
      'opaque',
      {'boundary': 'SDK'},
      [1],
      ['SDK', 1],
    ]) {
      test('malformed boundary metadata $boundaries fails closed', () {
        final client = _clientMetrics();
        final originalCoverage = <String, Object?>{
          'transport_copy_bytes': 'complete_client_connectanum_path',
          'unknown_boundaries': boundaries,
        };
        client['coverage'] = originalCoverage;
        final metrics = mergeRouterTransportCopyMetrics(
          client,
          scenario: _scenario(),
          before: _routerMetrics(dartToNative: 10),
          after: _routerMetrics(dartToNative: 16),
        );

        expect(metrics['transport_copy_bytes'], isA<Map>());
        expect(metrics['known_own_transport_copy_bytes'], 46);
        expect((metrics['coverage'] as Map)['transport_copy_bytes'], 'partial');
        expect(
          (metrics['coverage'] as Map)['unknown_boundaries'],
          contains('client transport copy coverage is incomplete'),
        );
        expect(
          originalCoverage['transport_copy_bytes'],
          'complete_client_connectanum_path',
        );
        expect(originalCoverage['unknown_boundaries'], same(boundaries));
      });
    }

    for (final invalid in [
      -1,
      0.5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      9007199254740992.0,
      '40',
      null,
    ]) {
      test(
        'invalid byte count $invalid remains unmeasured without throwing',
        () {
          final client = _clientMetrics(transportCopyBytes: invalid)
            ..['known_own_transport_copy_bytes'] = invalid;
          final metrics = mergeRouterTransportCopyMetrics(
            client,
            scenario: _scenario(),
            before: _routerMetrics(dartToNative: 10),
            after: _routerMetrics(dartToNative: 16),
          );

          expect(metrics['transport_copy_bytes'], isA<Map>());
          expect(metrics['known_own_transport_copy_bytes'], 6);
          expect(
            (metrics['coverage'] as Map)['transport_copy_bytes'],
            'partial',
          );
          expect(
            (metrics['coverage'] as Map)['unknown_boundaries'],
            contains('client transport copy counter is invalid or unavailable'),
          );
        },
      );
    }

    for (final count in [0.0, 40.0, 1 << 60]) {
      test(
        'exact nonnegative byte count $count preserves its integer value',
        () {
          final metrics = mergeRouterTransportCopyMetrics(
            _clientMetrics(transportCopyBytes: count)
              ..['known_own_transport_copy_bytes'] = count,
            scenario: _scenario(),
            before: _routerMetrics(dartToNative: 10),
            after: _routerMetrics(dartToNative: 16),
          );

          expect(metrics['transport_copy_bytes'], count.toInt() + 6);
          expect(metrics['known_own_transport_copy_bytes'], count.toInt() + 6);
          expect((metrics['coverage'] as Map)['unknown_boundaries'], isEmpty);
        },
      );
    }

    test('absent or malformed client maps retain only known router copies', () {
      for (final client in <Map<String, Object?>>[
        {},
        {'coverage': 'opaque', 'known_own_copy_breakdown': 'opaque'},
        {
          'known_own_copy_breakdown': {'client': 'opaque'},
        },
      ]) {
        final metrics = mergeRouterTransportCopyMetrics(
          client,
          scenario: _scenario(),
          before: _routerMetrics(dartToNative: 10),
          after: _routerMetrics(dartToNative: 16),
        );

        expect(metrics['transport_copy_bytes'], isA<Map>());
        expect(metrics['known_own_transport_copy_bytes'], 6);
        expect((metrics['coverage'] as Map)['transport_copy_bytes'], 'partial');
        expect(
          (metrics['known_own_copy_breakdown'] as Map)['client'],
          isEmpty,
        );
        expect(client.containsKey('known_own_transport_copy_bytes'), isFalse);
      }
    });

    test('TLS plaintext count requires valid counters on both sides', () {
      for (final clientTls in [null, double.infinity, -1]) {
        final metrics = mergeRouterTransportCopyMetrics(
          _clientMetrics(tlsPlaintextAcceptedBytes: clientTls),
          scenario: _scenario(secureTransport: true),
          before: _routerMetrics(tlsPlaintext: 20),
          after: _routerMetrics(tlsPlaintext: 33),
        );
        expect(metrics['tls_plaintext_accepted_bytes'], isA<Map>());
        expect(metrics['tls_copy_bytes'], isA<Map>());
      }
      final metrics = mergeRouterTransportCopyMetrics(
        _clientMetrics(tlsPlaintextAcceptedBytes: 7),
        scenario: _scenario(secureTransport: true),
        before: _routerMetrics(tlsPlaintext: null),
        after: _routerMetrics(tlsPlaintext: null),
      );
      expect(metrics['tls_plaintext_accepted_bytes'], isA<Map>());
      expect(metrics['tls_copy_bytes'], isA<Map>());
    });

    test('counts client and router cleartext RawSocket copies', () {
      final metrics = mergeRouterTransportCopyMetrics(
        _clientMetrics(),
        scenario: _scenario(),
        before: _routerMetrics(dartToNative: 10),
        after: _routerMetrics(dartToNative: 16),
      );

      expect(metrics['transport_copy_bytes'], 46);
      expect(metrics['known_own_transport_copy_bytes'], 46);
      expect(
        (metrics['coverage'] as Map)['transport_copy_bytes'],
        'complete_connectanum_owned_path',
      );
      expect((metrics['coverage'] as Map)['unknown_boundaries'], isEmpty);
    });

    test('counts router WebSocket coalescing and native-copy bytes', () {
      final metrics = mergeRouterTransportCopyMetrics(
        _clientMetrics(),
        scenario: _scenario(transport: WampTransport.websocket),
        before: _routerMetrics(
          dartToNative: 10,
          websocketCoalesce: 20,
        ),
        after: _routerMetrics(
          dartToNative: 16,
          websocketCoalesce: 29,
        ),
      );

      expect(metrics['transport_copy_bytes'], 55);
      expect(metrics['known_own_transport_copy_bytes'], 55);
      expect(
        ((metrics['known_own_copy_breakdown'] as Map)['router']
            as Map)['websocket_coalesce_copy_bytes'],
        9,
      );
      expect(
        (metrics['coverage'] as Map)['transport_copy_bytes'],
        'complete_connectanum_owned_path',
      );
    });

    test(
      'keeps client copy totals as a lower bound when router metrics are absent',
      () {
        final metrics = mergeRouterTransportCopyMetrics(
          _clientMetrics(),
          scenario: _scenario(),
          before: null,
          after: null,
        );

        expect(metrics['known_own_transport_copy_bytes'], 40);
        expect(metrics['transport_copy_bytes'], isA<Map>());
        expect(
          (metrics['coverage'] as Map)['transport_copy_bytes'],
          'partial',
        );
        expect(
          (metrics['coverage'] as Map)['unknown_boundaries'],
          contains('router transport copy snapshots are unavailable'),
        );
      },
    );

    test('does not claim complete coverage for missing WebSocket counters', () {
      final metrics = mergeRouterTransportCopyMetrics(
        _clientMetrics(),
        scenario: _scenario(transport: WampTransport.websocket),
        before: _routerMetrics(
          dartToNative: 10,
          websocketCoalesce: null,
        ),
        after: _routerMetrics(
          dartToNative: 16,
          websocketCoalesce: null,
        ),
      );

      expect(metrics['known_own_transport_copy_bytes'], 46);
      expect(metrics['transport_copy_bytes'], isA<Map>());
      expect(
        (metrics['coverage'] as Map)['transport_copy_bytes'],
        'partial',
      );
      expect(
        (metrics['coverage'] as Map)['unknown_boundaries'],
        contains('router WebSocket coalescing copy counter is unavailable'),
      );
    });

    test(
      'keeps TLS copy totals unmeasured while summing accepted plaintext',
      () {
        final metrics = mergeRouterTransportCopyMetrics(
          _clientMetrics(
            transportCopyBytes: {'status': 'not_measured'},
            tlsPlaintextAcceptedBytes: 7,
          ),
          scenario: _scenario(secureTransport: true),
          before: _routerMetrics(tlsPlaintext: 20),
          after: _routerMetrics(tlsPlaintext: 33),
        );

        expect(metrics['transport_copy_bytes'], isA<Map>());
        expect(metrics['tls_copy_bytes'], isA<Map>());
        expect(metrics['tls_plaintext_accepted_bytes'], 20);
        expect(
          (metrics['coverage'] as Map)['transport_copy_bytes'],
          'partial',
        );
      },
    );

    test('preserves client unknown boundaries in the aggregate report', () {
      final clientMetrics =
          _clientMetrics(
              transportCopyBytes: {'status': 'not_measured'},
            )
            ..['coverage'] = <String, Object?>{
              'transport_copy_bytes': 'partial',
              'unknown_boundaries': <String>['Dart socket writes'],
            };
      final metrics = mergeRouterTransportCopyMetrics(
        clientMetrics,
        scenario: _scenario(),
        before: _routerMetrics(dartToNative: 10),
        after: _routerMetrics(dartToNative: 16),
      );

      expect(
        (metrics['coverage'] as Map)['unknown_boundaries'],
        containsAll([
          'Dart socket writes',
          'client transport copy coverage is incomplete',
        ]),
      );
      expect((metrics['coverage'] as Map)['transport_copy_bytes'], 'partial');
      expect(metrics['transport_copy_bytes'], isA<Map>());
    });
  });
}

WampScenario _scenario({
  WampTransport transport = WampTransport.rawsocket,
  bool secureTransport = false,
}) => WampScenario(
  transport: transport,
  secureTransport: secureTransport,
  serializer: WampSerializer.flatbuffers,
  mode: WampMode.rpc,
  uri: 'bench.rpc.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 1024,
);

Map<String, Object?> _clientMetrics({
  Object? transportCopyBytes = 40,
  Object? tlsPlaintextAcceptedBytes = 0,
}) => {
  'transport_copy_bytes': transportCopyBytes,
  'known_own_transport_copy_bytes': 40,
  'known_own_copy_breakdown': <String, Object?>{
    'client': <String, Object?>{'dart_to_native_copy_bytes': 40},
  },
  'coverage': <String, Object?>{
    'transport_copy_bytes': 'complete_client_connectanum_path',
    'unknown_boundaries': <String>[],
  },
  'tls_copy_bytes': {'status': 'not_applicable', 'reason': 'cleartext'},
  'tls_plaintext_accepted_bytes': tlsPlaintextAcceptedBytes,
};

NativeRouterTransportCopyMetrics _routerMetrics({
  int dartToNative = 0,
  int? websocketCoalesce = 0,
  int? tlsPlaintext = 0,
}) => NativeRouterTransportCopyMetrics(
  dartToNativeCopiedBytesTotal: dartToNative,
  websocketMaskCopyBytesTotal: 0,
  websocketCoalesceCopyBytesTotal: websocketCoalesce,
  tlsPlaintextAcceptedBytesTotal: tlsPlaintext,
);
