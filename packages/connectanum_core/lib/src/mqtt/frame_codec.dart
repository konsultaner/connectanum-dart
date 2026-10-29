import 'dart:typed_data';

/// The fifteen MQTT control packet kinds, in their wire-number order.
enum MqttPacketType {
  connect,
  connack,
  publish,
  puback,
  pubrec,
  pubrel,
  pubcomp,
  subscribe,
  suback,
  unsubscribe,
  unsuback,
  pingreq,
  pingresp,
  disconnect,
  auth;

  int get wireValue => index + 1;
}

/// A malformed MQTT control packet or a configured packet-size violation.
final class MqttProtocolException implements Exception {
  const MqttProtocolException(this.message);

  final String message;

  @override
  String toString() => 'MqttProtocolException: $message';
}

/// A complete MQTT fixed header and its unparsed variable-header/payload bytes.
///
/// [body] is an owned byte array. The packet codec will interpret its contents
/// after the stream framer has established the exact packet boundary.
final class MqttFrame {
  factory MqttFrame(
    MqttPacketType type, {
    required int flags,
    required Uint8List body,
  }) {
    _validateFlags(type, flags);
    return MqttFrame._owned(type, flags, Uint8List.fromList(body));
  }

  MqttFrame._owned(this.type, this.flags, this.body);

  static const int maxRemainingLength = 268435455;
  static const int maxWirePacketSize = maxRemainingLength + 5;

  final MqttPacketType type;
  final int flags;
  final Uint8List body;

  /// Encode with MQTT's shortest possible Remaining Length representation.
  Uint8List encode({int maxPacketSize = 1024 * 1024}) {
    _validatePacketLimit(maxPacketSize);
    final lengthBytes = encodeMqttVariableByteInteger(body.length);
    final packetSize = 1 + lengthBytes.length + body.length;
    if (packetSize > maxPacketSize) {
      throw const MqttProtocolException('packet exceeds configured size limit');
    }
    final result = Uint8List(packetSize);
    result[0] = (type.wireValue << 4) | flags;
    result.setRange(1, 1 + lengthBytes.length, lengthBytes);
    result.setRange(1 + lengthBytes.length, packetSize, body);
    return result;
  }
}

/// Incrementally extracts MQTT packets from arbitrarily split TCP/WS bytes.
///
/// The configured cap applies to each complete wire packet, including its
/// fixed header. It also bounds the decoder's retained buffer. Several small
/// packets in one input chunk remain valid even when their sum exceeds the cap.
final class MqttFrameDecoder {
  MqttFrameDecoder({this.maxPacketSize = 1024 * 1024}) {
    _validatePacketLimit(maxPacketSize);
  }

  final int maxPacketSize;
  int _first = -1;
  int _remainingLength = 0;
  int _lengthBytes = 0;
  int _multiplier = 1;
  Uint8List? _body;
  int _bodyEnd = 0;
  bool _failed = false;

  int get bufferedBytes => _first < 0 ? 0 : 1 + _lengthBytes + _bodyEnd;

  /// Accept bytes and return every complete packet in input order.
  ///
  /// A malformed packet is terminal for this decoder and its connection.
  List<MqttFrame> add(Uint8List input) {
    if (_failed) {
      throw StateError('MQTT decoder is terminal after a protocol error');
    }
    final frames = <MqttFrame>[];
    var offset = 0;
    var first = _first;
    var remainingLength = _remainingLength;
    var lengthBytes = _lengthBytes;
    var multiplier = _multiplier;
    var body = _body;
    var bodyEnd = _bodyEnd;
    packets:
    while (offset < input.length) {
      if (body == null) {
        if (first < 0) {
          first = input[offset++];
          final code = first >> 4;
          if (code < 1 || code > MqttPacketType.values.length) {
            _fail('invalid MQTT control packet type');
          }
          try {
            _validateFlags(MqttPacketType.values[code - 1], first & 0x0f);
          } on MqttProtocolException catch (error) {
            _fail(error.message);
          }
        }
        while (true) {
          if (offset == input.length) break packets;
          if (1 + lengthBytes >= maxPacketSize) {
            _fail('packet exceeds configured size limit');
          }
          final digit = input[offset++];
          remainingLength += (digit & 0x7f) * multiplier;
          lengthBytes++;
          if (digit & 0x80 == 0) {
            if (lengthBytes > 1 && remainingLength < multiplier) {
              _fail('remaining length is not minimally encoded');
            }
            if (1 + lengthBytes + remainingLength > maxPacketSize) {
              _fail('packet exceeds configured size limit');
            }
            // Reserve modest headroom for fragmented input, rather than the
            // entire advertised body before its bytes arrive.
            final capacity = (input.length - offset) * 2 + 4096;
            body = Uint8List(
              remainingLength < capacity ? remainingLength : capacity,
            );
            break;
          }
          if (lengthBytes == 4) {
            _fail('remaining length exceeds four bytes');
          }
          multiplier *= 128;
        }
      }
      final missing = remainingLength - bodyEnd;
      final available = input.length - offset;
      final count = missing < available ? missing : available;
      if (bodyEnd + count > body!.length) {
        var capacity = body.length * 2;
        final required = bodyEnd + count + 4096;
        if (capacity < required) capacity = required;
        if (capacity > remainingLength) capacity = remainingLength;
        final next = Uint8List(capacity);
        next.setRange(0, bodyEnd, body);
        body = next;
      }
      final currentBody = body;
      currentBody.setRange(bodyEnd, bodyEnd + count, input, offset);
      offset += count;
      bodyEnd += count;
      if (bodyEnd == remainingLength) {
        frames.add(
          MqttFrame._owned(
            MqttPacketType.values[(first >> 4) - 1],
            first & 0x0f,
            currentBody,
          ),
        );
        first = -1;
        remainingLength = 0;
        lengthBytes = 0;
        multiplier = 1;
        body = null;
        bodyEnd = 0;
      }
    }
    _first = first;
    _remainingLength = remainingLength;
    _lengthBytes = lengthBytes;
    _multiplier = multiplier;
    _body = body;
    _bodyEnd = bodyEnd;
    return frames;
  }

  Never _fail(String message) {
    _failed = true;
    _first = -1;
    _lengthBytes = 0;
    _body = null;
    _bodyEnd = 0;
    throw MqttProtocolException(message);
  }
}

void _validatePacketLimit(int maxPacketSize) {
  if (maxPacketSize < 2 || maxPacketSize > MqttFrame.maxWirePacketSize) {
    throw ArgumentError.value(maxPacketSize, 'maxPacketSize');
  }
}

void _validateFlags(MqttPacketType type, int flags) {
  if (flags < 0 || flags > 0x0f) {
    throw const MqttProtocolException('invalid fixed-header flags');
  }
  if (type == MqttPacketType.publish) {
    final qos = (flags >> 1) & 0x03;
    if (qos == 3 || (qos == 0 && flags & 0x08 != 0)) {
      throw const MqttProtocolException('invalid PUBLISH QoS or DUP flags');
    }
    return;
  }
  final expected =
      type == MqttPacketType.pubrel ||
          type == MqttPacketType.subscribe ||
          type == MqttPacketType.unsubscribe
      ? 2
      : 0;
  if (flags != expected) {
    throw const MqttProtocolException('invalid reserved fixed-header flags');
  }
}

/// Encode an MQTT variable-byte integer, including Remaining Length values.
Uint8List encodeMqttVariableByteInteger(int value) {
  if (value < 0 || value > MqttFrame.maxRemainingLength) {
    throw const MqttProtocolException(
      'variable-byte integer exceeds MQTT limit',
    );
  }
  final result = <int>[];
  do {
    var digit = value % 128;
    value ~/= 128;
    if (value != 0) {
      digit |= 0x80;
    }
    result.add(digit);
  } while (value != 0);
  return Uint8List.fromList(result);
}
