import 'dart:typed_data';

import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/serializer/cbor/serializer.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('serialize', () {
    test('Challenge', () {
      var challenge = serializer.deserialize(
          Uint8List.fromList([131, 4, 103, 119, 97, 109, 112, 99, 114, 97, 164, 105, 99, 104, 97, 108, 108, 101, 110, 103, 101, 120, 172, 123, 34, 97, 117, 116, 104, 105, 100, 34, 58, 34, 82, 105, 99, 104, 105, 34, 44, 34, 97, 117, 116, 104, 114, 111, 108, 101, 34, 58, 34, 97, 100, 109, 105, 110, 34, 44, 34, 97, 117, 116, 104, 109, 101, 116, 104, 111, 100, 34, 58, 34, 119, 97, 109, 112, 99, 114, 97, 34, 44, 34, 97, 117, 116, 104, 112, 114, 111, 118, 105, 100, 101, 114, 34, 58, 34, 115, 101, 114, 118, 101, 114, 34, 44, 34, 110, 111, 110, 99, 101, 34, 58, 34, 53, 54, 51, 54, 49, 49, 55, 53, 54, 56, 55, 54, 56, 49, 50, 50, 34, 44, 34, 116, 105, 109, 101, 115, 116, 97, 109, 112, 34, 58, 34, 50, 48, 49, 56, 45, 48, 51, 45, 49, 54, 84, 48, 55, 58, 50, 57, 90, 34, 44, 34, 115, 101, 115, 115, 105, 111, 110, 34, 58, 34, 53, 55, 54, 56, 53, 48, 49, 48, 57, 57, 49, 51, 48, 56, 51, 54, 34, 125, 100, 115, 97, 108, 116, 114, 102, 104, 104, 105, 50, 57, 48, 102, 104, 55, 194, 167, 41, 71, 81, 41, 71, 41, 102, 107, 101, 121, 108, 101, 110, 24, 35, 106, 105, 116, 101, 114, 97, 116, 105, 111, 110, 115, 25, 1, 154])
      ) as Challenge;
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.CODE_CHALLENGE));
      expect(challenge.authMethod, equals('wampcra'));
      expect(
          challenge.extra.challenge,
          equals(
              '{\"authid\":\"Richi\",\"authrole\":\"admin\",\"authmethod\":\"wampcra\",\"authprovider\":\"server\",\"nonce\":\"5636117568768122\",\"timestamp\":\"2018-03-16T07:29Z\",\"session\":\"5768501099130836\"}'));
      expect(challenge.extra.salt, equals('fhhi290fh7§)GQ)G)'));
      expect(challenge.extra.keylen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
  });
}