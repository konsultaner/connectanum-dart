// Standalone VM-service child: force collections and observe actual native
// allocation destruction without depending on the parent test runner's roots.
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/native_buffers.dart';

typedef _CountNative = UintPtr Function();
typedef _Count = int Function();

class _Survivor {
  _Survivor(this.view, this.owner, this.builder, this.allocator);
  ByteData? view;
  final WeakReference<NativeOwnedBuffer> owner;
  final WeakReference<NativeBufferBuilder> builder;
  final WeakReference<NativeBufferAllocator> allocator;
}

@pragma('vm:never-inline')
_Survivor _makeSurvivor(DynamicLibrary library) {
  final allocator = NativeBufferAllocator(library);
  final builder = allocator.allocate(1024)..setUint32(1016, 0x04030201);
  final owner = builder.freeze(offset: 1016, length: 8);
  // Keep only a derived ByteData view; neither the root list nor its wrapper
  // remains strongly reachable after returning.
  final derived = ByteData.sublistView(
    Uint8List.sublistView(owner.bytes, 1, 3),
  );
  return _Survivor(
    derived,
    WeakReference(owner),
    WeakReference(builder),
    WeakReference(allocator),
  );
}

@pragma('vm:never-inline')
void _abandonMutable(DynamicLibrary library) {
  final allocator = NativeBufferAllocator(library);
  allocator.allocate(32).setUint8(0, 7);
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
  final info = await Service.getInfo();
  final server = info.serverUri;
  if (server == null) throw StateError('Probe requires --enable-vm-service=0');
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collectUntil(bool Function() predicate) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final uri = server
          .resolve('getAllocationProfile')
          .replace(
            queryParameters: {'isolateId': isolate, 'gc': 'true'},
          );
      final response = await (await client.getUrl(uri)).close();
      final result =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (result.containsKey('error')) throw StateError('$result');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (predicate()) return;
    }
    throw StateError(
      'GC did not release expected native owners: allocations=${allocations()}, '
      'handles=${handles()}',
    );
  }

  try {
    if (allocations() != 0 || handles() != 0) {
      throw StateError('Probe must start with no owned allocations');
    }
    final survivor = _makeSurvivor(library);
    _abandonMutable(library);
    await collectUntil(
      () =>
          handles() == 0 &&
          survivor.owner.target == null &&
          survivor.builder.target == null &&
          survivor.allocator.target == null,
    );
    if (allocations() != 1 ||
        survivor.view!.getUint16(0, Endian.little) != 0x0302) {
      throw StateError('Derived view failed to retain its native allocation');
    }
    survivor.view = null;
    await collectUntil(() => allocations() == 0);
    stdout.writeln(
      'owned-buffer-gc: derived view retained then released storage',
    );
  } finally {
    client.close(force: true);
  }
}
