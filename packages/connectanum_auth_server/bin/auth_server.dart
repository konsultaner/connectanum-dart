import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  final parser = _buildParser();
  late final _Args parsed;
  try {
    parsed = _parseArgs(parser, args);
  } on ArgParserException catch (error) {
    _printUsage(parser, error: error.message);
    exitCode = 64; // EX_USAGE
    return;
  } on _UsageException catch (error) {
    _printUsage(parser, error: error.message);
    exitCode = 64;
    return;
  }

  if (parsed.showHelp) {
    _printUsage(parser);
    return;
  }

  NativeTransportRuntime? runtime;
  RouterBinding? routerBinding;
  AuthServerProcedureBinding? procedureBinding;
  try {
    final configPath = parsed.configPath;
    final settings = await RouterConfigLoaderIo.fromFile(configPath);
    final authServer = AuthServer(settings: settings);
    final endpoints = settings.listeners
        .map(Endpoint.fromListenerSettings)
        .toList(growable: false);
    if (endpoints.isEmpty) {
      stderr.writeln(
        'Configuration must define at least one listener for the auth service.',
      );
      exitCode = 64;
      return;
    }
    if (!settings.realms.any((realm) => realm.name == parsed.realm)) {
      stderr.writeln(
        'Configuration must define the auth service realm "${parsed.realm}".',
      );
      exitCode = 64;
      return;
    }

    runtime = NativeTransportRuntime(libraryPath: parsed.nativeLibPath);
    runtime.setListenerCallbacks(
      onStarted: (listenerId, status) {
        if (status == NativeTransportErrorCode.success) {
          stdout.writeln('Auth listener $listenerId started.');
        } else {
          stderr.writeln('Auth listener $listenerId failed: $status.');
        }
      },
      onConnection: (listenerId, connectionId) {
        stdout.writeln(
          'Auth listener $listenerId accepted connection $connectionId.',
        );
      },
    );
    runtime.start();

    final router = Router(
      RouterConfig(endpoints: endpoints),
      settings: settings,
    );
    routerBinding = router.start(runtime);
    final session = await routerBinding.createInternalSession(
      realmUri: parsed.realm,
      authId: parsed.authId,
      authRole: parsed.authRole,
    );
    procedureBinding = await AuthServerProcedureBinding.bind(
      server: authServer,
      session: session,
    );

    stdout.writeln(
      'Loaded configuration from $configPath for realms: '
      '${settings.realms.map((realm) => realm.name).join(', ')}',
    );
    for (final listener in routerBinding.listeners) {
      stdout.writeln(
        'Auth service listening on ${listener.endpoint.host}:${listener.port} '
        '(listenerId=${listener.listenerId}, http3Port=${listener.http3Port})',
      );
    }
    stdout.writeln(
      'Auth server procedures bound on realm ${parsed.realm}: '
      '${procedureBinding.helloProcedure}, '
      '${procedureBinding.authenticateProcedure}, '
      '${procedureBinding.abortProcedure}.',
    );
    if (parsed.check) {
      stdout.writeln('Auth server runtime check completed.');
      return;
    }
    stdout.writeln('Auth server running. Press Ctrl+C to stop.');
    await Future.any([
      ProcessSignal.sigint.watch().first,
      ProcessSignal.sigterm.watch().first,
    ]);
  } on FormatException catch (error) {
    stderr.writeln('Failed to parse configuration: ${error.message}');
    exitCode = 65; // EX_DATAERR
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to read configuration: ${error.message}');
    exitCode = 66; // EX_NOINPUT
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}',
    );
    exitCode = 78; // EX_CONFIG
  } catch (error, stackTrace) {
    stderr.writeln('Unexpected error: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    try {
      await procedureBinding?.close();
    } catch (_) {}
    try {
      await routerBinding?.dispose();
    } catch (_) {}
    try {
      runtime?.shutdown();
    } catch (_) {}
    runtime?.dispose();
  }
}

ArgParser _buildParser() => ArgParser()
  ..addOption(
    'config',
    abbr: 'c',
    valueHelp: 'path',
    help: 'Path to a router/auth service configuration file (JSON or YAML).',
  )
  ..addOption(
    'native-lib',
    valueHelp: 'path',
    help:
        'Path to libct_ffi. Defaults to CONNECTANUM_NATIVE_LIB or build-hook resolution.',
  )
  ..addOption(
    'realm',
    defaultsTo: 'connectanum.authenticate',
    valueHelp: 'uri',
    help: 'Service realm where auth procedures are registered.',
  )
  ..addOption(
    'auth-id',
    defaultsTo: 'auth-service',
    valueHelp: 'id',
    help: 'Auth ID for the internal procedure registration session.',
  )
  ..addOption(
    'auth-role',
    defaultsTo: 'internal',
    valueHelp: 'role',
    help: 'Auth role for the internal procedure registration session.',
  )
  ..addFlag(
    'check',
    negatable: false,
    help: 'Start, bind auth procedures, report readiness, then exit.',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show usage information.',
  );

_Args _parseArgs(ArgParser parser, List<String> args) {
  final results = parser.parse(args);
  if (results['help'] as bool) {
    return const _Args(configPath: '', showHelp: true);
  }
  final configPath = _trimmed(results['config'] as String?);
  if (configPath == null) {
    throw const _UsageException('Missing --config <path>');
  }
  final nativeLibPath =
      _trimmed(results['native-lib'] as String?) ??
      _trimmed(Platform.environment['CONNECTANUM_NATIVE_LIB']);
  final realm = _trimmed(results['realm'] as String?);
  if (realm == null) {
    throw const _UsageException('--realm must not be empty');
  }
  final authId = _trimmed(results['auth-id'] as String?);
  if (authId == null) {
    throw const _UsageException('--auth-id must not be empty');
  }
  final authRole = _trimmed(results['auth-role'] as String?);
  if (authRole == null) {
    throw const _UsageException('--auth-role must not be empty');
  }
  return _Args(
    configPath: configPath,
    nativeLibPath: nativeLibPath,
    realm: realm,
    authId: authId,
    authRole: authRole,
    check: results['check'] as bool,
  );
}

String? _trimmed(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

void _printUsage(ArgParser parser, {String? error}) {
  if (error != null) {
    stderr.writeln(error);
  }
  stdout
    ..writeln('Usage: auth_server --config <path> [options]')
    ..writeln(parser.usage);
}

class _Args {
  const _Args({
    required this.configPath,
    this.nativeLibPath,
    this.realm = 'connectanum.authenticate',
    this.authId = 'auth-service',
    this.authRole = 'internal',
    this.check = false,
    this.showHelp = false,
  });

  final String configPath;
  final String? nativeLibPath;
  final String realm;
  final String authId;
  final String authRole;
  final bool check;
  final bool showHelp;
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}
