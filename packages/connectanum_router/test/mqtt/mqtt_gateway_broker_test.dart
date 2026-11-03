import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/mqtt.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  late MqttQos0Broker broker;
  late _Policy policy;
  final sent = <int, List<Uint8List>>{};
  final closed = <int>{};

  void connect(int id, String realm, [MqttVersion version = MqttVersion.v5]) {
    sent[id] = [];
    broker.attachNativeConnection(
      id,
      realm: realm,
      send: sent[id]!.add,
      close: () => closed.add(id),
    );
    broker.receiveNativeChunk(
      id,
      MqttPacketCodec.encodeConnect(
        MqttConnect(version: version, clientId: 'peer-$id'),
      ),
    );
    sent[id]!.clear();
  }

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));

  Future<void> subscribe(int id, String filter) async {
    broker.receiveNativeChunk(
      id,
      MqttPacketCodec.encodeSubscribe(
        MqttVersion.v5,
        packetId: 1,
        filter: filter,
      ),
    );
    await tick();
    sent[id]!.clear();
  }

  void publish(int id, String topic, List<int> bytes) =>
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: topic,
          payload: Uint8List.fromList(bytes),
        ),
      );

  setUp(() {
    broker = MqttQos0Broker.native();
    policy = _Policy();
    sent.clear();
    closed.clear();
    broker.installGateway('a', policy);
  });
  tearDown(() => broker.close());

  test(
    'authorizes before delivery and preserves realm, bytes and identity',
    () async {
      connect(1, 'a');
      connect(2, 'a');
      connect(3, 'b');
      await subscribe(2, '#');
      await subscribe(3, '#');
      publish(1, 'sensors/é', [0, 255, 17]);
      await tick();
      expect(policy.publications.single.topic, 'sensors/é');
      expect(policy.publications.single.payload, [0, 255, 17]);
      expect(policy.peers.single.clientId, 'peer-1');
      expect(policy.peers.single.connectionId, 1);
      expect(policy.peers.single.realm, 'a');
      expect(policy.peers.single.version, MqttVersion.v5);
      expect(sent[2], hasLength(1));
      expect(sent[3], isEmpty);
      expect(broker.gatewayMetrics['pending_bytes'], 0);
    },
  );

  test(
    'denied publication reaches neither MQTT nor the gateway output',
    () async {
      policy.allowPublish = false;
      connect(1, 'a');
      connect(2, 'a');
      await subscribe(2, '#');
      publish(1, 'denied', [1]);
      await tick();
      expect(sent[2], isEmpty);
      expect(closed, contains(1));
    },
  );

  test('wildcard subscribers cannot receive denied concrete topics', () async {
    policy.allowReceive = false;
    connect(1, 'a');
    connect(2, 'a');
    await subscribe(2, '#');
    publish(1, 'private/topic', [1]);
    await tick();
    expect(policy.receivedTopics, ['private/topic']);
    expect(sent[2], isEmpty);
  });

  test('external gateway publications require the installed policy', () async {
    connect(2, 'a');
    await subscribe(2, '#');
    broker.publishFromGateway(
      'a',
      policy,
      MqttGatewayPublication(
        topic: 'a/b',
        payload: Uint8List.fromList([0, 255]),
      ),
    );
    await tick();
    expect(sent[2], hasLength(1));
    expect(
      () => broker.publishFromGateway(
        'a',
        _Policy(),
        MqttGatewayPublication(topic: 'a/b', payload: Uint8List(0)),
      ),
      throwsStateError,
    );
  });

  test('pending authorization is bounded and stops after disconnect', () async {
    final permission = Completer<bool>();
    policy.publishDecision = permission.future;
    connect(1, 'a');
    connect(2, 'a');
    await subscribe(2, '#');
    publish(1, 'pending', List<int>.filled(100, 7));
    await tick();
    expect(broker.gatewayMetrics['pending_bytes'], greaterThan(0));
    broker.closeNativeConnection(1);
    permission.complete(true);
    await tick();
    expect(sent[2], isEmpty);
    expect(broker.gatewayMetrics['pending_bytes'], 0);
  });

  test(
    'a live policy cannot be replaced and a closed one remains deny-only',
    () async {
      expect(() => broker.installGateway('a', _Policy()), throwsStateError);
      policy.closed = true;
      connect(1, 'a');
      publish(1, 'closed', [1]);
      await tick();
      expect(closed, contains(1));
      broker.installGateway('a', _Policy());
    },
  );

  for (final fromWamp in [false, true]) {
    test(
      'slow MQTT recipient is bounded and isolated, WAMP origin=$fromWamp',
      () async {
        connect(1, 'a');
        connect(2, 'a');
        await subscribe(2, '#');
        sent[4] = [];
        broker.attachNativeConnection(
          4,
          realm: 'a',
          send: (bytes) {
            if (bytes.first >> 4 == MqttPacketType.publish.wireValue) {
              throw NativeTransportException(
                NativeTransportErrorCode.sendQueueFull,
                'controlled slow peer',
              );
            }
            sent[4]!.add(bytes);
          },
          close: () => closed.add(4),
        );
        broker.receiveNativeChunk(
          4,
          MqttPacketCodec.encodeConnect(
            const MqttConnect(version: MqttVersion.v5, clientId: 'slow'),
          ),
        );
        await subscribe(4, '#');
        for (var i = 0; i < 140; i++) {
          final payload = Uint8List(32768)..[0] = i;
          if (fromWamp) {
            broker.publishFromGateway(
              'a',
              policy,
              MqttGatewayPublication(topic: 'load', payload: payload),
            );
          } else {
            publish(1, 'load', payload);
          }
          await Future<void>.delayed(Duration.zero);
        }
        await tick();
        expect(closed, contains(4));
        expect(closed, isNot(contains(1)));
        expect(sent[2], hasLength(140));
        for (var i = 0; i < 140; i++) {
          final frame = MqttFrameDecoder().add(sent[2]![i]).single;
          expect(
            MqttPacketCodec.decodePublish(frame, MqttVersion.v5).payload[0],
            i,
          );
        }
        expect(broker.gatewayMetrics['pending_bytes'], 0);
        expect(broker.gatewayMetrics['pending_tasks'], 0);
        expect(broker.gatewayMetrics['outbound_bytes'], 0);
      },
    );
  }

  test('a blocked policy cannot retain an unbounded burst', () async {
    final permission = Completer<bool>();
    policy.publishDecision = permission.future;
    connect(1, 'a');
    for (var i = 0; i < 258; i++) {
      publish(1, 'burst', [i & 255]);
    }
    await tick();
    expect(closed, contains(1));
    permission.complete(true);
    await tick();
    expect(broker.gatewayMetrics['pending_bytes'], 0);
    expect(broker.gatewayMetrics['pending_tasks'], 0);
  });

  test(
    'policy ordering keeps control packets responsive after a publication',
    () async {
      connect(1, 'a');
      publish(1, 'topic', [1]);
      broker.receiveNativeChunk(1, Uint8List.fromList([0xc0, 0]));
      await tick();
      expect(sent[1], contains(equals([0xd0, 0])));
    },
  );
}

final class _Policy implements MqttBrokerGatewayPolicy {
  bool closed = false;
  bool allowPublish = true;
  bool allowReceive = true;
  Future<bool>? publishDecision;
  final peers = <MqttPeerContext>[];
  final publications = <MqttPublish>[];
  final receivedTopics = <String>[];

  @override
  bool get isClosed => closed;

  @override
  Future<bool> publish(MqttPeerContext peer, MqttPublish publication) async {
    peers.add(peer);
    publications.add(publication);
    return publishDecision ?? allowPublish;
  }

  @override
  Future<bool> receive(MqttPeerContext peer, String topic) async {
    receivedTopics.add(topic);
    return allowReceive;
  }

  @override
  Future<bool> subscribe(MqttPeerContext peer, String filter) async => true;
}
