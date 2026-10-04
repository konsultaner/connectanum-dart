import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  for (final length in [0, 5]) {
    test(
      'opaque typed PPT explicit decoding preserves a $length-byte subview',
      () {
        final storage = Uint8List.fromList([99, 98, 1, 2, 3, 4, 5, 97]);
        final span = Uint8List.sublistView(storage, 2, 2 + length);
        final owner = Object();
        final wire = LazyMessagePayload.materialized(
          transparentBinaryPayload: span,
          anchor: owner,
        );
        final decoded = decodeLazyPayloadView(
          wire,
          pptScheme: 'x_app',
          pptSerializer: 'flatbuffers',
        );
        expect(decoded.arguments, hasLength(1));
        expect(decoded.arguments!.single, same(span));
        expect(decoded.argumentsKeywords, isNull);
        expect(wire.arguments, isNull);
        expect(wire.argumentsKeywords, isNull);
        expect(wire.transparentBinaryPayload, same(span));
        expect(wire.anchor, same(owner));
        expect(wire.pptDecoded, isFalse);
      },
    );

    test(
      'opaque typed PPT lazy unwrapping retains a $length-byte subview and owner',
      () {
        final storage = Uint8List.fromList([99, 98, 1, 2, 3, 4, 5, 97]);
        final span = Uint8List.sublistView(storage, 2, 2 + length);
        final owner = Object();
        final wire = LazyMessagePayload.materialized(
          transparentBinaryPayload: span,
          anchor: owner,
        );
        final application = unwrapLazyPayloadView(
          wire,
          pptScheme: 'x_app',
          pptSerializer: 'flatbuffers',
        );
        expect(application.packedPayloadBytes, same(span));
        expect(application.encoding?.name, 'flatbuffers');
        expect(application.anchor, same(owner));
        expect(application.arguments, hasLength(1));
        expect(application.arguments!.single, same(span));
        expect(application.argumentsKeywords, isNull);
        expect(wire.arguments, isNull);
        expect(wire.pptDecoded, isFalse);
        expect(
          unwrapLazyPayloadView(
            application,
            pptScheme: 'x_app',
            pptSerializer: 'flatbuffers',
          ).arguments!.single,
          same(span),
        );
      },
    );
  }

  test(
    'a raw opaque payload without a PPT scheme keeps its wire representation',
    () {
      final span = Uint8List.fromList([1, 2, 3]);
      final wire = LazyMessagePayload.materialized(
        transparentBinaryPayload: span,
      );
      final payload = unwrapLazyPayloadView(wire, pptSerializer: 'flatbuffers');
      expect(payload.arguments, isNull);
      expect(payload.argumentsKeywords, isNull);
      expect(payload.transparentBinaryPayload, same(span));
      expect(payload.pptDecoded, isFalse);
      final decoded = decodeLazyPayloadView(
        wire,
        pptSerializer: 'flatbuffers',
      );
      expect(decoded.arguments, isNull);
      expect(decoded.argumentsKeywords, isNull);
    },
  );

  test('keeping the same anchor preserves the original payload view', () {
    final owner = Object();
    final payload = LazyMessagePayload.materialized(anchor: owner);
    expect(payload.withAnchor(owner), same(payload));
  });

  for (final representation in [
    'encoded arguments without decoder',
    'encoded keywords without decoder',
    'packed empty payload',
    'materialized arguments',
    'materialized keywords',
  ]) {
    test('$representation takes precedence over an opaque PPT span', () {
      final opaque = Uint8List.fromList([1, 2, 3]);
      final ordinary = Uint8List.fromList([7, 8, 9]);
      final payload = switch (representation) {
        'encoded arguments without decoder' => LazyMessagePayload.encoded(
          transparentBinaryPayload: opaque,
          encoding: LazyPayloadEncoding.cbor,
          argumentsBytes: Uint8List.fromList([0x80]),
        ),
        'encoded keywords without decoder' => LazyMessagePayload.encoded(
          transparentBinaryPayload: opaque,
          encoding: LazyPayloadEncoding.cbor,
          argumentsKeywordsBytes: Uint8List.fromList([0xa0]),
        ),
        'packed empty payload' => LazyMessagePayload.packed(
          transparentBinaryPayload: opaque,
          encoding: LazyPayloadEncoding.flatbuffers,
          packedPayloadBytes: ordinary,
          packedPayloadDecoder: (_) => (
            arguments: null,
            argumentsKeywords: null,
          ),
          pptDecoded: false,
        ),
        'materialized arguments' => LazyMessagePayload.materialized(
          transparentBinaryPayload: opaque,
          arguments: [ordinary],
        ),
        _ => LazyMessagePayload.materialized(
          transparentBinaryPayload: opaque,
          argumentsKeywords: {'marker': 'ordinary'},
        ),
      };
      final decoded = decodeLazyPayloadView(
        payload,
        pptScheme: 'x_app',
        pptSerializer: 'flatbuffers',
      );
      if (representation == 'materialized arguments') {
        expect(decoded.arguments, hasLength(1));
        expect(decoded.arguments!.single, same(ordinary));
      } else {
        expect(decoded.arguments, isNull);
      }
      expect(decoded.argumentsKeywords, isNull);
      expect(payload.transparentBinaryPayload, same(opaque));
    });
  }
}
