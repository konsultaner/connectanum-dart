import 'dart:typed_data';
import 'dart:math';
import 'package:test/test.dart';
import 'package:cbor/cbor.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_validation.dart';

void main() {
  test('scalar arrays preserve CBOR count headers and exact byte budgets', () {
    for (final count in [0, 1, 23, 24, 25, 31, 32, 47, 48]) {
      final value = List<int>.filled(count, 0);
      final expected = cbor.encode(CborValue(value));
      final actual = encodeWampFlatBufferCbor(
        value,
        maximumBytes: expected.length,
      );
      expect(actual, orderedEquals(expected), reason: 'count=$count');
      validateFlatBufferCbor(actual, rootMajor: 4);
      expect(
        () => encodeWampFlatBufferCbor(
          value,
          maximumBytes: expected.length - 1,
        ),
        throwsArgumentError,
        reason: 'count=$count',
      );
    }
  });

  test('ASCII scalar arrays preserve CBOR string header boundaries', () {
    for (final length in [0, 1, 23, 24, 255, 256]) {
      final value = ['a' * length];
      expect(
        encodeWampFlatBufferCbor(value),
        orderedEquals(cbor.encode(CborValue(value))),
      );
    }
  });

  test('Unicode scalar arrays fall back after partial fast-path output', () {
    for (final value in <List<String>>[
      ['ascii', 'é'],
      ['ascii', '🧪'],
      ['e\u0301'],
    ]) {
      expect(
        encodeWampFlatBufferCbor(value),
        orderedEquals(cbor.encode(CborValue(value))),
      );
    }
  });

  Uint8List encode(Map<String, dynamic> value, {int maximumBytes = 1048576}) =>
      encodeWampFlatBufferCbor(
        value,
        maximumBytes: maximumBytes,
        stringDictionaryKeys: true,
      );
  void exact(Map<String, dynamic> value) {
    final expected = cbor.encode(CborValue(value));
    final actual = encode(value);
    expect(actual, orderedEquals(expected));
    validateFlatBufferCbor(
      actual,
      rootMajor: 5,
      stringDictionaryKeys: true,
      limits: const FlatBufferCborLimits(maxBytes: 1048576),
    );
    expect(decodeFlatBufferMetadata(actual), value);
  }

  test(
    'metadata scalar encoding preserves every CBOR width and ASCII byte',
    () {
      for (final value in <dynamic>[
        null,
        false,
        true,
        0,
        1,
        23,
        24,
        255,
        256,
        65535,
        65536,
        4294967295,
        -1,
        -24,
        -25,
        -256,
        -257,
        -65536,
        -65537,
        -4294967296,
        '',
        'abc',
        String.fromCharCodes(List.generate(128, (i) => i)),
      ]) {
        exact({'key': value});
      }
      for (final length in [0, 1, 23, 24, 255, 256, 65535, 65536]) {
        exact({'x': 'a' * length});
        exact({'a' * length: false});
      }
    },
  );
  test(
    'metadata scalar encoding preserves map boundaries and iteration order',
    () {
      for (final count in [0, 1, 22, 23, 24, 255, 256]) {
        exact({for (var i = count; i > 0; i--) 'k$i': i});
      }
      final random = Random(20261016);
      final values = <dynamic>[
        null,
        true,
        false,
        -4294967296,
        4294967295,
        'abc',
        '',
      ];
      for (var seed = 0; seed < 1000; seed++) {
        exact({
          for (var i = 0; i < random.nextInt(24); i++)
            'key$i': values[random.nextInt(values.length)],
        });
      }
    },
  );
  test('metadata scalar encoding keeps the inclusive output budget', () {
    for (final value in <Map<String, dynamic>>[
      {},
      {'ascii': 'text'},
      {'width': 4294967295},
      {'x': 'a' * (1048576 - 8)},
    ]) {
      final length = cbor.encode(CborValue(value)).length;
      expect(encode(value, maximumBytes: length).length, length);
      expect(
        () => encode(value, maximumBytes: length - 1),
        throwsArgumentError,
      );
    }
    expect(() => encode({}, maximumBytes: -1), throwsArgumentError);
    expect(() => encode({'long': null}, maximumBytes: 1), throwsArgumentError);
    expect(() => encode({'x': 'a' * 1048576}), throwsArgumentError);
  });
  test('metadata scalar encoding preserves complex and Unicode fallbacks', () {
    for (final value in <Map<String, dynamic>>[
      {'unicode': '\u{1f642}'},
      {'e\u0301': 'é'},
      {'wide': 4294967296},
      {'wide': -4294967297},
      {'decimal': 1.5},
      {
        'array': [1, 2],
      },
      {
        'binary': Uint8List.fromList([0, 255]),
      },
      {
        'map': {'x': 1},
      },
    ]) {
      exact(value);
    }
    final cycle = <String, dynamic>{};
    cycle['cycle'] = cycle;
    expect(() => encode(cycle), throwsArgumentError);
    expect(
      () => encodeWampFlatBufferCbor({1: false}, stringDictionaryKeys: true),
      throwsArgumentError,
    );
    expect(
      () => encodeWampFlatBufferCbor({
        Object(): false,
      }, stringDictionaryKeys: true),
      throwsArgumentError,
    );
  });
  test(
    'nonmetadata CBOR input keeps normal construction and coercion rules',
    () {
      for (final value in <dynamic>[
        {1: false},
        [1, 2],
        'text',
        null,
        123,
      ]) {
        expect(
          encodeWampFlatBufferCbor(value),
          orderedEquals(cbor.encode(CborValue(value))),
        );
        if (value is! Map) {
          expect(
            encodeWampFlatBufferCbor(value, stringDictionaryKeys: true),
            orderedEquals(cbor.encode(CborValue(value))),
          );
        }
      }
    },
  );
}
