import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('selectDartVmMetricIsolateIds', () {
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
        greaterThan(16 * 1024 * 1024),
      );
      expect(result['gc_count_delta'], isA<int>());
      expect(result['gc_pause_us_delta'], isA<int>());
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  });
}
