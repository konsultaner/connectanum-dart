import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart'
    show LazyPayloadEncoding;
import 'package:connectanum_core/src/message/binary_ppt_payload_view.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  for (final encoding in [
    LazyPayloadEncoding.cbor,
    LazyPayloadEncoding.messagePack,
  ]) {
    for (final size in [0, 1, 23, 24, 255, 256, 65535, 65536, 100001]) {
      test('$encoding retains $size byte singleton and its exact subview', () {
        final payload = Uint8List.fromList(
          List.generate(size, (i) => (i * 31) & 255),
        );
        final encoded = encoding == LazyPayloadEncoding.cbor
            ? cbor.cbor.encode(cbor.CborValue([payload]))
            : msgpack.serialize([payload]);
        final storage = Uint8List(encoded.length + 11)
          ..fillRange(0, encoded.length + 11, 0xa5);
        storage.setRange(7, 7 + encoded.length, encoded);
        final input = Uint8List.sublistView(
          storage,
          7,
          7 + encoded.length,
        ).asUnmodifiableView();
        final view = binaryPptArgumentView(encoding, input)!;
        expect(view, orderedEquals(payload));
        expect(view.buffer.lengthInBytes, input.buffer.lengthInBytes);
        expect(view.offsetInBytes, input.offsetInBytes + encoded.length - size);
        expect(view.length, size);
        if (size > 0) {
          expect(() => view[0] = 17, throwsUnsupportedError);
          storage[view.offsetInBytes] ^= 0xff;
          expect(
            view[0],
            payload[0] ^ 0xff,
            reason: 'contents retain the input allocation',
          );
        }
        expect(storage.take(7), everyElement(0xa5));
        expect(storage.skip(7 + encoded.length), everyElement(0xa5));
      });
    }
  }

  test('CBOR wider binary lengths retain a bounded view', () {
    for (final width in [1, 2, 4, 8]) {
      final header = Uint8List(2 + width + 3)..[0] = 0x81;
      header[1] = {1: 0x58, 2: 0x59, 4: 0x5a, 8: 0x5b}[width]!;
      header[1 + width] = 3;
      header.setRange(2 + width, header.length, [7, 8, 9]);
      expect(binaryPptArgumentView(LazyPayloadEncoding.cbor, header), [
        7,
        8,
        9,
      ]);
    }
  });

  test(
    'other shapes, indefinite containers, truncation and trailing bytes decline',
    () {
      final cases = <LazyPayloadEncoding, List<List<int>>>{
        LazyPayloadEncoding.cbor: [
          [],
          [0x80],
          [0x82, 0x40, 0x40],
          [0x81, 0x61, 0x61],
          [0x9f, 0x40, 0xff],
          [0x81, 0x5f, 0xff],
          [0x81, 0x41],
          [0x81, 0x40, 0],
          [0x81, 0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
        ],
        LazyPayloadEncoding.messagePack: [
          [],
          [0x90],
          [0x92, 0xc4, 0, 0xc4, 0],
          [0x91, 0xa1, 0x61],
          [0x91, 0xc4],
          [0x91, 0xc4, 1],
          [0x91, 0xc4, 0, 0],
          [0x91, 0xc6, 0xff, 0xff, 0xff, 0xff],
        ],
      };
      for (final entry in cases.entries) {
        for (final value in entry.value) {
          expect(
            binaryPptArgumentView(entry.key, Uint8List.fromList(value)),
            isNull,
            reason: '$value',
          );
        }
      }
      for (final encoding in [
        LazyPayloadEncoding.json,
        LazyPayloadEncoding.flatbuffers,
      ]) {
        expect(
          binaryPptArgumentView(encoding, Uint8List.fromList([0x81, 0x40])),
          isNull,
        );
      }
      for (final bytes in [
        [0x81, 0x58, 0],
        [0x81, 0x59, 0, 0],
        [0x81, 0x5a, 0, 0, 0, 0],
        [0x81, 0x5b, 0, 0, 0, 0, 0, 0, 0, 0],
        [0x91, 0xc5, 0, 0],
        [0x91, 0xc6, 0, 0, 0, 0],
      ]) {
        for (var length = 0; length < bytes.length; length++) {
          expect(
            binaryPptArgumentView(
              bytes[0] == 0x81
                  ? LazyPayloadEncoding.cbor
                  : LazyPayloadEncoding.messagePack,
              Uint8List.fromList(bytes.sublist(0, length)),
            ),
            isNull,
          );
        }
      }
    },
  );
}
