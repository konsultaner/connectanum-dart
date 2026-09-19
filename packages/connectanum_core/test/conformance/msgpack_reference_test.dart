import 'dart:typed_data';

import 'package:test/test.dart';

import 'msgpack_reference.dart';

Uint8List hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

void main() {
  final vectors = <String, Object?>{
    '00': 0,
    '7f': 127,
    'e0': -32,
    'ff': -1,
    'c0': null,
    'c2': false,
    'c3': true,
    'ccff': 255,
    'cdffff': 65535,
    'ceffffffff': 4294967295,
    'cf0000000100000000': 4294967296,
    'cf000000012a05f200': 5000000000,
    'cf001fffffffffffff': 9007199254740991,
    'd080': -128,
    'd10080': 128,
    'd18000': -32768,
    'd280000000': -2147483648,
    'd3fffffffeffffffff': -4294967297,
    'd3ffe0000000000001': -9007199254740991,
    'd3001fffffffffffff': 9007199254740991,
    'ca3fc00000': 1.5,
    'cbbff8000000000000': -1.5,
    'a0': '',
    'a3616263': 'abc',
    'd903616263': 'abc',
    'da0003616263': 'abc',
    'db00000003616263': 'abc',
    'a2c3bc': '\u00fc',
    'a4f09f9880': '\u{1f600}',
    'c400': Uint8List(0),
    'c40300ff80': Uint8List.fromList([0, 255, 128]),
    'c5000300ff80': Uint8List.fromList([0, 255, 128]),
    'c60000000300ff80': Uint8List.fromList([0, 255, 128]),
    '90': <Object?>[],
    '93c001ff': <Object?>[null, 1, -1],
    'dc0002c2c3': <Object?>[false, true],
    'dd00000002c2c3': <Object?>[false, true],
    'dc000101': <Object?>[1],
    'dd0000000101': <Object?>[1],
    '80': <String, Object?>{},
    '81a16101': <String, Object?>{'a': 1},
    'de0001a16101': <String, Object?>{'a': 1},
    'df00000001a16101': <String, Object?>{'a': 1},
    '9281a17892c0cf000000012a05f200c40200ff': <Object?>[
      {
        'x': [null, 5000000000],
      },
      Uint8List.fromList([0, 255]),
    ],
  };

  for (final vector in vectors.entries) {
    test('literal independent vector ${vector.key}', () {
      final decoded = decodeReferenceMessagePack(hex(vector.key));
      expect(decoded, equals(vector.value));
      if (vector.value is Uint8List) {
        expect(decoded, isA<Uint8List>());
      }
    });
  }

  for (final value in [
    '',
    'c1',
    'c001',
    'cc',
    'cd00',
    'ce000000',
    'cf00000000000000',
    'd0',
    'd100',
    'd2000000',
    'd300000000000000',
    'ca000000',
    'cb00000000000000',
    'a261',
    'd901',
    'da0001',
    'db00000001',
    'c401',
    'c50001',
    'c600000001',
    '9201',
    'dc0001',
    'dd00000001',
    '81a161',
    'de0001a161',
    'df00000001a161',
    'a1ff',
    'a2c328',
    'a3eda080',
    '8201010102',
    '82a16101a16102',
    'ddffffffff',
    'dfffffffff',
    'dbffffffff',
    'c6ffffffff',
    'cf0020000000000000',
    'cf0020000000000001',
    'cfffffffffffffffff',
    'd30020000000000000',
    'd3ffe0000000000000',
    'd38000000000000000',
    'c700',
    'c80000',
    'c900000000',
    'd40000',
    'd5000000',
    'd60000000000',
    'd7000000000000000000',
    'd80000000000000000000000000000000000',
  ]) {
    test('rejects malformed or unsupported input $value', () {
      expect(
        () => decodeReferenceMessagePack(hex(value)),
        throwsFormatException,
      );
    });
  }

  test('rejects deep nesting rather than overflowing', () {
    expect(
      () => decodeReferenceMessagePack(
        Uint8List.fromList([
          ...List.filled(65, 0x91),
          0xc0,
        ]),
      ),
      throwsFormatException,
    );
  });

  test('reads a view without including its surrounding bytes', () {
    final bytes = hex('c1cf000000012a05f200c1');
    expect(
      decodeReferenceMessagePack(Uint8List.sublistView(bytes, 1, 10)),
      5000000000,
    );
  });

  test('binary result is detached from the input buffer', () {
    final bytes = hex('c40200ff');
    final decoded = decodeReferenceMessagePack(bytes);
    bytes[2] = 99;
    expect(decoded, equals([0, 255]));
  });
}
