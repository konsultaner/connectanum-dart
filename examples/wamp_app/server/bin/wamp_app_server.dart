import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'wamp_app_server.yaml')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln('Usage: dart run wamp_app_server --config <path>');
    stdout.writeln(parser.usage);
    return;
  }

  final config = await WampAppServerConfig.load(options.option('config')!);
  final server = await WampAppServer.start(config);
  stdout.writeln('WampApp listening on ${server.websocketUri}');
  stdout.writeln('Press Ctrl+C to stop.');

  await Future.any([
    ProcessSignal.sigint.watch().first,
    ProcessSignal.sigterm.watch().first,
  ]);
  await server.close();
}
