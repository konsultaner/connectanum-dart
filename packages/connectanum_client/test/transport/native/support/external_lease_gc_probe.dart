// Independent C producer: a collected Dart wrapper must not end the native
// transaction while a derived byte view still references its memory.
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/native_buffers.dart';
import 'package:ffi/ffi.dart';

typedef _CreateN =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<NativeBufferToken>);
typedef _CreateD =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<NativeBufferToken>);
typedef _StateN = Int32 Function(Pointer<Void>);
typedef _StateD = int Function(Pointer<Void>);
typedef _StopN = Void Function(Pointer<Void>);
typedef _StopD = void Function(Pointer<Void>);

class _Survivor {
  _Survivor(this.view, this.owner, this.allocator);
  ByteData? view;
  final WeakReference<NativeOwnedBuffer> owner;
  final WeakReference<NativeBufferAllocator> allocator;
}

@pragma('vm:never-inline')
_Survivor _adopt(DynamicLibrary library, Pointer<NativeBufferToken> token) {
  final allocator = NativeBufferAllocator(library);
  if (!allocator.supportsExternalTokens) {
    throw StateError('Missing lease ABI');
  }
  final identity = token.ref.identity;
  final id = token.ref.handle;
  token.ref.identity = nullptr;
  try {
    allocator.adoptTrustedNativeToken(token);
    throw StateError('Wrong library token accepted');
  } on ArgumentError {
    if (token.ref.handle != id) throw StateError('Rejected token consumed');
  }
  token.ref.identity = identity;
  final owner = allocator.adoptTrustedNativeToken(token);
  if (token.ref.handle != 0 || token.ref.identity != nullptr) {
    throw StateError('Adoption did not consume the token');
  }
  try {
    allocator.adoptTrustedNativeToken(token);
    throw StateError('Repeated adoption accepted');
  } on ArgumentError {
    // The cleared token cannot claim the same producer reference twice.
  }
  final bytes = owner.bytes;
  if (bytes.length != 3 || bytes[0] != 0 || bytes[1] != 255 || bytes[2] != 7) {
    throw StateError('Imported native subrange is incorrect');
  }
  final view = ByteData.sublistView(Uint8List.sublistView(bytes, 1, 2));
  try {
    view.setUint8(0, 9);
    throw StateError('Imported view is mutable');
  } on UnsupportedError {
    // No mutable alias may escape the producer lease.
  }
  owner.dispose();
  return _Survivor(view, WeakReference(owner), WeakReference(allocator));
}

Future<void> main(List<String> arguments) async {
  final nativePath = Platform.environment['CONNECTANUM_NATIVE_LIB']!;
  final native = DynamicLibrary.open(nativePath);
  final fixture = DynamicLibrary.open(arguments.single);
  final create = fixture.lookupFunction<_CreateN, _CreateD>('fixture_create');
  final state = fixture.lookupFunction<_StateN, _StateD>('fixture_state');
  final stop = fixture.lookupFunction<_StopN, _StopD>('fixture_stop');
  final destroy = fixture.lookupFunction<_StateN, _StateD>('fixture_destroy');
  final path = nativePath.toNativeUtf8();
  final token = calloc<NativeBufferToken>();
  final actor = create(path, token);
  calloc.free(path);
  if (actor == nullptr) {
    throw StateError('C producer could not register memory');
  }
  final server = (await Service.getInfo()).serverUri;
  if (server == null) throw StateError('Probe requires VM service');
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collectUntil(bool Function() predicate) async {
    for (var attempt = 0; attempt < 80; attempt++) {
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
      'Native lease did not reach expected state: ${state(actor)}',
    );
  }

  try {
    final survivor = _adopt(native, token);
    stop(actor);
    await collectUntil(
      () => survivor.owner.target == null && survivor.allocator.target == null,
    );
    if (state(actor) != 0 || survivor.view!.getUint8(0) != 255) {
      throw StateError('Derived view failed to preserve producer memory');
    }
    survivor.view = null;
    await collectUntil(() => state(actor) == 513);
    if (destroy(actor) != 0) throw StateError('Producer could not shut down');
    stdout.writeln(
      'external-lease-gc: native owner thread released after derived view',
    );
  } finally {
    calloc.free(token);
    client.close(force: true);
  }
}
