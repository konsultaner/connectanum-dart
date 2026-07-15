import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('realm', mandatory: true)
    ..addOption('targets-json', mandatory: true)
    ..addOption('secure-targets-json', defaultsTo: '{}')
    ..addOption('native-lib', mandatory: true)
    ..addFlag('verbose', negatable: true, defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(parser.usage);
    return;
  }

  ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (results['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  _configureLogging(results['verbose'] as bool);

  final realmUri = results['realm'] as String;
  final nativeLibraryPath = results['native-lib'] as String;
  final targetsJson = results['targets-json'] as String;
  final secureTargetsJson = results['secure-targets-json'] as String;
  final wampTargets = _decodeTargets(targetsJson);
  final secureWampTargets = _decodeTargets(secureTargetsJson);

  final runner = WampWorkloadRunner(
    sessionFactory: (scenario) {
      final target = resolveWampTransportTargetForScenario(
        scenario: scenario,
        wampTargets: wampTargets,
        secureWampTargets: secureWampTargets,
      );
      switch (scenario.transport) {
        case WampTransport.rawsocket:
          final scenarioRealm = scenario.realmUri.isEmpty
              ? realmUri
              : scenario.realmUri;
          return RawSocketWampSessionFactory(
            host: target.host,
            port: target.port,
            realmUri: scenarioRealm,
            authId: scenario.authId,
            authenticationMethods: authenticationMethodsForScenario(scenario),
            serializer: scenario.serializer,
            clientImplementation: scenario.clientImplementation,
            ssl: target.secure,
            allowInsecureCertificates: target.secure,
            nativeLibraryPath: nativeLibraryPath,
            e2eeProviderFactory: e2eeProviderFactoryForScenario(scenario),
          ).call();
        case WampTransport.websocket:
          final scenarioRealm = scenario.realmUri.isEmpty
              ? realmUri
              : scenario.realmUri;
          return WebSocketWampSessionFactory(
            url: target.webSocketUri.toString(),
            realmUri: scenarioRealm,
            authId: scenario.authId,
            authenticationMethods: authenticationMethodsForScenario(scenario),
            serializer: scenario.serializer,
            clientImplementation: scenario.clientImplementation,
            headers: const {'x-connectanum-bench': '1'},
            allowInsecureCertificates: target.secure,
            websocketFragmentSize: scenario.websocketFragmentSize,
            nativeLibraryPath: nativeLibraryPath,
            e2eeProviderFactory: e2eeProviderFactoryForScenario(scenario),
          ).call();
      }
    },
    logger: Logger('NativeWampWorker'),
  );

  try {
    stdout.writeln('READY');
    await stdout.flush();

    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed == 'STOP') {
        break;
      }
      try {
        final scenario = WampScenario.fromJson(
          Map<String, Object?>.from(jsonDecode(trimmed) as Map),
        );
        final samples = await runner.run(scenario);
        stdout.writeln(
          jsonEncode({
            'samples': samples.map((sample) => sample.toJson()).toList(),
          }),
        );
        await stdout.flush();
      } catch (error, stackTrace) {
        Logger(
          'NativeWampWorker',
        ).warning('Failed to run WAMP workload', error, stackTrace);
        stdout.writeln(jsonEncode({'error': error.toString()}));
        await stdout.flush();
      }
    }
  } finally {
    NativeClientRuntime.shutdownShared();
  }
}

Map<WampTransport, WampTransportTarget> _decodeTargets(String raw) {
  final decodedTargets = jsonDecode(raw) as Map<String, Object?>;
  return <WampTransport, WampTransportTarget>{
    for (final entry in decodedTargets.entries)
      WampTransport.parse(entry.key): WampTransportTarget.fromJson(
        Map<String, Object?>.from(entry.value as Map),
      ),
  };
}

void _configureLogging(bool verbose) {
  Logger.root
    ..level = verbose ? Level.ALL : Level.WARNING
    ..onRecord.listen((record) {
      stderr.writeln(
        '[${record.time.toIso8601String()}][${record.level.name}]'
        '[${record.loggerName}] ${record.message}',
      );
      if (record.error != null) {
        stderr.writeln('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        stderr.writeln(record.stackTrace);
      }
    });
}
