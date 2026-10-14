import 'dart:io';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';

/// Native TCP or TLS MQTT router process for matched broker benchmarks.
Future<void> main(List<String> args) async {
  if (args.length != 1 && args.length != 3) {
    throw ArgumentError('expected listener port [certificate key]');
  }
  final port = int.parse(args[0]);
  final tls = args.length == 3;
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
  final binding =
      Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: port,
              tlsMode: tls ? TlsMode.native : TlsMode.disabled,
              maxRawSocketSizeExponent: 16,
              sniCertificates: tls
                  ? [
                      SniCertificate(
                        hostname: 'localhost',
                        certificateChainPem: File(args[1]).readAsStringSync(),
                        privateKeyPem: File(args[2]).readAsStringSync(),
                      ),
                    ]
                  : const [],
            ),
          ],
        ),
        settings: settings.build(),
      ).start(
        runtime,
        onEvent: (event) {
          if (event is Map && event['type'] == 'mqtt_connection_closed') {
            stderr.writeln(event);
          }
        },
      );
  stdout.writeln('ready ${binding.listeners.single.port}');
  await stdin.drain<void>();
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();
}
