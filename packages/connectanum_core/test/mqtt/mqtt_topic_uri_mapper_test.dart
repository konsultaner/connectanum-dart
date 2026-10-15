import 'package:connectanum_core/mqtt.dart';
import 'package:test/test.dart';

void main() {
  group('MQTT topic URI mapper', () {
    test('encodes hierarchy and empty levels without collisions', () {
      const cases = {
        'a/b': 'connectanum.mqtt.v1.topic.s61.s62',
        'a//b/': 'connectanum.mqtt.v1.topic.s61.s.s62.s',
        '/': 'connectanum.mqtt.v1.topic.s.s',
        'a.b': 'connectanum.mqtt.v1.topic.s612e62',
        r'$SYS/status': 'connectanum.mqtt.v1.topic.s24535953.s737461747573',
        'é': 'connectanum.mqtt.v1.topic.sc3a9',
      };
      final strict = RegExp(r'^([0-9a-z_]+\.)*[0-9a-z_]+$');
      for (final entry in cases.entries) {
        expect(MqttTopicUriMapper.toWampUri(entry.key), entry.value);
        expect(strict.hasMatch(entry.value), isTrue);
        expect(MqttTopicUriMapper.fromWampUri(entry.value), entry.key);
      }
    });

    test('rejects invalid MQTT topic names and overlong UTF-8', () {
      for (final topic in [
        '',
        'a/#',
        'a/+',
        'a\u0000b',
        'a' * 65536,
        '\uD800',
      ]) {
        expect(
          () => MqttTopicUriMapper.toWampUri(topic),
          throwsA(isA<MqttProtocolException>()),
        );
      }
    });

    test('accepts the maximum MQTT topic byte length', () {
      final topic = 'a' * 65535;
      expect(
        MqttTopicUriMapper.fromWampUri(MqttTopicUriMapper.toWampUri(topic)),
        topic,
      );
    });

    test('rejects noncanonical and malformed WAMP topic URIs', () {
      for (final uri in [
        'connectanum.mqtt.v1.topic',
        'mqtt.topic.s61',
        'connectanum.mqtt.v1.topic.sA',
        'connectanum.mqtt.v1.topic.s6',
        'connectanum.mqtt.v1.topic.sgg',
        'connectanum.mqtt.v1.topic.s612f62',
        'connectanum.mqtt.v1.topic.sff',
        'connectanum.mqtt.v1.topic.s',
        'connectanum.mqtt.v1.topic.s23',
        'connectanum.mqtt.v1.topic.s00',
      ]) {
        expect(
          () => MqttTopicUriMapper.fromWampUri(uri),
          throwsA(isA<MqttProtocolException>()),
          reason: uri,
        );
      }
    });
  });
}
