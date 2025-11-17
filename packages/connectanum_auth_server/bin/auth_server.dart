import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      valueHelp: 'path',
      help: 'Path to a router/auth configuration file (JSON or YAML).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    );

  ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (error) {
    _printUsage(parser, error: error.message);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (results['help'] as bool) {
    _printUsage(parser);
    return;
  }

  final configPath = results['config'] as String?;
  if (configPath == null) {
    _printUsage(parser, error: 'Missing --config <path>');
    exitCode = 64;
    return;
  }

  try {
    final settings = await RouterConfigLoaderIo.fromFile(configPath);
    final authServer = AuthServer(settings: settings);
    stdout.writeln(
      'Loaded configuration from $configPath for realms: '
      '${settings.realms.map((realm) => realm.name).join(', ')}',
    );
    stdout.writeln(
      'AuthServer instance created (integration with router runtime pending).',
    );
    // Placeholder until runtime wiring is implemented.
    stdout.writeln('Instance hash: ${authServer.hashCode}.');
  } on FormatException catch (error) {
    stderr.writeln('Failed to parse configuration: ${error.message}');
    exitCode = 65; // EX_DATAERR
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to read configuration: ${error.message}');
    exitCode = 66; // EX_NOINPUT
  } catch (error, stackTrace) {
    stderr.writeln('Unexpected error: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

void _printUsage(ArgParser parser, {String? error}) {
  if (error != null) {
    stderr.writeln(error);
  }
  stdout
    ..writeln('Usage: auth_server --config <path>')
    ..writeln(parser.usage);
}
