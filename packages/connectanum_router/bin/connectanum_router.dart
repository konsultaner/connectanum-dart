import 'dart:async';
import 'dart:io';

import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> args) async {
  late final _Args parsed;
  try {
    parsed = _parseArgs(args);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }
  if (parsed.showHelp) {
    _printUsage();
    return;
  }

  _configureLogging(verbose: parsed.verbose);

  final nativeLibPath =
      parsed.nativeLibPath ?? Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (nativeLibPath == null || nativeLibPath.trim().isEmpty) {
    stderr.writeln(
      'Missing native library path. Provide --native-lib or set CONNECTANUM_NATIVE_LIB.',
    );
    exitCode = 64;
    return;
  }

  final configPath = parsed.configPath;
  RouterSettings routerSettings;
  try {
    routerSettings = await RouterConfigLoaderIo.fromFile(configPath);
  } catch (error) {
    stderr.writeln('Failed to load router config "$configPath": $error');
    exitCode = 64;
    return;
  }

  late final List<Endpoint> endpoints;
  try {
    endpoints = routerSettings.listeners
        .map(Endpoint.fromListenerSettings)
        .toList(growable: false);
  } catch (error) {
    stderr.writeln('Failed to parse endpoints from "$configPath": $error');
    exitCode = 64;
    return;
  }
  if (endpoints.isEmpty) {
    stderr.writeln('Router configuration must define at least one listener.');
    exitCode = 64;
    return;
  }

  registerDefaultAuthenticators();

  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(libraryPath: nativeLibPath);
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}\n'
      'Build ct_ffi and either place it next to the router executable or set CONNECTANUM_NATIVE_LIB.',
    );
    exitCode = 78;
    return;
  }

  runtime.setListenerCallbacks(
    onStarted: (listenerId, status) {
      if (status == NativeTransportErrorCode.success) {
        stdout.writeln('Listener $listenerId started');
      } else {
        stderr.writeln('Listener $listenerId failed: $status');
      }
    },
    onConnection: (listenerId, connectionId) {
      Logger(
        'router',
      ).fine('Listener $listenerId accepted connection $connectionId');
    },
  );

  runtime.start();

  RouterBinding? binding;
  try {
    final router = Router(
      RouterConfig(endpoints: endpoints),
      settings: routerSettings,
    );
    binding = router.start(runtime, onEvent: _logEvent);
    for (final listener in binding.listeners) {
      stdout.writeln(
        'Listening on ${listener.endpoint.host}:${listener.port} '
        '(listenerId=${listener.listenerId}, http3Port=${listener.http3Port})',
      );
    }

    final metricsSettings = routerSettings.metrics?.openMetrics;
    if (metricsSettings != null &&
        metricsSettings.enabled &&
        (metricsSettings.listen?.trim().isNotEmpty ?? false)) {
      try {
        final server = await binding.startOpenMetricsHttpServer(
          settingsOverride: metricsSettings,
        );
        if (server != null) {
          stdout.writeln(
            'OpenMetrics exporter listening on ${server.address.address}:${server.port}${metricsSettings.path} '
            '(healthz: /healthz)',
          );
        }
      } catch (error) {
        stderr.writeln('Failed to start OpenMetrics HTTP exporter: $error');
        exitCode = 64;
        return;
      }
    }

    stdout.writeln('Router running. Press Ctrl+C to stop.');
    var shuttingDown = false;
    var reloading = false;
    Future<void> reloadTls() async {
      if (shuttingDown || reloading) {
        return;
      }
      reloading = true;
      try {
        final newSettings = await RouterConfigLoaderIo.fromFile(configPath);
        final newEndpoints = newSettings.listeners
            .map(Endpoint.fromListenerSettings)
            .toList(growable: false);
        final reloadRouter = Router(
          RouterConfig(endpoints: newEndpoints),
          settings: newSettings,
        );
        final nativeConfig = reloadRouter.buildNativeConfigJson(newSettings);
        runtime.applyRouterConfig(nativeConfig);
        final count = runtime.reloadTls();
        stdout.writeln('Reloaded TLS configuration for $count listener(s).');
      } catch (error) {
        stderr.writeln('Failed to reload TLS configuration: $error');
      } finally {
        reloading = false;
      }
    }

    final hupSubscription = ProcessSignal.sighup.watch().listen((_) {
      unawaited(reloadTls());
    });
    await Future.any([
      ProcessSignal.sigint.watch().first,
      ProcessSignal.sigterm.watch().first,
    ]);
    shuttingDown = true;
    await hupSubscription.cancel();
  } finally {
    try {
      await binding?.dispose();
    } catch (_) {}
    runtime.shutdown();
    runtime.dispose();
  }
  exit(exitCode);
}

void _logEvent(Object event) {
  Logger('router.event').fine(event.toString());
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

void _printUsage() {
  stdout.writeln(
    'Usage: dart run connectanum_router --config <path> [--native-lib <path>] [--verbose]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --config <path>      Router config file (.json/.yaml/.yml).',
  );
  stdout.writeln(
    '  --native-lib <path>  Path to libct_ffi (defaults to CONNECTANUM_NATIVE_LIB).',
  );
  stdout.writeln('  --verbose            Enable verbose logging.');
  stdout.writeln('  --help               Show this help message.');
}

class _Args {
  const _Args({
    required this.configPath,
    this.nativeLibPath,
    required this.verbose,
    required this.showHelp,
  });

  final String configPath;
  final String? nativeLibPath;
  final bool verbose;
  final bool showHelp;
}

_Args _parseArgs(List<String> args) {
  var configPath = 'router.yaml';
  String? nativeLibPath;
  var verbose = false;
  var showHelp = false;

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    switch (arg) {
      case '--help':
      case '-h':
        showHelp = true;
        break;
      case '--verbose':
      case '-v':
        verbose = true;
        break;
      case '--config':
      case '-c':
        if (i + 1 >= args.length) {
          throw ArgumentError('Missing value for $arg');
        }
        configPath = args[++i];
        break;
      case '--native-lib':
        if (i + 1 >= args.length) {
          throw ArgumentError('Missing value for $arg');
        }
        nativeLibPath = args[++i];
        break;
      default:
        if (arg.startsWith('-')) {
          throw ArgumentError('Unknown argument: $arg');
        }
        configPath = arg;
    }
  }

  return _Args(
    configPath: configPath,
    nativeLibPath: nativeLibPath,
    verbose: verbose,
    showHelp: showHelp,
  );
}
