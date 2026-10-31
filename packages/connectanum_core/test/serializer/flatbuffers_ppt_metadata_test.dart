import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/ppt_metadata.dart';
import 'package:test/test.dart';

void main() {
  Uint8List encode(Object? value) => encodeWampFlatBufferCbor(value);

  test('matches both field orders and ASCII text header boundaries', () {
    for (final length in [0, 1, 23, 24, 255, 256, 65535]) {
      final scheme = 'x' * length;
      for (final reverse in [false, true]) {
        final bytes = encode({
          if (reverse) 'ppt_serializer': 'flatbuffers',
          'ppt_scheme': scheme,
          if (!reverse) 'ppt_serializer': 'flatbuffers',
        });
        expect(
          matchesFlatBufferPptMetadata(bytes, scheme, 'flatbuffers'),
          isTrue,
        );
      }
    }
  });

  test('rejects incomplete, additional, contradictory and non-text fields', () {
    for (final value in [
      null,
      [],
      {},
      {'ppt_scheme': 'x'},
      {'ppt_serializer': 'flatbuffers'},
      {'ppt_scheme': 'different', 'ppt_serializer': 'flatbuffers'},
      {'ppt_scheme': 'x', 'ppt_serializer': 'cbor'},
      {'ppt_scheme': 'x', 'other': 'flatbuffers'},
      {'ppt_scheme': 'x', 'ppt_serializer': null},
      {'ppt_scheme': null, 'ppt_serializer': 'flatbuffers'},
      {'ppt_scheme': 'x', 'ppt_serializer': 'flatbuffers', 'progress': false},
      {'ppt_scheme': 'x', 'ppt_serializer': 'flatbuffers', 'extension': 7},
    ]) {
      expect(
        matchesFlatBufferPptMetadata(encode(value), 'x', 'flatbuffers'),
        isFalse,
      );
    }
    final good = encode({'ppt_scheme': 'x', 'ppt_serializer': 'flatbuffers'});
    expect(matchesFlatBufferPptMetadata(good, null, 'flatbuffers'), isFalse);
    expect(matchesFlatBufferPptMetadata(good, 'x', null), isFalse);
    expect(
      matchesFlatBufferPptMetadata(Uint8List(1048577), 'x', 'flatbuffers'),
      isFalse,
    );
    expect(
      matchesFlatBufferPptMetadata(
        encode({'ppt_scheme': 'ü', 'ppt_serializer': 'flatbuffers'}),
        'ü',
        'flatbuffers',
      ),
      isFalse,
    );
    expect(
      matchesFlatBufferPptMetadata(
        encode({'ppt_scheme': 'x' * 65536, 'ppt_serializer': 'flatbuffers'}),
        'x' * 65536,
        'flatbuffers',
      ),
      isFalse,
    );
  });

  test(
    'rejects every truncated byte, duplicate keys, tags and trailing bytes',
    () {
      final bytes = encode({
        'ppt_scheme': 'x',
        'ppt_serializer': 'flatbuffers',
      });
      for (var end = 0; end < bytes.length; end++) {
        expect(
          matchesFlatBufferPptMetadata(
            Uint8List.sublistView(bytes, 0, end),
            'x',
            'flatbuffers',
          ),
          isFalse,
          reason: 'end=$end',
        );
      }
      for (final incomplete in [
        [0xa2, 0x78],
        [0xa2, 0x79],
        [0xa2, 0x79, 0],
      ]) {
        expect(
          matchesFlatBufferPptMetadata(
            Uint8List.fromList(incomplete),
            'x',
            'flatbuffers',
          ),
          isFalse,
        );
      }
      expect(matchesFlatBufferPptMetadata(bytes, 'ü', 'flatbuffers'), isFalse);
      final one = encode({'ppt_scheme': 'x'});
      expect(
        matchesFlatBufferPptMetadata(
          Uint8List.fromList([0xa2, ...one.skip(1), ...one.skip(1)]),
          'x',
          'flatbuffers',
        ),
        isFalse,
      );
      expect(
        matchesFlatBufferPptMetadata(
          Uint8List.fromList([0xc0, ...bytes]),
          'x',
          'flatbuffers',
        ),
        isFalse,
      );
      expect(
        matchesFlatBufferPptMetadata(
          Uint8List.fromList([...bytes, 0]),
          'x',
          'flatbuffers',
        ),
        isFalse,
      );
    },
  );
}
