// Run on Linux with tool/sdk_socket_copy_probe.c preloaded.
// This verifies libc write pointers, not total SDK/TLS copy volume.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final library = DynamicLibrary.process();
final reset = library
    .lookupFunction<
      Void Function(Uint16, UintPtr, Int32),
      void Function(int, int, int)
    >('probe_reset');
final count = library.lookupFunction<UintPtr Function(), int Function()>(
  'probe_count',
);
final overflow = library.lookupFunction<Int32 Function(), int Function()>(
  'probe_overflow',
);
final address = library
    .lookupFunction<UintPtr Function(UintPtr), int Function(int)>(
      'probe_address',
    );
final requested = library
    .lookupFunction<UintPtr Function(UintPtr), int Function(int)>(
      'probe_requested',
    );
final submitted = library
    .lookupFunction<UintPtr Function(UintPtr), int Function(int)>(
      'probe_submitted',
    );
final accepted = library
    .lookupFunction<IntPtr Function(UintPtr), int Function(int)>(
      'probe_accepted',
    );
final error = library
    .lookupFunction<Int32 Function(UintPtr), int Function(int)>('probe_error');
final control = library
    .lookupFunction<
      IntPtr Function(Uint16, Pointer<Uint8>, UintPtr),
      int Function(int, Pointer<Uint8>, int)
    >('probe_control');

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> run(
  String shape,
  bool retries, {
  bool direct = false,
  bool ignoredPort = false,
}) async {
  final pointer = calloc<Uint8>(256);
  final all = pointer.asTypedList(256);
  for (var i = 0; i < all.length; i++) {
    all[i] = (i * 37 + 11) & 255;
  }
  final partial = shape.contains('partial');
  final start = partial ? 32 : 0;
  final length = direct
      ? 9
      : partial
      ? 96
      : 256;
  Uint8List view = direct
      ? Uint8List.sublistView(all, 0, 9)
      : partial
      ? Uint8List.sublistView(all, start, start + length)
      : all;
  if (shape.contains('readonly')) view = view.asUnmodifiableView();
  final expected = List<int>.of(view);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final received = Completer<List<int>>();
  final connection = server.listen((socket) {
    final bytes = <int>[];
    socket.listen(
      bytes.addAll,
      onError: received.completeError,
      onDone: () {
        socket.destroy();
        if (!received.isCompleted) received.complete(bytes);
      },
    );
  });
  Socket? client;
  final other = ignoredPort
      ? await ServerSocket.bind(InternetAddress.loopbackIPv4, 0)
      : null;
  try {
    reset(other?.port ?? server.port, retries ? 31 : 0, retries ? 1 : 0);
    if (direct) {
      check(control(server.port, pointer, length) == length, 'C control write');
    } else {
      client = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      client.add(view);
      await client.flush();
      await client.close();
    }
    final bytes = await received.future.timeout(const Duration(seconds: 10));
    check(bytes.length == expected.length, 'receiver length');
    check(
      List.generate(
        bytes.length,
        (i) => bytes[i] == expected[i],
      ).every((v) => v),
      'receiver payload',
    );
    if (ignoredPort) {
      check(
        count() == 0 && overflow() == 0,
        'unselected port must not be observed',
      );
      print(
        jsonEncode({
          'shape': shape,
          'ignoredPortControl': true,
          'payloadEqual': true,
          'writes': 0,
        }),
      );
      return;
    }
    check(count() > 0 && overflow() == 0, 'interposition observed every write');
    final rows = <Map<String, int>>[];
    var offset = 0;
    var mismatches = 0;
    var interrupted = 0;
    for (var i = 0; i < count(); i++) {
      final n = accepted(i);
      final same = address(i) == pointer.address + start + offset;
      if (!same) mismatches++;
      rows.add({
        'address': address(i),
        'requested': requested(i),
        'submitted': submitted(i),
        'accepted': n,
        'errno': error(i),
        'inputOffset': offset,
        'matchesInput': same ? 1 : 0,
      });
      if (n > 0) offset += n;
      if (n < 0 && error(i) == 4) interrupted++;
    }
    check(offset == length, 'all accepted bytes accounted');
    check(
      partial && !direct ? mismatches == count() : mismatches == 0,
      'SDK address reuse expectation',
    );
    if (retries) {
      check(
        interrupted == 1 && count() >= 5,
        'real short-write and EINTR retries',
      );
    }
    print(
      jsonEncode({
        'shape': shape,
        'forcedRetries': retries,
        'directControl': direct,
        'nativeInputAddress': pointer.address + start,
        'inputBytes': length,
        'backingBytes': view.buffer.lengthInBytes,
        'viewOffset': view.offsetInBytes,
        'payloadEqual': true,
        'observations': rows,
      }),
    );
  } finally {
    reset(0, 0, 0);
    client?.destroy();
    await connection.cancel();
    await server.close();
    await other?.close();
    calloc.free(pointer);
  }
}

Future<void> main() async {
  if (!Platform.isLinux) {
    throw UnsupportedError(
      'The socket write probe requires Linux and LD_PRELOAD',
    );
  }
  print(
    jsonEncode({
      'sdk': Platform.version,
      'platform': Platform.operatingSystem,
      'scope': 'libc write arguments; no SDK/TLS total-copy claim',
    }),
  );
  await run('control', false, direct: true);
  await run('ignored-port-control', false, direct: true, ignoredPort: true);
  for (final retries in [false, true]) {
    for (final shape in [
      'full',
      'full-readonly',
      'partial',
      'partial-readonly',
    ]) {
      await run(shape, retries);
    }
  }
}
