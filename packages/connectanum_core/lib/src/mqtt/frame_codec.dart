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
    _storage = Uint8List(maxPacketSize < 4096 ? maxPacketSize : 4096);
  }

  final int maxPacketSize;
  late Uint8List _storage;
  int _start = 0;
  int _end = 0;
  bool _failed = false;

  int get bufferedBytes => _end - _start;

  /// Accept bytes and return every complete packet in input order.
  ///
  /// A malformed packet is terminal for this decoder and its connection.
  List<MqttFrame> add(Uint8List input) {
    if (_failed) {
      throw StateError('MQTT decoder is terminal after a protocol error');
    }
    final frames = <MqttFrame>[];
    var offset = 0;
    _drain(frames);
    while (offset < input.length) {
      final available = maxPacketSize - bufferedBytes;
      if (available == 0) {
        _fail('packet exceeds configured size limit');
      }
      final remaining = input.length - offset;
      final count = remaining < available ? remaining : available;
      _append(input, offset, count);
      offset += count;
      _drain(frames);
    }
    return frames;
  }

  void _append(Uint8List input, int offset, int count) {
    if (_end + count > _storage.length) {
      final retained = bufferedBytes;
      var capacity = _storage.length;
      while (capacity < retained + count) {
        capacity *= 2;
      }
      if (capacity > maxPacketSize) {
        capacity = maxPacketSize;
      }
      final next = Uint8List(capacity);
      next.setRange(0, retained, _storage, _start);
      _storage = next;
      _start = 0;
      _end = retained;
    }
    _storage.setRange(_end, _end + count, input, offset);
    _end += count;
  }

  void _drain(List<MqttFrame> frames) {
    while (bufferedBytes > 0) {
      final first = _storage[_start];
      final code = first >> 4;
      if (code < 1 || code > MqttPacketType.values.length) {
        _fail('invalid MQTT control packet type');
      }
      final type = MqttPacketType.values[code - 1];
      try {
        _validateFlags(type, first & 0x0f);
      } on MqttProtocolException catch (error) {
        _fail(error.message);
      }
      if (bufferedBytes < 2) {
        return;
      }

      var remainingLength = 0;
      var multiplier = 1;
      var lengthBytes = 0;
      while (lengthBytes < 4) {
        if (bufferedBytes <= lengthBytes + 1) {
          return;
        }
        final digit = _storage[_start + 1 + lengthBytes];
        remainingLength += (digit & 0x7f) * multiplier;
        lengthBytes++;
        if (digit & 0x80 == 0) {
          if (lengthBytes > 1 && remainingLength < multiplier) {
            _fail('remaining length is not minimally encoded');
          }
          final packetSize = 1 + lengthBytes + remainingLength;
          if (packetSize > maxPacketSize) {
            _fail('packet exceeds configured size limit');
          }
          if (bufferedBytes < packetSize) {
            return;
          }
          final bodyStart = _start + 1 + lengthBytes;
          final body = Uint8List(remainingLength);
          body.setRange(0, remainingLength, _storage, bodyStart);
          frames.add(MqttFrame._owned(type, first & 0x0f, body));
          _start += packetSize;
          if (_start == _end) {
            _start = 0;
            _end = 0;
          }
          break;
        }
        if (lengthBytes == 4) {
          _fail('remaining length exceeds four bytes');
        }
        multiplier *= 128;
      }
    }
  }

  Never _fail(String message) {
    _failed = true;
    _start = 0;
    _end = 0;
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
