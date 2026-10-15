import 'dart:io';

import 'package:connectanum_router/mqtt.dart';

/// Dedicated broker process for a matched MQTT benchmark.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('expected listener port');
  final broker = await MqttQos0Broker.bind('127.0.0.1', int.parse(args.single));
  stdout.writeln('ready ${broker.port}');
  await stdin.drain<void>();
  await broker.close();
}
