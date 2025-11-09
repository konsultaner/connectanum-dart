import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_bench/src/benchmark_config.dart';
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
        .map((listener) => _endpointFromListener(listener))
        .toList(growable: false);
    final routerConfig = RouterConfig(endpoints: endpoints);
    if (dryRun) {
      _logger.info('Dry run enabled – scenarios will not execute load.');
    }
    final runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
    runtime.start();
    RouterBinding? binding;
    try {
      final router = Router(routerConfig, settings: routerSettings);
      binding = router.start(runtime);
      for (final scenario in config.scenarios) {
        await _runScenario(binding, scenario);
      }
    } finally {
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
    BenchmarkScenario scenario,
  ) async {
    _logger.info('Running scenario "${scenario.name}"');
    final startSnapshot = await binding.collectMetrics();
    if (scenario.warmup > Duration.zero) {
      _logger.info(' Warm-up for ${scenario.warmup.inSeconds}s');
      await Future<void>.delayed(scenario.warmup);
    }
    final scenarioStart = DateTime.now();
    if (!dryRun) {
      _logger.warning(
        ' No load generators are configured yet. Sleeping for scenario duration.',
      );
    }
    await Future<void>.delayed(scenario.duration);
    final scenarioEnd = DateTime.now();
    final endSnapshot = await binding.collectMetrics();
    _reportScenarioSummary(
      scenario: scenario,
      start: scenarioStart,
      end: scenarioEnd,
      startSnapshot: startSnapshot,
      endSnapshot: endSnapshot,
    );
  }

  void _reportScenarioSummary({
    required BenchmarkScenario scenario,
    required DateTime start,
    required DateTime end,
    required RouterMetricsSnapshot startSnapshot,
    required RouterMetricsSnapshot endSnapshot,
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
  }

  Endpoint _endpointFromListener(ListenerSettings settings) {
    final parsed = _parseEndpoint(settings.endpoint);
    final options = settings.options;
    final maxExponent = _asInt(
      options['max_rawsocket_size_exponent'],
      defaultValue: 16,
    );
    final idleTimeout = _asDuration(options['idle_timeout_ms']);
    final handshakeTimeout = _asDuration(options['handshake_timeout_ms']);
    final maxHttpContentLength =
        options['max_http_content_length'] is int
            ? options['max_http_content_length'] as int
            : null;
    final tlsMode = _resolveTlsMode(settings.tls);
    final webSocketPath = settings.path;
    return Endpoint(
      host: parsed.host,
      port: parsed.port,
      tlsMode: tlsMode,
      idleTimeout: idleTimeout,
      handshakeTimeout: handshakeTimeout,
      maxHttpContentLength: maxHttpContentLength,
      maxRawSocketSizeExponent: maxExponent,
      webSocketPath: webSocketPath,
    );
  }

  _ParsedEndpoint _parseEndpoint(String value) {
    Uri? uri;
    if (value.contains('://')) {
      uri = Uri.tryParse(value);
    }
    if (uri != null && uri.host.isNotEmpty) {
      final port = uri.hasPort ? uri.port : 0;
      return _ParsedEndpoint(host: uri.host, port: port);
    }
    final lastColon = value.lastIndexOf(':');
    if (lastColon == -1) {
      throw FormatException('Endpoint "$value" missing port separator');
    }
    final host = value.substring(0, lastColon);
    final portPart = value.substring(lastColon + 1);
    final port = int.parse(portPart);
    return _ParsedEndpoint(host: host, port: port);
  }

  TlsMode _resolveTlsMode(Map<String, Object?>? tls) {
    if (tls == null) {
      return TlsMode.disabled;
    }
    final mode = tls['mode'];
    if (mode is String) {
      switch (mode.toLowerCase()) {
        case 'native':
          return TlsMode.native;
        case 'disabled':
        case 'none':
          return TlsMode.disabled;
      }
    }
    return TlsMode.native;
  }

  Duration? _asDuration(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return Duration(milliseconds: value);
    }
    if (value is String) {
      return Duration(milliseconds: int.parse(value));
    }
    throw FormatException('Expected duration value in milliseconds');
  }

  int _asInt(Object? value, {required int defaultValue}) {
    if (value == null) {
      return defaultValue;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.parse(value);
    }
    throw FormatException('Expected integer value');
  }
}

class _ParsedEndpoint {
  const _ParsedEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

ArgParser buildArgParser() {
  return ArgParser()
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
