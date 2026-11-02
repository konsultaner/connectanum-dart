import 'dart:typed_data';
import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/serializer.dart'
    as flatbuffers;
import 'package:test/test.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';

void main() {
  final codec = flatbuffers.Serializer();
  for (final size in [16383, 16384, 65536]) {
    for (final shape in ['binary', 'topic-binary', 'binary-topic']) {
      test('owned binary CBOR $shape bytes=$size matches generic encoding', () {
        final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
        final arguments = [
          if (shape == 'topic-binary') 'sensors/µ',
          bytes,
          if (shape == 'binary-topic') 'application/µ',
        ];
        final expected = cbor.cbor.encode(cbor.CborValue(arguments));
        final encoded = encodeWampFlatBufferCbor(
          arguments,
          maximumBytes: expected.length,
        );
        expect(encoded, expected);
        expect(encoded.buffer.lengthInBytes, encoded.length);
        expect(
          encodeWampFlatBufferCbor(arguments, stringDictionaryKeys: true),
          expected,
        );
        expect(
          () => encodeWampFlatBufferCbor(
            arguments,
            maximumBytes: expected.length - 1,
          ),
          throwsArgumentError,
        );
        bytes.fillRange(0, bytes.length, 0);
        expect(encoded, expected);
      });
    }
  }
  test(
    'ordinary and transport encoding retain the complete-frame byte cap',
    () {
      final message = Call(
        1,
        'com.large',
        options: CallOptions(pptScheme: 'opaque', pptSerializer: 'flatbuffers'),
      )..transparentBinaryPayload = Uint8List(64 * 1024 * 1024);
      final byteLimit = isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        contains('byte limit'),
      );
      expect(() => codec.serialize(message), throwsA(byteLimit));
      expect(
        () => codec.serializeTransportFragments(message),
        throwsA(byteLimit),
      );
    },
  );
  test(
    'transport fragments finish empty payload frames without rebuilding',
    () {
      for (final message in <AbstractMessage>[
        Result(1, ResultDetails()),
        Call(2, 'com.empty'),
        Event(3, 4, EventDetails()),
      ]) {
        final counting = _CountingSerializer();
        final parts = counting.serializeTransportFragments(message);
        expect(counting.normalEncodes, 0);
        expect(parts, hasLength(1));
        expect(parts.single, codec.serialize(message));
        expect(codec.deserialize(parts.single)!.id, message.id);
      }
      final counting = _CountingSerializer();
      final control = Goodbye(null, 'wamp.close.normal');
      final parts = counting.serializeTransportFragments(control);
      expect(counting.normalEncodes, 1);
      expect(parts.single, codec.serialize(control));
    },
  );
  test('default fragments preserve detached binary argument storage', () {
    final bytes = Uint8List.fromList(List.generate(65536, (i) => i % 251));
    final message = Publish(1, 'com.test', arguments: [bytes]);
    final parts = codec.serializeFragments(message)!;
    expect(parts.any((part) => identical(part, bytes)), isFalse);
    final output = BytesBuilder(copy: false);
    for (final part in parts) {
      output.add(part);
    }
    bytes.fillRange(0, bytes.length, 0);
    final decoded = codec.deserialize(output.takeBytes()) as Publish;
    expect(decoded.arguments!.single, List.generate(65536, (i) => i % 251));
  });
  test(
    'binary CBOR fragments reject unsupported shapes and enforce exact encoded size',
    () {
      final bytes = Uint8List(24);
      for (final unsupported in <Object?>[
        null,
        [],
        [bytes, bytes],
        ['topic', bytes, 'extra'],
        bytes,
      ]) {
        expect(encodeWampFlatBufferBinaryCborFragments(unsupported), isNull);
      }
      expect(
        () =>
            encodeWampFlatBufferBinaryCborFragments([bytes], maximumBytes: 26),
        throwsArgumentError,
      );
      final exact = encodeWampFlatBufferBinaryCborFragments([
        bytes,
      ], maximumBytes: 27)!;
      expect(exact.fold<int>(0, (sum, part) => sum + part.length), 27);
      expect(
        () => encodeWampFlatBufferBinaryCborFragments([
          'é',
          Uint8List(0),
        ], maximumBytes: 4),
        throwsArgumentError,
      );
      expect(
        () => encodeWampFlatBufferBinaryCborFragments([
          Uint8List(0),
          'é',
        ], maximumBytes: 4),
        throwsArgumentError,
      );
    },
  );
  test(
    'deferred vectors snapshot their parts and preserve the legacy byte getter',
    () {
      final first = Uint8List.fromList([1, 2]);
      final second = Uint8List.fromList([3]);
      final parts = [first, second];
      final vector = DeferredFlatBufferVector.withParts(1, 2, parts);
      final wrapped = FlatBufferByteVectorParts(parts);
      parts.clear();
      expect(vector.length, 3);
      expect(vector.bytes, [1, 2, 3]);
      expect(wrapped.parts, [first, second]);
      expect(() => wrapped.parts.clear(), throwsUnsupportedError);
      expect(
        identical(DeferredFlatBufferVector(1, 2, first).bytes, first),
        isTrue,
      );
    },
  );
  test(
    'offset binary views and a second application vector retain exact bounds',
    () {
      final storage = Uint8List.fromList(List.generate(65544, (i) => i % 251));
      final bytes = Uint8List.sublistView(storage, 3, 65539);
      for (var padding = 0; padding < 8; padding++) {
        final message = Call(
          1,
          'com.test',
          arguments: ['topic${'x' * padding}', bytes],
          argumentsKeywords: {'extra': 17},
        );
        final fragments = codec.serializeFragments(
          message,
          borrowBinaryArguments: true,
        )!;
        expect(fragments.any((part) => identical(part, bytes)), isTrue);
        final output = BytesBuilder(copy: false);
        for (final part in fragments) {
          output.add(part);
        }
        final decoded = codec.deserialize(output.takeBytes()) as Call;
        expect(decoded.arguments, message.arguments);
        expect(decoded.argumentsKeywords, {'extra': 17});
      }
    },
  );
  for (final size in [128, 65536]) {
    for (final shape in ['binary', 'topic-binary', 'binary-topic']) {
      test(
        'materialized $shape bytes=$size remain original FlatBuffers fragments',
        () {
          final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
          final arguments = <dynamic>[
            if (shape == 'topic-binary') 'sensors/µ',
            bytes,
            if (shape == 'binary-topic') 'application/octet-stream',
          ];
          for (final message in <AbstractMessageWithPayload>[
            Call(1, 'com.test', arguments: arguments),
            Publish(1, 'com.test', arguments: arguments),
            Event(1, 2, EventDetails(), arguments: arguments),
          ]) {
            final fragments = codec.serializeFragments(
              message,
              borrowBinaryArguments: true,
            )!;
            expect(fragments.any((part) => identical(part, bytes)), isTrue);
            final output = BytesBuilder(copy: false);
            for (final part in fragments) {
              output.add(part);
            }
            final decoded =
                codec.deserialize(output.takeBytes())
                    as AbstractMessageWithPayload;
            expect(decoded.arguments, arguments);
            expect(decoded.arguments!.whereType<Uint8List>().single, bytes);
          }
        },
      );
    }
  }
}

class _CountingSerializer extends flatbuffers.Serializer {
  int normalEncodes = 0;

  @override
  Uint8List serialize(AbstractMessage message) {
    normalEncodes++;
    return super.serialize(message);
  }
}
