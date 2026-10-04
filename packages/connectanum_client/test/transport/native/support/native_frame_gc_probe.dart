// Collect abandoned frame wrappers in a separate process, then observe actual
// native allocation destruction while an independently derived view survives.
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;

typedef _CountNative = UintPtr Function();
typedef _Count = int Function();

class _Survivor {
  _Survivor(
    this.view,
    this.prefix,
    this.frame,
    this.retained,
    this.control,
    this.arguments,
    this.allocator,
  );
  ByteData? view;
  final int prefix;
  final WeakReference<NativeFlatBufferFrame> frame;
  final WeakReference<NativeFlatBufferFrame> retained;
  final WeakReference<NativeOwnedBuffer> control;
  final WeakReference<NativeOwnedBuffer> arguments;
  final WeakReference<NativeBufferAllocator> allocator;
}

@pragma('vm:never-inline')
_Survivor _makeSurvivor(DynamicLibrary library) {
  final allocator = NativeBufferAllocator(library);
  final controlBuilder = allocator.flatBuffers(initialSize: 8192);
  controlBuilder.finish(
    flat.writeWampFlatBufferMessage(Call(7, 'com.gc'), controlBuilder),
  );
  final control = controlBuilder.freeze();
  controlBuilder.dispose();
  final argumentsBuilder = allocator.allocate(4)
    ..setUint8(0, 0x83)
    ..setUint8(1, 1)
    ..setUint8(2, 2)
    ..setUint8(3, 3);
  final arguments = argumentsBuilder.freeze();
  argumentsBuilder.dispose();
  final frame = allocator.composeFlatBufferFrame(control, arguments: arguments);
  final retained = frame.retain();
  final view = ByteData.sublistView(
    Uint8List.sublistView(frame.controlBytes, 0, 8),
  );
  return _Survivor(
    view,
    view.getUint32(0, Endian.little),
    WeakReference(frame),
    WeakReference(retained),
    WeakReference(control),
    WeakReference(arguments),
    WeakReference(allocator),
  );
}

Future<void> main() async {
  final library = DynamicLibrary.open(
    Platform.environment['CONNECTANUM_NATIVE_LIB']!,
  );
  final allocations = library.lookupFunction<_CountNative, _Count>(
    'ct_test_owned_buffer_live_allocations',
  );
  final handles = library.lookupFunction<_CountNative, _Count>(
    'ct_test_owned_buffer_live_handles',
  );
  final service = await Service.getInfo();
  final server = service.serverUri;
  if (server == null) throw StateError('Probe requires --enable-vm-service=0');
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collectUntil(bool Function() predicate) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final uri = server
          .resolve('getAllocationProfile')
          .replace(queryParameters: {'isolateId': isolate, 'gc': 'true'});
      final response = await (await client.getUrl(uri)).close();
      final result =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (result.containsKey('error')) throw StateError('$result');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (predicate()) return;
    }
    throw StateError(
      'GC did not release frame owners: allocations=${allocations()}, '
      'handles=${handles()}',
    );
  }

  try {
    if (allocations() != 0 || handles() != 0) {
      throw StateError('Probe must start with no owned allocations');
    }
    final survivor = _makeSurvivor(library);
    if (allocations() != 2) {
      throw StateError('Probe must start with separate control and arguments');
    }
    await collectUntil(
      () =>
          handles() == 0 &&
          allocations() == 1 &&
          survivor.frame.target == null &&
          survivor.retained.target == null &&
          survivor.control.target == null &&
          survivor.arguments.target == null &&
          survivor.allocator.target == null,
    );
    if (survivor.prefix == 0 ||
        survivor.view!.getUint32(0, Endian.little) != survivor.prefix) {
      throw StateError('Derived control view failed to retain its allocation');
    }
    survivor.view = null;
    await collectUntil(() => allocations() == 0 && handles() == 0);
    stdout.writeln(
      'native-frame-gc: abandoned frames released payload; derived control view retained then released storage',
    );
  } finally {
    client.close(force: true);
  }
}
