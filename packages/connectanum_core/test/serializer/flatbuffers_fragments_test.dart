import 'dart:typed_data';
import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';
import 'package:test/test.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/serializer.dart'
    as flatbuffers;

Uint8List join(List<Uint8List> fragments) =>
    (BytesBuilder(copy: false)..addAllFragments(fragments)).takeBytes();

extension on BytesBuilder {
  void addAllFragments(List<Uint8List> fragments) {
    for (final fragment in fragments) {
      add(fragment);
    }
  }
}

void expectCallVectorsAligned(Uint8List joined) {
  final raw = ByteData.sublistView(joined);
  final root = raw.getUint32(0, Endian.little);
  final rootVtable = root - raw.getInt32(root, Endian.little);
  final msgField = root + raw.getUint16(rootVtable + 6, Endian.little);
  final body = msgField + raw.getUint32(msgField, Endian.little);
  final vtable = body - raw.getInt32(body, Endian.little);
  for (final slot in [3, 4, 5]) {
    final slotOffset = 4 + 2 * slot;
    if (slotOffset >= raw.getUint16(vtable, Endian.little)) continue;
    final offset = raw.getUint16(vtable + slotOffset, Endian.little);
    if (offset == 0) continue;
    final field = body + offset;
    final vector = field + raw.getUint32(field, Endian.little);
    expect((vector + 4) % 8, 0);
  }
}

void main() {
  final codec = flatbuffers.Serializer();
  test('large encoded opaque body can remain an original send fragment', () {
    final bytes = Uint8List(65536);
    final message = Call(
      1,
      'com.probe',
      options: CallOptions(pptScheme: 'opaque', pptSerializer: 'flatbuffers'),
    )..transparentBinaryPayload = bytes;
    final fragments = flatbuffers.Serializer().serializeFragments(message);
    expect(fragments, isNotNull);
    expect(fragments!.any((part) => identical(part, bytes)), true);
  });
  test('encoded CBOR arguments remain an original send fragment', () {
    final bytes = Uint8List.fromList([0x81, 1]);
    final message = Call(1, 'com.probe')
      ..setLazyPayload(
        argumentsBytes: bytes,
        argumentsDecoder: (_) => throw StateError('materialized'),
        encoding: LazyPayloadEncoding.cbor,
      );
    final fragments = flatbuffers.Serializer().serializeFragments(message);
    expect(fragments, isNotNull);
    expect(fragments!.any((part) => identical(part, bytes)), true);
  });

  for (final length in [0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 23, 65536]) {
    for (final shape in ['full', 'partial', 'readonly']) {
      test('opaque $shape body $length exact identity and alignment', () {
        final backing = Uint8List(length + (shape == 'full' ? 0 : 64));
        final mutable = shape == 'full'
            ? backing
            : Uint8List.sublistView(backing, 32, 32 + length);
        for (var i = 0; i < length; i++) {
          mutable[i] = (i * 17) % 256;
        }
        final bytes = shape == 'readonly'
            ? mutable.asUnmodifiableView()
            : mutable;
        final message = Call(
          42,
          'com.probe.${'x' * (length % 8)}',
          options: CallOptions(
            pptScheme: 'opaque',
            pptSerializer: 'flatbuffers',
            custom: {
              'nested': {'flag': true},
            },
          ),
        )..transparentBinaryPayload = bytes;
        final fragments = codec.serializeFragments(message)!;
        expect(fragments.where((part) => identical(part, bytes)), hasLength(1));
        expect(
          fragments.fold<int>(0, (sum, p) => sum + p.length),
          lessThan(length + 1024),
        );
        final encoded = join(fragments);
        validateWampFlatBuffer(encoded);
        final generated = wire.Message(encoded).msg as wire.Call;
        expect(generated.payload, bytes);
        expectCallVectorsAligned(encoded);
        final decoded = codec.deserialize(encoded) as Call;
        expect(decoded.requestId, 42);
        expect(decoded.procedure, message.procedure);
        expect(decoded.transparentBinaryPayload, bytes);
        expect(codec.metadataFor(decoded), codec.metadataFor(message));
        if (length > 0 && shape != 'readonly') {
          bytes[0] ^= 255;
          expect(join(fragments), isNot(encoded));
          expect(
            (wire.Message(join(fragments)).msg as wire.Call).payload,
            bytes,
          );
        }
      });
    }
  }
  test('lazy args and kwargs retain both exact encoded views', () {
    final args = Uint8List.fromList(
      cbor.encode(
        CborValue([
          1,
          'hello',
          Uint8List.fromList([0, 255]),
        ]),
      ),
    );
    final kwargsBacking = Uint8List.fromList([
      99,
      ...cbor.encode(
        CborValue({
          'key': [1, 2],
        }),
      ),
      88,
    ]);
    final kwargs = Uint8List.sublistView(
      kwargsBacking,
      1,
      kwargsBacking.length - 1,
    ).asUnmodifiableView();
    final message = Call(9, 'com.proc')
      ..setLazyPayload(
        argumentsBytes: args,
        argumentsKeywordsBytes: kwargs,
        argumentsDecoder: (_) => throw StateError('args materialized'),
        argumentsKeywordsDecoder: (_) =>
            throw StateError('kwargs materialized'),
        encoding: LazyPayloadEncoding.cbor,
      );
    final fragments = codec.serializeFragments(message)!;
    expect(fragments.any((p) => identical(p, args)), true);
    expect(fragments.any((p) => identical(p, kwargs)), true);
    final bytes = join(fragments);
    validateWampFlatBuffer(bytes);
    final generated = wire.Message(bytes).msg as wire.Call;
    expect(generated.args, args);
    expect(generated.kwargs, kwargs);
    expectCallVectorsAligned(bytes);
    expect(message.hasLazyArguments, true);
    final decoded = codec.deserialize(bytes) as Call;
    expect(decoded.arguments, [
      1,
      'hello',
      Uint8List.fromList([0, 255]),
    ]);
    expect(decoded.argumentsKeywords, {
      'key': [1, 2],
    });
  });
  test('materialized args encode and empty kwargs preserve presence', () {
    final message = Call(
      1,
      'com.proc',
      arguments: [4, 'text'],
      argumentsKeywords: {},
    );
    final bytes = join(codec.serializeFragments(message)!);
    validateWampFlatBuffer(bytes);
    final decoded = codec.deserialize(bytes) as Call;
    expect(decoded.arguments, [4, 'text']);
    expect(decoded.argumentsKeywords, isEmpty);
    expect((wire.Message(bytes).msg as wire.Call).kwargs, [0xa0]);
  });
  test('controls and absent arguments use the normal serialization path', () {
    for (final message in <AbstractMessage>[
      Hello('realm', Details.forHello()),
      Welcome(9, Details.forWelcome()),
      Goodbye(null, 'wamp.close.normal'),
      Heartbeat(ping: 0),
      Call(42, 'com.probe'),
    ]) {
      expect(codec.serializeFragments(message), isNull);
      final bytes = codec.serialize(message);
      validateWampFlatBuffer(bytes);
      expect(codec.deserialize(bytes)!.id, message.id);
    }
  });
  test('invalid borrowed CBOR is rejected before sending', () {
    final message = Call(1, 'com.proc')
      ..setLazyPayload(
        argumentsBytes: Uint8List.fromList([0xa0]),
        argumentsDecoder: (_) => throw StateError('unexpected decoding'),
        encoding: LazyPayloadEncoding.cbor,
      );
    expect(() => codec.serializeFragments(message), throwsFormatException);
  });
  test('invalid deferred table and slot are rejected', () {
    for (final slot in [-1, 3, 200]) {
      final builder = WampFlatBufferBuilder();
      final root = writeWampFlatBufferMessage(Call(1, 'com.proc'), builder);
      expect(
        () => finishWampFlatBufferFragments(builder, root, [
          DeferredFlatBufferVector(root, slot, Uint8List(1)),
        ]),
        throwsStateError,
      );
    }
    final builder = WampFlatBufferBuilder();
    final root = writeWampFlatBufferMessage(Call(1, 'com.proc'), builder);
    expect(
      () => finishWampFlatBufferFragments(builder, root, [
        DeferredFlatBufferVector(999999, 0, Uint8List(1)),
      ]),
      throwsStateError,
    );
  });
  test('oversized opaque vector fails aggregate frame bound', () {
    final message = Call(
      1,
      'com.proc',
      options: CallOptions(pptScheme: 'opaque', pptSerializer: 'flatbuffers'),
    )..transparentBinaryPayload = Uint8List(64 * 1024 * 1024);
    expect(() => codec.serializeFragments(message), throwsArgumentError);
  });

  final payloadFactories = <String, AbstractMessageWithPayload Function(bool)>{
    'CALL': (ppt) => Call(
      42,
      'com.probe',
      options: CallOptions(
        pptScheme: ppt ? 'opaque' : null,
        pptSerializer: ppt ? 'flatbuffers' : null,
      ),
    ),
    'INVOCATION': (ppt) => Invocation(
      42,
      43,
      InvocationDetails(
        44,
        'com.probe',
        true,
        ppt ? 'opaque' : null,
        ppt ? 'flatbuffers' : null,
      )..progress = true,
    ),
    'YIELD': (ppt) => Yield(
      42,
      options: YieldOptions(
        progress: true,
        pptScheme: ppt ? 'opaque' : null,
        pptSerializer: ppt ? 'flatbuffers' : null,
      ),
    ),
    'RESULT': (ppt) => Result(
      42,
      ResultDetails(
        progress: true,
        pptScheme: ppt ? 'opaque' : null,
        pptSerializer: ppt ? 'flatbuffers' : null,
      ),
    ),
    'PUBLISH': (ppt) => Publish(
      42,
      'com.topic',
      options: PublishOptions(
        acknowledge: true,
        pptScheme: ppt ? 'opaque' : null,
        pptSerializer: ppt ? 'flatbuffers' : null,
      ),
    ),
    'EVENT': (ppt) => Event(
      42,
      43,
      EventDetails(
        publisher: 44,
        topic: 'com.topic',
        pptScheme: ppt ? 'opaque' : null,
        pptSerializer: ppt ? 'flatbuffers' : null,
      ),
    ),
    'ERROR': (ppt) => Error(
      48,
      42,
      ppt ? {'ppt_scheme': 'opaque', 'ppt_serializer': 'flatbuffers'} : {},
      'wamp.error.runtime_error',
    ),
  };
  for (final entry in payloadFactories.entries) {
    test(
      '${entry.key} keeps encoded args and kwargs without materialization',
      () {
        final args = Uint8List.fromList([0x82, 1, 2]).asUnmodifiableView();
        final kwargsBacking = Uint8List.fromList([
          99,
          0xa1,
          0x61,
          0x78,
          0xf5,
          88,
        ]);
        final kwargs = Uint8List.sublistView(
          kwargsBacking,
          1,
          5,
        ).asUnmodifiableView();
        final message = entry.value(false)
          ..setLazyPayload(
            argumentsBytes: args,
            argumentsKeywordsBytes: kwargs,
            argumentsDecoder: (_) => throw StateError('args materialized'),
            argumentsKeywordsDecoder: (_) =>
                throw StateError('kwargs materialized'),
            encoding: LazyPayloadEncoding.cbor,
          );
        final fragments = codec.serializeFragments(message)!;
        expect(fragments.any((p) => identical(p, args)), true);
        expect(fragments.any((p) => identical(p, kwargs)), true);
        final bytes = join(fragments);
        validateWampFlatBuffer(bytes);
        final decoded = codec.deserialize(bytes) as AbstractMessageWithPayload;
        expect(decoded.id, message.id);
        expect(decoded.arguments, [1, 2]);
        expect(decoded.argumentsKeywords, {'x': true});
        expect(codec.metadataFor(decoded), codec.metadataFor(message));
        expect(codec.serialize(decoded), codec.serialize(message));
        expect(message.hasLazyArguments, true);
      },
    );
    test('${entry.key} keeps the exact opaque read-only subview', () {
      final backing = Uint8List(16448);
      final bytes = Uint8List.sublistView(
        backing,
        32,
        16416,
      ).asUnmodifiableView();
      final message = entry.value(true)..transparentBinaryPayload = bytes;
      final fragments = codec.serializeFragments(message)!;
      expect(fragments.any((p) => identical(p, bytes)), true);
      final encoded = join(fragments);
      validateWampFlatBuffer(encoded);
      final decoded = codec.deserialize(encoded) as AbstractMessageWithPayload;
      expect(decoded.id, message.id);
      expect(decoded.transparentBinaryPayload, bytes);
      expect(codec.metadataFor(decoded), codec.metadataFor(message));
      expect(codec.serialize(decoded), codec.serialize(message));
    });
  }
}
