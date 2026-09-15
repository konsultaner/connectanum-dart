import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/msgpack/codec.dart' as codec;
import 'package:msgpack_dart/msgpack_dart.dart' as delegate;
import 'package:test/test.dart';

const _wide = 0x100000000;
const _wideWire = [0xcf, 0, 0, 0, 1, 0, 0, 0, 0];

bool _supports64BitAccessors() {
  try {
    ByteData(8).getUint64(0);
    return true;
  } on UnsupportedError {
    return false;
  }
}

void main() {
  final nativeIntegers = _supports64BitAccessors();
  final scalars = <(String, List<int>, Object?)>[
    ('positive fixint', [0x7f], 127),
    ('negative fixint', [0xe0], -32),
    ('nil', [0xc0], null),
    ('false', [0xc2], false),
    ('true', [0xc3], true),
    ('uint8', [0xcc, 0xff], 255),
    ('int8', [0xd0, 0x80], -128),
    ('uint16', [0xcd, 0xff, 0xff], 65535),
    ('int16', [0xd1, 0x80, 0], -32768),
    ('uint32', [0xce, 0xff, 0xff, 0xff, 0xff], 0xffffffff),
    ('int32', [0xd2, 0x80, 0, 0, 0], -0x80000000),
    ('float32', [0xca, 0x3f, 0xc0, 0, 0], 1.5),
    ('float64', [0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0], 1.5),
    ('fixstr', [0xa2, 0xc3, 0xa4], '\u00e4'),
    ('str8', [0xd9, 2, 0xc3, 0xa4], '\u00e4'),
    ('str16', [0xda, 0, 2, 0xc3, 0xa4], '\u00e4'),
    ('str32', [0xdb, 0, 0, 0, 2, 0xc3, 0xa4], '\u00e4'),
    ('bin8', [0xc4, 2, 0, 0xff], Uint8List.fromList([0, 0xff])),
    ('bin16', [0xc5, 0, 2, 0, 0xff], Uint8List.fromList([0, 0xff])),
    ('bin32', [0xc6, 0, 0, 0, 2, 0, 0xff], Uint8List.fromList([0, 0xff])),
    for (final (marker, size) in [
      (0xd4, 1),
      (0xd5, 2),
      (0xd6, 4),
      (0xd7, 8),
      (0xd8, 16),
    ])
      ('fixext$size', [marker, 42, ...List.filled(size, 7)], null),
    ('ext8', [0xc7, 2, 42, 7, 8], null),
    ('ext16', [0xc8, 0, 2, 42, 7, 8], null),
    ('ext32', [0xc9, 0, 0, 0, 2, 42, 7, 8], null),
  ];

  group('MessagePack codec wire boundaries', () {
    // Leading uint64 enters the JavaScript fallback before the scalar. A final
    // boolean proves that each scalar consumes exactly its own wire bytes.
    for (final (name, wire, value) in scalars) {
      test('decodes $name after uint64 without consuming the next value', () {
        final frame = Uint8List.fromList([0x93, ..._wideWire, ...wire, 0xc3]);
        expect(codec.deserialize(frame), equals([_wide, value, true]));
        final padded = Uint8List.fromList([0x7e, ...frame, 0x7f]);
        expect(
          codec.deserialize(
            Uint8List.sublistView(padded, 1, padded.length - 1),
          ),
          equals([_wide, value, true]),
        );
      });

      test('rejects every truncated $name prefix after uint64', () {
        for (var length = 0; length < wire.length; length++) {
          final frame = Uint8List.fromList([
            0x92,
            ..._wideWire,
            ...wire.take(length),
          ]);
          expect(
            () => codec.deserialize(frame),
            nativeIntegers ? throwsRangeError : throwsFormatException,
            reason: '$name truncated to $length/${wire.length} bytes',
          );
        }
      });
    }

    for (final (name, header, payload, expected)
        in <(String, List<int>, List<int>, Object)>[
          ('fixarray', [0x91], [7], [7]),
          ('array16', [0xdc, 0, 1], [7], [7]),
          ('array32', [0xdd, 0, 0, 0, 1], [7], [7]),
          ('fixmap', [0x81], [0xa1, 0x6b, 7], {'k': 7}),
          ('map16', [0xde, 0, 1], [0xa1, 0x6b, 7], {'k': 7}),
          ('map32', [0xdf, 0, 0, 0, 1], [0xa1, 0x6b, 7], {'k': 7}),
        ]) {
      test('decodes $name headers inside a fallback collection', () {
        final frame = Uint8List.fromList([
          0x93,
          ..._wideWire,
          ...header,
          ...payload,
          0xc3,
        ]);
        expect(codec.deserialize(frame), equals([_wide, expected, true]));
      });
      test('rejects truncated $name headers and bodies', () {
        final wire = [...header, ...payload];
        for (var length = 0; length < wire.length; length++) {
          expect(
            () => codec.deserialize(
              Uint8List.fromList([
                0x92,
                ..._wideWire,
                ...wire.take(length),
              ]),
            ),
            nativeIntegers ? throwsRangeError : throwsFormatException,
            reason: '$name truncated to $length/${wire.length} bytes',
          );
        }
      });
    }

    test('rejects reserved markers after entering the fallback', () {
      expect(
        () => codec.deserialize(Uint8List.fromList([0x92, ..._wideWire, 0xc1])),
        nativeIntegers
            ? throwsA(isA<delegate.FormatError>())
            : throwsFormatException,
      );
    });

    test('rejects declared collections larger than the available payload', () {
      for (final header in <List<int>>[
        [0xdc, 0, 64],
        [0xdd, 0, 0, 0, 64],
        [0xde, 0, 64],
        [0xdf, 0, 0, 0, 64],
      ]) {
        expect(
          () => codec.deserialize(
            Uint8List.fromList([0x92, ..._wideWire, ...header, 0]),
          ),
          nativeIntegers ? throwsRangeError : throwsFormatException,
        );
      }
    });

    test('keeps exact signed and unsigned 64-bit boundary wire values', () {
      for (final (value, wire) in <(int, List<int>)>[
        (_wide, _wideWire),
        (_wide + 1, [0xcf, 0, 0, 0, 1, 0, 0, 0, 1]),
        (0x20000000000000, [0xcf, 0, 0x20, 0, 0, 0, 0, 0, 0]),
        (-0x80000001, [0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]),
        (-_wide, [0xd3, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0]),
        (-_wide - 1, [0xd3, 0xff, 0xff, 0xff, 0xfe, 0xff, 0xff, 0xff, 0xff]),
        (-0x20000000000000, [0xd3, 0xff, 0xe0, 0, 0, 0, 0, 0, 0]),
      ]) {
        expect(codec.serialize(value), orderedEquals(wire), reason: '$value');
        expect(codec.deserialize(Uint8List.fromList(wire)), value);
        expect(
          codec.deserialize(Uint8List.fromList([0x91, ...wire])),
          equals([value]),
        );
      }
    });

    test(
      'honors platform integer precision rather than rounding wire values',
      () {
        for (final (decimal, wire) in <(String, List<int>)>[
          ('9007199254740993', [0xcf, 0, 0x20, 0, 0, 0, 0, 0, 1]),
          ('9007199254740994', [0xd3, 0, 0x20, 0, 0, 0, 0, 0, 2]),
          (
            '-9007199254740993',
            [0xd3, 0xff, 0xdf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
          ),
        ]) {
          final bytes = Uint8List.fromList(wire);
          if (nativeIntegers) {
            expect(codec.deserialize(bytes), int.parse(decimal));
          } else {
            expect(() => codec.deserialize(bytes), throwsFormatException);
          }
        }
        for (final value in [0x20000000000002, -0x20000000000002]) {
          if (nativeIntegers) {
            expect(codec.deserialize(codec.serialize(value)), value);
          } else {
            expect(() => codec.serialize(value), throwsFormatException);
          }
        }
      },
    );

    for (final length in [15, 16, 65535, 65536]) {
      test('encodes array/map header transitions at $length entries', () {
        final values = List<Object?>.filled(length, 7)..[0] = _wide;
        final array = codec.serialize(values);
        final map = {for (var i = 0; i < length; i++) i: i == 0 ? _wide : 7};
        final dictionary = codec.serialize(map);
        final arrayHeader = length <= 15
            ? [0x90 | length]
            : length <= 65535
            ? [0xdc, length >> 8, length & 0xff]
            : [0xdd, 0, 1, 0, 0];
        final mapHeader = [...arrayHeader]
          ..[0] = length <= 15
              ? 0x80 | length
              : length <= 65535
              ? 0xde
              : 0xdf;
        expect(array.take(arrayHeader.length), orderedEquals(arrayHeader));
        expect(dictionary.take(mapHeader.length), orderedEquals(mapHeader));
        expect(codec.deserialize(array), equals(values));
        expect(codec.deserialize(dictionary), equals(map));
      });
    }

    test('encodes a non-list iterable containing a wide integer', () {
      final values = [_wide, 7].map((value) => value);
      expect(codec.serialize(values), orderedEquals([0x92, ..._wideWire, 7]));
      expect(codec.deserialize(codec.serialize(values)), equals([_wide, 7]));
    });
  });
}
