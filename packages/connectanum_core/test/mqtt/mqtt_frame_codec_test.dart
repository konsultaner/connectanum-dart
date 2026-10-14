import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('MQTT fixed-header framing', () {
    test('holds fragmented input and emits coalesced packets in order', () {
      final decoder = MqttFrameDecoder();

      expect(decoder.add(bytes([0x10])), isEmpty);
      final frames = decoder.add(bytes([0x00, 0xc0, 0x00, 0xd0, 0x00]));

      expect(frames.map((frame) => frame.type), [
        MqttPacketType.connect,
        MqttPacketType.pingreq,
        MqttPacketType.pingresp,
      ]);
      expect(frames.every((frame) => frame.body.isEmpty), isTrue);
      expect(decoder.bufferedBytes, 0);
    });

    test('accepts canonical two-byte remaining length split across chunks', () {
      final decoder = MqttFrameDecoder(maxPacketSize: 131);
      expect(decoder.add(bytes([0x30, 0x80])), isEmpty);
      expect(
        decoder.add(bytes([0x01, ...List<int>.filled(63, 0xa5)])),
        isEmpty,
      );

      final frames = decoder.add(bytes(List<int>.filled(65, 0xa5)));
      expect(frames, hasLength(1));
      expect(frames.single.type, MqttPacketType.publish);
      expect(frames.single.body, List<int>.filled(128, 0xa5));
      expect(decoder.bufferedBytes, 0);
    });

    test('rejects overlong and five-byte remaining-length encodings', () {
      expect(
        () => MqttFrameDecoder().add(bytes([0xc0, 0x80, 0x00])),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttFrameDecoder().add(bytes([0xc0, 0xff, 0xff, 0xff, 0x80])),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('protocol errors terminate the decoder', () {
      final decoder = MqttFrameDecoder();
      expect(
        () => decoder.add(bytes([0x80, 0x00])),
        throwsA(
          isA<MqttProtocolException>().having(
            (error) => error.toString(),
            'description',
            contains('invalid reserved fixed-header flags'),
          ),
        ),
      );
      expect(() => decoder.add(bytes([0xc0, 0x00])), throwsStateError);
    });

    test('rejects invalid packet types and fixed-header flags', () {
      for (final firstByte in [0x00, 0x80, 0x60, 0x36, 0x38]) {
        expect(
          () => MqttFrameDecoder().add(bytes([firstByte, 0x00])),
          throwsA(isA<MqttProtocolException>()),
          reason: 'fixed-header byte 0x${firstByte.toRadixString(16)}',
        );
      }
    });

    test(
      'enforces the per-packet size cap without rejecting coalesced packets',
      () {
        expect(
          () => MqttFrameDecoder(maxPacketSize: 5).add(bytes([0x30, 0x04])),
          throwsA(isA<MqttProtocolException>()),
        );

        final decoder = MqttFrameDecoder(maxPacketSize: 5);
        final frames = decoder.add(
          bytes([
            0x30,
            0x03,
            1,
            2,
            3,
            0xc0,
            0x00,
          ]),
        );
        expect(frames, hasLength(2));
        expect(frames.first.body, [1, 2, 3]);
        expect(frames.last.type, MqttPacketType.pingreq);
      },
    );

    test('rejects a partial length header that exhausts the packet cap', () {
      final decoder = MqttFrameDecoder(maxPacketSize: 2);
      expect(decoder.add(bytes([0x30, 0x80])), isEmpty);
      expect(
        () => decoder.add(bytes([0x01])),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('grows its bounded buffer for a large fragmented packet', () {
      final frame = MqttFrame(
        MqttPacketType.publish,
        flags: 0,
        body: bytes(List<int>.filled(5000, 0x42)),
      );
      final encoded = frame.encode(maxPacketSize: 6000);
      final decoder = MqttFrameDecoder(maxPacketSize: 6000);
      expect(decoder.add(bytes(encoded.sublist(0, 3000))), isEmpty);
      final decoded = decoder.add(bytes(encoded.sublist(3000)));
      expect(decoded, hasLength(1));
      expect(decoded.single.body, List<int>.filled(5000, 0x42));
    });

    test('encodes canonical length and checks outgoing flags and size', () {
      final frame = MqttFrame(
        MqttPacketType.publish,
        flags: 0,
        body: bytes(List<int>.filled(128, 0x5a)),
      );
      final encoded = frame.encode(maxPacketSize: 131);
      expect(encoded.sublist(0, 3), [0x30, 0x80, 0x01]);
      expect(encoded.length, 131);
      expect(
        () => frame.encode(maxPacketSize: 130),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttFrame(MqttPacketType.subscribe, flags: 0, body: bytes([])),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => MqttFrame(MqttPacketType.publish, flags: 16, body: bytes([])),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('variable-byte integer uses one to four minimal bytes', () {
      expect(encodeMqttVariableByteInteger(0), [0]);
      expect(encodeMqttVariableByteInteger(127), [127]);
      expect(encodeMqttVariableByteInteger(128), [0x80, 0x01]);
      expect(encodeMqttVariableByteInteger(16384), [0x80, 0x80, 0x01]);
      expect(encodeMqttVariableByteInteger(268435455), [
        0xff,
        0xff,
        0xff,
        0x7f,
      ]);
      expect(
        () => encodeMqttVariableByteInteger(-1),
        throwsA(isA<MqttProtocolException>()),
      );
      expect(
        () => encodeMqttVariableByteInteger(268435456),
        throwsA(isA<MqttProtocolException>()),
      );
    });

    test('copies decoded payload before accepting later input', () {
      final input = bytes([0x30, 0x01, 0x2a]);
      final decoder = MqttFrameDecoder();
      final first = decoder.add(input).single;
      input[2] = 0;
      decoder.add(bytes([0xc0, 0x00]));
      expect(first.body, [0x2a]);
    });

    test('rejects invalid decoder limits', () {
      expect(() => MqttFrameDecoder(maxPacketSize: 1), throwsArgumentError);
      expect(
        () => MqttFrameDecoder(maxPacketSize: 268435461),
        throwsArgumentError,
      );
    });
  });
}
