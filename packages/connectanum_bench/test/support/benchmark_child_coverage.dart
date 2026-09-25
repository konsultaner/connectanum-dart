import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<void> collectBenchmarkChildCoverage(
  Uri uri,
  File output,
  Directory root, {
  Future<Process> Function(String, List<String>)? startProcess,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.port <= 0) {
    throw ArgumentError.value(uri, 'uri', 'Expected loopback VM service');
  }
  if (await output.exists()) {
    throw StateError('Child coverage output already exists: ${output.path}');
  }
  await output.parent.create(recursive: true);
  final arguments = [
    '--packages=${root.path}/.dart_tool/package_config.json',
    '${root.path}/packages/connectanum_bench/test/support/collect_benchmark_child_coverage.dart',
    '$uri',
    output.path,
  ];
  final process = await (startProcess ?? Process.start)(
    Platform.resolvedExecutable,
    arguments,
  );
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  // Own both pipes immediately, even when a collector fails before exit.
  final pipes = [
    process.stdout.fold<List<int>>([], (all, bytes) => all..addAll(bytes)),
    process.stderr.fold<List<int>>([], (all, bytes) => all..addAll(bytes)),
  ];
  final completion = Future.wait<Object>([exit, ...pipes], eagerError: true);
  Future<void>? cleanup;
  Future<void> close() => cleanup ??= () async {
    if (!exited) process.kill(ProcessSignal.sigkill);
    await exit;
    // The caller retains the original process/stream failure.
    await Future.wait(pipes).then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
  }();
  addTearDown(close);
  try {
    final result = await completion.timeout(timeout);
    final code = result[0] as int;
    if (code != 0) {
      throw ProcessException(
        Platform.resolvedExecutable,
        arguments,
        '${utf8.decode(result[1] as List<int>, allowMalformed: true)}\n'
        '${utf8.decode(result[2] as List<int>, allowMalformed: true)}',
        code,
      );
    }
    validateBenchmarkChildCoverage(jsonDecode(await output.readAsString()));
  } finally {
    await close();
  }
}

void validateBenchmarkChildCoverage(Object? report) {
  const source = 'package:connectanum_bench/src/benchmark_runner.dart';
  if (report is! Map || report['coverage'] is! List) {
    throw const FormatException('Missing child coverage entries');
  }
  final entries = (report['coverage'] as List).where(
    (entry) => entry is Map && entry['source'] == source,
  );
  if (entries.length != 1) {
    throw const FormatException(
      'Expected exactly one benchmark runner hit map',
    );
  }
  final hits = (entries.single as Map)['hits'];
  if (hits is! List || hits.isEmpty || hits.length.isOdd) {
    throw const FormatException('Invalid benchmark runner hit pairs');
  }
  final lines = <int>{};
  var hasHits = false;
  for (var index = 0; index < hits.length; index += 2) {
    final line = hits[index];
    final count = hits[index + 1];
    if (line is! int ||
        line <= 0 ||
        count is! int ||
        count < 0 ||
        !lines.add(line)) {
      throw const FormatException('Invalid benchmark runner line or hit count');
    }
    hasHits |= count > 0;
  }
  if (!hasHits) {
    throw const FormatException(
      'Child coverage contains no executed runner lines',
    );
  }
}
