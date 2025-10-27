import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:test/test.dart';

void main() {
  group('Serializer challenge/welcome', () {
    test('json serializer encodes challenge', () {
      final serializer = json_serializer.Serializer();
      final challenge = Challenge(
        'ticket',
        Extra(
          challenge: 'abc',
          salt: 'salt',
          keyLen: 32,
          iterations: 10,
          memory: 64,
          kdf: 'pbkdf2',
          nonce: 'nonce',
          channelBinding: 'tls-unique',
        ),
      );
      final encoded = serializer.serializeToString(challenge);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      expect(decoded[0], MessageTypes.codeChallenge);
      expect(decoded[1], 'ticket');
      final extra = decoded[2] as Map<String, dynamic>;
      expect(extra['challenge'], 'abc');
      expect(extra['salt'], 'salt');
      expect(extra['keylen'], 32);
      expect(extra['iterations'], 10);
      expect(extra['memory'], 64);
      expect(extra['kdf'], 'pbkdf2');
      expect(extra['nonce'], 'nonce');
      expect(extra['channel_binding'], 'tls-unique');
    });

    test('json serializer encodes welcome', () {
      final serializer = json_serializer.Serializer();
      final details = Details.forWelcome(
        realm: 'realm1',
        authId: 'anonymous',
        authMethod: 'anonymous',
        authProvider: 'static',
        authRole: 'anonymous',
      );
      final welcome = Welcome(12345, details);
      final encoded = serializer.serializeToString(welcome);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      expect(decoded[0], MessageTypes.codeWelcome);
      expect(decoded[1], 12345);
      final detailMap = decoded[2] as Map<String, dynamic>;
      expect(detailMap['authid'], 'anonymous');
      expect(detailMap['roles'], isA<Map>());
    });

    test('msgpack serializer encodes challenge', () {
      final serializer = msgpack_serializer.Serializer();
      final challenge = Challenge('ticket', Extra(challenge: 'abc'));
      final encoded = serializer.serialize(challenge);
      final decoded =
          msgpack_serializer.Serializer().deserialize(encoded) as Challenge;
      expect(decoded.authMethod, 'ticket');
      expect(decoded.extra.challenge, 'abc');
    });

    test('msgpack serializer encodes welcome', () {
      final serializer = msgpack_serializer.Serializer();
      final details = Details.forWelcome(
        realm: 'realm1',
        authId: 'user',
        authMethod: 'anonymous',
        authProvider: 'static',
        authRole: 'anonymous',
      );
      final welcome = Welcome(67890, details);
      final encoded = serializer.serialize(welcome);
      final decoded =
          msgpack_serializer.Serializer().deserialize(encoded) as Welcome;
      expect(decoded.sessionId, 67890);
      expect(decoded.details.authid, 'user');
    });
  });
}
