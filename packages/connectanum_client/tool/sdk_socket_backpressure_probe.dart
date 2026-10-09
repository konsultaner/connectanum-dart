// Linux diagnostic for genuine kernel backpressure and Dart socket resumption.
// Run with tool/sdk_socket_copy_probe.c preloaded; this does not measure TLS.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'sdk_socket_copy_probe.dart' as probe;

Future<void> runBackpressure(String shape) async {
  const length = 16 * 1024 * 1024;
  final partial = shape.contains('partial');
  final start = partial ? 32 : 0;
  final backingLength = partial ? length + 64 : length;
  final pointer = calloc<Uint8>(backingLength);
  final storage = pointer.asTypedList(backingLength);
  for (var i = 0; i < storage.length; i++) {
    storage[i] = (i * 37 + 11) & 255;
  }
  Uint8List view = partial
      ? Uint8List.sublistView(storage, start, start + length)
      : storage;
  if (shape.contains('readonly')) view = view.asUnmodifiableView();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final peerReady = Completer<void>();
  final received = Completer<void>();
  Socket? peer;
  StreamSubscription<Uint8List>? receiver;
  var receivedBytes = 0;
  var payloadMatches = true;
  final connection = server.listen((socket) {
    peer = socket;
    receiver = socket.listen(
      (bytes) {
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] != (((receivedBytes + i + start) * 37 + 11) & 255)) {
            payloadMatches = false;
          }
        }
        receivedBytes += bytes.length;
      },
      onError: (Object e, StackTrace s) {
        if (!received.isCompleted) received.completeError(e, s);
      },
      onDone: () {
        socket.destroy();
        if (!received.isCompleted) received.complete();
      },
    );
    receiver!.pause();
    peerReady.complete();
  });
  Socket? client;
  try {
    probe.reset(server.port, 0, 0);
    client = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    await peerReady.future.timeout(const Duration(seconds: 10));
    client.add(view);
    var flushFinished = false;
    final flush = client.flush().then((_) {
      flushFinished = true;
    });
    var sawEagain = false;
    for (var attempt = 0; attempt < 200; attempt++) {
      sawEagain = List.generate(
        probe.count(),
        (i) => probe.accepted(i) < 0 && probe.error(i) == 11,
      ).any((value) => value);
      if (sawEagain) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    probe.check(
      sawEagain,
      'kernel EAGAIN observed while peer reads are paused',
    );
    probe.check(
      !flushFinished,
      'flush remains pending at backpressure boundary',
    );
    final beforeResumeWrites = probe.count();
    var beforeResumeAccepted = 0;
    for (var i = 0; i < beforeResumeWrites; i++) {
      if (probe.accepted(i) > 0) beforeResumeAccepted += probe.accepted(i);
    }
    probe.check(
      beforeResumeAccepted > 0 && beforeResumeAccepted < length,
      'partial kernel acceptance before Dart resumes',
    );
    receiver!.resume();
    await flush.timeout(const Duration(seconds: 30));
    await client.close();
    await received.future.timeout(const Duration(seconds: 30));
    probe.check(
      receivedBytes == length && payloadMatches,
      'exact received payload',
    );
    probe.check(probe.overflow() == 0, 'no missing observations');
    var inputOffset = 0;
    var mismatches = 0;
    var eagain = 0;
    var acceptedAfterResume = 0;
    final observations = <Map<String, int>>[];
    for (var i = 0; i < probe.count(); i++) {
      final n = probe.accepted(i);
      final same = probe.address(i) == pointer.address + start + inputOffset;
      if (!same) mismatches++;
      observations.add({
        'address': probe.address(i),
        'requested': probe.requested(i),
        'accepted': n,
        'errno': probe.error(i),
        'inputOffset': inputOffset,
        'matchesInput': same ? 1 : 0,
      });
      if (n > 0) {
        inputOffset += n;
        if (i >= beforeResumeWrites) acceptedAfterResume += n;
      }
      if (n < 0 && probe.error(i) == 11) eagain++;
    }
    probe.check(inputOffset == length, 'all accepted bytes accounted');
    probe.check(
      acceptedAfterResume > 0,
      'writes resume after reader is unpaused',
    );
    probe.check(
      partial ? mismatches == probe.count() : mismatches == 0,
      'SDK storage identity through event-loop resumption',
    );
    print(
      jsonEncode({
        'shape': shape,
        'inputBytes': length,
        'backingBytes': view.buffer.lengthInBytes,
        'viewOffset': view.offsetInBytes,
        'nativeInputAddress': pointer.address + start,
        'kernelEagainCount': eagain,
        'writesBeforeReaderResume': beforeResumeWrites,
        'acceptedBeforeReaderResume': beforeResumeAccepted,
        'acceptedAfterReaderResume': acceptedAfterResume,
        'flushWasPending': true,
        'payloadEqual': true,
        'originalStorageAtEveryWrite': mismatches == 0,
        'observations': observations,
      }),
    );
  } finally {
    probe.reset(0, 0, 0);
    client?.destroy();
    peer?.destroy();
    await receiver?.cancel();
    await connection.cancel();
    await server.close();
    calloc.free(pointer);
  }
}

Future<void> main() async {
  if (!Platform.isLinux) throw UnsupportedError('Linux only');
  for (final shape in [
    'full',
    'full-readonly',
    'partial',
    'partial-readonly',
  ]) {
    await runBackpressure(shape);
  }
}
