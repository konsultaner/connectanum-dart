import 'dart:io';

import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  test('native worker process metrics preserve byte counters', () {
    final metrics = NativeWampWorkerProcessMetrics.fromJson({
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
    });

    expect(metrics.pid, 42);
    expect(metrics.rssBeforeBytes, 67_108_864);
    expect(metrics.currentRssBytes, 536_870_912);
    expect(metrics.maxRssBytes, 805_306_368);
    expect(metrics.toJson(), {
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
    });
  });

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
}
