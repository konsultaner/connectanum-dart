import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
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
  final nativeRuntime = NativeClientRuntime.instance(
    libraryPath: nativeLibraryPath,
  );
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
            messageLengthExponent: scenario.rawSocketMessageLengthExponent,
            nativeLibraryPath: nativeLibraryPath,
            e2eeProviderFactory: e2eeProviderFactoryForScenario(
              scenario,
              nativeLibraryPath: nativeLibraryPath,
            ),
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
            e2eeProviderFactory: e2eeProviderFactoryForScenario(
              scenario,
              nativeLibraryPath: nativeLibraryPath,
            ),
          ).call();
      }
    },
    logger: Logger('NativeWampWorker'),
    nativeBufferAllocator: nativeRuntime.nativeBuffers,
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
        final fileMetricsBefore = nativeRuntime.fileSegmentMetricsSnapshot();
        final copyMetricsBefore = nativeRuntime.transportCopyMetricsSnapshot();
        final rssBeforeBytes = ProcessInfo.currentRss;
        final samples = await runner.run(scenario);
        final fileMetrics = nativeRuntime
            .fileSegmentMetricsSnapshot()
            .deltaFrom(fileMetricsBefore);
        final copyMetrics = nativeRuntime
            .transportCopyMetricsSnapshot()
            .deltaFrom(copyMetricsBefore);
        stdout.writeln(
          jsonEncode({
            'samples': samples.map((sample) => sample.toJson()).toList(),
            'file_segment_metrics': {
              'rawsocket_zero_copy_calls':
                  fileMetrics.rawSocketZeroCopyCallsTotal,
              'rawsocket_zero_copy_bytes':
                  fileMetrics.rawSocketZeroCopyBytesTotal,
              'buffered_file_segment_calls':
                  fileMetrics.bufferedFileSegmentCallsTotal,
              'buffered_file_segment_bytes':
                  fileMetrics.bufferedFileSegmentBytesTotal,
            },
            'copy_metrics': _copyMetricsFor(scenario, samples, copyMetrics),
            'process_metrics': {
              'pid': pid,
              'rss_before_bytes': rssBeforeBytes,
              'current_rss_bytes': ProcessInfo.currentRss,
              'max_rss_bytes': ProcessInfo.maxRss,
            },
          }),
        );
        await stdout.flush();
      } catch (error, stackTrace) {
        Logger(
          'NativeWampWorker',
        ).warning('Failed to run WAMP workload', error, stackTrace);
        stdout.writeln(jsonEncode({'error': _describeWorkerError(error)}));
        await stdout.flush();
      }
    }
  } finally {
    NativeClientRuntime.shutdownShared();
  }
}

Map<String, Object?> _copyMetricsFor(
  WampScenario scenario,
  List<WampSample> samples,
  NativeTransportCopyMetrics nativeCopyMetrics,
) {
  Map<String, Object?> notApplicable(String reason) => {
    'status': 'not_applicable',
    'reason': reason,
  };
  Map<String, Object?> notMeasured(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };
  final builderMeasurementsAvailable = samples.any(
    (sample) =>
        sample.nativeBuilderInputCopiedBytes != null ||
        sample.nativeBuilderGrowthCopiedBytes != null,
  );
  final inputCopies = samples.fold<int>(
    0,
    (total, sample) => total + (sample.nativeBuilderInputCopiedBytes ?? 0),
  );
  final growthCopies = samples.fold<int>(
    0,
    (total, sample) => total + (sample.nativeBuilderGrowthCopiedBytes ?? 0),
  );
  final ownsFlatBuffersPayload =
      scenario.pptScheme == 'x_connectanum_bench_typed' &&
      scenario.pptSerializer == 'flatbuffers' &&
      scenario.clientImplementation == WampClientImplementation.native &&
      scenario.serializer == WampSerializer.flatbuffers &&
      (scenario.mode == WampMode.rpc || scenario.mode == WampMode.pubsub) &&
      scenario.payloadConstruction != WampPayloadConstruction.dartValues;
  final websocket = scenario.transport == WampTransport.websocket;
  final nativeClient =
      scenario.clientImplementation == WampClientImplementation.native;
  final websocketCountersAvailable =
      nativeCopyMetrics.websocketMaskCopyBytesTotal != null &&
      nativeCopyMetrics.websocketCoalesceCopyBytesTotal != null;
  final transportCountersAvailable =
      nativeClient && (!websocket || websocketCountersAvailable);
  final measuredTransportCopyBytes = transportCountersAvailable
      ? nativeCopyMetrics.dartToNativeCopiedBytesTotal +
            (websocket
                ? nativeCopyMetrics.websocketMaskCopyBytesTotal! +
                      nativeCopyMetrics.websocketCoalesceCopyBytesTotal!
                : 0)
      : null;
  final transportCopyBytes = scenario.secureTransport
      ? null
      : measuredTransportCopyBytes;
  return {
    // This counter covers only the application payload after the explicit
    // native FlatBuffers owner is frozen and submitted through the owned-view
    // API. Construction copies are reported separately below.
    'optimized_payload_copy_bytes': ownsFlatBuffersPayload
        ? 0
        : notApplicable('workload does not use native-owned typed FlatBuffers'),
    'builder_input_copy_bytes': builderMeasurementsAvailable
        ? inputCopies
        : notApplicable('workload did not use a Connectanum native builder'),
    'builder_growth_copy_bytes': builderMeasurementsAvailable
        ? growthCopies
        : notApplicable('workload did not grow a Connectanum native builder'),
    'transport_copy_bytes':
        transportCopyBytes ??
        notMeasured(
          scenario.secureTransport
              ? 'TLS copy behavior is not instrumented'
              : nativeClient
              ? 'an active transport copy counter is unavailable'
              : 'Dart client transport copy paths are not instrumented',
        ),
    'websocket_mask_copy_bytes': websocket
        ? (nativeClient
              ? (nativeCopyMetrics.websocketMaskCopyBytesTotal ??
                    notMeasured('WebSocket mask copy counter is unavailable'))
              : notMeasured('Dart WebSocket mask copies are not instrumented'))
        : notApplicable('RawSocket does not mask WebSocket frames'),
    'tls_copy_bytes': scenario.secureTransport
        ? notMeasured(
            'TLS accepted-plaintext bytes do not measure memory copies',
          )
        : notApplicable('workload uses cleartext transport'),
    'tls_plaintext_accepted_bytes': scenario.secureTransport
        ? (nativeClient
              ? (nativeCopyMetrics.tlsPlaintextAcceptedBytesTotal ??
                    notMeasured('Rustls plaintext counter is unavailable'))
              : notMeasured(
                  'Dart TLS plaintext acceptance is not instrumented',
                ))
        : notApplicable('workload uses cleartext transport'),
    'transcode_copy_bytes': scenario.peerSerializer != null
        ? {
            'status': 'not_measured',
            'reason':
                'mixed-serializer router transcode copies are not instrumented',
          }
        : notApplicable('workload uses a homogeneous serializer'),
  };
}

String _describeWorkerError(Object error) {
  if (error is wamp_core.Error) {
    return 'WAMP ${error.error ?? wamp_core.Error.unknown}';
  }
  return '${error.runtimeType}: $error';
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
