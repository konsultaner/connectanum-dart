import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:connectanum_core/src/message/invocation.dart' as invocation_msg;
import 'package:connectanum_core/src/message/registered.dart' as registered_msg;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'router-config',
      help: 'Path to router config JSON consumed by RouterConfigLoaderIo.',
      defaultsTo: 'native/bench/bench_router.json',
    )
    ..addOption(
      'native-lib',
      help: 'Path to libct_ffi.so (defaults to CONNECTANUM_NATIVE_LIB env).',
    )
    ..addOption(
      'control-realm',
      help: 'Realm used for control RPCs.',
      defaultsTo: 'bench.control',
    )
    ..addFlag('verbose', negatable: true, defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false);

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

  _configureLogging(verbose: results['verbose'] as bool);

  final routerConfigPath = results['router-config'] as String;
  final nativeLib =
      (results['native-lib'] as String?) ??
      Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (nativeLib == null || nativeLib.isEmpty) {
    stderr.writeln(
      'Missing native library path. Provide --native-lib or set CONNECTANUM_NATIVE_LIB.',
    );
    exitCode = 64;
    return;
  }

  final controlRealm = results['control-realm'] as String;

  final runner = _BenchRouterService(
    routerConfigPath: routerConfigPath,
    nativeLibraryPath: nativeLib,
    controlRealm: controlRealm,
  );

  final sigintSub = ProcessSignal.sigint.watch().listen(
    (_) => runner.requestShutdown('SIGINT'),
  );
  final sigtermSub = ProcessSignal.sigterm.watch().listen(
    (_) => runner.requestShutdown('SIGTERM'),
  );

  try {
    await runner.run();
  } catch (error, stackTrace) {
    Logger('bench_main').severe('Bench runner failed', error, stackTrace);
    exitCode = 1;
  } finally {
    await sigintSub.cancel();
    await sigtermSub.cancel();
  }
}

void _configureLogging({required bool verbose}) {
  Logger.root
    ..level = verbose ? Level.ALL : Level.INFO
    ..onRecord.listen((record) {
      final time = record.time.toIso8601String();
      final logger = record.loggerName;
      final level = record.level.name;
      final message = record.message;
      stderr.writeln('[$time][$level][$logger] $message');
      if (record.error != null) {
        stderr.writeln('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        stderr.writeln(record.stackTrace);
      }
    });
}

class _BenchRouterService {
  _BenchRouterService({
    required this.routerConfigPath,
    required this.nativeLibraryPath,
    required this.controlRealm,
  });

  final String routerConfigPath;
  final String nativeLibraryPath;
  final String controlRealm;

  final _logger = Logger('BenchRouterService');
  final _shutdownCompleter = Completer<void>();
  Timer? _forceExitTimer;

  NativeTransportRuntime? _runtime;
  RouterBinding? _binding;
  _BenchControlRegistry? _controlRegistry;
  StreamSubscription<String>? _stdinSubscription;

  Future<void> run() async {
    var teardownStarted = false;
    try {
      final routerSettings = await RouterConfigLoaderIo.fromFile(
        routerConfigPath,
      );
      final endpoints = routerSettings.listeners
          .map(Endpoint.fromListenerSettings)
          .toList(growable: false);
      if (endpoints.isEmpty) {
        throw StateError(
          'Router configuration must define at least one listener',
        );
      }
      final routerConfig = RouterConfig(endpoints: endpoints);
      final primaryEndpoint = endpoints.first;

      final runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
      runtime.start();
      _runtime = runtime;

      final router = Router(routerConfig, settings: routerSettings);
      final binding = router.start(
        runtime,
        onEvent: (event) => _logger.fine('router_event: $event'),
      );
      _binding = binding;

      final controlSession = await binding.createInternalSession(
        realmUri: controlRealm,
        authId: 'bench-control',
        authRole: 'bench',
      );
      final control = _BenchControlRegistry(
        binding: binding,
        session: controlSession,
        onStopRequested: () => requestShutdown('RPC'),
        routerHost: primaryEndpoint.host,
        routerPort: primaryEndpoint.port,
        realmUri: controlRealm,
      );
      await control.initialize();
      _controlRegistry = control;

      _listenForStdin();

      stdout.writeln('READY');

      await _shutdownCompleter.future;
    } finally {
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete();
      }
      if (!teardownStarted) {
        teardownStarted = true;
        await _teardown();
      }
    }
  }

  void _listenForStdin() {
    _stdinSubscription = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final normalized = line.trim().toUpperCase();
          if (normalized == 'STOP' || normalized == 'SHUTDOWN') {
            requestShutdown('stdin');
          }
        });
  }

  void requestShutdown(String reason) {
    if (_shutdownCompleter.isCompleted) {
      return;
    }
    _logger.info('Shutdown requested via $reason');
    _controlRegistry?.markStopping();
    _forceExitTimer ??= Timer(const Duration(seconds: 30), () {
      _logger.severe('Shutdown deadline exceeded, forcing process exit');
      exit(1);
    });
    _shutdownCompleter.complete();
  }

  Future<void> _teardown() async {
    _logger.info('Teardown starting');
    await _stdinSubscription?.cancel();
    final control = _controlRegistry;
    if (control != null) {
      _logger.fine('Disposing control registry');
      await control.dispose();
    }
    if (_binding != null) {
      _logger.fine('Disposing router binding');
      try {
        // Capture a pre-dispose snapshot for debugging shutdown hangs.
        try {
          final metrics = await _binding!.collectMetrics();
          _logger.info(
            'Pre-dispose metrics: sessions=${metrics.sessionCount} '
            'pending_invocations=${metrics.pendingInvocationCount} '
            'registrations=${metrics.registrationCount} '
            'transport=${metrics.transport}',
          );
          _logger.info(
            'Realm sessions=${metrics.realmCount} '
            'total_publications=${metrics.totalPublicationsRouted} '
            'total_invocations=${metrics.totalInvocationsDispatched}',
          );
        } catch (error, stackTrace) {
          _logger.warning(
            'Failed to collect metrics pre-dispose',
            error,
            stackTrace,
          );
        }
        await _binding!.dispose().timeout(const Duration(seconds: 20));
      } on TimeoutException {
        _logger.severe(
          'Router binding disposal timed out; collecting metrics before force shutdown',
        );
        try {
          final metrics = await _binding!.collectMetrics();
          _logger.severe(
            'Pending before force shutdown: '
            'sessions=${metrics.sessionCount} '
            'pending_invocations=${metrics.pendingInvocationCount} '
            'registrations=${metrics.registrationCount} '
            'transport=${metrics.transport}',
          );
          _logger.severe(
            'Realm sessions: ${metrics.realmCount} '
            'total_publications=${metrics.totalPublicationsRouted} '
            'total_invocations=${metrics.totalInvocationsDispatched}',
          );
        } catch (error, stackTrace) {
          _logger.severe(
            'Failed to collect metrics on timeout',
            error,
            stackTrace,
          );
        }
      }
    }
    _logger.fine('Shutting down native runtime');
    _runtime?.shutdown();
    _runtime?.dispose();
    _forceExitTimer?.cancel();
    _forceExitTimer = null;
    _logger.info('Teardown complete');
  }
}

class _BenchControlRegistry {
  _BenchControlRegistry({
    required this.binding,
    required this.session,
    required this.onStopRequested,
    required this.routerHost,
    required this.routerPort,
    required this.realmUri,
  }) {
    final sessionFactory = RawSocketWampSessionFactory(
      host: routerHost,
      port: routerPort,
      realmUri: realmUri,
    );
    _wampRunner = WampWorkloadRunner(
      sessionFactory: sessionFactory.call,
      logger: _logger,
    );
  }

  final RouterBinding binding;
  final RouterSession session;
  final void Function() onStopRequested;
  final String routerHost;
  final int routerPort;
  final String realmUri;

  final _logger = Logger('BenchControlRegistry');
  final List<registered_msg.Registered> _registrations = [];
  bool _stopping = false;
  late final WampWorkloadRunner _wampRunner;

  void markStopping() {
    _stopping = true;
  }

  Future<void> initialize() async {
    await _register('bench.control.metrics', _handleMetricsInvoke);
    await _register('bench.control.stop', _handleStopInvoke);
    await _register('bench.http.healthz', _handleHealthzInvoke);
    await _register('bench.http.metrics', _handleMetricsInvoke);
    await _register('bench.http.stop', _handleStopInvoke);
    await _register('bench.http.stream', _handleStreamInvoke);
    await _register('bench.http.wamp', _handleWampInvoke);
    await _register('bench.rpc.echo', _handleRpcEchoInvoke);
  }

  Future<void> dispose() async {
    for (final registration in _registrations) {
      await session.unregister(registration.registrationId);
    }
    _registrations.clear();
  }

  Future<void> _register(
    String procedure,
    FutureOr<void> Function(invocation_msg.Invocation) handler,
  ) async {
    final registration = await session.register(procedure);
    registration.onInvoke(handler);
    _registrations.add(registration);
  }

  Future<void> _handleHealthzInvoke(
    invocation_msg.Invocation invocation,
  ) async {
    final context = HttpInvocationContext.maybeFromInvocation(invocation);
    if (context == null) {
      invocation.respondWith(arguments: ['http_only']);
      return;
    }
    context.sendJson(
      body: {
        'status': 'ok',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _handleMetricsInvoke(
    invocation_msg.Invocation invocation,
  ) async {
    try {
      final snapshot = await binding.collectMetrics();
      final openMetrics = await binding.collectOpenMetricsText(snapshot);
      final metricsPayload = snapshot.toJson();
      final responseKeywords = <String, Object?>{
        'metrics': metricsPayload,
        if (openMetrics != null) 'open_metrics': openMetrics,
      };
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      if (context != null) {
        _logger.fine('HTTP metrics request served');
        context.sendJson(body: responseKeywords);
        return;
      }
      _logger.fine('RPC metrics request served');
      invocation.respondWith(argumentsKeywords: responseKeywords);
    } catch (error, stackTrace) {
      _reportError('metrics_error', error, stackTrace);
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      if (context != null) {
        context.sendJson(
          status: 500,
          body: {
            'error': 'failed_to_collect_metrics',
            'reason': error.toString(),
          },
        );
        return;
      }
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.runtimeError,
        arguments: ['failed to collect metrics'],
        argumentsKeywords: {'reason': error.toString()},
      );
    }
  }

  Future<void> _handleStopInvoke(invocation_msg.Invocation invocation) async {
    _stopping = true;
    final context = HttpInvocationContext.maybeFromInvocation(invocation);
    if (context != null) {
      context.sendJson(status: 202, body: {'status': 'stopping'});
    } else {
      invocation.respondWith(arguments: ['ok']);
    }
    onStopRequested();
  }

  Future<void> _handleStreamInvoke(invocation_msg.Invocation invocation) async {
    final context = HttpInvocationContext.maybeFromInvocation(invocation);
    if (context == null) {
      invocation.respondWith(arguments: ['no_http_context']);
      return;
    }
    final payload = context.request.body ?? Uint8List(0);
    final responseBytes = _parseHeaderInt(
      context.request.headers,
      'x-bench-response-bytes',
    );
    final responseChunkBytes =
        _parseHeaderInt(
          context.request.headers,
          'x-bench-response-chunk-bytes',
        ) ??
        math.min(payload.length, 64 * 1024);
    final response = context.streamResponse(
      status: 207,
      headers: const {
        'content-type': 'application/octet-stream',
        'x-bench': 'stream',
      },
    );
    if (responseBytes != null && responseBytes > 0) {
      final chunk = _buildPatternChunk(math.max(1, responseChunkBytes));
      var remaining = responseBytes;
      while (remaining > 0) {
        final sliceLength = math.min(remaining, chunk.length);
        response.add(Uint8List.sublistView(chunk, 0, sliceLength));
        remaining -= sliceLength;
      }
    } else if (payload.isEmpty) {
      response.add(Uint8List.fromList('bench'.codeUnits));
    } else {
      response.add(payload);
    }
    response.close();
  }

  Future<void> _handleWampInvoke(invocation_msg.Invocation invocation) async {
    if (_stopping) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      if (context != null) {
        context.sendJson(status: 503, body: {'error': 'stopping'});
      } else {
        invocation.respondWith(
          isError: true,
          errorUri: wamp_core.Error.runtimeError,
          arguments: ['router_stopping'],
          argumentsKeywords: {'reason': 'bench control stopping'},
        );
      }
      return;
    }
    final context = HttpInvocationContext.maybeFromInvocation(invocation);
    if (context == null) {
      invocation.respondWith(
        isError: true,
        errorUri: wamp_core.Error.runtimeError,
        arguments: ['wamp benchmark requires HTTP'],
      );
      return;
    }
    final rawBody = context.request.body;
    if (rawBody == null || rawBody.isEmpty) {
      context.sendJson(status: 400, body: {'error': 'missing_body'});
      return;
    }
    Map<String, Object?> payload;
    try {
      payload = json.decode(utf8.decode(rawBody)) as Map<String, Object?>;
    } catch (error) {
      context.sendJson(
        status: 400,
        body: {'error': 'invalid_json', 'reason': error.toString()},
      );
      return;
    }
    try {
      final scenario = WampScenario.fromJson(payload);
      final samples = await _wampRunner.run(scenario);
      context.sendJson(
        body: {'samples': samples.map((sample) => sample.toJson()).toList()},
      );
    } catch (error, stackTrace) {
      _reportError('wamp_error', error, stackTrace);
      try {
        final snapshot = await binding.collectMetrics();
        _logger.warning(
          'WAMP handler failure metrics: '
          'pending_invocations=${snapshot.pendingInvocationCount} '
          'sessions=${snapshot.sessionCount} '
          'registrations=${snapshot.registrationCount} '
          'total_invocations=${snapshot.totalInvocationsDispatched} '
          'total_publications=${snapshot.totalPublicationsRouted}',
        );
      } catch (_) {}
      context.sendJson(
        status: 500,
        body: {'error': 'wamp_scenario_failed', 'reason': error.toString()},
      );
    }
  }

  Future<void> _handleRpcEchoInvoke(
    invocation_msg.Invocation invocation,
  ) async {
    _logger.fine(
      'RPC echo invoked requestId=${invocation.requestId} '
      'args=${invocation.arguments} kwargs=${invocation.argumentsKeywords}',
    );
    invocation.respondWith(
      arguments: invocation.arguments,
      argumentsKeywords: invocation.argumentsKeywords,
    );
    _logger.fine('RPC echo responded requestId=${invocation.requestId}');
  }

  void _reportError(String type, Object error, StackTrace stackTrace) {
    _logger.warning('Control handler error ($type)', error, stackTrace);
    binding.onEvent?.call({
      'source': 'bench',
      'type': type,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }

  int? _parseHeaderInt(Map<String, String> headers, String headerName) {
    final lower = headerName.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return int.tryParse(entry.value);
      }
    }
    return null;
  }
}

Uint8List _buildPatternChunk(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31) & 0xFF;
  }
  return bytes;
}
