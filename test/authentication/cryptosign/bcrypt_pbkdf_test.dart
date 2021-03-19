import 'dart:typed_data';

import 'package:connectanum/src/authentication/cryptosign/bcrypt_pbkdf.dart';
import 'package:test/test.dart';

void main() {
  group('BCRYPT PBKDF', () {
    var fourRounds = Uint8List.fromList([
      0x5b,
      0xbf,
      0x0c,
      0xc2,
      0x93,
      0x58,
      0x7f,
      0x1c,
      0x36,
      0x35,
      0x55,
      0x5c,
      0x27,
      0x79,
      0x65,
      0x98,
      0xd4,
      0x7e,
      0x57,
      0x90,
      0x71,
      0xbf,
      0x42,
      0x7e,
      0x9d,
      0x8f,
      0xbe,
      0x84,
      0x2a,
      0xba,
      0x34,
      0xd9
    ]);
    var eightRounds = Uint8List.fromList([
      0xe1,
      0x36,
      0x7e,
      0xc5,
      0x15,
      0x1a,
      0x33,
      0xfa,
      0xac,
      0x4c,
      0xc1,
      0xc1,
      0x44,
      0xcd,
      0x23,
      0xfa,
      0x15,
      0xd5,
      0x54,
      0x84,
      0x93,
      0xec,
      0xc9,
      0x9b,
      0x9b,
      0x5d,
      0x9c,
      0x0d,
      0x3b,
      0x27,
      0xbe,
      0xc7,
      0x62,
      0x27,
      0xea,
      0x66,
      0x08,
      0x8b,
      0x84,
      0x9b,
      0x20,
      0xab,
      0x7a,
      0xa4,
      0x78,
      0x01,
      0x02,
      0x46,
      0xe7,
      0x4b,
      0xba,
      0x51,
      0x72,
      0x3f,
      0xef,
      0xa9,
      0xf9,
      0x47,
      0x4d,
      0x65,
      0x08,
      0x84,
      0x5e,
      0x8d
    ]);
    var fortyTwoRounds = Uint8List.fromList([
      0x83,
      0x3c,
      0xf0,
      0xdc,
      0xf5,
      0x6d,
      0xb6,
      0x56,
      0x08,
      0xe8,
      0xf0,
      0xdc,
      0x0c,
      0xe8,
      0x82,
      0xbd
    ]);

    test('four rounds', () {
      var output = Uint8List(fourRounds.length);
      BcryptPbkdf.pbkdf(
          'password', Uint8List.fromList('salt'.codeUnits), 4, output);
      expect(output, equals(fourRounds));
    });

    test('eight rounds', () {
      var output = Uint8List(eightRounds.length);
      BcryptPbkdf.pbkdf(
          'password', Uint8List.fromList('salt'.codeUnits), 8, output);
      expect(output, equals(eightRounds));
    });

    test('forty two rounds', () {
      var output = Uint8List(fortyTwoRounds.length);
      BcryptPbkdf.pbkdf(
          'password', Uint8List.fromList('salt'.codeUnits), 42, output);
      expect(output, equals(fortyTwoRounds));
    });
  });
}
