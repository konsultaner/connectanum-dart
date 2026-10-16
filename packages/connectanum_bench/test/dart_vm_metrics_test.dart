import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('selectDartVmMetricIsolateIds', () {
    test(
      'falls back to a renamed application isolate, never a system isolate',
      () {
        expect(
          selectDartVmMetricIsolateIds([
            IsolateRef(
              id: 'service',
              name: 'vm-service',
              isSystemIsolate: true,
            ),
            IsolateRef(id: 'worker', name: 'renamed-main'),
          ], allIsolates: false),
          ['worker'],
        );
      },
    );

    test(
      'missing application IDs and system-only processes have no fallback',
      () {
        for (final isolates in <List<IsolateRef>>[
          [],
          [IsolateRef(name: 'renamed-main')],
          [
            IsolateRef(
              id: 'service',
              name: 'vm-service',
              isSystemIsolate: true,
            ),
          ],
        ]) {
          for (final allIsolates in [false, true]) {
            expect(
              selectDartVmMetricIsolateIds(isolates, allIsolates: allIsolates),
              isEmpty,
            );
          }
        }
      },
    );

    test('profiles all application isolates and skips VM service isolates', () {
      final isolates = [
        IsolateRef(id: 'worker-2', name: 'router-worker-2'),
        IsolateRef(id: 'service', name: 'vm-service', isSystemIsolate: true),
        IsolateRef(id: 'main', name: 'main'),
        IsolateRef(id: 'worker-1', name: 'router-worker-1'),
      ];

      expect(
        selectDartVmMetricIsolateIds(isolates, allIsolates: true),
        ['main', 'worker-1', 'worker-2'],
      );
    });

    test('keeps client worker profiling scoped to its main isolate', () {
      final isolates = [
        IsolateRef(id: 'worker', name: 'worker'),
        IsolateRef(id: 'main', name: 'main'),
      ];

      expect(
        selectDartVmMetricIsolateIds(isolates, allIsolates: false),
        ['main'],
      );
    });
  });

  test('metric windows reject isolate creation or shutdown', () {
    expect(
      () => requireStableDartVmMetricIsolates(
        ['main', 'worker-1'],
        ['main', 'worker-1', 'worker-2'],
      ),
      throwsStateError,
    );
    expect(
      () => requireStableDartVmMetricIsolates(
        ['main', 'worker-1'],
        ['main'],
      ),
      throwsStateError,
    );
  });

  test(
    'RSS stop awaits an active read and samples the same end boundary',
    () async {
      final activeRead = Completer<int?>();
      var readCount = 0;
      final sampler = DartVmMetricsRssSampler(
        pid,
        readRssBytes: () {
          readCount++;
          return readCount == 1 ? activeRead.future : Future<int?>.value(4096);
        },
      );

      expect(readCount, 1);
      final stop = sampler.stop();
      expect(identical(stop, sampler.stop()), isTrue);
      var completed = false;
      unawaited(stop.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      activeRead.complete(8192);
      final snapshot = await stop;

      expect(readCount, 2);
      expect(snapshot.currentRssBytes, 4096);
      expect(snapshot.peakRssBytes, 8192);
    },
  );

  test('RSS joint endpoint preserves the two observed fields', () async {
    for (final maximum in [339804160, 350000000]) {
      final active = Completer<int?>();
      final reads = <String>[];
      final sampler = DartVmMetricsRssSampler(
        pid,
        readRssBytes: () {
          reads.add('live');
          return active.future;
        },
        readFinalRss: () async {
          reads.add('endpoint');
          return (
            currentRssBytes: 339804160,
            lifetimeMaxRssBytes: maximum,
          );
        },
        readMaxRssBytes: () => throw StateError('Unexpected separate read'),
      );
      final stop = sampler.stop();
      expect(identical(stop, sampler.stop()), isTrue);
      expect(reads, ['live']);
      active.complete(339664896);
      final result = await stop;
      expect(reads, ['live', 'endpoint']);
      expect(result.currentRssBytes, 339804160);
      expect(result.peakRssBytes, 339804160);
      expect(result.lifetimeMaxRssBytes, maximum);
      expect(result.lifetimeMaxReadAttemptsBytes, [maximum]);
    }
  });

  test('RSS joint endpoint still checks the historical sampled peak', () async {
    final result = await DartVmMetricsRssSampler(
      pid,
      readRssBytes: () async => 32768,
      readFinalRss: () async => (
        currentRssBytes: 8192,
        lifetimeMaxRssBytes: 16384,
      ),
      readMaxRssBytes: () async => 16384,
    ).stop();
    expect(result.currentRssBytes, 8192);
    expect(result.peakRssBytes, 32768);
    expect(result.lifetimeMaxRssBytes, isNull);
    expect(result.lifetimeMaxReadAttemptsBytes, [16384, 16384, 16384]);
  });

  test('RSS explicit endpoint works with default live readers', () async {
    final result = await DartVmMetricsRssSampler(
      999999999,
      readFinalRss: () async => (
        currentRssBytes: 4096,
        lifetimeMaxRssBytes: 8192,
      ),
    ).stop();
    expect(result.currentRssBytes, 4096);
    expect(result.peakRssBytes, 4096);
    expect(result.lifetimeMaxRssBytes, 8192);
    expect(result.lifetimeMaxReadAttemptsBytes, [8192]);
  });

  test(
    'RSS joint endpoint retries only actual contradictory HWM values',
    () async {
      final result = await DartVmMetricsRssSampler(
        pid,
        readRssBytes: () async => 8192,
        readFinalRss: () async => (
          currentRssBytes: 4096,
          lifetimeMaxRssBytes: 4096,
        ),
        readMaxRssBytes: () async => 16384,
      ).stop();
      expect(result.currentRssBytes, 4096);
      expect(result.peakRssBytes, 8192);
      expect(result.lifetimeMaxRssBytes, 16384);
      expect(result.lifetimeMaxReadAttemptsBytes, [4096, 16384]);
    },
  );

  for (final current in <int?>[null, 0, -1, 9007199254740992]) {
    test(
      'RSS joint invalid final current stays unavailable: $current',
      () async {
        final result = await DartVmMetricsRssSampler(
          pid,
          readRssBytes: () async => 4096,
          readFinalRss: () async => (
            currentRssBytes: current,
            lifetimeMaxRssBytes: 8192,
          ),
          readMaxRssBytes: () => throw StateError('Unexpected separate read'),
        ).stop();
        expect(result.currentRssBytes, isNull);
        expect(result.peakRssBytes, 4096);
        expect(result.lifetimeMaxRssBytes, isNull);
        expect(result.lifetimeMaxReadAttemptsBytes, [8192]);
      },
    );
  }

  for (final maximum in <int?>[null, 0, -1, 4096, 9007199254740992]) {
    test('RSS joint invalid final HWM stays unavailable: $maximum', () async {
      final result = await DartVmMetricsRssSampler(
        pid,
        readRssBytes: () async => 4096,
        readFinalRss: () async => (
          currentRssBytes: 8192,
          lifetimeMaxRssBytes: maximum,
        ),
        readMaxRssBytes: () async => maximum,
      ).stop();
      expect(result.currentRssBytes, 8192);
      expect(result.peakRssBytes, 8192);
      expect(result.lifetimeMaxRssBytes, isNull);
      expect(
        result.lifetimeMaxReadAttemptsBytes,
        maximum == 4096 ? [4096, 4096, 4096] : [maximum],
      );
    });
  }

  test('RSS failed joint endpoint does not reuse a live observation', () async {
    final result = await DartVmMetricsRssSampler(
      pid,
      readRssBytes: () async => 4096,
      readFinalRss: () => throw const FileSystemException('gone'),
      readMaxRssBytes: () => throw StateError('Unexpected separate read'),
    ).stop();
    expect(result.currentRssBytes, isNull);
    expect(result.peakRssBytes, 4096);
    expect(result.lifetimeMaxRssBytes, isNull);
    expect(result.lifetimeMaxReadAttemptsBytes, [null]);
  });

  test('RSS lifetime maximum is read after the final live boundary', () async {
    final reads = <String>[];
    final active = Completer<int?>();
    var calls = 0;
    final sampler = DartVmMetricsRssSampler(
      pid,
      readRssBytes: () {
        calls++;
        reads.add('live$calls');
        return calls == 1 ? active.future : Future.value(16384);
      },
      readMaxRssBytes: () async {
        reads.add('maximum');
        return 32768;
      },
    );
    final stop = sampler.stop();
    expect(identical(stop, sampler.stop()), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(reads, ['live1']);
    active.complete(8192);
    final result = await stop;
    expect(reads, ['live1', 'live2', 'maximum']);
    expect(result.currentRssBytes, 16384);
    expect(result.peakRssBytes, 16384);
    expect(result.lifetimeMaxRssBytes, 32768);
  });

  test(
    'RSS rereads a transiently lagging lifetime maximum without inference',
    () async {
      var reads = 0;
      final sampler = DartVmMetricsRssSampler(
        pid,
        readRssBytes: () async => 8192,
        readMaxRssBytes: () async => ++reads == 1 ? 4096 : 16384,
      );
      final result = await sampler.stop();
      expect(reads, 2);
      expect(result.currentRssBytes, 8192);
      expect(result.peakRssBytes, 8192);
      expect(result.lifetimeMaxRssBytes, 16384);
      expect(result.lifetimeMaxReadAttemptsBytes, [4096, 16384]);
    },
  );

  test(
    'RSS accepts an equal maximum and does not retry missing endpoints',
    () async {
      for (final missing in [false, true]) {
        var reads = 0;
        final sampler = DartVmMetricsRssSampler(
          pid,
          readRssBytes: () async => 8192,
          readMaxRssBytes: () async {
            reads++;
            if (missing) throw const FileSystemException('gone');
            return 8192;
          },
        );
        final result = await sampler.stop();
        expect(reads, 1);
        expect(result.lifetimeMaxRssBytes, missing ? isNull : 8192);
        expect(result.lifetimeMaxReadAttemptsBytes, missing ? [null] : [8192]);
      }
    },
  );

  test(
    'RSS bounds contradictory lifetime rereads and never infers a maximum',
    () async {
      var reads = 0;
      final sampler = DartVmMetricsRssSampler(
        pid,
        readRssBytes: () async => 8192,
        readMaxRssBytes: () async => ++reads <= 3 ? 4096 : 16384,
      );
      final result = await sampler.stop();
      expect(reads, 3);
      expect(result.lifetimeMaxRssBytes, isNull);
      expect(result.lifetimeMaxReadAttemptsBytes, [4096, 4096, 4096]);
      expect(result.currentRssBytes, 8192);
      expect(result.peakRssBytes, 8192);
    },
  );
  for (final maximum in <int?>[null, 0, 4096, 9007199254740992]) {
    test(
      'RSS missing or contradictory lifetime maximum stays unavailable: $maximum',
      () async {
        var calls = 0;
        final sampler = DartVmMetricsRssSampler(
          pid,
          readRssBytes: () async => ++calls == 1 ? 8192 : 4096,
          readMaxRssBytes: () async => maximum,
        );
        final result = await sampler.stop();
        expect(result.currentRssBytes, 4096);
        expect(result.peakRssBytes, 8192);
        expect(result.lifetimeMaxRssBytes, isNull);
      },
    );
  }
  for (final throwOnRead in [false, true]) {
    test(
      'RSS failed final read does not reuse an earlier live value throw=$throwOnRead',
      () async {
        var calls = 0;
        final sampler = DartVmMetricsRssSampler(
          pid,
          readRssBytes: () async {
            if (++calls == 1) return 8192;
            if (throwOnRead) throw const FileSystemException('gone');
            return null;
          },
          readMaxRssBytes: () async => 16384,
        );
        final result = await sampler.stop();
        expect(result.currentRssBytes, isNull);
        expect(result.peakRssBytes, 8192);
        expect(result.lifetimeMaxRssBytes, isNull);
      },
    );
  }

  test('RSS missing process or lifetime read remains unavailable', () async {
    final absent = await DartVmMetricsRssSampler(999999999).stop();
    expect(absent.currentRssBytes, isNull);
    expect(absent.peakRssBytes, isNull);
    expect(absent.lifetimeMaxRssBytes, isNull);
    final failedMaximum = await DartVmMetricsRssSampler(
      pid,
      readRssBytes: () async => 4096,
      readMaxRssBytes: () async => throw const FileSystemException('gone'),
    ).stop();
    expect(failedMaximum.currentRssBytes, 4096);
    expect(failedMaximum.lifetimeMaxRssBytes, isNull);
  });

  test('profiles allocation work across stable application isolates', () async {
    var workspaceDirectory = Directory.current.absolute;
    while (!File(
      '${workspaceDirectory.path}/packages/connectanum_bench/pubspec.yaml',
    ).existsSync()) {
      final parent = workspaceDirectory.parent;
      if (parent.path == workspaceDirectory.path) {
        throw StateError('Could not locate the connectanum workspace root');
      }
      workspaceDirectory = parent;
    }
    final packageConfig = File(
      '${workspaceDirectory.path}/.dart_tool/package_config.json',
    );
    final probeScript = File(
      '${workspaceDirectory.path}/packages/connectanum_bench/test/support/dart_vm_metrics_probe.dart',
    );
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--packages=${packageConfig.path}',
        '--timeline_streams=GC',
        '--observe=0/127.0.0.1',
        '--no-pause-isolates-on-exit',
        probeScript.path,
      ],
      workingDirectory: '${workspaceDirectory.path}/packages/connectanum_bench',
    );
    final output = StringBuffer();
    final measurement = Completer<Map<String, Object?>>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          output.writeln(line);
          if (line.startsWith('{') && !measurement.isCompleted) {
            measurement.complete(
              Map<String, Object?>.from(jsonDecode(line) as Map),
            );
          }
        });
    process.stderr.transform(utf8.decoder).listen(output.write);

    try {
      final result = await measurement.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Dart VM metrics probe did not report: $output',
        ),
      );
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
      );

      expect(exitCode, 0, reason: '$output');
      expect(
        result['allocated_bytes_delta'],
        greaterThanOrEqualTo(result['known_payload_allocation_bytes'] as int),
      );
      expect(result['known_payload_allocation_bytes'], 80 * 1024 * 1024);
      expect(
        result['allocated_bytes_delta'],
        lessThan(160 * 1024 * 1024),
        reason: 'Isolates in one group must not duplicate the same heap',
      );
      final allocation = result['allocation_measurement'] as Map;
      expect(allocation['status'], 'measured');
      expect(allocation['method'], 'dart_heap_gc_volume_v1');
      expect(allocation['capture_strategy'], 'external_process');
      expect(allocation['observer_pid'], isNot(allocation['observed_pid']));
      expect(result['pid_mismatch_rejected'], isTrue);
      expect(result['observer_crash_propagated'], isTrue);
      expect(result['close_idempotent'], isTrue);
      expect(result['gc_count_delta'], greaterThan(0));
      expect(result['gc_pause_us_delta'], greaterThan(0));
      expect(result['missing_metadata_allocated_bytes'], isNull);
      expect(result['missing_metadata_gc_count'], isNull);
      expect(result['missing_metadata_gc_pause_us'], isNull);
      expect(result['current_rss_bytes'], greaterThan(0));
      expect(
        result['peak_rss_bytes'],
        greaterThanOrEqualTo(result['current_rss_bytes'] as int),
      );
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  });
}
