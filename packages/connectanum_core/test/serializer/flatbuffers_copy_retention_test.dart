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

void main() {
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
