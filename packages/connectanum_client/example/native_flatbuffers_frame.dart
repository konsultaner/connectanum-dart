// VM example. Select a compatible native library with CONNECTANUM_NATIVE_LIB.
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;

void main() {
  final allocator = NativeBufferAllocator.instance();
  if (!allocator.supportsFlatBufferFrames) {
    throw UnsupportedError('Native segmented-frame ABI v1 is required');
  }
  final controlBuilder = allocator.flatBuffers(initialSize: 8192);
  final argumentsBuilder = allocator.allocate(4);
  NativeOwnedBuffer? control;
  NativeOwnedBuffer? arguments;
  NativeFlatBufferFrame? frame;
  NativeFlatBufferFrame? retained;
  try {
    controlBuilder.finish(
      flat.writeWampFlatBufferMessage(
        Call(1, 'com.example.echo'),
        controlBuilder,
      ),
    );
    control = controlBuilder.freeze();
    // Encode the CBOR array [1, 2, 3] directly into native storage.
    argumentsBuilder
      ..setUint8(0, 0x83)
      ..setUint8(1, 1)
      ..setUint8(2, 2)
      ..setUint8(3, 3);
    arguments = argumentsBuilder.freeze();
    frame = allocator.composeFlatBufferFrame(control, arguments: arguments);
    retained = frame.retain();
    // An established NativeFrameTransport can send this immutable frame with
    // sendNativeFrameTracked(frame); its receipt describes local completion.
    print('frameBytes=${frame.length} segments=${frame.segmentCount}');
    print('applicationInputCopies=${arguments.inputCopiedBytes}');
    print('controlGrowthCopies=${control.growthCopiedBytes}');
  } finally {
    retained?.dispose();
    frame?.dispose();
    arguments?.dispose();
    control?.dispose();
    argumentsBuilder.dispose();
    controlBuilder.dispose();
  }
}
