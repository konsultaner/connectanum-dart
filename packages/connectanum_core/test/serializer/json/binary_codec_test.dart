import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/json/binary_codec.dart';
import 'package:test/test.dart';

T _success<T>(T Function() operation) {
  late T value;
  expect(() => value = operation(), returnsNormally);
  return value;
}

Uint8List _encode(Uint8List bytes) => _success(() => encodeBase64Bytes(bytes));

Uint8List _decode(String text, int start) =>
    _success(() => decodeBase64Bytes(text, start));

Uint8List? _canonical(Uint8List bytes, int start, int end) =>
    _success(() => tryDecodeCanonicalBase64Bytes(bytes, start, end));

void main() {
  test('binary JSON base64 fast path matches the SDK across boundaries', () {
    for (var length = 0; length <= 1025; length++) {
      final bytes = Uint8List.fromList(
        List<int>.generate(length, (index) => (index * 31) & 0xff),
      );
      final encoded = _encode(bytes);
      expect(ascii.decode(encoded), base64.encode(bytes));

      final wrapped = 'prefix:${ascii.decode(encoded)}';
      expect(
        _decode(wrapped, 'prefix:'.length),
        orderedEquals(bytes),
      );
    }
  });

  test('binary JSON base64 decoder preserves compatible SDK fallbacks', () {
    final bytes = Uint8List.fromList(const [251, 255, 239]);
    final urlSafe = 'prefix:${base64Url.encode(bytes)}';
    expect(
      _decode(urlSafe, 'prefix:'.length),
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
        _canonical(wrapped, 2, 2 + encoded.length),
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
        _canonical(input, 0, input.length),
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
            _canonical(input, 0, input.length),
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
      expect(_decode(encoded, 0), orderedEquals(bytes));
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
          expect(_decode(encoded, 0), orderedEquals(expected));
          expect(
            _canonical(input, 0, input.length),
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

  test('mixed alphabet tails preserve independently specified octets', () {
    for (final (encoded, expected) in [
      ('00A0', [211, 64, 52]),
      ('00a0', [211, 70, 180]),
      ('aB3+', [104, 29, 254]),
    ]) {
      final wire = Uint8List.fromList(ascii.encode(encoded));
      expect(_decode(encoded, 0), orderedEquals(expected));
      expect(_canonical(wire, 0, wire.length), orderedEquals(expected));
      expect(_encode(Uint8List.fromList(expected)), orderedEquals(wire));
    }
  });

  test('alphabet classes mix in both initial and final quartets', () {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    // All-A context can mask a broken tail by triggering SDK fallback earlier.
    for (final context in ['A', 'a', '0', '+', '/']) {
      for (final character in alphabet.split('')) {
        for (var position = 0; position < 8; position++) {
          final encoded = (context * 8).replaceRange(
            position,
            position + 1,
            character,
          );
          final expected = base64.decode(encoded);
          final wire = Uint8List.fromList([255, ...ascii.encode(encoded), 255]);
          expect(
            _decode('!$encoded', 1),
            orderedEquals(expected),
            reason: '$encoded, position $position',
          );
          expect(
            _canonical(wire, 1, wire.length - 1),
            orderedEquals(expected),
            reason: '$encoded, position $position',
          );
        }
      }
    }
  });

  test('invalid character boundaries cannot become valid sextets', () {
    const acceptedCharacters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_=';
    for (final codeUnit in [
      ...List.generate(256, (index) => index),
      0x100,
      0xd800,
      0xdfff,
      0xffff,
    ]) {
      final invalid = String.fromCharCode(codeUnit);
      if (acceptedCharacters.contains(invalid)) continue;
      for (final context in ['A', 'a', '0', '+', '/']) {
        for (var position = 0; position < 8; position++) {
          final encoded = (context * 8).replaceRange(
            position,
            position + 1,
            invalid,
          );
          final reason = 'code unit $codeUnit in $context at $position';
          expect(
            () => base64.decode(encoded),
            throwsFormatException,
            reason: reason,
          );
          expect(
            () => decodeBase64Bytes('!$encoded', 1),
            throwsFormatException,
            reason: reason,
          );
          if (codeUnit <= 255) {
            final wire = Uint8List.fromList([255, ...encoded.codeUnits, 255]);
            expect(
              _canonical(wire, 1, wire.length - 1),
              isNull,
              reason: reason,
            );
          }
        }
      }
    }
  });

  test('padding bits are validated across every alphabet class', () {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (final context in ['A', 'a', '0', '+', '/']) {
      for (var index = 0; index < alphabet.length; index++) {
        for (final (tail, valid) in [
          ('$context${alphabet[index]}==', index % 16 == 0),
          ('$context$context${alphabet[index]}=', index % 4 == 0),
        ]) {
          for (final prefix in ['', '0a+/']) {
            final encoded = '$prefix$tail';
            final wire = Uint8List.fromList(ascii.encode(encoded));
            if (valid) {
              final expected = base64.decode(encoded);
              expect(
                _decode(encoded, 0),
                orderedEquals(expected),
                reason: encoded,
              );
              expect(
                _canonical(wire, 0, wire.length),
                orderedEquals(expected),
                reason: encoded,
              );
            } else {
              expect(
                () => base64.decode(encoded),
                throwsFormatException,
                reason: encoded,
              );
              expect(
                () => decodeBase64Bytes(encoded, 0),
                throwsFormatException,
                reason: encoded,
              );
              expect(_canonical(wire, 0, wire.length), isNull, reason: encoded);
            }
          }
        }
      }
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
          _decode(encoded, start),
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
          _decode(encoded, prefix.length),
          orderedEquals(expected),
          reason: encoded,
        );
      }
    }
  });

  test('RFC 4648 vectors preserve exact wire bytes in both decoders', () {
    for (final (plain, encoded) in [
      ('', ''),
      ('f', 'Zg=='),
      ('fo', 'Zm8='),
      ('foo', 'Zm9v'),
      ('foob', 'Zm9vYg=='),
      ('fooba', 'Zm9vYmE='),
      ('foobar', 'Zm9vYmFy'),
    ]) {
      final bytes = Uint8List.fromList(ascii.encode(plain));
      final wire = Uint8List.fromList(ascii.encode(encoded));
      expect(_encode(bytes), orderedEquals(wire));
      expect(_decode(encoded, 0), orderedEquals(bytes));
      expect(_canonical(wire, 0, wire.length), orderedEquals(bytes));
    }
  });

  test('byte subranges neither read guard bytes nor alias decoded output', () {
    for (final encoded in ['', 'Zg==', 'Zm8=', 'Zm9v', 'Zm9vYmFy']) {
      final wire = ascii.encode(encoded);
      final backing = Uint8List.fromList([0xff, ...wire, 0xff]);
      final original = Uint8List.fromList(backing);
      final decoded = _canonical(backing, 1, backing.length - 1);
      expect(decoded, isNotNull);
      final expected = ascii.encode(switch (encoded) {
        '' => '',
        'Zg==' => 'f',
        'Zm8=' => 'fo',
        'Zm9v' => 'foo',
        _ => 'foobar',
      });
      expect(decoded, orderedEquals(expected));
      expect(backing, orderedEquals(original));
      backing.fillRange(0, backing.length, 0);
      expect(decoded, orderedEquals(expected));
      if (decoded!.isNotEmpty) {
        decoded[0] = 255;
        expect(backing, everyElement(0));
      }
    }
  });

  test('encoder accepts byte views without including or modifying guards', () {
    final backing = Uint8List.fromList([0xff, 102, 111, 111, 0xff]);
    final encoded = _encode(Uint8List.sublistView(backing, 1, 4));
    expect(encoded, orderedEquals([90, 109, 57, 118]));
    expect(backing, orderedEquals([0xff, 102, 111, 111, 0xff]));
    backing.fillRange(0, backing.length, 0);
    expect(encoded, orderedEquals([90, 109, 57, 118]));
  });

  test(
    'canonical decoder rejects reversed ranges and accepts empty end view',
    () {
      final input = Uint8List.fromList([33, 33, 33]);
      expect(
        () => tryDecodeCanonicalBase64Bytes(input, 2, 1),
        throwsRangeError,
      );
      expect(
        () => tryDecodeCanonicalBase64Bytes(input, 4, 4),
        throwsRangeError,
      );
      expect(_canonical(input, 3, 3), isEmpty);
      expect(_canonical(input, 1, 1), isEmpty);
    },
  );
}
