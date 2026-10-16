import 'dart:io';

import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  for (final entrypoint in [
    './tool/worker.dart',
    'bin/worker',
    'worker:with/slashes',
  ]) {
    test(
      'process metrics retain unavailable RSS without losing allocation evidence',
      () {
        final metrics = NativeWampWorkerProcessMetrics.fromJson({
          'pid': 42,
          'rss_before_bytes': 1,
          'current_rss_bytes': null,
          'max_rss_bytes': null,
          'rss_lifetime_max_read_attempts_bytes': [4096, 4096, null],
          'allocated_bytes_delta': 8192,
          'cpu_user_us_delta': 123,
        });
        expect(metrics.toJson()['current_rss_bytes'], isNull);
        expect(metrics.toJson()['max_rss_bytes'], isNull);
        expect(metrics.toJson()['rss_lifetime_max_read_attempts_bytes'], [
          4096,
          4096,
          null,
        ]);
        expect(metrics.allocatedBytesDelta, 8192);
        expect(metrics.cpuUserUsDelta, 123);
      },
    );

    test('native worker normalizes relative file entrypoint $entrypoint', () {
      final worker = NativeWampWorker(
        realmUri: 'bench.control',
        wampTargets: const {},
        nativeLibraryPath: 'unused_native_library',
        workerScriptPath: entrypoint,
      );
      expect(worker.workerScriptPath, File(entrypoint).absolute.path);
      expect(
        worker.nativeLibraryPath,
        File('unused_native_library').absolute.path,
      );
      expect(worker.dartExecutable, Platform.resolvedExecutable);
    });
  }

  test('native worker process metrics preserve byte counters', () {
    final metrics = NativeWampWorkerProcessMetrics.fromJson({
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
      'cpu_user_us_delta': 1234,
      'cpu_system_us_delta': 432,
      'allocated_bytes_delta': 98_765,
      'gc_count_delta': 2,
      'gc_pause_us_delta': 456,
      'peak_rss_during_bytes': 805_306_368,
    });

    expect(metrics.pid, 42);
    expect(metrics.rssBeforeBytes, 67_108_864);
    expect(metrics.currentRssBytes, 536_870_912);
    expect(metrics.maxRssBytes, 805_306_368);
    expect(metrics.cpuUserUsDelta, 1234);
    expect(metrics.cpuSystemUsDelta, 432);
    expect(metrics.allocatedBytesDelta, 98_765);
    expect(metrics.gcCountDelta, 2);
    expect(metrics.gcPauseUsDelta, 456);
    expect(metrics.peakRssDuringBytes, 805_306_368);
    expect(metrics.toJson(), {
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
      'cpu_user_us_delta': 1234,
      'cpu_system_us_delta': 432,
      'allocated_bytes_delta': 98_765,
      'gc_count_delta': 2,
      'gc_pause_us_delta': 456,
      'peak_rss_during_bytes': 805_306_368,
    });
  });

  test(
    'process metrics retain allocation evidence without inventing legacy proof',
    () {
      final metadata = <String, Object?>{
        'status': 'measured',
        'method': 'dart_heap_gc_volume_v1',
        'heap_group_ids': ['isolateGroups/7'],
        'gc_observations': <Object?>[],
      };
      final parsed = NativeWampWorkerProcessMetrics.fromJson({
        'pid': 42,
        'rss_before_bytes': 100,
        'current_rss_bytes': 200,
        'max_rss_bytes': 300,
        'allocated_bytes_delta': 500000,
        'allocation_measurement': metadata,
      });
      expect(parsed.allocationMeasurement, metadata);
      expect(parsed.toJson()['allocation_measurement'], metadata);
      final legacy = NativeWampWorkerProcessMetrics.fromJson({
        'pid': 42,
        'rss_before_bytes': 1,
        'current_rss_bytes': 1,
        'max_rss_bytes': 1,
      });
      expect(legacy.allocationMeasurement, isNull);
      expect(legacy.toJson(), isNot(contains('allocation_measurement')));
    },
  );

  test('native worker preserves Dart package executable entrypoints', () {
    final worker = NativeWampWorker(
      realmUri: 'bench.control',
      wampTargets: const {},
      nativeLibraryPath: 'unused_native_library',
      workerScriptPath: 'connectanum_bench:wamp_client_worker',
    );

    expect(worker.workerScriptPath, 'connectanum_bench:wamp_client_worker');
  });

  test(
    'native worker launches a colon-bearing prebuilt executable directly',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'connectanum_native_worker_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final executable = File('${tempDirectory.path}/fake:worker');
      await executable.writeAsString(r'''#!/bin/sh
printf 'READY\n'
IFS= read -r request
printf '%s\n' '{"samples":[],"file_segment_metrics":{},"process_metrics":{"pid":42,"rss_before_bytes":1,"current_rss_bytes":2,"max_rss_bytes":3}}'
IFS= read -r stop || true
''');
      final chmod = await Process.run('chmod', ['+x', executable.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

      final worker = NativeWampWorker(
        realmUri: 'bench.control',
        wampTargets: const {},
        nativeLibraryPath: '${tempDirectory.path}/unused_native_library',
        workerScriptPath: executable.path,
        dartExecutable: '${tempDirectory.path}/must_not_be_invoked',
      );
      final result = await worker.runWithMetrics(
        WampScenario.fromJson({
          'transport': 'rawsocket',
          'client_impl': 'native',
          'mode': 'rpc',
          'uri': 'bench.rpc.echo',
        }),
      );

      expect(result.samples, isEmpty);
      expect(result.processMetrics?.pid, 42);
      expect(result.processMetrics?.maxRssBytes, 3);
    },
    skip: Platform.isWindows
        ? 'The direct-launch fixture uses a POSIX shell script.'
        : false,
  );

  test(
    'source worker exposes allocation, GC, CPU, and sampled RSS metrics',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'connectanum_native_vm_metrics_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final script = File('${tempDirectory.path}/worker.dart');
      await script.writeAsString(r'''import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('READY');
  await stdout.flush();
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line == 'STOP') break;
    final earlyMaximum = ProcessInfo.maxRss;
    final retained = <List<int>>[];
    for (var i = 0; i < 80; i++) {
      retained.add(List<int>.filled(128 * 1024, i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    stdout.writeln(jsonEncode({
      'samples': [],
      'file_segment_metrics': {},
      'process_metrics': {
        'pid': pid,
        'rss_before_bytes': ProcessInfo.currentRss,
        'current_rss_bytes': ProcessInfo.currentRss,
        'max_rss_bytes': earlyMaximum,
      },
    }));
    await stdout.flush();
    if (retained.length != 80) throw StateError('allocation fixture failed');
  }
}
''');

      final worker = NativeWampWorker(
        realmUri: 'bench.control',
        wampTargets: const {},
        nativeLibraryPath: '${tempDirectory.path}/unused_native_library',
        workerScriptPath: script.path,
        enableVmMetrics: true,
      );
      addTearDown(worker.close);

      final result = await worker.runWithMetrics(
        WampScenario.fromJson({
          'transport': 'rawsocket',
          'client_impl': 'native',
          'mode': 'rpc',
          'uri': 'bench.rpc.echo',
        }),
      );

      final metrics = result.processMetrics!;
      expect(metrics.allocatedBytesDelta, greaterThan(0));
      expect(metrics.gcCountDelta, isNotNull);
      expect(metrics.gcPauseUsDelta, isNotNull);
      if (Platform.isLinux) {
        expect(metrics.cpuUserUsDelta, isNotNull);
        expect(metrics.cpuSystemUsDelta, isNotNull);
        expect(metrics.peakRssDuringBytes, greaterThan(0));
        expect(
          metrics.maxRssBytes,
          greaterThanOrEqualTo(metrics.currentRssBytes!),
        );
        expect(
          metrics.maxRssBytes,
          greaterThanOrEqualTo(metrics.peakRssDuringBytes!),
        );
      }
    },
    skip: Platform.isWindows
        ? 'The source worker fixture uses a Dart CLI runtime with POSIX VM-service flags.'
        : false,
  );

  test(
    'client worker forwards Dart implementation scenarios unchanged',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'connectanum_dart_worker_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final executable = File('${tempDirectory.path}/fake-worker');
      await executable.writeAsString(r'''#!/bin/sh
printf 'READY\n'
IFS= read -r request
case "$request" in
  *'"client_impl":"dart"'*)
    printf '%s\n' '{"samples":[],"file_segment_metrics":{},"process_metrics":{"pid":43,"rss_before_bytes":1,"current_rss_bytes":2,"max_rss_bytes":3}}'
    ;;
  *)
    printf '%s\n' '{"error":"client implementation changed"}'
    ;;
esac
IFS= read -r stop || true
''');
      final chmod = await Process.run('chmod', ['+x', executable.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

      final worker = NativeWampWorker(
        realmUri: 'bench.control',
        wampTargets: const {},
        nativeLibraryPath: '${tempDirectory.path}/unused_native_library',
        workerScriptPath: executable.path,
      );
      final result = await worker.runWithMetrics(
        WampScenario.fromJson({
          'transport': 'websocket',
          'client_impl': 'dart',
          'serializer': 'json',
          'mode': 'file_transfer',
          'uri': 'bench.file.set',
        }),
      );

      expect(result.samples, isEmpty);
      expect(result.processMetrics?.pid, 43);
    },
    skip: Platform.isWindows
        ? 'The direct-launch fixture uses a POSIX shell script.'
        : false,
  );
}
