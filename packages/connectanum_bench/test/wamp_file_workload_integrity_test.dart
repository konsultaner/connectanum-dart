@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final length in [
    0,
    1,
    255,
    256,
    257,
    1048575,
    1048576,
    1048577,
    2097169,
  ]) {
    test(
      'file workload preserves $length bytes and deletes its payload',
      () async {
        final receiver = _FileSession(length);
        final session = _FileSession(length, receiver: receiver);
        var opened = 0;
        final outerStart = DateTime.now();
        final samples = await WampWorkloadRunner(
          sessionFactory: (_) async => opened++ == 0 ? session : receiver,
        ).run(_scenario(length));
        final outerMs =
            DateTime.now().difference(outerStart).inMicroseconds / 1000;
        expect(samples, hasLength(2));
        expect(samples.map((sample) => sample.requestBytes), [length, length]);
        expect(samples.map((sample) => sample.responseBytes), [0, 0]);
        expect(
          samples.map((sample) => sample.iteration),
          unorderedEquals([0, 1]),
        );
        expect(session.transferDurations, hasLength(2));
        for (final sample in samples) {
          expect(
            sample.latencyMs,
            greaterThanOrEqualTo(session.transferDurations[sample.iteration]!),
          );
          expect(sample.latencyMs, lessThanOrEqualTo(outerMs));
        }
        expect(session.transfers, 2);
        expect(opened, 2);
        expect(session.closeCount, 1);
        expect(receiver.closeCount, 1);
        expect(session.cancelCount, 0);
        expect(receiver.cancelCount, 1);
        expect(receiver.transfers, 0);
        expect(receiver.registration, (
          2,
          257,
          const Duration(milliseconds: 3333),
        ));
        expect(session.paths.toSet(), hasLength(1));
        for (final path in session.paths) {
          expect(File(path).existsSync(), isFalse);
          expect(File(path).parent.existsSync(), isFalse);
        }
      },
    );
  }
  test(
    'failed file transfer preserves the error and removes payload and registration',
    () async {
      final error = StateError('injected file transfer rejection');
      final receiver = _FileSession(257);
      final session = _FileSession(257, error: error, receiver: receiver);
      var opened = 0;
      await expectLater(
        WampWorkloadRunner(
          sessionFactory: (_) async => opened++ == 0 ? session : receiver,
        ).run(
          _scenario(257, iterations: 1),
        ),
        throwsA(same(error)),
      );
      expect(session.transfers, 1);
      expect(session.paths, hasLength(1));
      expect(opened, 2);
      expect(session.closeCount, 1);
      expect(receiver.closeCount, 1);
      expect(session.cancelCount, 0);
      expect(receiver.cancelCount, 1);
      expect(receiver.transfers, 0);
      expect(File(session.paths.single).existsSync(), isFalse);
      expect(File(session.paths.single).parent.existsSync(), isFalse);
    },
  );
}

WampScenario _scenario(int length, {int iterations = 2}) => WampScenario(
  transport: WampTransport.rawsocket,
  serializer: WampSerializer.cbor,
  mode: WampMode.fileTransfer,
  uri: 'bench.file_integrity',
  iterations: iterations,
  concurrency: 1,
  inFlightPerSession: 2,
  payloadBytes: length,
  fileChunkBytes: 257,
  eventTimeoutMs: 3333,
);

class _FileSession implements WampSession, WampFileSession {
  _FileSession(this.length, {this.error, this.receiver});
  final int length;
  final Object? error;
  final _FileSession? receiver;
  final paths = <String>[];
  final transferDurations = <int, double>{};
  int transfers = 0;
  int closeCount = 0;
  int cancelCount = 0;
  (int, int, Duration)? registration;
  String? registeredProcedure;

  @override
  int get id => 11;
  @override
  Future<dynamic> get onDisconnect => Completer<void>().future;
  @override
  Future<void> close() async => closeCount++;

  @override
  Future<WampRegistration> registerFileReceiver(
    String procedure, {
    required int maxConcurrentTransfers,
    required int maxChunkSize,
    required Duration idleTimeout,
  }) async {
    registeredProcedure = procedure;
    registration = (maxConcurrentTransfers, maxChunkSize, idleTimeout);
    return WampRegistration(cancel: () async => cancelCount++);
  }

  @override
  Future<void> sendFile(
    String procedure,
    client.WampFileSource source, {
    required int chunkSize,
    required Duration timeout,
    core.CallOptions? options,
  }) async {
    final transfer = transfers++;
    final innerStart = DateTime.now();
    expect(receiver, isNotNull);
    expect(procedure, receiver!.registeredProcedure);
    expect(chunkSize, 257);
    expect(timeout, const Duration(milliseconds: 3333));
    expect(options, isNull);
    expect(source.name, 'payload.bin');
    expect(source.contentType, 'application/octet-stream');
    expect(source.length, length);
    expect(source.nativePath, isNotNull);
    final path = source.nativePath!;
    paths.add(path);
    expect(File(path).lengthSync(), length);
    var offset = 0;
    var firstMismatch = -1;
    await for (final chunk in source.openRead()) {
      for (final byte in chunk) {
        if (firstMismatch < 0 && byte != offset % 256) firstMismatch = offset;
        offset++;
      }
    }
    expect(offset, length);
    expect(
      firstMismatch,
      -1,
      reason: 'The payload must repeat bytes 0 through 255.',
    );
    if (error != null) throw error!;
    transferDurations[transfer] =
        DateTime.now().difference(innerStart).inMicroseconds / 1000;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
