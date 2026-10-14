import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';
import 'package:test/test.dart';

Uint8List wire(List<int> values) => Uint8List.fromList(values);

MqttFrame frame(List<int> values) =>
    MqttFrameDecoder().add(wire(values)).single;

void main() {
  group('MQTT packet codec', () {
    const connect5 = [
      0x10,
      0x0e,
      0x00,
      0x04,
      0x4d,
      0x51,
      0x54,
      0x54,
      0x05,
      0x02,
      0x00,
      0x3c,
      0x00,
      0x00,
      0x01,
      0x61,
    ];
    const connect311 = [
      0x10,
      0x0d,
      0x00,
      0x04,
      0x4d,
      0x51,
      0x54,
      0x54,
      0x04,
      0x02,
      0x00,
      0x3c,
      0x00,
      0x01,
      0x61,
    ];

    test('decodes and emits MQTT 5 CONNECT without properties', () {
      final connect = MqttPacketCodec.decodeConnect(frame(connect5));
      expect(connect.version, MqttVersion.v5);
      expect(connect.clientId, 'a');
      expect(connect.cleanStart, isTrue);
      expect(connect.keepAliveSeconds, 60);
      expect(connect.username, isNull);
      expect(connect.password, isNull);
      expect(MqttPacketCodec.encodeConnect(connect), connect5);
    });

    test('decodes and emits MQTT 3.1.1 CONNECT', () {
      final connect = MqttPacketCodec.decodeConnect(frame(connect311));
      expect(connect.version, MqttVersion.v311);
      expect(MqttPacketCodec.encodeConnect(connect), connect311);
    });

    test('CONNECT credentials round trip as a binary password', () {
      final encoded = MqttPacketCodec.encodeConnect(
        MqttConnect(
          version: MqttVersion.v5,
          clientId: 'credentialed',
          username: 'user',
          password: wire([0, 255]),
        ),
      );
      final decoded = MqttPacketCodec.decodeConnect(frame(encoded));
      expect(decoded.username, 'user');
      expect(decoded.password, [0, 255]);
    });

    test('rejects malformed UTF-8 in CONNECT', () {
      final bad = List<int>.from(connect5)..[15] = 0xff;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(bad)),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('rejects malformed CONNECT and unsupported properties', () {
      final badFlag = List<int>.from(connect5)..[9] = 0x03;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(badFlag)),
        throwsA(isA<MqttProtocolException>()),
      );
      final badProperty = List<int>.from(connect5)..[12] = 0x01;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(badProperty)),
        throwsA(isA<MqttProtocolException>()),
      );
      final badName = List<int>.from(connect5)..[4] = 0x58;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(badName)),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('decodes and emits MQTT 5 QoS 0 SUBSCRIBE and SUBACK', () {
      final subscribeWire = wire([
        0x82,
        0x09,
        0x00,
        0x01,
        0x00,
        0x00,
        0x03,
        0x61,
        0x2f,
        0x62,
        0x00,
      ]);
      final subscription = MqttPacketCodec.decodeSubscribe(
        frame(subscribeWire),
        MqttVersion.v5,
      );
      expect(subscription.packetId, 1);
      expect(subscription.filters, ['a/b']);
      expect(subscription.qos, [0]);
      expect(
        MqttPacketCodec.encodeSubscribe(
          MqttVersion.v5,
          packetId: 1,
          filter: 'a/b',
        ),
        subscribeWire,
      );
      expect(
        MqttPacketCodec.encodeSuback(MqttVersion.v5, 1, [0]),
        [0x90, 0x04, 0x00, 0x01, 0x00, 0x00],
      );
      expect(
        MqttPacketCodec.decodeSuback(
          frame([0x90, 0x04, 0x00, 0x01, 0x00, 0x00]),
          MqttVersion.v5,
        ).grantedQos,
        [0],
      );
    });

    test('decodes and emits MQTT 5 binary QoS 0 PUBLISH', () {
      final publishWire = wire([
        0x30,
        0x08,
        0x00,
        0x03,
        0x61,
        0x2f,
        0x62,
        0x00,
        0x00,
        0xff,
      ]);
      final publication = MqttPacketCodec.decodePublish(
        frame(publishWire),
        MqttVersion.v5,
      );
      expect(publication.topic, 'a/b');
      expect(publication.payload, [0x00, 0xff]);
      expect(publication.qos, 0);
      expect(publication.retain, isFalse);
      expect(
        MqttPacketCodec.encodePublish(
          MqttVersion.v5,
          topic: 'a/b',
          payload: wire([0x00, 0xff]),
        ),
        publishWire,
      );
      expect(
        MqttPacketCodec.encodePublish(
          MqttVersion.v311,
          topic: 'a/b',
          payload: wire([0x00, 0xff]),
        ),
        [0x30, 0x07, 0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0xff],
      );
    });

    test('encodes and decodes CONNACK by version', () {
      expect(
        MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 0),
        [0x20, 0x03, 0x00, 0x00, 0x00],
      );
      expect(
        MqttPacketCodec.decodeConnack(
          frame([0x20, 0x03, 0x00, 0x00, 0x00]),
          MqttVersion.v5,
        ).reasonCode,
        0,
      );
      expect(
        MqttPacketCodec.encodeConnack(MqttVersion.v311, reasonCode: 0),
        [0x20, 0x02, 0x00, 0x00],
      );
    });

    test('accepts Mosquitto MQTT 5 CONNACK capability properties', () {
      final packet = frame([
        0x20,
        0x0e,
        0x00,
        0x00,
        0x0b,
        0x22,
        0x00,
        0x0a,
        0x27,
        0x00,
        0x1e,
        0x84,
        0x80,
        0x21,
        0x00,
        0x14,
      ]);
      expect(
        MqttPacketCodec.decodeConnack(packet, MqttVersion.v5).reasonCode,
        0,
      );
    });

    test('rejects nonminimal CONNACK property length', () {
      expect(
        () => MqttPacketCodec.decodeConnack(
          frame([0x20, 0x04, 0x00, 0x00, 0x80, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('rejects malformed and unsupported publish/subscribe forms', () {
      expect(
        () => MqttPacketCodec.decodePublish(
          frame([0x30, 0x03, 0x00, 0x01, 0x2b]),
          MqttVersion.v311,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeSubscribe(
          frame([
            0x82,
            0x09,
            0x00,
            0x00,
            0x00,
            0x00,
            0x03,
            0x61,
            0x2f,
            0x62,
            0x00,
          ]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodePublish(
          frame([0x30, 0x01, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('rejects unsupported MQTT versions and packet fields', () {
      final badVersion = List<int>.from(connect5)..[8] = 3;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(badVersion)),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeConnack(
          frame([0x20, 0x03, 0x02, 0x00, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeSubscribe(
          frame([0x82, 0x06, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeSubscribe(
          frame([
            0x82,
            0x09,
            0x00,
            0x01,
            0x00,
            0x00,
            0x03,
            0x61,
            0x2f,
            0x62,
            0x03,
          ]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeSubscribe(
          frame([0x82, 0x03, 0x00, 0x01, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeSuback(
          frame([0x90, 0x03, 0x00, 0x01, 0x00]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodePublish(
          frame([0x32, 0x00]),
          MqttVersion.v311,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeConnect(frame([0x20, 0x02, 0x00, 0x00])),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('rejects malformed lengths, strings, and encoded values', () {
      expect(
        () => MqttPacketCodec.decodeConnect(frame([0x10, 0x01, 0x00])),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeConnect(
          frame([0x10, 0x03, 0x00, 0x04, 0x4d]),
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      final nul = List<int>.from(connect5)..[15] = 0;
      expect(
        () => MqttPacketCodec.decodeConnect(frame(nul)),
        throwsA(isA<MqttProtocolException>()),
      );
      final trailing = List<int>.from(connect5);
      trailing[1] = 0x0f;
      trailing.add(0);
      expect(
        () => MqttPacketCodec.decodeConnect(frame(trailing)),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.decodeConnack(
          frame([0x20, 0x07, 0, 0, 0x80, 0x80, 0x80, 0x80, 0]),
          MqttVersion.v5,
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 256),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.encodeConnect(
          MqttConnect(
            version: MqttVersion.v5,
            clientId: 'x',
            keepAliveSeconds: 65536,
          ),
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.encodeSubscribe(
          MqttVersion.v5,
          packetId: 0,
          filter: 'x',
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttPacketCodec.encodeSubscribe(
          MqttVersion.v5,
          packetId: 1,
          filter: '',
        ),
        throwsA(isA<MqttProtocolException>()),
      );
    });
  });
}
