import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/mqtt.dart';
import 'package:test/test.dart';

void main() {
  test(
    'anonymous provisional listener binds only a loopback address',
    () async {
      for (final host in ['0.0.0.0', '::', 'localhost']) {
        await expectLater(
          MqttQos0Broker.bind(host, 0),
          throwsArgumentError,
          reason: host,
        );
      }
    },
  );

  test(
    'two Connectanum clients exchange exact binary QoS 0 payloads',
    () async {
      final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
      final subscriber = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'subscriber',
        version: MqttVersion.v5,
      );
      final publisher = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'publisher',
        version: MqttVersion.v311,
      );
      addTearDown(() async {
        await publisher.close();
        await subscriber.close();
        await broker.close();
      });

      await subscriber.subscribe('sensors/+/raw');
      final received = subscriber.messages.first.timeout(
        const Duration(seconds: 3),
      );
      await publisher.publish(
        'sensors/one/raw',
        Uint8List.fromList([0, 255, 0, 17]),
      );
      final message = await received;
      expect(message.topic, 'sensors/one/raw');
      expect(message.payload, [0, 255, 0, 17]);
    },
  );

  test('MQTT 5 publisher reaches MQTT 3.1.1 wildcard subscriber', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final subscriber = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'v311-sub',
      version: MqttVersion.v311,
    );
    final publisher = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'v5-pub',
      version: MqttVersion.v5,
    );
    addTearDown(() async {
      await publisher.close();
      await subscriber.close();
      await broker.close();
    });
    await subscriber.subscribe('sensors/#');
    final received = subscriber.messages.first.timeout(
      const Duration(seconds: 3),
    );
    await publisher.publish('sensors/one/raw', Uint8List.fromList([1, 2, 3]));
    expect((await received).payload, [1, 2, 3]);
    final parent = subscriber.messages.first.timeout(
      const Duration(seconds: 3),
    );
    await publisher.publish('sensors', Uint8List.fromList([4]));
    expect((await parent).payload, [4]);
  });

  test('batched wire publications arrive once and in order', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final subscriber = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'batch-sub',
    );
    final publisher = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(() async {
      publisher.destroy();
      await subscriber.close();
      await broker.close();
    });
    await subscriber.subscribe('batch/topic');
    final received = subscriber.messages
        .take(64)
        .toList()
        .timeout(
          const Duration(seconds: 3),
        );
    final wire = BytesBuilder(copy: false)
      ..add(
        MqttPacketCodec.encodeConnect(
          const MqttConnect(version: MqttVersion.v5, clientId: 'batch-pub'),
        ),
      );
    for (var id = 0; id < 64; id++) {
      wire.add(
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: 'batch/topic',
          payload: Uint8List.fromList([id]),
        ),
      );
    }
    publisher.add(wire.takeBytes());
    await publisher.flush();
    await publisher.close();
    expect(
      (await received).map((message) => message.payload.single).toList(),
      List<int>.generate(64, (id) => id),
    );
  });

  test('client batch bounds and ordered delivery', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final subscriber = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'batch-api-sub',
    );
    final publisher = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'batch-api-pub',
    );
    addTearDown(() async {
      await publisher.close();
      await subscriber.close();
      await broker.close();
    });
    await subscriber.subscribe('batch/api');
    await publisher.publishBatch('batch/api', const []);
    await expectLater(
      publisher.publishBatch(
        'batch/api',
        List<Uint8List>.generate(513, (id) => Uint8List.fromList([id & 255])),
      ),
      throwsRangeError,
    );
    await expectLater(
      publisher.publishBatch('batch/api', [
        Uint8List(600000),
        Uint8List(600000),
      ]),
      throwsRangeError,
    );
    final received = subscriber.messages
        .take(512)
        .toList()
        .timeout(
          const Duration(seconds: 3),
        );
    await publisher.publishBatch(
      'batch/api',
      List<Uint8List>.generate(
        512,
        (id) => Uint8List.fromList([id >> 8, id & 255]),
      ),
    );
    expect(
      (await received)
          .map((message) => message.payload[0] << 8 | message.payload[1])
          .toList(),
      List<int>.generate(512, (id) => id),
    );
  });

  test(
    'malformed client packet does not take down another connection',
    () async {
      final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
      final client = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'live',
        version: MqttVersion.v5,
      );
      addTearDown(() async {
        await client.close();
        await broker.close();
      });
      final bad = await Socket.connect('127.0.0.1', broker.port);
      final closed = expectLater(bad, emitsDone);
      bad.add([0x00, 0x00]);
      await bad.flush();
      await closed.timeout(const Duration(seconds: 3));
      bad.destroy();
      await client.ping();
    },
  );

  test('anonymous-only broker rejects supplied credentials', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    addTearDown(broker.close);
    final socket = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(socket.destroy);
    socket.add(
      MqttPacketCodec.encodeConnect(
        MqttConnect(
          version: MqttVersion.v5,
          clientId: 'credentialed',
          username: 'user',
        ),
      ),
    );
    final wire = await socket.first.timeout(const Duration(seconds: 3));
    final frame = MqttFrameDecoder().add(Uint8List.fromList(wire)).single;
    expect(
      MqttPacketCodec.decodeConnack(frame, MqttVersion.v5).reasonCode,
      0x87,
    );
  });

  test('client reports remote broker closure to its message stream', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final client = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'closing',
      version: MqttVersion.v5,
    );
    addTearDown(client.close);
    final terminal = expectLater(
      client.messages,
      emitsInOrder([emitsError(isA<MqttProtocolException>()), emitsDone]),
    );
    await broker.close();
    await terminal.timeout(const Duration(seconds: 3));
  });

  test('client rejects a nonzero CONNACK reason', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    server.listen((socket) {
      socket.listen((_) {
        socket.add(
          MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 0x87),
        );
      });
    });
    addTearDown(server.close);
    await expectLater(
      MqttQos0Client.connect('127.0.0.1', server.port, clientId: 'rejected'),
      throwsA(isA<MqttProtocolException>()),
    );
  });

  test(
    'client fails a pending subscription on malformed broker traffic',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      server.listen((socket) {
        final decoder = MqttFrameDecoder();
        socket.listen((bytes) {
          for (final packet in decoder.add(Uint8List.fromList(bytes))) {
            if (packet.type == MqttPacketType.connect) {
              socket.add(
                MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 0),
              );
            } else if (packet.type == MqttPacketType.subscribe) {
              socket.add([0x00, 0x00]);
            }
          }
        });
      });
      addTearDown(server.close);
      final client = await MqttQos0Client.connect(
        '127.0.0.1',
        server.port,
        clientId: 'pending',
      );
      addTearDown(client.close);
      await expectLater(
        client.subscribe('x'),
        throwsA(isA<MqttProtocolException>()),
      );
    },
  );

  test(
    'Paho MQTT 5 and 3.1.1 exchange binary payloads with a Connectanum client',
    () async {
      final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
      final client = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'dart-peer',
        version: MqttVersion.v5,
      );
      addTearDown(() async {
        await client.close();
        await broker.close();
      });
      await client.subscribe('test/from-paho');
      final incoming = client.messages.first.timeout(
        const Duration(seconds: 5),
      );
      final process = await Process.start(
        Platform.environment['PAHO_PYTHON']!,
        ['test/mqtt/paho_qos0_peer.py', '${broker.port}'],
      );
      addTearDown(() => process.kill());
      final ready = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      expect(ready, 'READY');
      expect((await incoming).payload, [0, 255, 0, 17]);
      await client.publish('test/to-paho', Uint8List.fromList([17, 0, 255]));
      final stderr = await process.stderr.transform(utf8.decoder).join();
      expect(
        await process.exitCode.timeout(const Duration(seconds: 5)),
        0,
        reason: stderr,
      );
    },
    skip: Platform.environment['PAHO_PYTHON'] == null
        ? 'set PAHO_PYTHON to a Python with paho-mqtt 2.1.0'
        : false,
  );
}
