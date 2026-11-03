@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:test/test.dart';

const _topic = 'receive/burst';

void main() {
  for (final websocket in [false, true]) {
    for (final version in MqttVersion.values) {
      final label = '${websocket ? 'WebSocket' : 'TCP'} $version';
      test('closing during receive stops the unread backlog: $label', () async {
        final broker = await _Broker.bind(websocket, version);
        addTearDown(broker.dispose);
        final client = await broker.connect(version);
        addTearDown(client.close);
        final received = <MqttPublish>[];
        final done = Completer<void>();
        Future<void>? closing;
        client.messages.listen(
          (message) {
            received.add(message);
            closing ??= client.close();
          },
          onError: done.completeError,
          onDone: done.complete,
        );
        await client.subscribe(_topic);
        final peer = await broker.accepted.future;
        peer.send(
          _publications(version, [
            Uint8List(70000)..fillRange(0, 70000, 1),
            Uint8List(70000)..fillRange(0, 70000, 2),
            Uint8List(70000)..fillRange(0, 70000, 3),
          ]),
        );
        await done.future.timeout(const Duration(seconds: 3));
        await closing!.timeout(const Duration(seconds: 3));
        expect(received, hasLength(1));
        expect(received.single.topic, _topic);
        expect(received.single.payload, hasLength(70000));
        expect(received.single.payload, everyElement(1));
        await peer.disconnected.future.timeout(const Duration(seconds: 3));
        expect(peer.disconnects, 1);
      });

      test(
        'large receive batches preserve payloads and pending controls: $label',
        () async {
          final broker = await _Broker.bind(websocket, version);
          addTearDown(broker.dispose);
          final client = await broker.connect(version);
          addTearDown(client.close);
          final received = <MqttPublish>[];
          final done = Completer<void>();
          Future<void>? ping;
          Future<void>? subscribe;
          final listener = client.messages.listen((message) {
            received.add(message);
            ping ??= client.ping();
            subscribe ??= client.subscribe('after/burst');
            if (received.length == 3) done.complete();
          }, onError: done.completeError);
          addTearDown(listener.cancel);
          await client.subscribe(_topic);
          final payloads = [
            for (final size in [65536, 65537, 131072])
              Uint8List.fromList(
                List.generate(size, (i) => (i * 31 + size) & 255),
              ),
          ];
          (await broker.accepted.future).send(_publications(version, payloads));
          await done.future.timeout(const Duration(seconds: 3));
          await Future.wait([
            ping!,
            subscribe!,
          ]).timeout(const Duration(seconds: 3));
          for (var i = 0; i < payloads.length; i++) {
            expect(received[i].topic, _topic);
            expect(received[i].payload, payloads[i]);
          }
        },
      );

      if (websocket) {
        test('malformed backlog tail fails pending controls: $label', () async {
          final broker = await _Broker.bind(true, version);
          addTearDown(broker.dispose);
          final client = await broker.connect(version);
          addTearDown(client.close);
          final received = <MqttPublish>[];
          final errors = <Object>[];
          final done = Completer<void>();
          client.messages.listen(
            received.add,
            onError: errors.add,
            onDone: done.complete,
          );
          await client.subscribe(_topic);
          final peer = await broker.accepted.future;
          peer.answerPing = false;
          final pending = expectLater(
            client.ping(),
            throwsA(isA<MqttProtocolException>()),
          );
          await peer.pingSeen.future.timeout(const Duration(seconds: 3));
          final prefix = _publications(version, [
            Uint8List(70000)..fillRange(0, 70000, 7),
            Uint8List(70000)..fillRange(0, 70000, 8),
          ]);
          peer.send(
            (BytesBuilder(copy: false)
                  ..add(prefix)
                  ..add([0, 0]))
                .takeBytes(),
          );
          await pending;
          await done.future.timeout(const Duration(seconds: 3));
          expect(received, isNotEmpty);
          expect(received.length, lessThanOrEqualTo(2));
          for (var i = 0; i < received.length; i++) {
            expect(received[i].payload, hasLength(70000));
            expect(received[i].payload, everyElement(7 + i));
          }
          expect(
            errors.any(
              (error) =>
                  error is MqttProtocolException &&
                  error.message == 'invalid MQTT control packet type',
            ),
            isTrue,
          );
        });
      }
    }
  }
}

Uint8List _publications(MqttVersion version, List<Uint8List> payloads) {
  final bytes = BytesBuilder(copy: false);
  for (final payload in payloads) {
    bytes.add(
      MqttPacketCodec.encodePublish(version, topic: _topic, payload: payload),
    );
  }
  return bytes.takeBytes();
}

final class _Peer {
  _Peer(
    Stream<List<int>> input,
    this.send,
    this.close,
    MqttVersion version,
  ) {
    final decoder = MqttFrameDecoder();
    subscription = input.listen((data) {
      for (final frame in decoder.add(Uint8List.fromList(data))) {
        switch (frame.type) {
          case MqttPacketType.connect:
            send(MqttPacketCodec.encodeConnack(version, reasonCode: 0));
          case MqttPacketType.subscribe:
            final packet = MqttPacketCodec.decodeSubscribe(frame, version);
            send(MqttPacketCodec.encodeSuback(version, packet.packetId, [0]));
          case MqttPacketType.pingreq:
            if (!pingSeen.isCompleted) pingSeen.complete();
            if (answerPing) {
              send(
                MqttFrame(
                  MqttPacketType.pingresp,
                  flags: 0,
                  body: Uint8List(0),
                ).encode(),
              );
            }
          case MqttPacketType.disconnect:
            disconnects++;
            if (!disconnected.isCompleted) disconnected.complete();
          default:
            fail('Unexpected client packet ${frame.type}');
        }
      }
    });
  }
  final void Function(Uint8List) send;
  final Future<void> Function() close;
  late final StreamSubscription<List<int>> subscription;
  final disconnected = Completer<void>();
  final pingSeen = Completer<void>();
  bool answerPing = true;
  int disconnects = 0;
}

final class _Broker {
  _Broker(this.port, this.websocket, this.closeServer);
  final int port;
  final bool websocket;
  final Future<void> Function() closeServer;
  final accepted = Completer<_Peer>();

  static Future<_Broker> bind(bool websocket, MqttVersion version) async {
    if (websocket) {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final broker = _Broker(server.port, true, () async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (_) => 'mqtt',
        );
        broker.accepted.complete(
          _Peer(
            socket.cast<List<int>>(),
            socket.add,
            () async {
              await socket.close();
            },
            version,
          ),
        );
      });
      return broker;
    }
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final broker = _Broker(server.port, false, () async {
      await server.close();
    });
    server.listen((socket) {
      broker.accepted.complete(
        _Peer(
          socket,
          socket.add,
          () async {
            socket.destroy();
          },
          version,
        ),
      );
    });
    return broker;
  }

  Future<MqttQos0Client> connect(MqttVersion version) => websocket
      ? MqttQos0Client.connectWebSocket(
          Uri.parse('ws://127.0.0.1:$port/mqtt'),
          clientId: 'receive-test',
          version: version,
        )
      : MqttQos0Client.connect(
          '127.0.0.1',
          port,
          clientId: 'receive-test',
          version: version,
        );

  Future<void> dispose() async {
    if (accepted.isCompleted) {
      final peer = await accepted.future;
      await peer.close();
      await peer.subscription.cancel();
    }
    await closeServer();
  }
}
