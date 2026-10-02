@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final (iterations, limit) in [(1, 4), (5, 1), (5, 2), (7, 3)]) {
    test(
      'schedules $iterations file transfers with at most $limit active',
      () async {
        final receiver = _ScheduledFileSession(iterations, limit);
        final sender = _ScheduledFileSession(iterations, limit);
        var opened = 0;
        final samples =
            await WampWorkloadRunner(
              sessionFactory: (_) async => opened++ == 0 ? sender : receiver,
            ).run(
              WampScenario(
                transport: WampTransport.rawsocket,
                serializer: WampSerializer.cbor,
                mode: WampMode.fileTransfer,
                uri: 'bench.file_schedule',
                iterations: iterations,
                concurrency: 1,
                inFlightPerSession: limit,
                payloadBytes: 257,
                fileChunkBytes: 256,
                eventTimeoutMs: 3333,
              ),
            );

        expect(samples, hasLength(iterations));
        expect(samples.map((sample) => sample.iteration).toSet(), {
          for (var i = 0; i < iterations; i++) i,
        });
        expect(samples.every((sample) => sample.worker == 0), isTrue);
        expect(samples.every((sample) => sample.requestBytes == 257), isTrue);
        expect(samples.every((sample) => sample.responseBytes == 0), isTrue);
        expect(sender.started, iterations);
        expect(sender.completed, iterations);
        expect(sender.active, 0);
        expect(sender.peak, limit > iterations ? iterations : limit);
        expect(sender.closeCount, 1);
        expect(receiver.closeCount, 1);
        expect(receiver.started, 0);
        expect(receiver.cancelCount, 1);
        expect(sender.cancelCount, 0);
        expect(receiver.receiverLimit, limit);
        expect(opened, 2);
      },
    );
  }
}

class _ScheduledFileSession implements WampSession, WampFileSession {
  _ScheduledFileSession(this.iterations, this.limit);
  final int iterations;
  final int limit;
  final pending = <Completer<void>>[];
  int started = 0;
  int completed = 0;
  int active = 0;
  int peak = 0;
  int closeCount = 0;
  int cancelCount = 0;
  int? receiverLimit;

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
    receiverLimit = maxConcurrentTransfers;
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
    started++;
    active++;
    if (active > peak) peak = active;
    try {
      expect(started, lessThanOrEqualTo(iterations));
      expect(active, lessThanOrEqualTo(limit));
      final done = Completer<void>();
      pending.add(done);
      // Release full batches in reverse order, plus the final partial batch.
      // The Futures settle asynchronously; completing a batch is not a free slot
      // until each sendFile Future actually returns.
      if (pending.length == limit || started == iterations) {
        final batch = pending.toList();
        pending.clear();
        for (final transfer in batch.reversed) {
          transfer.complete();
        }
      }
      await done.future;
      completed++;
    } finally {
      active--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
