@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_bench/src/mqtt_gateway_measurement.dart';
import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';
import 'package:test/test.dart';

Map<String, dynamic> profile([Map<String, Object?> changes = const {}]) => {
  'path': 'mqtt_to_wamp',
  'transport': 'tcp',
  'serializer': 'cbor',
  'mqtt_version': '5',
  'payload_bytes': 24,
  'window': 2,
  'port': 1,
  'native_library': 'fake',
  ...changes,
};

final class Peer implements GatewayBenchmarkPeer {
  final controller = StreamController<Uint8List>.broadcast(sync: true);
  final publications = <Uint8List>[];
  int closed = 0;
  @override
  Stream<Uint8List> get messages => controller.stream;
  @override
  Future<void> publish(Uint8List payload) async => publications.add(payload);
  @override
  Future<void> close() async {
    closed++;
    await controller.close();
  }
}

final class Server implements GatewayBenchmarkServer {
  int closed = 0;
  @override
  int get port => 1234;
  @override
  Map<String, int> get metrics => {'pending_bytes': 0};
  @override
  Future<Map<String, int>> sampleQueues() async => metrics;
  @override
  Future<void> close() async {
    closed++;
  }
}

void main() {
  test(
    'profiles cover both protocols, controls and all supported links/codecs',
    () {
      for (final path in [
        'mqtt_to_mqtt',
        'wamp_to_wamp',
        'wamp_to_wamp_ack',
        'mqtt_to_wamp',
        'wamp_to_mqtt',
      ]) {
        for (final link in ['tcp', 'tls', 'ws', 'wss']) {
          for (final codec in ['json', 'msgpack', 'cbor', 'flatbuffers']) {
            final config = GatewayBenchmarkConfig(
              profile({
                'path': path,
                'transport': link,
                'serializer': codec,
                'certificate': 'cert',
                'key': 'key',
              }),
            );
            expect(config.secure, link == 'tls' || link == 'wss');
            expect(config.websocket, link == 'ws' || link == 'wss');
            expect(
              config.translation,
              path == 'mqtt_to_wamp' || path == 'wamp_to_mqtt',
            );
            expect(config.mqttFor('publisher'), path.startsWith('mqtt'));
            expect(config.mqttFor('subscriber'), path.endsWith('mqtt'));
            expect(config.ordered, path != 'wamp_to_mqtt');
          }
        }
      }
      for (final changes in <Map<String, Object?>>[
        {'path': 'bad'},
        {'transport': 'bad'},
        {'serializer': 'bad'},
        {'mqtt_version': 'bad'},
        {'payload_bytes': 23},
        {'payload_bytes': 65537},
        {'window': 0},
        {'window': 513},
        {'port': -1},
        {'port': 65536},
        {'native_library': ''},
        {'transport': 'tls'},
        {'transport': 'tls', 'certificate': 'cert'},
      ]) {
        expect(
          () => GatewayBenchmarkConfig(profile(changes)),
          throwsArgumentError,
        );
      }
      expect(
        GatewayBenchmarkConfig(
          profile({'path': 'wamp_to_mqtt', 'window': 1}),
        ).ordered,
        isTrue,
      );
    },
  );

  test(
    'server separates ready, warm, sample and closed lifecycle phases',
    () async {
      final server = Server();
      final events = <Map<String, Object?>>[];
      await runGatewayBenchmarkWorker(
        ['server', jsonEncode(profile())],
        input: Stream.fromIterable([
          jsonEncode({'op': 'begin', 'phase': 1, 'count': 2}),
          jsonEncode({'op': 'sample'}),
          jsonEncode({'op': 'close'}),
        ]),
        emit: events.add,
        readRss: () => 100,
        serverFactory: (_) async => server,
      );
      expect(events.map((e) => e['kind']), [
        'ready',
        'armed',
        'sampled',
        'closed',
      ]);
      expect(events.first['port'], 1234);
      expect(events[2]['queues'], {'pending_bytes': 0});
      expect(events[2]['memory'], {
        'warm_rss_bytes': 100,
        'peak_rss_bytes': 100,
        'drained_rss_bytes': 100,
      });
      expect(server.closed, 1);
    },
  );

  test(
    'publisher credits bound in-flight load and preserve exact payload/sequence',
    () async {
      final peer = Peer();
      final events = <Map<String, Object?>>[];
      await runGatewayBenchmarkWorker(
        ['publisher', jsonEncode(profile())],
        input: Stream.fromIterable([
          jsonEncode({'op': 'begin', 'phase': 2, 'count': 3}),
          jsonEncode({'op': 'publish', 'phase': 2, 'count': 3}),
          jsonEncode({'op': 'credit', 'phase': 2, 'received': 2}),
          jsonEncode({'op': 'credit', 'phase': 2, 'received': 3}),
          jsonEncode({'op': 'sample'}),
          jsonEncode({'op': 'close'}),
        ]),
        emit: events.add,
        readRss: () => 100,
        nowMicros: () => 100,
        peerFactory: (_, role) async {
          expect(role, 'publisher');
          return peer;
        },
      );
      expect(events.map((e) => e['kind']), [
        'ready',
        'armed',
        'sent',
        'sampled',
        'closed',
      ]);
      final measurement = GatewayDeliveryMeasurement(
        payloadBytes: 24,
        requireOrder: true,
      )..begin(2, 3);
      for (final bytes in peer.publications) {
        measurement.accept(bytes, 110);
      }
      expect(measurement.summary()['received'], 3);
      expect(peer.closed, 1);
    },
  );

  test(
    'subscriber validates before progress and reports malformed payload/stream errors',
    () async {
      final peer = Peer();
      final commands = StreamController<String>();
      final done = Completer<void>();
      final events = <Map<String, Object?>>[];
      final work = runGatewayBenchmarkWorker(
        ['subscriber', jsonEncode(profile())],
        input: commands.stream,
        readRss: () => 100,
        nowMicros: () => 110,
        peerFactory: (_, __) async => peer,
        emit: (event) {
          events.add(event);
          if (event['kind'] == 'ready') {
            commands.add(jsonEncode({'op': 'begin', 'phase': 3, 'count': 3}));
          } else if (event['kind'] == 'armed') {
            peer.controller.add(Uint8List(0));
            peer.controller.addError(StateError('transport failure'));
            for (var i = 0; i < 3; i++) {
              peer.controller.add(gatewayBenchmarkPayload(24, 3, i, 100));
            }
          } else if (event['kind'] == 'received') {
            commands.add(jsonEncode({'op': 'close'}));
          } else if (event['kind'] == 'closed') {
            done.complete();
          }
        },
      );
      await done.future.timeout(const Duration(seconds: 2));
      await work;
      await commands.close();
      expect(events.where((e) => e['kind'] == 'error'), hasLength(2));
      expect(
        events.where((e) => e['kind'] == 'progress').map((e) => e['received']),
        [2, 3],
      );
      expect(events.singleWhere((e) => e['kind'] == 'received')['received'], 3);
      expect(peer.closed, 1);
    },
  );

  test(
    'invalid control messages fail and still release acquired resources',
    () async {
      for (final commands in <List<Map<String, Object?>>>[
        [
          {'op': 'stall', 'milliseconds': 1},
        ],
        [
          {'op': 'unknown'},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 0},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 1000001},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 1},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 1},
          {'op': 'credit', 'phase': 2, 'received': 1},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 1},
          {'op': 'sample', 'phase': 1, 'received': 1},
        ],
        [
          {'op': 'publish', 'phase': 1, 'count': 1},
          {'op': 'credit', 'phase': 1, 'received': 0},
        ],
      ]) {
        final peer = Peer();
        await expectLater(
          runGatewayBenchmarkWorker(
            ['publisher', jsonEncode(profile())],
            input: Stream.fromIterable(commands.map(jsonEncode)),
            emit: (_) {},
            peerFactory: (_, __) async => peer,
            readRss: () => 100,
          ),
          throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
        );
        expect(peer.closed, 1);
      }
      final server = Server();
      await expectLater(
        runGatewayBenchmarkWorker(
          ['server', jsonEncode(profile())],
          input: Stream.value(jsonEncode({'op': 'publish'})),
          emit: (_) {},
          readRss: () => 100,
          serverFactory: (_) async => server,
        ),
        throwsStateError,
      );
      expect(server.closed, 1);
      for (final args in <List<String>>[
        [],
        ['bad', '{}'],
      ]) {
        await expectLater(runGatewayBenchmarkWorker(args), throwsArgumentError);
      }
    },
  );

  test(
    'a deliberately stalled subscriber reports pause and resume boundaries',
    () async {
      final peer = Peer();
      final events = <Map<String, Object?>>[];
      await runGatewayBenchmarkWorker(
        ['subscriber', jsonEncode(profile())],
        input: Stream.fromIterable(
          [
            {'op': 'begin', 'phase': 4, 'count': 1},
            {'op': 'stall', 'milliseconds': 1},
            {'op': 'close'},
          ].map(jsonEncode),
        ),
        emit: events.add,
        readRss: () => 100,
        peerFactory: (_, __) async => peer,
      );
      expect(events.map((e) => e['kind']), [
        'ready',
        'armed',
        'stalled',
        'resumed',
        'closed',
      ]);
      expect(events[2]['phase'], 4);
      for (final milliseconds in [0, 60001]) {
        final invalid = Peer();
        await expectLater(
          runGatewayBenchmarkWorker(
            ['subscriber', jsonEncode(profile())],
            input: Stream.value(
              jsonEncode({'op': 'stall', 'milliseconds': milliseconds}),
            ),
            emit: (_) {},
            readRss: () => 100,
            peerFactory: (_, __) async => invalid,
          ),
          throwsArgumentError,
        );
        expect(invalid.closed, 1);
      }
    },
  );

  test(
    'a subscriber disconnect is reported before the benchmark can time out',
    () async {
      final peer = Peer();
      final commands = StreamController<String>();
      final events = <Map<String, Object?>>[];
      await runGatewayBenchmarkWorker(
        ['subscriber', jsonEncode(profile())],
        input: commands.stream,
        readRss: () => 100,
        peerFactory: (_, __) async => peer,
        emit: (event) {
          events.add(event);
          if (event['kind'] == 'ready') {
            peer.controller.close().ignore();
          } else if (event['kind'] == 'disconnected') {
            commands.add(jsonEncode({'op': 'close'}));
          }
        },
      );
      await commands.close();
      expect(events.map((e) => e['kind']), ['ready', 'disconnected', 'closed']);
      expect(peer.closed, 1);
    },
  );

  test(
    'EOF drains a peer and uncredited diagnostic load can be run explicitly',
    () async {
      final peer = Peer();
      await runGatewayBenchmarkWorker(
        ['publisher', jsonEncode(profile())],
        input: Stream.value(
          jsonEncode({
            'op': 'publish',
            'phase': 1,
            'count': 1,
            'flow_control': false,
          }),
        ),
        emit: (_) {},
        readRss: () => 100,
        peerFactory: (_, __) async => peer,
      );
      expect(peer.publications, hasLength(1));
      expect(peer.closed, 1);
      await expectLater(
        connectGatewayBenchmarkPeer(
          GatewayBenchmarkConfig(profile({'port': 0})),
          'publisher',
        ),
        throwsArgumentError,
      );
    },
  );
}
