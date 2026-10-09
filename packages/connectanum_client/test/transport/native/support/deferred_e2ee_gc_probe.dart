// Observe exported native owner destruction in a separate VM process. There
// are no queued consumers: freeing an output owner destroys its backing Vec.
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:ffi/ffi.dart';

typedef _CountNative = UintPtr Function();
typedef _Count = int Function();
typedef _EnqueueNative = Int64 Function(Int32, Int32, Pointer<Uint8>, Int32);
typedef _Enqueue = int Function(int, int, Pointer<Uint8>, int);

class _Survivor {
  _Survivor(this.view, this.incoming, this.provider);
  ByteData? view;
  final WeakReference<NativeIncomingMessage> incoming;
  final WeakReference<DisposableWampE2eeProvider> provider;
}

@pragma('vm:never-inline')
void _checkView(_Survivor survivor) {
  final view = survivor.view!;
  for (var index = 0; index < view.lengthInBytes; index++) {
    if (view.getUint8(index) != [30, 40, 50, 60][index]) {
      throw StateError('Derived view lost plaintext storage');
    }
  }
  try {
    view.setUint8(0, 0);
    throw StateError('Derived decrypted view became writable');
  } on UnsupportedError {
    // Mutation must fail because the derived view is read-only.
  }
}

@pragma('vm:never-inline')
_Survivor _makeSurvivor(
  bool aes,
  DynamicLibrary library,
  NativeClientRuntime runtime,
) {
  final key = List<int>.generate(32, (index) => index + 1);
  final provider = aes
      ? NativeWampFlatBuffersAes256GcmProvider.single(keyId: 'gc-key', key: key)
      : NativeWampFlatBuffersXsalsa20Poly1305Provider.single(
          keyId: 'gc-key',
          key: key,
        );
  final portable = aes
      ? WampFlatBuffersAes256GcmProvider.single(keyId: 'gc-key', key: key)
      : WampFlatBuffersXsalsa20Poly1305Provider.single(
          keyId: 'gc-key',
          key: key,
        );
  final options = PublishOptions();
  final packed = portable.packPayload(
    [
      Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]),
    ],
    null,
    options,
  );
  final frame = flat.Serializer().serialize(
    Invocation(
      71,
      81,
      InvocationDetails(
        91,
        'typed.gc',
        true,
        'wamp',
        'flatbuffers',
        options.pptCipher,
        'gc-key',
      ),
      arguments: packed,
    ),
  );
  final input = malloc<Uint8>(frame.length);
  final enqueue = library.lookupFunction<_EnqueueNative, _Enqueue>(
    'ct_test_message_enqueue_wide',
  );
  int handle;
  try {
    input.asTypedList(frame.length).setAll(0, frame);
    handle = enqueue(777, 5, input, frame.length);
  } finally {
    malloc.free(input);
  }
  if (handle <= 0 || runtime.pollMessageHandle(777) != handle) {
    throw StateError('GC fixture did not enqueue the typed message');
  }
  final incoming = runtime.materialize(handle, deferPayloadExports: true);
  final anchor = Object();
  attachSessionMessageAnchor(anchor, incoming);
  final payload = provider.unpackPayload(
    null,
    options,
    runtimeContext: WampE2eeRuntimeContext(
      direction: WampE2eeDirection.inbound,
      messageType: WampE2eeMessageType.invocation,
      payloadAnchor: anchor,
    ),
  );
  final bytes = payload.arguments!.single as Uint8List;
  final view = ByteData.sublistView(Uint8List.sublistView(bytes, 1, 7), 1, 5);
  incoming.release();
  provider.release();
  return _Survivor(view, WeakReference(incoming), WeakReference(provider));
}

class _DeferredHolder {
  _DeferredHolder(this.incoming, this.weak, this.observer);
  NativeIncomingMessage? incoming;
  final WeakReference<NativeIncomingMessage> weak;
  final Pointer<Void> observer;
}

@pragma('vm:never-inline')
_DeferredHolder _makeDeferred(
  bool retain,
  DynamicLibrary library,
  NativeClientRuntime runtime,
) {
  final frame = flat.Serializer().serialize(
    Invocation(
      71,
      81,
      InvocationDetails(91, 'deferred.gc', true),
      arguments: [
        Uint8List.fromList([1, 2, 3]),
      ],
    ),
  );
  final input = malloc<Uint8>(frame.length);
  final enqueue = library.lookupFunction<_EnqueueNative, _Enqueue>(
    'ct_test_message_enqueue_wide',
  );
  int handle;
  try {
    input.asTypedList(frame.length).setAll(0, frame);
    handle = enqueue(777, 5, input, frame.length);
  } finally {
    malloc.free(input);
  }
  if (handle <= 0 || runtime.pollMessageHandle(777) != handle) {
    throw StateError('Deferred GC fixture failed to enqueue');
  }
  final observer = library
      .lookupFunction<
        Pointer<Void> Function(Int64),
        Pointer<Void> Function(int)
      >('ct_test_message_observer_new_wide')(handle);
  if (observer.address == 0)
    throw StateError('Failed to create native observer');
  final incoming = runtime.materialize(handle, deferPayloadExports: true);
  return _DeferredHolder(
    retain ? incoming : null,
    WeakReference(incoming),
    observer,
  );
}

Future<void> main() async {
  final library = DynamicLibrary.open(
    Platform.environment['CONNECTANUM_NATIVE_LIB']!,
  );
  final owners = library.lookupFunction<_CountNative, _Count>(
    'ct_test_external_byte_buffer_live_owners',
  );
  final runtime = NativeClientRuntime.instance();
  if (!runtime.supportsTypedConsumingE2eeMessagePayloadDecrypt) {
    throw StateError('GC probe requires the explicit typed consuming ABI');
  }
  final service = await Service.getInfo();
  final server = service.serverUri;
  if (server == null) throw StateError('Probe requires --enable-vm-service=0');
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<void> collectUntil(bool Function() predicate) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      final response = await (await client.getUrl(
        server
            .resolve('getAllocationProfile')
            .replace(queryParameters: {'isolateId': isolate, 'gc': 'true'}),
      )).close();
      final result =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (result.containsKey('error')) throw StateError('$result');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (predicate()) return;
    }
    throw StateError('GC did not settle decrypted byte owners: ${owners()}');
  }

  try {
    if (owners() != 0)
      throw StateError('Probe must start with no external owners');
    final alive = library
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('ct_test_message_observer_alive');
    final free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('ct_test_message_observer_free');
    final held = _makeDeferred(true, library, runtime);
    final abandonedInput = _makeDeferred(false, library, runtime);
    try {
      await collectUntil(
        () =>
            abandonedInput.weak.target == null &&
            alive(abandonedInput.observer) == 0,
      );
      if (held.weak.target == null || alive(held.observer) != 1) {
        throw StateError('Retained deferred input was released too early');
      }
      held.incoming = null;
      await collectUntil(
        () => held.weak.target == null && alive(held.observer) == 0,
      );
      stdout.writeln(
        'native-deferred-input-gc: retained then released unexported handles',
      );
    } finally {
      free(held.observer);
      free(abandonedInput.observer);
    }
    for (final aes in [false, true]) {
      final retained = _makeSurvivor(aes, library, runtime);
      final abandoned = _makeSurvivor(aes, library, runtime)..view = null;
      if (owners() != 2)
        throw StateError('Probe must create two plaintext owners');
      await collectUntil(
        () =>
            owners() == 1 &&
            retained.incoming.target == null &&
            retained.provider.target == null &&
            abandoned.incoming.target == null &&
            abandoned.provider.target == null,
      );
      _checkView(retained);
      retained.view = null;
      // Check the live view inside a separate function so this stack does not
      // retain it across the final collection.
      await collectUntil(() => owners() == 0);
      stdout.writeln(
        'native-deferred-e2ee-gc: ${aes ? 'aes256gcm' : 'xsalsa20poly1305'} derived read-only view retained then released storage',
      );
    }
  } finally {
    client.close(force: true);
    NativeClientRuntime.shutdownShared();
  }
}
