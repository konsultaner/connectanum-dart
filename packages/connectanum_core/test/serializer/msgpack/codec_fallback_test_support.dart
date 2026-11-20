import 'dart:collection';
import 'dart:typed_data';
import 'dart:math';

import 'package:msgpack_dart/msgpack_dart.dart' as delegate;
import 'package:test/test.dart';

import 'codec_test_support.dart' as support;

const _wide = [0xcf, 0, 0, 0, 1, 0, 0, 0, 0];

void registerFallbackTests(
  support.CheckedCodec checked, {
  bool delegatedRootErrors = false,
}) {
  test('portable integer words match an exact BigInt reference', () {
    final random = Random(143);
    final limit = BigInt.one << 53;
    final highs = [
      0,
      1,
      0xffffffff,
      for (final boundary in [0x200000, 0x80000000, 0xffe00000])
        for (var delta = -3; delta <= 3; delta++) boundary + delta,
      for (var index = 0; index < 256; index++) random.nextInt(0x100000000),
    ];
    for (final signed in [false, true]) {
      for (final high in highs) {
        for (final low in [
          0,
          1,
          0x7fffffff,
          0x80000000,
          0xfffffffe,
          0xffffffff,
        ]) {
          var exact = (BigInt.from(high) << 32) + BigInt.from(low);
          if (signed && high >= 0x80000000) exact -= BigInt.one << 64;
          final bytes = Uint8List(9)..[0] = signed ? 0xd3 : 0xcf;
          ByteData.sublistView(bytes)
            ..setUint32(1, high)
            ..setUint32(5, low);
          if (exact >= -limit && exact <= limit) {
            expect(checked.deserialize(bytes), exact.toInt());
          } else {
            expect(() => checked.decode(bytes), throwsFormatException);
          }
        }
      }
    }
  });

  test('nested containers keep the portable encoding integer limit', () {
    for (final value in [0x20000000000002, -0x20000000000002]) {
      for (final message in <Object?>[
        [value],
        {'value': value},
        {value: 'key'},
        [1, value].map((item) => item),
      ]) {
        expect(() => checked.encode(message), throwsFormatException);
      }
    }
  });

  test('encodes a streaming iterable in one traversal', () {
    final values = _SingleUseIterable([0x100000000, true, 'stream']);
    final bytes = checked.serialize(values);
    expect(checked.deserialize(bytes), [0x100000000, true, 'stream']);
  });

  test('iterable encoding preserves values observed during one traversal', () {
    final values = _ConversionObservedIterable();
    final wire = checked.serialize(values);
    final expected = [
      {'mode': null},
    ];
    expect(wire, orderedEquals(delegate.serialize(expected)));
    expect(checked.deserialize(wire), expected);
    expect(values.traversals, 1);
    expect(values.conversionMode, isNull);
  });

  test('visits a List lazily while encoding nested iterables', () {
    late List<Object?> values;
    final nested = _OnTraversalIterable(() => values[1] = 'updated');
    values = [nested, 'before'];

    final wire = checked.serialize(values);

    final expected = [
      ['nested'],
      'updated',
    ];
    expect(wire, orderedEquals(delegate.serialize(expected)));
    expect(checked.deserialize(wire), expected);
    expect(nested.traversals, 1);
  });

  test(
    'preserves delegated scalar and binary values on the fallback boundary',
    () {
      final byteData = ByteData(2)..setUint16(0, 0x1234);

      expect(
        checked.serialize(7),
        orderedEquals(delegate.serialize(7)),
      );
      expect(
        checked.serialize(byteData),
        orderedEquals(delegate.serialize(byteData)),
      );
      expect(
        checked.serialize('plain'),
        orderedEquals(delegate.serialize('plain')),
      );
    },
  );

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
        expect(checked.deserialize(wire), value);
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
          [0x80, 0, 0, 0, 0, 0, 0, 0],
        ]) {
          expect(
            () => checked.decode(Uint8List.fromList([marker, ...octets])),
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
        checked.deserialize(Uint8List.fromList([0x92, ..._wide, ...wire])),
        equals([0x100000000, expected]),
      );
    }
  });

  test('reports collection admission errors before recursive decoding', () {
    for (final header in [
      [0x92],
      [0x81],
      [0xdc, 0, 2],
      [0xde, 0, 1],
      [0xdc, 0, 64],
      [0xde, 0, 64],
    ]) {
      expect(
        () => checked.decode(
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

  test('truncated uint64 and int64 values retain the fallback error', () {
    for (final marker in [0xcf, 0xd3]) {
      for (var size = 1; size < 9; size++) {
        final truncated = [marker, ...List<int>.filled(size - 1, 0)];
        for (final wire in [
          truncated,
          [0x92, ..._wide, ...truncated],
        ]) {
          expect(
            () => checked.decode(Uint8List.fromList(wire)),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                'Truncated MessagePack integer',
              ),
            ),
            reason: 'marker=$marker size=$size wire=$wire',
          );
        }
      }
    }
  });

  test('rejects uint32-sized scalar lengths without reading beyond a view', () {
    for (final marker in [0xdb, 0xc6, 0xc9]) {
      final frame = [
        0x92,
        ..._wide,
        marker,
        0xff,
        0xff,
        0xff,
        0xff,
        if (marker == 0xc9) 42,
      ];
      final padded = Uint8List.fromList([0, ...frame, 0, 0]);
      expect(
        () => checked.decode(
          Uint8List.sublistView(padded, 1, padded.length - 2),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Truncated MessagePack value',
          ),
        ),
      );
    }
  });

  test('preserves root errors for the selected backend', () {
    expect(
      () => checked.decode(Uint8List(0)),
      delegatedRootErrors ? throwsRangeError : throwsFormatException,
    );
    expect(
      () => checked.decode(Uint8List.fromList([0xc1])),
      delegatedRootErrors
          ? throwsA(isA<delegate.FormatError>())
          : throwsFormatException,
    );
  });

  test('rejects trailing bytes after directly decoded 64-bit values', () {
    for (final marker in [0xcf, 0xd3]) {
      final wire = [..._wide]..[0] = marker;
      expect(checked.deserialize(Uint8List.fromList(wire)), 0x100000000);
      expect(
        () => checked.decode(Uint8List.fromList([...wire, 0xc0])),
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
        checked.deserialize(Uint8List.fromList(wire)),
        equals([0x100000000]),
      );
      expect(
        () => checked.decode(Uint8List.fromList([...wire, 0xc0])),
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

class _SingleUseIterable extends Iterable<Object?> {
  _SingleUseIterable(this.values);

  final List<Object?> values;
  bool _read = false;

  @override
  Iterator<Object?> get iterator {
    if (_read) throw StateError('Streaming iterable consumed twice');
    _read = true;
    return values.iterator;
  }
}

class _OnTraversalIterable extends Iterable<Object?> {
  _OnTraversalIterable(this.onTraversal);

  final void Function() onTraversal;
  int traversals = 0;

  @override
  Iterator<Object?> get iterator {
    traversals++;
    onTraversal();
    return ['nested'].iterator;
  }
}

// A valid conversion override can observe its options without changing the
// returned elements or their order. Its nested map exposes that public state.
class _ConversionObservedIterable extends IterableBase<Object?> {
  bool? conversionMode;
  int traversals = 0;

  @override
  Iterator<Object?> get iterator {
    traversals++;
    return [_ConversionObservedMap(this)].iterator;
  }

  @override
  List<Object?> toList({bool growable = true}) {
    conversionMode = growable;
    return super.toList(growable: growable);
  }
}

class _ConversionObservedMap extends MapBase<String, Object?> {
  _ConversionObservedMap(this.owner);

  final _ConversionObservedIterable owner;

  @override
  Iterable<String> get keys => const ['mode'];

  @override
  Object? operator [](Object? key) =>
      key == 'mode' ? owner.conversionMode : null;

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}
