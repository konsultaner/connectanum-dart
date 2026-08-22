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
}
