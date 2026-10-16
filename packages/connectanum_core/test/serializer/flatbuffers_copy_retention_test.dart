import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cbor/cbor.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_reader.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';

class _CaptureBuilder extends fb.Builder {
  _CaptureBuilder() : super();
  List<int>? input;
  @override
  int writeListUint8(List<int> values) {
    input = values;
    return super.writeListUint8(values);
  }
}

class _VectorAllocator extends fb.Allocator {
  late ByteData current;
  int allocations = 0;
  int growthBytes = 0;
  bool failGrowth = false;

  @override
  void deallocate(ByteData data) {}

  @override
  ByteData allocate(int size) {
    allocations++;
    return current = ByteData(size);
  }

  @override
  ByteData resize(ByteData old, int size, int back, int front) {
    if (failGrowth) throw StateError('injected growth failure');
    growthBytes += back + front;
    return super.resize(old, size, back, front);
  }
}

void main() {
  test('source aliasing builder storage retains SDK overlap behavior', () {
    final sdkStorage = _VectorAllocator();
    final storage = _VectorAllocator();
    final sdk = fb.Builder(initialSize: 512, allocator: sdkStorage);
    final builder = flatbuffers.WampFlatBufferBuilder(
      initialSize: 512,
      allocator: storage,
    );
    for (final data in [sdkStorage.current, storage.current]) {
      data.buffer.asUint8List().fillRange(0, 512, 7);
    }
    sdk.finish(
      sdk.writeListUint8(sdkStorage.current.buffer.asUint8List(252, 256)),
    );
    builder.finish(
      builder.writeListUint8(storage.current.buffer.asUint8List(252, 256)),
    );
    expect(builder.buffer, sdk.buffer);
  });

  test('typed word vectors preserve SDK wire, inputs and allocation layout', () {
    for (final length in [
      0,
      1,
      2,
      3,
      4,
      255,
      256,
      257,
      258,
      259,
      4096,
      4097,
      4098,
      4099,
      65536,
      65537,
      65538,
      65539,
    ]) {
      for (final start in [0, 1, 3, 4]) {
        final backing = Uint8List(length + start + 7);
        for (var i = 0; i < backing.length; i++) {
          backing[i] = (i * 29 + 7) & 255;
        }
        final bytes = Uint8List.sublistView(backing, start, start + length);
        for (final input in [
          bytes,
          bytes.asUnmodifiableView(),
          bytes.toList(),
        ]) {
          for (final prefix in [0, 1, 3, 4]) {
            for (final capacity in [8, length + 4, length + 128]) {
              for (final align8 in [false, true]) {
                final sdkStorage = _VectorAllocator();
                final storage = _VectorAllocator();
                final sdk = fb.Builder(
                  initialSize: capacity,
                  allocator: sdkStorage,
                );
                final builder = flatbuffers.WampFlatBufferBuilder(
                  initialSize: capacity,
                  allocator: storage,
                );
                for (final b in [sdk, builder]) {
                  if (align8) b.putFloat64(0);
                  for (var i = 0; i < prefix; i++) {
                    b.putUint8(i + 1);
                  }
                  final vector = b.writeListUint8(input);
                  b.startTable(2);
                  b.addOffset(0, vector);
                  b.addUint8(1, 7);
                  b.finish(b.endTable());
                }
                expect(
                  builder.buffer,
                  sdk.buffer,
                  reason:
                      'n=$length start=$start prefix=$prefix capacity=$capacity align8=$align8',
                );
                expect(
                  (
                    storage.current.lengthInBytes,
                    storage.allocations,
                    storage.growthBytes,
                  ),
                  (
                    sdkStorage.current.lengthInBytes,
                    sdkStorage.allocations,
                    sdkStorage.growthBytes,
                  ),
                );
                expect(input, bytes);
                for (var i = 0; i < backing.length; i++) {
                  if (backing[i] != ((i * 29 + 7) & 255)) {
                    fail('source changed at $i');
                  }
                }
              }
            }
          }
        }
      }
    }
  });

  test('typed word vectors observe copies once across reset and growth', () {
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot()!;
    final builder = flatbuffers.WampFlatBufferBuilder(initialSize: 8);
    final bytes = Uint8List(65537)..[65536] = 255;
    for (var i = 0; i < 2; i++) {
      builder.reset();
      builder.putUint32(17);
      builder.finish(builder.writeListUint8(bytes.asUnmodifiableView()));
      expect(
        const fb.ListReader<int>(
          fb.Uint8Reader(),
        ).read(fb.BufferContext.fromBytes(builder.buffer), 0),
        bytes,
      );
    }
    final after = OwnedCopyMetrics.snapshot()!;
    expect(
      after['flatbuffer_vector_copy_bytes']! -
          before['flatbuffer_vector_copy_bytes']!,
      2 * bytes.length,
    );
    expect(
      after['flatbuffer_growth_copy_bytes']! -
          before['flatbuffer_growth_copy_bytes']!,
      greaterThan(0),
    );
    expect(after['failed_copy_operations'], before['failed_copy_operations']);
    expect(
      after['unmeasured_copy_operations'],
      before['unmeasured_copy_operations'],
    );
  });

  test(
    'typed vector growth failure records failure without successful input copy',
    () {
      final storage = _VectorAllocator()..failGrowth = true;
      final builder = flatbuffers.WampFlatBufferBuilder(
        initialSize: 8,
        allocator: storage,
      );
      final bytes = Uint8List(65536)..fillRange(0, 65536, 7);
      OwnedCopyMetrics.enable();
      final before = OwnedCopyMetrics.snapshot()!;
      expect(
        () => builder.writeListUint8(bytes.asUnmodifiableView()),
        throwsStateError,
      );
      final after = OwnedCopyMetrics.snapshot()!;
      expect(
        after['flatbuffer_vector_copy_bytes'],
        before['flatbuffer_vector_copy_bytes'],
      );
      expect(
        after['failed_copy_operations']!,
        greaterThan(before['failed_copy_operations']!),
      );
      expect(bytes.every((v) => v == 7), isTrue);
    },
  );

  test('byte storage reaches vector builder without a cast wrapper', () {
    final bytes = Uint8List.fromList([0, 1, 255]);
    final b = _CaptureBuilder();
    final root = writeWampFlatBufferFields({
      'msg_type': 'Call',
      // This SDK-builder spy only needs string and byte-vector fields.
      'msg': {'procedure': 'com.echo', 'args': bytes},
    }, b);
    expect(identical(b.input, bytes), isTrue);
    b.finish(root);
    expect((wire.Message(b.buffer).msg as wire.Call).args, bytes);
  });
  for (final ppt in [false, true]) {
    test('public frame binary storage PPT=$ppt', () {
      final codec = flatbuffers.Serializer();
      final source = codec.serialize(
        wamp.Result(
          1,
          wamp.ResultDetails(
            pptScheme: ppt ? 'x_bytes' : null,
            pptSerializer: ppt ? 'flatbuffers' : null,
            custom: {'custom': true},
          ),
          arguments: [
            Uint8List.fromList([7, 8, 9]),
          ],
        ),
      );
      final message = codec.deserialize(source) as wamp.Result;
      final bytes = message.wireArguments!.single as Uint8List;
      expect(bytes, [7, 8, 9]);
      if (ppt) {
        final args = message.debugEncodedArgumentsBytes!;
        expect(bytes.buffer.lengthInBytes, source.buffer.lengthInBytes);
        expect(bytes.offsetInBytes, args.offsetInBytes + args.length - 3);
        expect(() => bytes[0] = 42, throwsUnsupportedError);
      } else {
        bytes[0] = 42;
        expect(
          (codec.deserialize(source) as wamp.Result).wireArguments!.single,
          [7, 8, 9],
        );
      }
    });
  }
  test('large frame reserves its already encoded vectors once', () {
    final message = wamp.Result(
      1,
      wamp.ResultDetails(),
      arguments: [Uint8List(65536)],
      argumentsKeywords: {'data': Uint8List(131072)},
    );
    final codec = flatbuffers.Serializer();
    final bytes = codec.serialize(message);
    final standard = flatbuffers.WampFlatBufferBuilder();
    standard.finish(writeWampFlatBufferMessage(message, standard));
    expect(bytes, standard.buffer);
    expect(bytes.buffer.lengthInBytes, lessThanOrEqualTo(bytes.length + 1024));
  });
  test('encoded CBOR storage is retained without a second byte copy', () {
    final expected = Uint8List.fromList(List.generate(65536, (i) => i & 255));
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot();
    final encoded = encodeWampFlatBufferCbor([expected]);
    final after = OwnedCopyMetrics.snapshot();
    expect(after!['clone_copy_bytes']! - before!['clone_copy_bytes']!, 0);
    final retained = Uint8List.fromList(encoded);
    encodeWampFlatBufferCbor([Uint8List(131072)]);
    expect(encoded, retained);
    expect((cbor.decode(encoded) as CborList).single.toObject(), expected);
    expected[0] = 77;
    expect(encoded, retained);
  });
  test('decoded CBOR typed storage is retained without a second byte copy', () {
    final expected = Uint8List.fromList(List.generate(65536, (i) => i & 255));
    final source = Uint8List.fromList(cbor.encode(CborValue([expected])));
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot();
    final decoded = decodeWampFlatBufferApplication(source) as List;
    final after = OwnedCopyMetrics.snapshot();
    expect(decoded.single, isA<Uint8List>());
    expect(decoded.single, expected);
    expect(after!['clone_copy_bytes']! - before!['clone_copy_bytes']!, 0);
    (decoded.single as Uint8List)[0] = 77;
    expect(expected[0], 0);
    expect((decodeWampFlatBufferApplication(source) as List).single, expected);
  });
}
