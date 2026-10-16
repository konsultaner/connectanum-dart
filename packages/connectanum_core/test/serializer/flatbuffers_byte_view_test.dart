import 'dart:typed_data';

import 'package:connectanum_core/flatbuffers_serializer.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:test/test.dart';

void main() {
  const reader = FlatBufferUint8ListReader();
  for (final prefix in [0, 1, 7, 16]) {
    for (final length in [0, 1, 255, 65536]) {
      test('byte view retains offset=$prefix length=$length storage', () {
        final storage = Uint8List(prefix + 8 + length + 17);
        final bytes = Uint8List.sublistView(
          storage,
          prefix,
          prefix + 8 + length,
        );
        final data = ByteData.sublistView(bytes);
        data.setUint32(0, 4, Endian.little);
        data.setUint32(4, length, Endian.little);
        for (var i = 0; i < length; i++) {
          bytes[8 + i] = i & 255;
        }
        final context = flatBufferContext(bytes);
        final value = reader.read(context, 0);
        expect(context.buffer.lengthInBytes, bytes.length);
        expect(value, Uint8List.sublistView(bytes, 8));
        expect(value.offsetInBytes, prefix + 8);
        expect(() => value.add(4), throwsUnsupportedError);
        if (length > 0) {
          expect(() => value[0] = 42, throwsUnsupportedError);
          storage[prefix + 8] = 197;
          expect(
            value[0],
            197,
            reason: 'The reader must alias its input storage',
          );
        }
      });
    }
  }

  test('a larger allocation cannot extend the logical input range', () {
    final storage = Uint8List(100);
    final bytes = Uint8List.sublistView(storage, 11, 23);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 4, Endian.little);
    data.setUint32(
      4,
      5,
      Endian.little,
    ); // Only four payload bytes are in range.
    expect(
      () => reader.read(flatBufferContext(bytes), 0),
      throwsFormatException,
    );
  });
  for (final reference in [0, 1, 3, 5, 0xffffffff]) {
    test('invalid forward reference $reference is rejected', () {
      final data = ByteData(8)..setUint32(0, reference, Endian.little);
      expect(
        () => reader.read(fb.BufferContext(data), 0),
        throwsFormatException,
      );
    });
  }
  for (final offset in [-1, 1, 5, 8]) {
    test(
      'reference outside an exact four-byte input at $offset is rejected',
      () {
        expect(
          () => reader.read(fb.BufferContext(ByteData(4)), offset),
          throwsFormatException,
        );
      },
    );
  }
  test('a declared vector cannot exceed its input', () {
    final data = ByteData(8)
      ..setUint32(0, 4, Endian.little)
      ..setUint32(4, 0xffffffff, Endian.little);
    expect(() => reader.read(fb.BufferContext(data), 0), throwsFormatException);
  });
  test('ordinary byte lists stay compatible and have bounded storage', () {
    final context = flatBufferContext([4, 0, 0, 0, 1, 0, 0, 0, 99]);
    expect(reader.read(context, 0), [99]);
    expect(context.buffer.lengthInBytes, 9);
  });
}
