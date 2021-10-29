import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum/src/authentication/cra_authentication.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:test/test.dart';

void main() {
  group('CRA', () {
    var salt = 'gbnk5ji1b0dgoeavu31er567nb';
    var secret = '3614';
    var keyValue = 'pjyujtcFkRES8z9jUqvPjokWp2G6xBh7QhtB0tMV6YA=';

    var challenge =
        '{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}';
    var hmac = 'APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=';

    var PBKDF2_HMAC_SHA256_testVectors = [
      ['3614', 'gbnk5ji1b0dgoeavu31er567nb', 1000, 32, base64.decode(keyValue)],
      [
        'password',
        'salt',
        1,
        20,
        [
          for (String i in [
            '12',
            '0f',
            'b6',
            'cf',
            'fc',
            'f8',
            'b3',
            '2c',
            '43',
            'e7',
            '22',
            '52',
            '56',
            'c4',
            'f8',
            '37',
            'a8',
            '65',
            '48',
            'c9'
          ])
            int.parse(i, radix: 16)
        ]
      ],
      [
        'password',
        'salt',
        2,
        20,
        [
          for (String i in [
            'ae',
            '4d',
            '0c',
            '95',
            'af',
            '6b',
            '46',
            'd3',
            '2d',
            '0a',
            'df',
            'f9',
            '28',
            'f0',
            '6d',
            'd0',
            '2a',
            '30',
            '3f',
            '8e'
          ])
            int.parse(i, radix: 16)
        ]
      ],
      [
        'password',
        'salt',
        4096,
        20,
        [
          for (String i in [
            'c5',
            'e4',
            '78',
            'd5',
            '92',
            '88',
            'c8',
            '41',
            'aa',
            '53',
            '0d',
            'b6',
            '84',
            '5c',
            '4c',
            '8d',
            '96',
            '28',
            '93',
            'a0'
          ])
            int.parse(i, radix: 16)
        ]
      ],
      [
        'passwordPASSWORDpassword',
        'saltSALTsaltSALTsaltSALTsaltSALTsalt',
        4096,
        25,
        [
          for (String i in [
            '34',
            '8c',
            '89',
            'db',
            'cb',
            'd3',
            '2b',
            '2f',
            '32',
            'd8',
            '14',
            'b8',
            '11',
            '6e',
            '84',
            'cf',
            '2b',
            '17',
            '34',
            '7e',
            'bc',
            '18',
            '00',
            '18',
            '1c'
          ])
            int.parse(i, radix: 16)
        ]
      ],
      ['pass' + String.fromCharCodes([0]) + 'word','sa' + String.fromCharCodes([0]) + 'lt',4096,16,[for (String i in ['89','b6','9d','05','16','f8','29','89','3c','69','62','26','65','0a','86','87']) int.parse(i, radix: 16)]]
    ];
    test('derive key', () {
      for (var vector in PBKDF2_HMAC_SHA256_testVectors) {
        final key = CraAuthentication.deriveKey(
            vector[0], (vector[1] as String).codeUnits,
            iterations: vector[2], keylen: vector[3]);
        expect(key, equals(vector[4]));
      }
    });
    test('hmac encode', () {
      final mac = CraAuthentication.encodeHmac(
          Uint8List.fromList(keyValue.codeUnits),
          32,
          Uint8List.fromList(challenge.codeUnits));
      expect(mac, equals(hmac));
    });
    test('message handling', () async {
      final authMethod = CraAuthentication(secret);
      expect(authMethod.getName(), equals('wampcra'));
      var extra =
          Extra(challenge: challenge, keylen: 32, iterations: 1000, salt: salt);
      final authenticate = await authMethod.challenge(extra);
      expect(authenticate.signature, equals(hmac));
    });
    test('challenge error', () async {
      final authMethod = CraAuthentication(secret);
      expect(authMethod.getName(), equals('wampcra'));
      expect(
          () async => await authMethod.challenge(null), throwsA(isA<Error>()));
    });
  });
  group('CRA-Unsalted', () {
    var secret = '3614';
    var challenge =
        '{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}';
    var hmac = 'IDDGUdKPgQMUKsYQUPjA5OMHixNrVz5pygaTDh51a0I=';
    test('message handling', () async {
      final authMethod = CraAuthentication(secret);
      expect(authMethod.getName(), equals('wampcra'));
      final extra = Extra(challenge: challenge);
      final authenticate = await authMethod.challenge(extra);
      expect(authenticate.signature, equals(hmac));
    });
  });
}
