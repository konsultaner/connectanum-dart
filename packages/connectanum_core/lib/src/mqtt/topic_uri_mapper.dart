import 'dart:convert';
import 'dart:typed_data';

import 'frame_codec.dart';

/// Reversible, strict-URI-safe namespace for explicit MQTT/WAMP gateways.
///
/// Each MQTT topic level becomes a WAMP component: `s` followed by lowercase
/// hexadecimal UTF-8 bytes. The lone `s` represents an empty topic level.
/// This class only maps names; it never grants routing or authorization.
abstract final class MqttTopicUriMapper {
  static const String prefix = 'connectanum.mqtt.v1.topic';
  static const String _hex = '0123456789abcdef';
  static final RegExp _hexDigits = RegExp(r'^[0-9a-f]*$');

  static String toWampUri(String topic) {
    _validateTopic(topic);
    final bytes = utf8.encode(topic);
    if (bytes.length > 65535 || utf8.decode(bytes) != topic) {
      throw const MqttProtocolException('invalid MQTT topic UTF-8 length');
    }
    final output = StringBuffer('$prefix.s');
    for (final byte in bytes) {
      if (byte == 0x2f) {
        output.write('.s');
      } else {
        output.writeCharCode(_hex.codeUnitAt(byte >> 4));
        output.writeCharCode(_hex.codeUnitAt(byte & 0x0f));
      }
    }
    return output.toString();
  }

  static String fromWampUri(String uri) {
    // Every source byte becomes exactly two URI characters: hex or `.s`.
    if (!uri.startsWith('$prefix.') ||
        uri.length > prefix.length + 2 + 2 * 65535) {
      throw const MqttProtocolException('invalid MQTT gateway URI');
    }
    final components = uri.substring(prefix.length + 1).split('.');
    final bytes = BytesBuilder(copy: false);
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      if (!component.startsWith('s') ||
          (component.length - 1).isOdd ||
          !_hexDigits.hasMatch(component.substring(1))) {
        throw const MqttProtocolException('noncanonical MQTT gateway URI');
      }
      if (i > 0) bytes.addByte(0x2f);
      for (var offset = 1; offset < component.length; offset += 2) {
        final value = int.parse(
          component.substring(offset, offset + 2),
          radix: 16,
        );
        if (value == 0x2f) {
          throw const MqttProtocolException('encoded topic level separator');
        }
        bytes.addByte(value);
      }
    }
    final encoded = bytes.takeBytes();
    late final String topic;
    try {
      topic = utf8.decode(encoded);
    } on FormatException {
      throw const MqttProtocolException('invalid MQTT topic UTF-8');
    }
    _validateTopic(topic);
    return topic;
  }

  static void _validateTopic(String topic) {
    if (topic.isEmpty ||
        topic.contains('\u0000') ||
        topic.contains('+') ||
        topic.contains('#')) {
      throw const MqttProtocolException('invalid MQTT topic name');
    }
  }
}
