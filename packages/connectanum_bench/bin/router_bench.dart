import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_bench/connectanum_bench.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> arguments) async {
  final parser = buildArgParser();
  late ArgResults results;
  try {
    results = parser.parse(arguments);
  } on ArgParserException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  _configureLogging();

  final scenarioPath = results['scenario'] as String;
  final configPath = results['config'] as String;
  final nativeLib = results['native-lib'] as String;
  final buildNative = results['build-native'] as bool;
  final dryRun = results['dry-run'] as bool;

  BenchmarkConfig benchmarkConfig;
  try {
    final file = File(scenarioPath);
    if (!file.existsSync()) {
      throw FormatException('Scenario file "$scenarioPath" not found');
    }
    benchmarkConfig = BenchmarkConfig.fromYaml(file.readAsStringSync());
  } catch (error) {
    Logger('BenchmarkRunner').severe('Failed to load scenarios: $error');
    exitCode = 2;
    return;
  }

  final runner = BenchmarkRunner(
    nativeLibraryPath: nativeLib,
    routerConfigPath: configPath,
    config: benchmarkConfig,
    buildNative: buildNative,
    dryRun: dryRun,
  );

  try {
    await runner.run();
  } catch (error, stackTrace) {
    Logger('BenchmarkRunner').severe('Benchmark run failed', error, stackTrace);
    exitCode = 1;
  }
}

void _configureLogging() {
  Logger.root
    ..level = Level.INFO
    ..onRecord.listen((record) {
      final time = record.time.toIso8601String();
      final logger = record.loggerName;
      final level = record.level.name;
      final message = record.message;
      stdout.writeln('[$time] [$level] [$logger] $message');
      if (record.error != null) {
        stdout.writeln('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        stdout.writeln(record.stackTrace);
      }
    });
}
