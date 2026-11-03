@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../connectanum_router/test/support/native_lib.dart';
import 'support/benchmark_child_coverage.dart';

void main() {
  test('gateway CLI owns stdin/stdout and exits after drain', () async {
    var root = Directory.current.absolute;
    while (!File('${root.path}/.dart_tool/package_config.json').existsSync()) {
      root = root.parent;
    }
    final temporary = await Directory.systemTemp.createTemp(
      'mqtt-gateway-cli-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final service = File('${temporary.path}/service.json');
    final coverageDirectory =
        Platform.environment['CONNECTANUM_TEST_CHILD_COVERAGE_DIR'];
    final coverageFile = coverageDirectory == null
        ? null
        : File('$coverageDirectory/mqtt-gateway-cli.json').absolute;
    final process = await Process.start(Platform.resolvedExecutable, [
      if (coverageFile != null) ...[
        '--enable-vm-service=0/127.0.0.1',
        '--write-service-info=${service.path}',
        '--pause-isolates-on-exit',
        '--no-serve-devtools',
        '--no-warn-on-pause-with-no-debugger',
      ],
      '--packages=${root.path}/.dart_tool/package_config.json',
      '${root.path}/packages/connectanum_bench/bin/mqtt_gateway_worker.dart',
      'server',
      jsonEncode({
        'path': 'mqtt_to_wamp',
        'transport': 'tcp',
        'serializer': 'cbor',
        'mqtt_version': '5',
        'payload_bytes': 128,
        'window': 1,
        'port': 0,
        'native_library': resolveOrBuildNativeLib()!,
      }),
    ]);
    final errors = process.stderr.transform(utf8.decoder).join();
    final done = Completer<void>();
    final kinds = <String>[];
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('{')) return;
          final event = jsonDecode(line) as Map;
          kinds.add(event['kind'] as String);
          if (event['kind'] == 'ready') {
            for (final command in [
              {'op': 'begin', 'phase': 1, 'count': 1},
              {'op': 'sample'},
              {'op': 'close'},
            ]) {
              process.stdin.writeln(jsonEncode(command));
            }
          } else if (event['kind'] == 'closed') {
            done.complete();
          }
        });
    addTearDown(() async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await output.cancel();
    });
    await done.future.timeout(const Duration(seconds: 30));
    await process.stdin.close();
    if (coverageFile != null) {
      final info = jsonDecode(await service.readAsString()) as Map;
      await collectBenchmarkChildCoverage(
        Uri.parse(info['uri'] as String),
        coverageFile,
        root,
        expectedSource:
            'package:connectanum_bench/src/mqtt_gateway_worker.dart',
        includeEntryPoint: true,
        timeout: const Duration(seconds: 60),
      );
    }
    expect(
      await process.exitCode.timeout(const Duration(seconds: 5)),
      0,
      reason: await errors,
    );
    expect(kinds, ['ready', 'armed', 'sampled', 'closed']);
  });
}
