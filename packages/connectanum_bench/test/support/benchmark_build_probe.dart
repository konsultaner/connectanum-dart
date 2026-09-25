import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/benchmark_config.dart';
import 'package:connectanum_bench/src/benchmark_runner.dart';

Future<void> main(List<String> args) async {
  stdout.writeln('PROBE_READY');
  try {
    await BenchmarkRunner(
      nativeLibraryPath: 'never-loaded',
      routerConfigPath: 'never-read.yaml',
      config: BenchmarkConfig(scenarios: []),
      buildNative: args.single == 'build',
    ).run();
    throw StateError('The deliberately missing router config must fail.');
  } on ProcessException catch (error) {
    stdout.writeln(
      'BUILD_PROBE_RESULT:${jsonEncode({
        'error_type': 'ProcessException',
        'exit_code': error.errorCode,
        'executable': error.executable,
        'arguments': error.arguments,
        'message': error.message,
      })}',
    );
  } on FileSystemException catch (error) {
    stdout.writeln(
      'BUILD_PROBE_RESULT:${jsonEncode({'error_type': 'FileSystemException', 'path': error.path})}',
    );
  }
}
