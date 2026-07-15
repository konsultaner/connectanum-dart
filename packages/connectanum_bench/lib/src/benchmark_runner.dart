import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_bench/src/benchmark_config.dart';
import 'package:connectanum_bench/src/wamp_echo_handler.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';

class BenchmarkRunner {
  BenchmarkRunner({
    required this.nativeLibraryPath,
    required this.routerConfigPath,
    required this.config,
    this.buildNative = false,
    this.dryRun = false,
  });

  final String nativeLibraryPath;
  final String routerConfigPath;
  final BenchmarkConfig config;
  final bool buildNative;
  final bool dryRun;

  final Logger _logger = Logger('BenchmarkRunner');

  Future<void> run() async {
    if (buildNative) {
      await _buildNativeLibrary();
    }
    final routerSettings = await RouterConfigLoaderIo.fromFile(
      routerConfigPath,
    );
    final endpoints = routerSettings.listeners
        .map(Endpoint.fromListenerSettings)
        .toList(growable: false);
    final routerConfig = RouterConfig(endpoints: endpoints);
    final wampTargets = resolveWampTransportTargets(routerSettings.listeners);
    final secureWampTargets = resolveWampTransportTargets(
      routerSettings.listeners,
      secureOnly: true,
    );
    if (dryRun) {
      _logger.info('Dry run enabled – scenarios will not execute load.');
    }
    final runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
    runtime.start();
    RouterBinding? binding;
    final echoRegistrations = _BenchmarkEchoRegistrations(logger: _logger);
    try {
      final router = Router(routerConfig, settings: routerSettings);
      binding = router.start(runtime);
      for (final scenario in config.scenarios) {
        await _runScenario(
          binding,
          scenario,
          wampTargets: wampTargets,
          secureWampTargets: secureWampTargets,
          echoRegistrations: echoRegistrations,
        );
      }
    } finally {
      await echoRegistrations.close();
      if (binding != null) {
        await binding.dispose();
      }
      runtime.shutdown();
      runtime.dispose();
    }
  }

  Future<void> _buildNativeLibrary() async {
    final proc = await Process.start(
      'cargo',
      ['build', '-p', 'ct_ffi', '--release'],
      workingDirectory: 'native/transport',
      runInShell: true,
    );
    await stdout.addStream(proc.stdout);
    await stderr.addStream(proc.stderr);
    final code = await proc.exitCode;
    if (code != 0) {
      throw ProcessException(
        'cargo',
        ['build', '-p', 'ct_ffi', '--release'],
        'Native build failed with exit code $code',
        code,
      );
    }
  }

  Future<void> _runScenario(
    RouterBinding binding,
    BenchmarkScenario scenario, {
    required Map<WampTransport, WampTransportTarget> wampTargets,
    required Map<WampTransport, WampTransportTarget> secureWampTargets,
    required _BenchmarkEchoRegistrations echoRegistrations,
  }) async {
    _logger.info('Running scenario "${scenario.name}"');
    final wampScenario = _asWampScenario(scenario);
    if (wampScenario != null &&
        wampScenario.mode == WampMode.rpc &&
        wampScenario.peerSerializer == null) {
      await echoRegistrations.ensure(binding, wampScenario.realmUri);
    }
    final startSnapshot = await binding.collectMetrics();
    if (scenario.warmup > Duration.zero) {
      _logger.info(' Warm-up for ${scenario.warmup.inSeconds}s');
      await Future<void>.delayed(scenario.warmup);
    }
    final scenarioStart = DateTime.now();
    List<WampSample>? wampSamples;
    if (wampScenario != null) {
      if (dryRun) {
        resolveWampTransportTargetForScenario(
          scenario: wampScenario,
          wampTargets: wampTargets,
          secureWampTargets: secureWampTargets,
        );
      } else {
        wampSamples = await _runWampScenario(
          wampScenario,
          wampTargets: wampTargets,
          secureWampTargets: secureWampTargets,
        );
      }
    } else if (!dryRun) {
      _logger.warning(
        ' No load generators are configured yet. Sleeping for scenario duration.',
      );
    }
    if (wampScenario == null || dryRun) {
      await Future<void>.delayed(scenario.duration);
    }
    final scenarioEnd = DateTime.now();
    final endSnapshot = await binding.collectMetrics();
    _reportScenarioSummary(
      scenario: scenario,
      start: scenarioStart,
      end: scenarioEnd,
      startSnapshot: startSnapshot,
      endSnapshot: endSnapshot,
      wampSamples: wampSamples,
    );
  }

  Future<List<WampSample>> _runWampScenario(
    WampScenario scenario, {
    required Map<WampTransport, WampTransportTarget> wampTargets,
    required Map<WampTransport, WampTransportTarget> secureWampTargets,
  }) {
    final runner = WampWorkloadRunner(
      sessionFactory: (sessionScenario) => _openWampSession(
        sessionScenario,
        wampTargets: wampTargets,
        secureWampTargets: secureWampTargets,
      ),
      logger: _logger,
    );
    return runner.run(scenario);
  }

  Future<WampSession> _openWampSession(
    WampScenario scenario, {
    required Map<WampTransport, WampTransportTarget> wampTargets,
    required Map<WampTransport, WampTransportTarget> secureWampTargets,
  }) {
    final target = resolveWampTransportTargetForScenario(
      scenario: scenario,
      wampTargets: wampTargets,
      secureWampTargets: secureWampTargets,
    );
    switch (scenario.transport) {
      case WampTransport.rawsocket:
        return RawSocketWampSessionFactory(
          host: target.host,
          port: target.port,
          realmUri: scenario.realmUri,
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
        return WebSocketWampSessionFactory(
          url: target.webSocketUri.toString(),
          realmUri: scenario.realmUri,
          authId: scenario.authId,
          authenticationMethods: authenticationMethodsForScenario(scenario),
          serializer: scenario.serializer,
          clientImplementation: scenario.clientImplementation,
          headers: const {'x-connectanum-bench': '1'},
          allowInsecureCertificates: target.secure,
          nativeLibraryPath: nativeLibraryPath,
          e2eeProviderFactory: e2eeProviderFactoryForScenario(scenario),
        ).call();
    }
  }

  void _reportScenarioSummary({
    required BenchmarkScenario scenario,
    required DateTime start,
    required DateTime end,
    required RouterMetricsSnapshot startSnapshot,
    required RouterMetricsSnapshot endSnapshot,
    required List<WampSample>? wampSamples,
  }) {
    final elapsed = end.difference(start);
    final deltaInvocations =
        endSnapshot.totalInvocationsDispatched -
        startSnapshot.totalInvocationsDispatched;
    final deltaPublications =
        endSnapshot.totalPublicationsRouted -
        startSnapshot.totalPublicationsRouted;
    _logger.info('Scenario "${scenario.name}" complete.');
    _logger.info(' Duration: ${elapsed.inSeconds}s');
    _logger.info(' Sessions: ${endSnapshot.sessionCount}');
    _logger.info(' Registrations: ${endSnapshot.registrationCount}');
    _logger.info(' Subscriptions: ${endSnapshot.subscriptionCount}');
    _logger.info(' Pending invocations: ${endSnapshot.pendingInvocationCount}');
    _logger.info(' Total invocations dispatched: $deltaInvocations');
    _logger.info(' Total publications routed: $deltaPublications');
    if (wampSamples != null) {
      _logger.info(' WAMP samples: ${wampSamples.length}');
      if (wampSamples.isNotEmpty) {
        final totalLatency = wampSamples.fold<double>(
          0,
          (sum, sample) => sum + sample.latencyMs,
        );
        final totalRequestBytes = wampSamples.fold<int>(
          0,
          (sum, sample) => sum + sample.requestBytes,
        );
        final totalResponseBytes = wampSamples.fold<int>(
          0,
          (sum, sample) => sum + sample.responseBytes,
        );
        _logger.info(
          ' WAMP mean latency: '
          '${(totalLatency / wampSamples.length).toStringAsFixed(3)} ms',
        );
        _logger.info(' WAMP request bytes: $totalRequestBytes');
        _logger.info(' WAMP response bytes: $totalResponseBytes');
      }
    }
  }
}

WampScenario? _asWampScenario(BenchmarkScenario scenario) {
  final normalizedType = scenario.type.toLowerCase();
  final protocol = scenario.extra['protocol'];
  if (normalizedType != 'wamp' &&
      !normalizedType.startsWith('wamp_') &&
      !(protocol is String && protocol.toLowerCase().startsWith('wamp'))) {
    return null;
  }

  final payload = <String, Object?>{...scenario.extra};
  if (protocol is String) {
    _applyWampProtocolDefaults(payload, protocol);
  }
  _applyWampProtocolDefaults(payload, scenario.type);
  _copyAlias(payload, target: 'uri', source: 'path');
  _copyAlias(payload, target: 'payload_bytes', source: 'request_bytes');
  _copyAlias(payload, target: 'realm', source: 'auth_realm');
  payload.putIfAbsent('concurrency', () => scenario.concurrency);
  return WampScenario.fromJson(payload);
}

void _applyWampProtocolDefaults(Map<String, Object?> payload, String protocol) {
  final normalized = protocol.toLowerCase();
  if (!normalized.startsWith('wamp')) {
    return;
  }

  var remainder = normalized;
  if (remainder.startsWith('wamp_')) {
    remainder = remainder.substring('wamp_'.length);
  }
  if (remainder.startsWith('rawsocket_')) {
    payload.putIfAbsent('transport', () => 'rawsocket');
    remainder = remainder.substring('rawsocket_'.length);
  } else if (remainder.startsWith('websocket_')) {
    payload.putIfAbsent('transport', () => 'websocket');
    remainder = remainder.substring('websocket_'.length);
  }
  if (remainder.isNotEmpty && remainder != 'wamp') {
    payload.putIfAbsent('mode', () => remainder);
  }
}

void _copyAlias(
  Map<String, Object?> payload, {
  required String target,
  required String source,
}) {
  if (payload[target] == null && payload[source] != null) {
    payload[target] = payload[source];
  }
}

final class _BenchmarkEchoRegistrations {
  _BenchmarkEchoRegistrations({required this.logger});

  final Logger logger;
  final Map<String, RouterSession> _sessions = {};
  final List<_BenchmarkEchoRegistration> _registrations = [];

  Future<void> ensure(RouterBinding binding, String realmUri) async {
    if (_sessions.containsKey(realmUri)) {
      return;
    }
    final session = await binding.createInternalSession(
      realmUri: realmUri,
      authId: 'bench-runner',
      authRole: realmUri == 'bench.secure' ? 'internal' : 'bench',
    );
    final registration = await session.register('bench.rpc.echo');
    registration.onLazyInvokePayload(
      (invocation) => respondEchoLazyInvocation(invocation, logger: logger),
    );
    _sessions[realmUri] = session;
    _registrations.add(
      _BenchmarkEchoRegistration(
        session: session,
        registrationId: registration.registrationId,
      ),
    );
  }

  Future<void> close() async {
    for (final registration in _registrations.reversed) {
      try {
        await registration.session.unregister(registration.registrationId);
      } catch (_) {
        // Best-effort cleanup; the binding disposal path will close leftovers.
      }
    }
    _registrations.clear();
    for (final session in _sessions.values) {
      try {
        await session.close();
      } catch (_) {
        // Best-effort cleanup; the runtime is already shutting down.
      }
    }
    _sessions.clear();
  }
}

final class _BenchmarkEchoRegistration {
  _BenchmarkEchoRegistration({
    required this.session,
    required this.registrationId,
  });

  final RouterSession session;
  final int registrationId;
}

ArgParser buildArgParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addOption(
      'scenario',
      abbr: 's',
      defaultsTo: 'benchmarks.yaml',
      help: 'Path to benchmark scenario definition (YAML).',
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Router configuration file (JSON/YAML).',
      mandatory: true,
    )
    ..addOption(
      'native-lib',
      abbr: 'n',
      help: 'Path to the native ct_ffi library to load.',
      mandatory: true,
    )
    ..addFlag(
      'build-native',
      defaultsTo: false,
      negatable: true,
      help: 'Build the native ct_ffi library before running benchmarks.',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: false,
      negatable: true,
      help: 'Skip load execution (useful for validating configuration).',
    );
}
