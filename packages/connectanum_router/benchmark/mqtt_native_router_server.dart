import 'dart:io';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';

/// Native TCP MQTT router process for matched broker benchmarks.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('expected listener port');
  final port = int.parse(args.single);
  final libraryPath = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (libraryPath == null || libraryPath.isEmpty) {
    throw StateError('CONNECTANUM_NATIVE_LIB is required');
  }
  final runtime = NativeTransportRuntime(libraryPath: libraryPath)..start();
  final settings = RouterSettingsBuilder()
    ..addListenerFromBuilder(
      ListenerSettingsBuilder('mqtt', '127.0.0.1:$port')
        ..addProtocol(ListenerProtocol.mqtt),
    );
  final binding = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: port,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: settings.build(),
  ).start(runtime);
  stdout.writeln('ready ${binding.listeners.single.port}');
  await stdin.drain<void>();
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();
}
