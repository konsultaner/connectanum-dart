import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:test/test.dart';

import 'package:connectanum_core/src/serializer/flatbuffers/cbor_validation.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test(
    'decode bounded dictionary preserves binary and portable integer values',
    () {
      final encoded = bytes(
        cbor.encode(
          CborValue({
            '_data': Uint8List.fromList([0, 255]),
            '_max': 9007199254740992,
            '_nested': {
              'é🐈': [null, true, 1.5],
            },
          }),
        ),
      );
      final result = decodeFlatBufferMetadata(encoded);
      expect(result['_data'], isA<Uint8List>());
      expect(result['_data'], [0, 255]);
      expect(result['_max'], 9007199254740992);
      expect(result['_nested'], {
        'é🐈': [null, true, 1.5],
      });
    },
  );

  final valid = <String, List<int>>{
    'empty definite map': [0xa0],
    'empty indefinite map': [0xbf, 0xff],
    'noncanonical length key': [0xa1, 0x78, 1, 0x61, 1],
    'indefinite string key': [0xa1, 0x7f, 0x61, 0x61, 0xff, 1],
    'nested indefinite array': [0xa1, 0x61, 0x61, 0x9f, 1, 2, 0xff],
    'indefinite binary chunks': [0xa1, 0x61, 0x61, 0x5f, 0x41, 1, 0x40, 0xff],
    'indefinite unicode string chunks': [
      0xa1,
      0x61,
      0x61,
      0x7f,
      0x62,
      0xc3,
      0xa9,
      0x61,
      0x61,
      0xff,
    ],
    'float16': [0xa1, 0x61, 0x61, 0xf9, 0x3c, 0],
    'tagged integer': [0xa1, 0x61, 0x61, 0xc0, 1],
    'empty keys are unique': [0xa1, 0x60, 0xf6],
  };
  for (final entry in valid.entries) {
    test('well-formed metadata: ${entry.key}', () {
      validateFlatBufferCbor(
        bytes(entry.value),
        rootMajor: 5,
        stringDictionaryKeys: true,
      );
    });
  }

  final invalid = <String, List<int>>{
    'empty input': [],
    'non-map': [0x80],
    'trailing value': [0xa0, 0xf6],
    'truncated key': [0xa1, 0x62, 0x61],
    'truncated value': [0xa1, 0x61, 0x61],
    'duplicate key': [0xa2, 0x61, 0x61, 1, 0x61, 0x61, 2],
    'duplicate differently encoded key': [
      0xa2,
      0x61,
      0x61,
      1,
      0x78,
      1,
      0x61,
      2,
    ],
    'duplicate indefinite key': [
      0xa2,
      0x61,
      0x61,
      1,
      0x7f,
      0x61,
      0x61,
      0xff,
      2,
    ],
    'nested duplicate': [0xa1, 0x61, 0x61, 0xa2, 0x61, 0x62, 1, 0x61, 0x62, 2],
    'integer dictionary key': [0xa1, 1, 1],
    'nested integer key': [0xa1, 0x61, 0x61, 0xa1, 1, 1],
    'map break after key': [0xbf, 0x61, 0x61, 0xff],
    'missing map break': [0xbf, 0x61, 0x61, 1],
    'break in definite array': [0xa1, 0x61, 0x61, 0x81, 0xff],
    'indefinite byte string nested chunk': [
      0xa1,
      0x61,
      0x61,
      0x5f,
      0x5f,
      0xff,
      0xff,
    ],
    'byte string text chunk': [0xa1, 0x61, 0x61, 0x5f, 0x60, 0xff],
    'split unicode code point': [
      0xa1,
      0x61,
      0x61,
      0x7f,
      0x61,
      0xc3,
      0x61,
      0xa9,
      0xff,
    ],
    'overlong UTF-8': [0xa1, 0x61, 0x61, 0x62, 0xc0, 0x80],
    'UTF-8 surrogate': [0xa1, 0x61, 0x61, 0x63, 0xed, 0xa0, 0x80],
    'UTF-8 above Unicode maximum': [
      0xa1,
      0x61,
      0x61,
      0x64,
      0xf4,
      0x90,
      0x80,
      0x80,
    ],
    'huge string length': [
      0xa1,
      0x61,
      0x61,
      0x7b,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
      0xff,
    ],
    'reserved additional info': [0xa1, 0x61, 0x61, 0x1c],
    'indefinite scalar': [0xa1, 0x61, 0x61, 0x1f],
    'reserved simple value': [0xa1, 0x61, 0x61, 0xf8, 0x18],
  };
  for (final entry in invalid.entries) {
    test('reject malformed metadata: ${entry.key}', () {
      expect(
        () => decodeFlatBufferMetadata(bytes(entry.value)),
        throwsFormatException,
      );
    });
  }

  test('resource budgets reject byte, item and depth excess', () {
    final input = bytes([0xa1, 0x61, 0x61, 0x81, 1]);
    expect(
      () => validateFlatBufferCbor(
        input,
        limits: const FlatBufferCborLimits(maxBytes: 4),
      ),
      throwsFormatException,
    );
    expect(
      () => validateFlatBufferCbor(
        input,
        limits: const FlatBufferCborLimits(maxItems: 3),
      ),
      throwsFormatException,
    );
    expect(
      () => validateFlatBufferCbor(
        input,
        limits: const FlatBufferCborLimits(maxDepth: 1),
      ),
      throwsFormatException,
    );
    validateFlatBufferCbor(
      input,
      limits: const FlatBufferCborLimits(maxBytes: 5, maxItems: 4, maxDepth: 2),
    );
  });

  test('byte string contents are opaque to validation', () {
    validateFlatBufferCbor(bytes([0x43, 0xff, 0x1c, 0xc0]), rootMajor: 2);
  });

  test('application CBOR allows non-string map keys', () {
    validateFlatBufferCbor(bytes([0x81, 0xa1, 1, 0xf6]), rootMajor: 4);
  });
}
