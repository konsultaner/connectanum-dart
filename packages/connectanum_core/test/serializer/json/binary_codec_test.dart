import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/json/binary_codec.dart';
import 'package:test/test.dart';

void main() {
  test('binary JSON base64 fast path matches the SDK across boundaries', () {
    for (var length = 0; length <= 1025; length++) {
      final bytes = Uint8List.fromList(
        List<int>.generate(length, (index) => (index * 31) & 0xff),
      );
      final encoded = encodeBase64Bytes(bytes);
      expect(ascii.decode(encoded), base64.encode(bytes));

      final wrapped = 'prefix:${ascii.decode(encoded)}';
      expect(
        decodeBase64Bytes(wrapped, 'prefix:'.length),
        orderedEquals(bytes),
      );
    }
  });

  test('binary JSON base64 decoder preserves compatible SDK fallbacks', () {
    final bytes = Uint8List.fromList(const [251, 255, 239]);
    final urlSafe = 'prefix:${base64Url.encode(bytes)}';
    expect(
      decodeBase64Bytes(urlSafe, 'prefix:'.length),
      orderedEquals(bytes),
    );
    expect(
      () => decodeBase64Bytes('prefix:not base64', 'prefix:'.length),
      throwsFormatException,
    );
  });

  test('canonical byte decoder supports boundaries and byte subranges', () {
    for (final length in const [0, 1, 2, 3, 4, 4095, 4096, 4097]) {
      final bytes = Uint8List.fromList(
        List<int>.generate(length, (index) => (index * 43 + 7) & 0xff),
      );
      final encoded = ascii.encode(base64.encode(bytes));
      final wrapped = Uint8List.fromList([1, 2, ...encoded, 3, 4]);

      expect(
        tryDecodeCanonicalBase64Bytes(wrapped, 2, 2 + encoded.length),
        orderedEquals(bytes),
      );
    }
  });

  test('canonical byte decoder rejects noncanonical input for fallback', () {
    Uint8List bytes(String value) => Uint8List.fromList(ascii.encode(value));

    for (final value in const [
      'A',
      'AA=A',
      'AA-A',
      'AA_A',
      'AAA===',
      'AB==',
      'AAB=',
      '!!!!',
    ]) {
      final input = bytes(value);
      expect(
        tryDecodeCanonicalBase64Bytes(input, 0, input.length),
        isNull,
        reason: value,
      );
    }
  });

  test('canonical byte decoder validates its byte range', () {
    final input = Uint8List.fromList(ascii.encode('AAAA'));
    expect(
      () => tryDecodeCanonicalBase64Bytes(input, -1, input.length),
      throwsRangeError,
    );
    expect(
      () => tryDecodeCanonicalBase64Bytes(input, 0, input.length + 1),
      throwsRangeError,
    );
  });

  test(
    'canonical decoder rejects an invalid byte in every quartet position',
    () {
      for (final invalid in [0, 1, 32, 33, 45, 95, 127, 128, 255]) {
        for (var position = 0; position < 8; position++) {
          final input = Uint8List.fromList(ascii.encode('AAAAAAAA'));
          input[position] = invalid;
          expect(
            tryDecodeCanonicalBase64Bytes(input, 0, input.length),
            isNull,
            reason: 'invalid $invalid at position $position',
          );
        }
      }
    },
  );

  test(
    'text decoder rejects invalid characters before and inside final quartet',
    () {
      for (final invalid in ['!', '\u0100']) {
        for (var position = 0; position < 8; position++) {
          final input = 'AAAAAAAA'.replaceRange(
            position,
            position + 1,
            invalid,
          );
          expect(
            () => decodeBase64Bytes(input, 0),
            throwsFormatException,
            reason: 'invalid at position $position',
          );
        }
      }
    },
  );

  test('URL-safe text fallback preserves multiple quartets and padding', () {
    for (final length in [1, 2, 3, 4, 5, 6, 7, 2048]) {
      final bytes = Uint8List.fromList(
        List.generate(length, (i) => (i * 31 + 251) & 255),
      );
      final encoded = base64Url.encode(bytes);
      expect(decodeBase64Bytes(encoded, 0), orderedEquals(bytes));
    }
  });

  test(
    'every canonical alphabet character decodes at each quartet position',
    () {
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      for (final character in alphabet.split('')) {
        for (var position = 0; position < 4; position++) {
          final encoded = 'AAAA'.replaceRange(
            position,
            position + 1,
            character,
          );
          final expected = base64.decode(encoded);
          final input = Uint8List.fromList(ascii.encode(encoded));
          expect(decodeBase64Bytes(encoded, 0), orderedEquals(expected));
          expect(
            tryDecodeCanonicalBase64Bytes(input, 0, input.length),
            orderedEquals(expected),
            reason: '$character in position $position',
          );
        }
      }
    },
  );

  test('text decoder rejects nonzero padding bits rather than truncating', () {
    for (final encoded in [
      'AB==',
      'AAB=',
      'AA=A',
      'AAA===',
      'AAAAAB==',
      'AAAAAAB=',
    ]) {
      expect(
        () => decodeBase64Bytes(encoded, 0),
        throwsFormatException,
        reason: encoded,
      );
    }
  });

  test('text subranges work with every prefix alignment', () {
    for (var start = 0; start < 9; start++) {
      for (final length in [0, 1, 2, 3, 4, 17]) {
        final input = Uint8List.fromList(
          List.generate(length, (index) => index * 13),
        );
        final encoded = '${'!' * start}${base64.encode(input)}';
        expect(
          decodeBase64Bytes(encoded, start),
          orderedEquals(input),
          reason: '$start / $length',
        );
      }
    }
  });

  test('short text and escaped padding match SDK acceptance and rejection', () {
    const samples = [
      '',
      'A',
      'AA',
      'AAA',
      'AAAA',
      'AAAAA',
      '=',
      '==',
      '===',
      '====',
      'A=',
      'AA=',
      'AAA=',
      'A==',
      'AA==',
      'A===',
      'AA===',
      '%41A==',
      'AA%3D%3D',
      'AA%3d%3d',
      'AA%',
      'AA%GG',
      '-w',
      '_w',
    ];
    for (final prefix in ['', '!', 'prefix:']) {
      for (final sample in samples) {
        final encoded = '$prefix$sample';
        Uint8List expected;
        try {
          expected = base64.decoder.convert(encoded, prefix.length);
        } on FormatException {
          expect(
            () => decodeBase64Bytes(encoded, prefix.length),
            throwsFormatException,
            reason: encoded,
          );
          continue;
        }
        expect(
          decodeBase64Bytes(encoded, prefix.length),
          orderedEquals(expected),
          reason: encoded,
        );
      }
    }
  });
}
