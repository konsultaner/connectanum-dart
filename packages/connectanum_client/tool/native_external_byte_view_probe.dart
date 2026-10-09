// Linux/glibc diagnostic for Connectanum-owned bounded native views.
// Checks real socket backpressure and native frees; it does not measure totals.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'sdk_socket_copy_probe.dart' as probe;

final watchFree = DynamicLibrary.process()
    .lookupFunction<Void Function(UintPtr), void Function(int)>(
      'probe_watch_free',
    );
final nativeFrees = DynamicLibrary.process()
    .lookupFunction<UintPtr Function(), int Function()>('probe_free_count');
final freeReuseControl = DynamicLibrary.process()
    .lookupFunction<Int Function(), int Function()>('probe_free_reuse_control');
var allocationPressure = false;
var pressureSeed = 0;
var pressureChecksum = 0;

@pragma('vm:never-inline')
void pressure() {
  final seed = pressureSeed++;
  final blocks = List.generate(
    16,
    (i) => Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, (seed + i) & 255),
  );
  for (final block in blocks) {
    pressureChecksum ^= block[seed % block.length];
  }
}

final class QueuedOwner {
  QueuedOwner(this.root, this.parent, this.address, this.offset, this.nested);
  final WeakReference<Uint8List> root;
  final WeakReference<Uint8List> parent;
  final int address;
  final int offset;
  final bool nested;
}

@pragma('vm:never-inline')
QueuedOwner queue(Socket socket, bool readonly, bool nested) {
  const length = 16 * 1024 * 1024;
  final root = allocateNativeExternalBytes(length + 128);
  for (var i = 0; i < root.length; i++) {
    root[i] = (i * 37 + 11) & 255;
  }
  final pointer = nativeExternalByteSlice(root)!.pointer.address;
  watchFree(pointer);
  final anchor = Object();
  retainNativeExternalBytes(anchor, root);
  var source = Uint8List.sublistView(root, 32, 32 + length + (nested ? 64 : 0));
  if (readonly) source = source.asUnmodifiableView();
  final parent = nativeExternalByteView(source, anchor: anchor)!;
  Uint8List bytes = parent;
  if (nested) {
    final childAnchor = Object();
    retainNativeExternalBytes(childAnchor, parent);
    var child = Uint8List.sublistView(parent, 13, 13 + length);
    if (readonly) child = child.asUnmodifiableView();
    bytes = nativeExternalByteView(child, anchor: childAnchor)!;
  }
  probe.check(
    bytes.offsetInBytes == 0 && bytes.buffer.lengthInBytes == length,
    'full bounded backing storage',
  );
  socket.add(bytes);
  final offset = nested ? 45 : 32;
  return QueuedOwner(
    WeakReference(root),
    WeakReference(parent),
    pointer + offset,
    offset,
    nested,
  );
}

@pragma('vm:never-inline')
bool rootAlive(QueuedOwner owner) => owner.root.target != null;

@pragma('vm:never-inline')
bool parentAlive(QueuedOwner owner) => owner.parent.target != null;

Future<void> collect(HttpClient client) async {
  if (allocationPressure) {
    pressure();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return;
  }
  final service = await Service.getInfo();
  final uri = service.serverUri!
      .resolve('getAllocationProfile')
      .replace(
        queryParameters: {
          'isolateId': Service.getIsolateId(Isolate.current)!,
          'gc': 'true',
        },
      );
  final response = await (await client.getUrl(uri)).close();
  final result = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
  probe.check(!result.containsKey('error'), 'actual VM collection succeeds');
  await Future<void>.delayed(const Duration(milliseconds: 25));
}

Future<void> run(bool readonly, bool nested) async {
  const length = 16 * 1024 * 1024;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final ready = Completer<void>();
  final received = Completer<void>();
  final gc = HttpClient();
  late QueuedOwner owner;
  Socket? peer;
  Socket? client;
  StreamSubscription<Uint8List>? receiver;
  var receivedBytes = 0;
  var equal = true;
  final connection = server.listen((socket) {
    peer = socket;
    receiver = socket.listen(
      (data) {
        for (var i = 0; i < data.length; i++) {
          if (data[i] !=
              (((receivedBytes + i + owner.offset) * 37 + 11) & 255)) {
            equal = false;
          }
        }
        receivedBytes += data.length;
      },
      onError: (Object error, StackTrace stack) {
        if (!received.isCompleted) received.completeError(error, stack);
      },
      onDone: () {
        socket.destroy();
        if (!received.isCompleted) received.complete();
      },
    );
    receiver!.pause();
    ready.complete();
  });
  try {
    probe.reset(server.port, 0, 0);
    client = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    await ready.future.timeout(const Duration(seconds: 10));
    owner = queue(client, readonly, nested);
    var flushed = false;
    final flush = client.flush().then((_) {
      flushed = true;
    });
    var eagain = false;
    for (var attempt = 0; attempt < 200; attempt++) {
      eagain = List.generate(
        probe.count(),
        (i) => probe.accepted(i) < 0 && probe.error(i) == 11,
      ).any((v) => v);
      if (eagain) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    probe.check(eagain && !flushed, 'genuine EAGAIN and pending flush');
    for (var i = 0; i < 8; i++) {
      await collect(gc);
    }
    probe.check(
      !flushed && rootAlive(owner) && nativeFrees() == 0,
      'queued bounded view retains original allocation through actual GC',
    );
    if (nested) {
      probe.check(!parentAlive(owner), 'derived view outlives parent facade');
    }
    final before = probe.count();
    var acceptedBefore = 0;
    for (var i = 0; i < before; i++) {
      if (probe.accepted(i) > 0) acceptedBefore += probe.accepted(i);
    }
    probe.check(
      acceptedBefore > 0 && acceptedBefore < length,
      'partial acceptance before reader resumption',
    );
    receiver!.resume();
    await flush.timeout(const Duration(seconds: 30));
    await client.close();
    await received.future.timeout(const Duration(seconds: 30));
    probe.check(receivedBytes == length && equal, 'exact received payload');
    probe.check(probe.overflow() == 0, 'all write observations retained');
    var offset = 0;
    var after = 0;
    var eagainCount = 0;
    final observations = <Map<String, int>>[];
    for (var i = 0; i < probe.count(); i++) {
      final accepted = probe.accepted(i);
      probe.check(
        probe.address(i) == owner.address + offset,
        'original allocation at every syscall, including retries',
      );
      observations.add({
        'address': probe.address(i),
        'requested': probe.requested(i),
        'accepted': accepted,
        'errno': probe.error(i),
        'offset': offset,
      });
      if (accepted > 0) {
        offset += accepted;
        if (i >= before) after += accepted;
      }
      if (accepted < 0 && probe.error(i) == 11) eagainCount++;
    }
    probe.check(
      offset == length && after > 0,
      'complete resumption accounting',
    );
    for (var i = 0; i < 40 && (rootAlive(owner) || nativeFrees() == 0); i++) {
      await collect(gc);
    }
    probe.check(
      !rootAlive(owner) && nativeFrees() == 1,
      'original allocation released after final queued view '
      '(readonly=$readonly nested=$nested '
      'rootAlive=${rootAlive(owner)} nativeFrees=${nativeFrees()})',
    );
    final releases = nativeFrees();
    watchFree(
      0,
    ); // End address tracking before a later allocation can reuse it.
    print(
      jsonEncode({
        'readonlySource': readonly,
        'nestedSource': nested,
        'inputBytes': length,
        'nativeInputAddress': owner.address,
        'offsetInOriginalAllocation': owner.offset,
        'kernelEagainCount': eagainCount,
        'flushWasPending': true,
        'acceptedBeforeReaderResume': acceptedBefore,
        'acceptedAfterReaderResume': after,
        'parentFacadeCollectedBeforeDrain': nested && !parentAlive(owner),
        'retainedThroughActualGc': true,
        'collectionMethod': allocationPressure
            ? 'allocation-pressure'
            : 'vm-service',
        'nativeFreeCount': releases,
        'originalStorageAtEveryWrite': true,
        'payloadEqual': true,
        'observations': observations,
      }),
    );
  } finally {
    probe.reset(0, 0, 0);
    watchFree(0);
    client?.destroy();
    peer?.destroy();
    await receiver?.cancel();
    await connection.cancel();
    await server.close();
    gc.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  allocationPressure = args.contains('--allocation-pressure');
  probe.check(Platform.isLinux, 'Linux-only diagnostic');
  probe.check(
    allocationPressure || (await Service.getInfo()).serverUri != null,
    'requires --enable-vm-service=0 --disable-service-auth-codes',
  );
  final control = malloc<Uint8>(64);
  watchFree(control.address);
  probe.check(nativeFrees() == 0, 'native-free control starts at zero');
  malloc.free(control);
  probe.check(
    nativeFrees() == 1,
    'independent allocation/free positive control',
  );
  watchFree(0);
  probe.check(
    freeReuseControl() == 1,
    'native allocation address-reuse control',
  );
  print(
    jsonEncode({
      'nativeFreePositiveControl': true,
      'nativeFreeAddressReuseControl': true,
      'collectionMethod': allocationPressure
          ? 'allocation-pressure'
          : 'vm-service',
    }),
  );
  for (final readonly in [false, true]) {
    for (final nested in [false, true]) {
      await run(readonly, nested);
    }
  }
  if (allocationPressure) {
    print(jsonEncode({'allocationPressureChecksum': pressureChecksum}));
  }
}
