import 'dart:typed_data';
import 'dart:math';

import 'package:cbor/cbor.dart';
import 'package:test/test.dart';

import 'package:connectanum_core/src/serializer/flatbuffers/cbor_validation.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('repeated text keeps decoded values independent of input and maps', () {
    final encoded = bytes([
      0xa1,
      0x63,
      0x73,
      0x61,
      0x78,
      0x63,
      0x76,
      0x61,
      0x78,
    ]);
    final first = decodeFlatBufferMetadata(encoded.asUnmodifiableView());
    encoded[3] = 0x62;
    encoded[7] = 0x62;
    final second = decodeFlatBufferMetadata(encoded.asUnmodifiableView());
    expect(first, {'sax': 'vax'});
    expect(second, {'sbx': 'vbx'});
    second['sbx'] = 'edited';
    expect(decodeFlatBufferMetadata(encoded), {'sbx': 'vbx'});
    expect(first, {'sax': 'vax'});
    encoded[7] = 0xff;
    expect(() => decodeFlatBufferMetadata(encoded), throwsFormatException);
    encoded[7] = 0x62;
    expect(
      () => decodeFlatBufferMetadata(
        Uint8List.sublistView(encoded, 0, encoded.length - 1),
      ),
      throwsFormatException,
    );
  });

  test('short text churn preserves every key and value across revisits', () {
    // Equal length and first/last bytes deliberately exercise cache collisions.
    for (var pass = 0; pass < 3; pass++) {
      for (var unit = 0; unit < 128; unit++) {
        final key = 's${String.fromCharCode(unit)}x';
        final value = 'v${String.fromCharCode(127 - unit)}x';
        final encoded = bytes(cbor.encode(CborValue({key: value})));
        expect(decodeFlatBufferMetadata(encoded), {key: value});
      }
    }
    for (final length in [0, 1, 63, 64, 65, 1000]) {
      final value = 'x' * length;
      expect(
        decodeFlatBufferMetadata(bytes(cbor.encode(CborValue({value: value})))),
        {value: value},
      );
    }
  });

  test('ASCII and Unicode metadata text preserves logical readonly ranges', () {
    for (final value in ['\u0000ASCII\u007f', 'é€🧪']) {
      final encoded = bytes(cbor.encode(CborValue({'\u0000\u007f': value})));
      for (var offset = 0; offset < 8; offset++) {
        final backing = Uint8List(encoded.length + offset + 7)
          ..fillRange(0, encoded.length + offset + 7, 255)
          ..setRange(offset, offset + encoded.length, encoded);
        final view = Uint8List.sublistView(
          backing,
          offset,
          offset + encoded.length,
        ).asUnmodifiableView();
        expect(decodeFlatBufferMetadata(view), {'\u0000\u007f': value});
      }
    }
    expect(
      decodeFlatBufferMetadata(
        bytes([0xa1, 0x61, 0x6b, 0x7f, 0x61, 0, 0x61, 127, 0xff]),
      ),
      {'k': '\u0000\u007f'},
    );
    // UTF-8 code points cannot be split across indefinite text chunks.
    expect(
      () => decodeFlatBufferMetadata(
        bytes([0xa1, 0x61, 0x6b, 0x7f, 0x61, 0xc3, 0x61, 0xa9, 0xff]),
      ),
      throwsFormatException,
    );
  });
  test('UTF-8 scan validates code points at ASCII block boundaries', () {
    for (var offset = 0; offset < 16; offset++) {
      final valid = List<int>.filled(24, 0x61)
        ..setRange(offset, offset + 2, [0xc3, 0xa9]);
      validateFlatBufferCbor(
        bytes([0x78, valid.length, ...valid]),
        rootMajor: 3,
      );

      final invalid = List<int>.filled(24, 0x61)
        ..setRange(offset, offset + 2, [0xc3, 0x41]);
      expect(
        () => validateFlatBufferCbor(
          bytes([0x78, invalid.length, ...invalid]),
          rootMajor: 3,
        ),
        throwsFormatException,
        reason: 'invalid continuation byte at offset $offset',
      );
    }

    final mixed = List<int>.filled(40, 0x61)
      ..setRange(7, 9, [0xc3, 0xa9])
      ..setRange(19, 23, [0xf0, 0x9f, 0xa7, 0xaa])
      ..setRange(31, 34, [0xe2, 0x82, 0xac]);
    validateFlatBufferCbor(bytes([0x78, mixed.length, ...mixed]), rootMajor: 3);

    final truncated = List<int>.filled(33, 0x61)
      ..setRange(31, 33, [0xe2, 0x82]);
    expect(
      () => validateFlatBufferCbor(
        bytes([0x78, truncated.length, ...truncated]),
        rootMajor: 3,
      ),
      throwsFormatException,
      reason: 'a truncated multibyte sequence after earlier code points',
    );
  });
  _singlePassMetadataCases();
  group('scalar metadata decoding', _scalarMetadataDecodeCases);
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

void _singlePassMetadataCases() {
  test('scalar dictionaries preserve Unicode keys and reject every prefix', () {
    final random = Random(142637);
    for (var index = 0; index < 32; index++) {
      final expected = <String, dynamic>{
        'text$index': '🙂 héllo ${random.nextInt(100000)}',
        'number': random.nextInt(1 << 30),
        'negative': -random.nextInt(1 << 30),
        'nil': null,
        'bool': random.nextBool(),
        'é': 1,
        'e\u0301': 2,
        'A': 3,
        'Ａ': 4,
      };
      final encoded = bytes(cbor.encode(CborValue(expected)));
      expect(decodeFlatBufferMetadata(encoded), expected);
      for (var end = 0; end < encoded.length; end++) {
        expect(
          () =>
              decodeFlatBufferMetadata(Uint8List.sublistView(encoded, 0, end)),
          throwsFormatException,
          reason: 'map=$index prefix=$end',
        );
      }
    }
  });
  test('scalar dictionaries enforce the inclusive metadata byte budget', () {
    const limit = 1048576;
    final encoded = Uint8List(limit)
      ..setRange(0, 4, [0xa1, 0x61, 0x6b, 0x7a])
      ..fillRange(8, limit, 0x61);
    ByteData.sublistView(encoded).setUint32(4, limit - 8, Endian.big);
    final value = decodeFlatBufferMetadata(encoded)['k'] as String;
    expect(value, hasLength(limit - 8));
    expect(value.codeUnitAt(0), 0x61);
    expect(value.codeUnitAt(value.length - 1), 0x61);
    final oversized = Uint8List(limit + 1)
      ..setRange(0, limit, encoded)
      ..[limit] = 0x61;
    ByteData.sublistView(oversized).setUint32(4, limit - 7, Endian.big);
    expect(() => decodeFlatBufferMetadata(oversized), throwsFormatException);
    expect(
      () => decodeFlatBufferMetadata(
        Uint8List.sublistView(encoded, 0, limit - 1),
      ),
      throwsFormatException,
    );
  });
}

void _scalarMetadataDecodeCases() {
  final values = <Object?>[
    null,
    true,
    false,
    '',
    'plain',
    'ä😀',
    0,
    1,
    23,
    24,
    255,
    256,
    65535,
    65536,
    4294967295,
    4294967296,
    9007199254740991,
    9007199254740992,
    -1,
    -24,
    -25,
    -256,
    -257,
    -65536,
    -65537,
    -9007199254740991,
    -9007199254740992,
    BigInt.parse('18446744073709551615'),
    BigInt.parse('-18446744073709551616'),
    1.25,
    double.infinity,
    double.negativeInfinity,
    Uint8List.fromList([1, 2, 3]),
    [1, 'text'],
    {'nested': true},
    DateTime.utc(2026, 10, 16),
  ];
  final vectors = <Uint8List>[
    Uint8List.fromList([0xa0]),
    Uint8List.fromList([0xbf, 0xff]),
    Uint8List.fromList([
      0xbf,
      0x7f,
      0x61,
      0x6b,
      0xff,
      0x7f,
      0x62,
      0xc3,
      0xa4,
      0x61,
      0x61,
      0xff,
      0xff,
    ]),
    for (final value in values)
      Uint8List.fromList(cbor.encode(CborValue({'value': value}))),
    for (final width in [1, 2, 4, 8])
      Uint8List.fromList([
        0xa1,
        0x61,
        0x6b,
        width == 1
            ? 0x18
            : width == 2
            ? 0x19
            : width == 4
            ? 0x1a
            : 0x1b,
        ...List.filled(width - 1, 0),
        1,
      ]),
  ];
  for (final magnitude in [
    BigInt.parse('9007199254740991'),
    BigInt.parse('9007199254740992'),
    BigInt.parse('9007199254740993'),
    BigInt.parse('9223372036854775807'),
    BigInt.parse('9223372036854775808'),
    BigInt.parse('18446744073709551615'),
  ]) {
    for (final major in [0, 1]) {
      vectors.add(
        Uint8List.fromList([
          0xa1,
          0x61,
          0x6b,
          (major << 5) | 27,
          for (var shift = 56; shift >= 0; shift -= 8)
            ((magnitude >> shift) & BigInt.from(255)).toInt(),
        ]),
      );
    }
  }
  for (var index = 0; index < vectors.length; index++) {
    final vector = vectors[index];
    test('preserves CBOR reference vector $index', () {
      // The protocol narrows exact portable BigInts, including 2^53.
      final expected = (cbor.decode(vector).toObject() as Map).map(
        (key, value) => MapEntry(
          key,
          value is BigInt && value.abs() <= BigInt.from(9007199254740992)
              ? value.toInt()
              : value,
        ),
      );
      final actual = decodeFlatBufferMetadata(vector);
      expect(actual, expected);
      for (final key in expected.keys) {
        final value = expected[key];
        if (value is! List && value is! Map) {
          expect(actual[key].runtimeType, value.runtimeType);
        }
      }
    });
    test('truncated vector $index preserves validation', () {
      for (var length = 0; length < vector.length; length++) {
        final prefix = Uint8List.sublistView(vector, 0, length);
        expect(() => decodeFlatBufferMetadata(prefix), throwsFormatException);
      }
    });
  }
  test('duplicate equivalent chunked keys remain rejected', () {
    final duplicate = Uint8List.fromList([
      0xa2,
      0x61,
      0x6b,
      0xf4,
      0x7f,
      0x61,
      0x6b,
      0xff,
      0xf5,
    ]);
    expect(() => decodeFlatBufferMetadata(duplicate), throwsFormatException);
  });
}
