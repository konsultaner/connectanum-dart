import 'dart:convert';
import 'dart:typed_data';

import 'frame_codec.dart';

/// Wire versions supported by the initial MQTT packet profile.
enum MqttVersion { v311, v5 }

final class MqttConnect {
  const MqttConnect({
    required this.version,
    required this.clientId,
    this.cleanStart = true,
    this.keepAliveSeconds = 60,
    this.username,
    this.password,
  });

  final MqttVersion version;
  final String clientId;
  final bool cleanStart;
  final int keepAliveSeconds;
  final String? username;
  final Uint8List? password;
}

final class MqttSubscribe {
  const MqttSubscribe(this.packetId, this.filters, this.qos);
  final int packetId;
  final List<String> filters;
  final List<int> qos;
}

final class MqttSuback {
  const MqttSuback(this.packetId, this.grantedQos);
  final int packetId;
  final List<int> grantedQos;
}

final class MqttPublish {
  const MqttPublish(this.topic, this.payload, this.qos, this.retain);
  final String topic;
  final Uint8List payload;
  final int qos;
  final bool retain;
}

final class MqttConnack {
  const MqttConnack(this.reasonCode);
  final int reasonCode;
}

/// Packet fields for the deliberately small, property-free QoS 0 profile.
/// Unsupported fields fail closed rather than silently changing semantics.
abstract final class MqttPacketCodec {
  static MqttConnect decodeConnect(MqttFrame frame) {
    _expectType(frame, MqttPacketType.connect);
    final reader = _Reader(frame.body);
    if (reader.string() != 'MQTT') {
      throw const MqttProtocolException('invalid protocol name');
    }
    final level = reader.byte();
    final version = switch (level) {
      4 => MqttVersion.v311,
      5 => MqttVersion.v5,
      _ => throw const MqttProtocolException('unsupported MQTT version'),
    };
    final flags = reader.byte();
    if (flags & 0x01 != 0 ||
        flags & 0x3c != 0 ||
        (flags & 0x40 != 0 && flags & 0x80 == 0)) {
      throw const MqttProtocolException('unsupported CONNECT flags');
    }
    final keepAlive = reader.uint16();
    if (version == MqttVersion.v5) reader.emptyProperties();
    final clientId = reader.string();
    final username = flags & 0x80 != 0 ? reader.string() : null;
    final password = flags & 0x40 != 0 ? reader.bytes(reader.uint16()) : null;
    reader.end();
    return MqttConnect(
      version: version,
      clientId: clientId,
      cleanStart: flags & 0x02 != 0,
      keepAliveSeconds: keepAlive,
      username: username,
      password: password,
    );
  }

  static Uint8List encodeConnect(MqttConnect packet) {
    final writer = _Writer();
    writer.string('MQTT');
    writer.byte(packet.version == MqttVersion.v5 ? 5 : 4);
    writer.byte(
      (packet.cleanStart ? 2 : 0) |
          (packet.username != null ? 0x80 : 0) |
          (packet.password != null ? 0x40 : 0),
    );
    writer.uint16(packet.keepAliveSeconds);
    if (packet.version == MqttVersion.v5) writer.byte(0);
    writer.string(packet.clientId);
    if (packet.username != null) writer.string(packet.username!);
    if (packet.password != null) {
      writer.uint16(packet.password!.length);
      writer.raw(packet.password!);
    }
    return _encode(MqttPacketType.connect, 0, writer);
  }

  static MqttConnack decodeConnack(MqttFrame frame, MqttVersion version) {
    _expectType(frame, MqttPacketType.connack);
    final reader = _Reader(frame.body);
    final flags = reader.byte();
    if (flags & 0xfe != 0) {
      throw const MqttProtocolException('invalid CONNACK flags');
    }
    final reason = reader.byte();
    if (version == MqttVersion.v5) reader.skipProperties();
    reader.end();
    return MqttConnack(reason);
  }

  static Uint8List encodeConnack(
    MqttVersion version, {
    required int reasonCode,
    bool advertiseQos0Limits = false,
  }) {
    final writer = _Writer()
      ..byte(0)
      ..byte(reasonCode);
    if (version == MqttVersion.v5) {
      if (advertiseQos0Limits) {
        // Maximum QoS 0, no retain, 1 MiB input cap, no subscription IDs or
        // shared subscriptions. Wildcards remain available by default.
        writer.raw(const [
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
      } else {
        writer.byte(0);
      }
    }
    return _encode(MqttPacketType.connack, 0, writer);
  }

  static MqttSubscribe decodeSubscribe(MqttFrame frame, MqttVersion version) {
    _expectType(frame, MqttPacketType.subscribe);
    final reader = _Reader(frame.body);
    final id = reader.packetId();
    if (version == MqttVersion.v5) reader.emptyProperties();
    final filters = <String>[];
    final qos = <int>[];
    while (reader.hasMore) {
      final filter = reader.string();
      if (filter.isEmpty) {
        throw const MqttProtocolException('empty topic filter');
      }
      final options = reader.byte();
      if (options > 2) {
        throw const MqttProtocolException('unsupported subscription options');
      }
      filters.add(filter);
      qos.add(options);
    }
    if (filters.isEmpty) {
      throw const MqttProtocolException('SUBSCRIBE requires a filter');
    }
    return MqttSubscribe(id, filters, qos);
  }

  static Uint8List encodeSubscribe(
    MqttVersion version, {
    required int packetId,
    required String filter,
  }) {
    if (filter.isEmpty) {
      throw const MqttProtocolException('empty topic filter');
    }
    final writer = _Writer()..packetId(packetId);
    if (version == MqttVersion.v5) writer.byte(0);
    writer.string(filter);
    writer.byte(0);
    return _encode(MqttPacketType.subscribe, 2, writer);
  }

  static MqttSuback decodeSuback(MqttFrame frame, MqttVersion version) {
    _expectType(frame, MqttPacketType.suback);
    final reader = _Reader(frame.body);
    final id = reader.packetId();
    if (version == MqttVersion.v5) reader.emptyProperties();
    final granted = reader.rest();
    if (granted.isEmpty) {
      throw const MqttProtocolException('SUBACK requires a reason code');
    }
    return MqttSuback(id, granted);
  }

  static Uint8List encodeSuback(
    MqttVersion version,
    int packetId,
    List<int> grantedQos,
  ) {
    if (grantedQos.isEmpty) {
      throw const MqttProtocolException('SUBACK requires a reason code');
    }
    final writer = _Writer()..packetId(packetId);
    if (version == MqttVersion.v5) writer.byte(0);
    for (final code in grantedQos) {
      writer.byte(code);
    }
    return _encode(MqttPacketType.suback, 0, writer);
  }

  static MqttPublish decodePublish(MqttFrame frame, MqttVersion version) {
    _expectType(frame, MqttPacketType.publish);
    final qos = frame.flags >> 1 & 3;
    if (qos != 0) {
      throw const MqttProtocolException('QoS above zero is not supported yet');
    }
    final reader = _Reader(frame.body);
    final topic = reader.string();
    _validateTopic(topic);
    if (version == MqttVersion.v5) reader.emptyProperties();
    return MqttPublish(topic, reader.rest(), qos, frame.flags & 1 != 0);
  }

  static Uint8List encodePublish(
    MqttVersion version, {
    required String topic,
    required Uint8List payload,
    bool retain = false,
  }) {
    _validateTopic(topic);
    final topicBytes = utf8.encode(topic);
    if (topicBytes.length > 65535) {
      throw const MqttProtocolException('16-bit field out of range');
    }
    final bodyLength =
        2 +
        topicBytes.length +
        (version == MqttVersion.v5 ? 1 : 0) +
        payload.length;
    final lengthBytes = encodeMqttVariableByteInteger(bodyLength);
    final packetSize = 1 + lengthBytes.length + bodyLength;
    if (packetSize > 1024 * 1024) {
      throw const MqttProtocolException('packet exceeds configured size limit');
    }
    final result = Uint8List(packetSize);
    result[0] = retain ? 0x31 : 0x30;
    result.setRange(1, 1 + lengthBytes.length, lengthBytes);
    var offset = 1 + lengthBytes.length;
    result[offset++] = topicBytes.length >> 8;
    result[offset++] = topicBytes.length & 0xff;
    result.setRange(offset, offset + topicBytes.length, topicBytes);
    offset += topicBytes.length;
    if (version == MqttVersion.v5) result[offset++] = 0;
    result.setRange(offset, packetSize, payload);
    return result;
  }

  static void _validateTopic(String topic) {
    if (topic.isEmpty || topic.contains('+') || topic.contains('#')) {
      throw const MqttProtocolException('invalid PUBLISH topic');
    }
  }

  static void _expectType(MqttFrame frame, MqttPacketType type) {
    if (frame.type != type) {
      throw const MqttProtocolException('unexpected MQTT packet type');
    }
  }

  static Uint8List _encode(MqttPacketType type, int flags, _Writer writer) =>
      MqttFrame(type, flags: flags, body: writer.result()).encode();
}

final class _Reader {
  _Reader(this.data);
  final Uint8List data;
  int offset = 0;

  bool get hasMore => offset < data.length;

  int byte() {
    if (!hasMore) throw const MqttProtocolException('truncated packet');
    return data[offset++];
  }

  int uint16() => (byte() << 8) | byte();

  int packetId() {
    final id = uint16();
    if (id == 0) throw const MqttProtocolException('packet identifier is zero');
    return id;
  }

  Uint8List bytes(int count) {
    if (count > data.length - offset) {
      throw const MqttProtocolException('truncated packet');
    }
    final result = Uint8List.sublistView(data, offset, offset + count);
    offset += count;
    return result;
  }

  String string() {
    final raw = bytes(uint16());
    try {
      final value = utf8.decode(raw);
      if (value.contains('\u0000')) {
        throw const MqttProtocolException('NUL in MQTT UTF-8 string');
      }
      return value;
    } on FormatException {
      throw const MqttProtocolException('invalid MQTT UTF-8');
    }
  }

  void emptyProperties() {
    if (byte() != 0) {
      throw const MqttProtocolException(
        'MQTT properties are not supported yet',
      );
    }
  }

  /// Consume server CONNACK properties; their capability fields are exposed in
  /// a later MQTT 5 profile stage. Their length is still strictly bounded.
  void skipProperties() {
    var length = 0;
    var multiplier = 1;
    for (var i = 0; i < 4; i++) {
      final digit = byte();
      length += (digit & 0x7f) * multiplier;
      if (digit & 0x80 == 0) {
        if (i > 0 && length < multiplier) {
          throw const MqttProtocolException('nonminimal property length');
        }
        bytes(length);
        return;
      }
      multiplier *= 128;
    }
    throw const MqttProtocolException('property length exceeds four bytes');
  }

  Uint8List rest() => bytes(data.length - offset);

  void end() {
    if (hasMore) throw const MqttProtocolException('trailing packet bytes');
  }
}

final class _Writer {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void byte(int value) {
    if (value < 0 || value > 255) {
      throw const MqttProtocolException('byte field out of range');
    }
    _bytes.addByte(value);
  }

  void uint16(int value) {
    if (value < 0 || value > 65535) {
      throw const MqttProtocolException('16-bit field out of range');
    }
    byte(value >> 8);
    byte(value & 0xff);
  }

  void packetId(int value) {
    if (value == 0) {
      throw const MqttProtocolException('packet identifier is zero');
    }
    uint16(value);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    uint16(encoded.length);
    raw(encoded);
  }

  void raw(List<int> values) => _bytes.add(values);

  Uint8List result() => _bytes.takeBytes();
}
