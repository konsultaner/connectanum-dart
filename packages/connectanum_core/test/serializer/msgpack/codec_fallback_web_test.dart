@TestOn('js')
library;

import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/msgpack/codec.dart' as codec;
import 'package:msgpack_dart/msgpack_dart.dart' as delegate;
import 'package:test/test.dart';

const _wide = [0xcf, 0, 0, 0, 1, 0, 0, 0, 0];

void main() {
  test(
    'decodes small and boundary values in legal nonminimal integer encodings',
    () {
      for (final (value, marker, octets) in <(int, int, List<int>)>[
        (0, 0xcf, [0, 0, 0, 0, 0, 0, 0, 0]),
        (1, 0xd3, [0, 0, 0, 0, 0, 0, 0, 1]),
        (-1, 0xd3, [255, 255, 255, 255, 255, 255, 255, 255]),
        (0x20000000000000, 0xd3, [0, 0x20, 0, 0, 0, 0, 0, 0]),
        (-0x1fffffffffffff, 0xd3, [255, 0xe0, 0, 0, 0, 0, 0, 1]),
      ]) {
        final wire = Uint8List.fromList([marker, ...octets]);
        expect(codec.deserialize(wire), value);
      }
    },
  );

  test(
    'rejects positive signed and unsigned integers just outside the exact range',
    () {
      for (final marker in [0xcf, 0xd3]) {
        for (final octets in [
          [0, 0x20, 0, 0, 0, 0, 0, 1],
          [0, 0x20, 0, 1, 0, 0, 0, 0],
          [0x7f, 255, 255, 255, 255, 255, 255, 255],
        ]) {
          expect(
            () => codec.deserialize(Uint8List.fromList([marker, ...octets])),
            throwsFormatException,
          );
        }
      }
    },
  );

  test('accepts exact-length and empty nested collections', () {
    for (final (wire, expected) in <(List<int>, Object)>[
      ([0x90], <Object?>[]),
      ([0x80], <String, Object?>{}),
      ([0x92, 1, 2], [1, 2]),
      ([0x81, 1, 2], {1: 2}),
    ]) {
      expect(
        codec.deserialize(Uint8List.fromList([0x92, ..._wide, ...wire])),
        equals([0x100000000, expected]),
      );
    }
  });

  test('reports collection admission errors before recursive decoding', () {
    for (final header in [
      [0xdc, 0, 64],
      [0xde, 0, 64],
    ]) {
      expect(
        () => codec.deserialize(
          Uint8List.fromList([0x92, ..._wide, ...header, 0]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'MessagePack collection length exceeds available bytes',
          ),
        ),
      );
    }
  });

  test('preserves delegated root errors when no uint64 fallback is needed', () {
    expect(() => codec.deserialize(Uint8List(0)), throwsRangeError);
    expect(
      () => codec.deserialize(Uint8List.fromList([0xc1])),
      throwsA(isA<delegate.FormatError>()),
    );
  });

  test('rejects trailing bytes after directly decoded 64-bit values', () {
    for (final marker in [0xcf, 0xd3]) {
      final wire = [..._wide]..[0] = marker;
      expect(codec.deserialize(Uint8List.fromList(wire)), 0x100000000);
      expect(
        () => codec.deserialize(Uint8List.fromList([...wire, 0xc0])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Trailing data after MessagePack value',
          ),
        ),
      );
    }
  });

  test(
    'rejects trailing bytes after retrying a collection in the fallback',
    () {
      final wire = [0x91, ..._wide];
      expect(
        codec.deserialize(Uint8List.fromList(wire)),
        equals([0x100000000]),
      );
      expect(
        () => codec.deserialize(Uint8List.fromList([...wire, 0xc0])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Trailing data after MessagePack value',
          ),
        ),
      );
    },
  );
}
