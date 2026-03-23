@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_router/src/native/message_binding.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('bindMessage', () {
    test('decodes CBOR payloads with lazy args and kwargs', () {
      final frameBytes = Uint8List.fromList(
        cbor.cborEncode(
          cbor.CborValue([
            MessageTypes.codePublish,
            42,
            <String, Object?>{},
            'bench.topic',
          ]),
        ),
      );
      final argsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue(['payload'])),
      );
      final kwargsBytes = Uint8List.fromList(
        cbor.cborEncode(cbor.CborValue({'flag': true})),
      );

      final message = bindMessage(
        NativeMessageSerializer.cbor,
        frameBytes,
        argsBytes: argsBytes,
        kwargsBytes: kwargsBytes,
      );

      expect(message, isA<Publish>());
      final publish = message as Publish;
      expect(publish.topic, 'bench.topic');
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['payload']);
      expect(publish.argumentsKeywords, {'flag': true});
    });
  });
}
