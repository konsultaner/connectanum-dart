import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/mqtt.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  for (final version in MqttVersion.values) {
    for (final (filter, topic, delivered) in [
      ('a', 'a', true),
      ('a', 'a/b', false),
      ('a/b', 'a', false),
      ('a/b', 'a/bc', false),
      ('a/b', 'a/c', false),
      ('/a/', '/a/', true),
      ('/a', '/a/', false),
      ('a/*', 'a/*', true),
      ('a/*', 'a/b', false),
      ('métric/é', 'métric/é', true),
      ('métric/é', 'métric/e\u0301', false),
      (r'$SYS/status', r'$SYS/status', true),
      (r'$SYS', r'$SYS/status', false),
      ('+', r'$SYS', false),
      ('#', r'$SYS/status', false),
      (r'$SYS/+', r'$SYS/status', true),
      (r'$SYS/#', r'$SYS/status/one', true),
      ('a/+', 'a/', true),
      ('a/+', 'a', false),
      ('a/+', 'a/b', true),
      ('a/+', 'a/b/c', false),
      ('a/#', 'a', true),
      ('a/#', 'a/', true),
      ('a/#', 'a/b/c', true),
      ('+', '/', false),
      ('/+', '/', true),
    ]) {
      test(
        'literal and wildcard topic semantics ${version.name} $filter $topic',
        () async {
          final broker = MqttQos0Broker.native();
          addTearDown(broker.close);
          final sent = <Uint8List>[];
          for (final id in [101, 102]) {
            broker.attachNativeConnection(
              id,
              send: id == 102 ? sent.add : (_) {},
              close: () {},
            );
            broker.receiveNativeChunk(
              id,
              MqttPacketCodec.encodeConnect(
                MqttConnect(version: version, clientId: 'matching-$id'),
              ),
            );
          }
          broker.receiveNativeChunk(
            102,
            MqttPacketCodec.encodeSubscribe(
              version,
              packetId: 1,
              filter: filter,
            ),
          );
          sent.clear();
          final wire = MqttPacketCodec.encodePublish(
            version,
            topic: topic,
            payload: Uint8List.fromList([0, 255]),
          );
          broker.receiveNativeChunk(101, wire);
          await Future<void>.delayed(Duration.zero);
          expect(sent, delivered ? [wire] : <Uint8List>[]);
          expect(broker.nativeConnectionIds, containsAll([101, 102]));
        },
      );
    }
  }

  test('native MQTT forwards validated QoS 0 frames across versions', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    final sent5 = <Uint8List>[];
    final sent311 = <Uint8List>[];
    broker.attachNativeConnection(71, send: sent5.add, close: () {});
    broker.attachNativeConnection(72, send: sent311.add, close: () {});
    for (final (id, version) in [
      (71, MqttVersion.v5),
      (72, MqttVersion.v311),
    ]) {
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeConnect(
          MqttConnect(version: version, clientId: 'forward-$id'),
        ),
      );
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeSubscribe(
          version,
          packetId: 1,
          filter: 'sensors/+',
        ),
      );
    }
    sent5.clear();
    sent311.clear();
    for (final (id, version) in [
      (71, MqttVersion.v5),
      (72, MqttVersion.v311),
    ]) {
      final payload = Uint8List.fromList([0, 255, id]);
      final wire = MqttPacketCodec.encodePublish(
        version,
        topic: 'sensors/µ',
        payload: payload,
      );
      broker.receiveNativeChunk(id, wire);
      await Future<void>.delayed(Duration.zero);
      expect(sent5, [
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: 'sensors/µ',
          payload: payload,
        ),
      ]);
      expect(sent311, [
        MqttPacketCodec.encodePublish(
          MqttVersion.v311,
          topic: 'sensors/µ',
          payload: payload,
        ),
      ]);
      sent5.clear();
      sent311.clear();
    }
  });

  test('native MQTT peer IDs cannot be attached twice', () async {
    final broker = MqttQos0Broker.native();
    broker.attachNativeConnection(42, send: (_) {}, close: () {});
    expect(
      () => broker.attachNativeConnection(42, send: (_) {}, close: () {}),
      throwsStateError,
    );
    broker.closeNativeConnection(42);
    await broker.close();
  });

  test('native close observer failure still destroys the peer', () async {
    final broker = MqttQos0Broker.native(
      onNativeClose: (_, _) => throw StateError('observer failed'),
    );
    var destroyed = false;
    broker.attachNativeConnection(
      47,
      send: (_) {},
      close: () => destroyed = true,
    );
    broker.closeNativeConnection(47, reason: 'native_poll_error');
    expect(destroyed, isTrue);
    expect(broker.nativeConnectionIds, isEmpty);
    await broker.close();
  });

  test('native MQTT send failure closes its peer', () async {
    final closeReasons = <String>[];
    final broker = MqttQos0Broker.native(
      onNativeClose: (connectionId, reason) {
        expect(connectionId, 43);
        closeReasons.add(reason);
      },
    );
    var closed = false;
    broker.attachNativeConnection(
      43,
      send: (_) => throw StateError('native send queue closed'),
      close: () => closed = true,
    );
    broker.receiveNativeChunk(
      43,
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'send-failure'),
      ),
    );
    expect(closed, isTrue);
    expect(closeReasons, ['send_error']);
    expect(broker.nativeConnectionIds, isEmpty);
    await broker.close();
  });

  test('native MQTT queue saturation retries without disconnecting', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    final sent = <Uint8List>[];
    var attempts = 0;
    var closed = false;
    broker.attachNativeConnection(
      44,
      send: (bytes) {
        if (attempts++ == 0) {
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
        sent.add(bytes);
      },
      close: () => closed = true,
    );
    broker.receiveNativeChunk(
      44,
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'backpressure'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, isFalse);
    expect(sent, hasLength(1));
    expect(
      MqttPacketCodec.decodeConnack(
        MqttFrameDecoder().add(sent.single).single,
        MqttVersion.v5,
      ).reasonCode,
      0,
    );
  });

  test('native MQTT queued control packets retain wire order', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    final sent = <Uint8List>[];
    var attempts = 0;
    broker.attachNativeConnection(
      45,
      send: (bytes) {
        if (attempts++ < 2) {
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
        sent.add(bytes);
      },
      close: () {},
    );
    broker.receiveNativeChunk(
      45,
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'ordered'),
      ),
    );
    broker.receiveNativeChunk(
      45,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, hasLength(2));
    expect(MqttFrameDecoder().add(sent[0]).single.type, MqttPacketType.connack);
    expect(MqttFrameDecoder().add(sent[1]).single.type, MqttPacketType.suback);
  });

  test('native MQTT new traffic drains a previously saturated queue', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    final sent = <Uint8List>[];
    var firstSend = true;
    broker.attachNativeConnection(
      50,
      send: (bytes) {
        if (firstSend) {
          firstSend = false;
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
        sent.add(bytes);
      },
      close: () {},
    );
    broker.receiveNativeChunk(
      50,
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'eager-drain'),
      ),
    );
    expect(sent, isEmpty);
    broker.receiveNativeChunk(
      50,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    expect(sent, hasLength(2));
    expect(MqttFrameDecoder().add(sent[0]).single.type, MqttPacketType.connack);
    expect(MqttFrameDecoder().add(sent[1]).single.type, MqttPacketType.suback);
  });

  test('native MQTT retry closes on a terminal send error', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    var attempts = 0;
    var closed = false;
    broker.attachNativeConnection(
      46,
      send: (_) {
        if (attempts++ == 0) {
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
        throw StateError('writer closed');
      },
      close: () => closed = true,
    );
    broker.receiveNativeChunk(
      46,
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'closed-writer'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, isTrue);
    expect(broker.nativeConnectionIds, isEmpty);
  });

  test(
    'native MQTT terminal transport errors close on send and retry',
    () async {
      for (final failuresBeforeTerminal in [0, 1]) {
        final broker = MqttQos0Broker.native();
        var attempts = 0;
        var closed = false;
        broker.attachNativeConnection(
          47,
          send: (_) {
            if (attempts++ < failuresBeforeTerminal) {
              throw NativeTransportException(
                NativeTransportErrorCode.sendQueueFull,
                'queue full',
              );
            }
            throw NativeTransportException(
              NativeTransportErrorCode.connectionNotFound,
              'closed',
            );
          },
          close: () => closed = true,
        );
        broker.receiveNativeChunk(
          47,
          MqttPacketCodec.encodeConnect(
            const MqttConnect(version: MqttVersion.v5, clientId: 'terminal'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(closed, isTrue);
        await broker.close();
      }
    },
  );

  test('native MQTT slow subscriber has a bounded outbound backlog', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    var closed = false;
    var queuedPublications = 0;
    broker.attachNativeConnection(
      48,
      send: (bytes) {
        if (bytes.first >> 4 == MqttPacketType.publish.wireValue) {
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
      },
      close: () => closed = true,
    );
    broker.attachNativeConnection(49, send: (_) {}, close: () {});
    for (final id in [48, 49]) {
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeConnect(
          MqttConnect(version: MqttVersion.v5, clientId: 'client-$id'),
        ),
      );
    }
    broker.receiveNativeChunk(
      48,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    final publish = MqttPacketCodec.encodePublish(
      MqttVersion.v5,
      topic: 'a',
      payload: Uint8List(256 * 1024),
    );
    for (var i = 0; i < 20 && !closed; i++) {
      broker.receiveNativeChunk(49, publish);
      queuedPublications++;
      await Future<void>.delayed(Duration.zero);
    }
    expect(closed, isTrue);
    expect(queuedPublications, 16);
    expect(broker.nativeConnectionIds, isNot(contains(48)));
  });

  test(
    'native MQTT large publications stay within the FFI send limit',
    () async {
      final broker = MqttQos0Broker.native();
      addTearDown(broker.close);
      final sent = <Uint8List>[];
      var subscriberClosed = false;
      broker.attachNativeConnection(
        51,
        send: (bytes) {
          if (bytes.isEmpty) {
            throw ArgumentError.value(bytes.length, 'bytes', 'empty FFI send');
          }
          if (bytes.length > 1 << 20) {
            throw ArgumentError.value(bytes.length, 'bytes', 'FFI send limit');
          }
          sent.add(bytes);
        },
        close: () => subscriberClosed = true,
      );
      broker.attachNativeConnection(52, send: (_) {}, close: () {});
      for (final id in [51, 52]) {
        broker.receiveNativeChunk(
          id,
          MqttPacketCodec.encodeConnect(
            MqttConnect(version: MqttVersion.v5, clientId: 'large-$id'),
          ),
        );
      }
      broker.receiveNativeChunk(
        51,
        Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
      );
      sent.clear();
      final publication = MqttPacketCodec.encodePublish(
        MqttVersion.v5,
        topic: 'a',
        payload: Uint8List(65536),
      );
      final burst = BytesBuilder(copy: false);
      for (var i = 0; i < 17; i++) {
        burst.add(publication);
      }
      broker.receiveNativeChunk(52, burst.takeBytes());
      await Future<void>.delayed(Duration.zero);
      expect(subscriberClosed, isFalse);
      final decoder = MqttFrameDecoder();
      final frames = sent.expand(decoder.add).toList();
      expect(frames, hasLength(17));
      expect(
        frames.every((frame) => frame.type == MqttPacketType.publish),
        isTrue,
      );
      sent.clear();
      final medium = MqttPacketCodec.encodePublish(
        MqttVersion.v5,
        topic: 'a',
        payload: Uint8List(32768),
      );
      final mediumBurst = BytesBuilder(copy: false);
      for (var i = 0; i < 33; i++) {
        mediumBurst.add(medium);
      }
      broker.receiveNativeChunk(52, mediumBurst.takeBytes());
      await Future<void>.delayed(Duration.zero);
      expect(subscriberClosed, isFalse);
      expect(sent.every((chunk) => chunk.length <= 1 << 20), isTrue);
      expect(sent.expand(decoder.add), hasLength(33));
    },
  );

  test(
    'native MQTT preserves order across small and large publications',
    () async {
      final broker = MqttQos0Broker.native();
      addTearDown(broker.close);
      final sent = <Uint8List>[];
      broker.attachNativeConnection(57, send: sent.add, close: () {});
      broker.attachNativeConnection(58, send: (_) {}, close: () {});
      for (final id in [57, 58]) {
        broker.receiveNativeChunk(
          id,
          MqttPacketCodec.encodeConnect(
            MqttConnect(version: MqttVersion.v5, clientId: 'mixed-$id'),
          ),
        );
      }
      broker.receiveNativeChunk(
        57,
        Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
      );
      sent.clear();
      final burst = BytesBuilder(copy: false)
        ..add(
          MqttPacketCodec.encodePublish(
            MqttVersion.v5,
            topic: 'a',
            payload: Uint8List.fromList([1]),
          ),
        )
        ..add(
          MqttPacketCodec.encodePublish(
            MqttVersion.v5,
            topic: 'a',
            payload: Uint8List(65536)..[0] = 2,
          ),
        )
        ..add(
          MqttPacketCodec.encodePublish(
            MqttVersion.v5,
            topic: 'a',
            payload: Uint8List.fromList([3]),
          ),
        );
      broker.receiveNativeChunk(58, burst.takeBytes());
      await Future<void>.delayed(Duration.zero);
      expect(sent.every((chunk) => chunk.isNotEmpty), isTrue);
      final decoder = MqttFrameDecoder();
      final frames = sent.expand(decoder.add).toList();
      expect(frames, hasLength(3));
      expect(
        frames
            .map(
              (frame) => MqttPacketCodec.decodePublish(frame, MqttVersion.v5),
            )
            .map((message) => message.payload.first),
        [1, 2, 3],
      );
    },
  );

  test('native MQTT stops coalescing when the bounded writer closes', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    var closed = false;
    broker.attachNativeConnection(
      53,
      send: (bytes) {
        if (bytes.length > 512 * 1024) throw StateError('writer closed');
      },
      close: () => closed = true,
    );
    broker.attachNativeConnection(54, send: (_) {}, close: () {});
    for (final id in [53, 54]) {
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeConnect(
          MqttConnect(version: MqttVersion.v5, clientId: 'closed-$id'),
        ),
      );
    }
    broker.receiveNativeChunk(
      53,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    final publication = MqttPacketCodec.encodePublish(
      MqttVersion.v5,
      topic: 'a',
      payload: Uint8List(600 * 1024),
    );
    final burst = BytesBuilder(copy: false)
      ..add(publication)
      ..add(publication);
    broker.receiveNativeChunk(54, burst.takeBytes());
    await Future<void>.delayed(Duration.zero);
    expect(closed, isTrue);
    expect(broker.nativeConnectionIds, isNot(contains(53)));
  });

  test('native MQTT limits a coalesced large-payload burst', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    var closed = false;
    broker.attachNativeConnection(
      55,
      send: (_) {},
      close: () => closed = true,
    );
    broker.attachNativeConnection(56, send: (_) {}, close: () {});
    for (final id in [55, 56]) {
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeConnect(
          MqttConnect(version: MqttVersion.v5, clientId: 'burst-$id'),
        ),
      );
    }
    broker.receiveNativeChunk(
      55,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    final publication = MqttPacketCodec.encodePublish(
      MqttVersion.v5,
      topic: 'a',
      payload: Uint8List(65536),
    );
    final burst = BytesBuilder(copy: false);
    for (var i = 0; i < 80; i++) {
      burst.add(publication);
    }
    broker.receiveNativeChunk(56, burst.takeBytes());
    await Future<void>.delayed(Duration.zero);
    expect(closed, isTrue);
    expect(broker.nativeConnectionIds, isNot(contains(55)));
  });

  test(
    'native MQTT control reply cannot exceed a full outbound queue',
    () async {
      final broker = MqttQos0Broker.native();
      addTearDown(broker.close);
      var closed = false;
      var saturated = false;
      broker.attachNativeConnection(
        57,
        send: (_) {
          if (saturated) {
            throw NativeTransportException(
              NativeTransportErrorCode.sendQueueFull,
              'queue full',
            );
          }
        },
        close: () => closed = true,
      );
      broker.attachNativeConnection(58, send: (_) {}, close: () {});
      for (final id in [57, 58]) {
        broker.receiveNativeChunk(
          id,
          MqttPacketCodec.encodeConnect(
            MqttConnect(version: MqttVersion.v5, clientId: 'full-$id'),
          ),
        );
      }
      broker.receiveNativeChunk(
        57,
        Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
      );
      saturated = true;
      final publication = MqttPacketCodec.encodePublish(
        MqttVersion.v5,
        topic: 'a',
        payload: Uint8List((1 << 20) - 8),
      );
      expect(publication, hasLength(1 << 20));
      final burst = BytesBuilder(copy: false);
      for (var i = 0; i < 4; i++) {
        burst.add(publication);
      }
      broker.receiveNativeChunk(58, burst.takeBytes());
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      broker.receiveNativeChunk(57, Uint8List.fromList([0xc0, 0]));
      expect(closed, isTrue);
    },
  );

  test('native MQTT large chunks preserve order across queue retry', () async {
    final broker = MqttQos0Broker.native();
    addTearDown(broker.close);
    final sent = <Uint8List>[];
    var saturated = false;
    var attempts = 0;
    broker.attachNativeConnection(
      59,
      send: (bytes) {
        if (saturated && attempts++ < 2) {
          throw NativeTransportException(
            NativeTransportErrorCode.sendQueueFull,
            'queue full',
          );
        }
        if (saturated) sent.add(bytes);
      },
      close: () {},
    );
    broker.attachNativeConnection(60, send: (_) {}, close: () {});
    for (final id in [59, 60]) {
      broker.receiveNativeChunk(
        id,
        MqttPacketCodec.encodeConnect(
          MqttConnect(version: MqttVersion.v5, clientId: 'retry-$id'),
        ),
      );
    }
    broker.receiveNativeChunk(
      59,
      Uint8List.fromList([0x82, 7, 0, 1, 0, 0, 1, 0x61, 0]),
    );
    saturated = true;
    final burst = BytesBuilder(copy: false);
    for (var i = 0; i < 17; i++) {
      final payload = Uint8List(65536);
      ByteData.sublistView(payload).setUint32(0, i);
      burst.add(
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: 'a',
          payload: payload,
        ),
      );
    }
    broker.receiveNativeChunk(60, burst.takeBytes());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final decoder = MqttFrameDecoder();
    final publications = sent
        .expand(decoder.add)
        .map((frame) => MqttPacketCodec.decodePublish(frame, MqttVersion.v5))
        .toList();
    expect(publications, hasLength(17));
    expect(
      publications
          .map((message) => ByteData.sublistView(message.payload).getUint32(0))
          .toList(),
      List<int>.generate(17, (i) => i),
    );
  });

  test('MQTT 5 CONNACK advertises the provisional QoS 0 limits', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final socket = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(() async {
      socket.destroy();
      await broker.close();
    });
    final frames = _decodedFrames(socket);
    final connack = frames.first.timeout(const Duration(seconds: 3));
    socket.add(
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'capabilities'),
      ),
    );
    expect((await connack).body, [
      0,
      0,
      13,
      0x24,
      0,
      0x25,
      0,
      0x27,
      0,
      0x10,
      0,
      0,
      0x29,
      0,
      0x2a,
      0,
    ]);
  });

  test('MQTT 5 QoS 1 and 2 subscription requests are granted QoS 0', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final socket = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(() async {
      socket.destroy();
      await broker.close();
    });
    final frames = _decodedFrames(socket);
    final connack = frames.first.timeout(const Duration(seconds: 3));
    socket.add(
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'sub-downgrade'),
      ),
    );
    expect(
      MqttPacketCodec.decodeConnack(await connack, MqttVersion.v5).reasonCode,
      0,
    );
    final suback = frames.first.timeout(const Duration(seconds: 3));
    socket.add([0x82, 0x0b, 0, 1, 0, 0, 1, 0x61, 1, 0, 1, 0x62, 2]);
    expect(
      MqttPacketCodec.decodeSuback(await suback, MqttVersion.v5).grantedQos,
      [0, 0],
    );
    final publisher = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'downgrade-pub',
    );
    addTearDown(publisher.close);
    final publication = frames.first.timeout(const Duration(seconds: 3));
    await publisher.publish('a', Uint8List.fromList([0, 255]));
    final received = MqttPacketCodec.decodePublish(
      await publication,
      MqttVersion.v5,
    );
    expect(received.qos, 0);
    expect(received.topic, 'a');
    expect(received.payload, [0, 255]);
  });

  test('MQTT 3.1.1 QoS 1 and 2 requests are granted QoS 0', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final socket = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(() async {
      socket.destroy();
      await broker.close();
    });
    final frames = _decodedFrames(socket);
    final connack = frames.first.timeout(const Duration(seconds: 3));
    socket.add(
      MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v311, clientId: 'v311-qos'),
      ),
    );
    expect(
      MqttPacketCodec.decodeConnack(await connack, MqttVersion.v311).reasonCode,
      0,
    );
    final suback = frames.first.timeout(const Duration(seconds: 3));
    socket.add([0x82, 0x0a, 0, 1, 0, 1, 0x61, 1, 0, 1, 0x62, 2]);
    expect(
      MqttPacketCodec.decodeSuback(await suback, MqttVersion.v311).grantedQos,
      [0, 0],
    );
  });

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
        tcpNoDelay: true,
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

  test('exact dollar topic matches while root wildcard excludes it', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final exact = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'dollar-exact',
    );
    final wildcard = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'dollar-wildcard',
    );
    final publisher = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'dollar-publisher',
    );
    addTearDown(() async {
      await publisher.close();
      await wildcard.close();
      await exact.close();
      await broker.close();
    });

    await exact.subscribe(r'$SYS/status');
    await wildcard.subscribe('#');
    final exactMessage = exact.messages.first.timeout(
      const Duration(seconds: 3),
    );
    final wildcardMessage = wildcard.messages.first.timeout(
      const Duration(seconds: 3),
    );
    await publisher.publish(r'$SYS/status', Uint8List.fromList([0, 255]));
    await publisher.publish('public/status', Uint8List.fromList([17]));

    final dollar = await exactMessage;
    expect(dollar.topic, r'$SYS/status');
    expect(dollar.payload, [0, 255]);
    final ordinary = await wildcardMessage;
    expect(ordinary.topic, 'public/status');
    expect(ordinary.payload, [17]);
  });

  test(
    'overlapping exact and wildcard filters deliver once in wire order',
    () async {
      final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
      final subscriber = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'overlap-subscriber',
      );
      final publisher = await MqttQos0Client.connect(
        '127.0.0.1',
        broker.port,
        clientId: 'overlap-publisher',
      );
      final topics = <String>[];
      final complete = Completer<void>();
      final subscription = subscriber.messages.listen((message) {
        topics.add(message.topic);
        if (message.topic == 'public/sentinel') complete.complete();
      });
      addTearDown(() async {
        await subscription.cancel();
        await publisher.close();
        await subscriber.close();
        await broker.close();
      });
      for (final filter in ['métric/one', 'métric/+', '#', r'$SYS/health']) {
        await subscriber.subscribe(filter);
      }
      for (final topic in [
        'métric/one',
        'métric/two',
        r'$SYS/health',
        r'$SYS/unmatched',
        'public/sentinel',
      ]) {
        await publisher.publish(topic, Uint8List.fromList([0, 255]));
      }
      await complete.future.timeout(const Duration(seconds: 3));
      expect(topics, [
        'métric/one',
        'métric/two',
        r'$SYS/health',
        'public/sentinel',
      ]);
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

  test('packets after DISCONNECT in the same read are ignored', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final subscriber = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'disconnect-sub',
    );
    final publisher = await Socket.connect('127.0.0.1', broker.port);
    addTearDown(() async {
      publisher.destroy();
      await subscriber.close();
      await broker.close();
    });
    await subscriber.subscribe('disconnect/topic');
    final received = subscriber.messages.first.timeout(
      const Duration(milliseconds: 250),
    );
    final wire = BytesBuilder(copy: false)
      ..add(
        MqttPacketCodec.encodeConnect(
          const MqttConnect(
            version: MqttVersion.v5,
            clientId: 'disconnect-pub',
          ),
        ),
      )
      ..add([0xe0, 0x00])
      ..add(
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: 'disconnect/topic',
          payload: Uint8List.fromList([1]),
        ),
      );
    publisher.add(wire.takeBytes());
    await publisher.flush();
    await expectLater(received, throwsA(isA<TimeoutException>()));
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

  test('queued client publishes flush under load and drain on close', () async {
    final broker = await MqttQos0Broker.bind('127.0.0.1', 0);
    final subscriber = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'queued-publish-sub',
    );
    final publisher = await MqttQos0Client.connect(
      '127.0.0.1',
      broker.port,
      clientId: 'queued-publish-pub',
    );
    addTearDown(() async {
      await publisher.close();
      await subscriber.close();
      await broker.close();
    });
    await subscriber.subscribe('queued/publish');
    await expectLater(
      publisher.publish('queued/#', Uint8List(0)),
      throwsA(isA<MqttProtocolException>()),
    );
    Uint8List payload(int id) {
      final bytes = Uint8List(128);
      bytes[0] = id >> 8;
      bytes[1] = id & 0xff;
      return bytes;
    }

    final received = subscriber.messages
        .take(705)
        .toList()
        .timeout(const Duration(seconds: 5));
    for (var id = 0; id < 700; id++) {
      await publisher.publish('queued/publish', payload(id));
    }
    await publisher.publishBatch('queued/publish', [
      payload(700),
      payload(701),
    ]);
    for (var id = 702; id < 705; id++) {
      await publisher.publish('queued/publish', payload(id));
    }
    await publisher.close();

    final messages = await received;
    expect(messages, hasLength(705));
    for (var id = 0; id < messages.length; id++) {
      expect(messages[id].topic, 'queued/publish');
      expect(messages[id].payload, payload(id), reason: 'publication $id');
    }
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

Stream<MqttFrame> _decodedFrames(Socket socket) {
  final controller = StreamController<MqttFrame>.broadcast();
  final decoder = MqttFrameDecoder();
  socket.listen(
    (data) {
      for (final frame in decoder.add(data)) {
        controller.add(frame);
      }
    },
    onError: controller.addError,
    onDone: controller.close,
  );
  return controller.stream;
}
