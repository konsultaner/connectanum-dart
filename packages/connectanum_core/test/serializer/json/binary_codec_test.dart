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
}
