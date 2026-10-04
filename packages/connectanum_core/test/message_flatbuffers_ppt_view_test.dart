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
    },
  );
}
