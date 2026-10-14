@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  test('native listener negotiates MQTT and HTTP on one TCP port', () async {
    final port = await _startRouter(
      protocols: [ListenerProtocol.mqtt, ListenerProtocol.http],
    );
    final client = await MqttQos0Client.connect(
      '127.0.0.1',
      port,
      clientId: 'mixed-listener-mqtt',
    );
    addTearDown(client.close);
    await client.ping();
    final http = HttpClient();
    addTearDown(http.close);
    final request = await http.getUrl(
      Uri.parse('http://127.0.0.1:$port/unmapped'),
    );
    final response = await request.close();
    expect(response.statusCode, isIn([400, 404, 501]));
    await response.drain<void>();
  });

  test(
    'native MQTT listener exchanges exact QoS 0 bytes across versions',
    () async {
      final port = await _startRouter();
      final subscriber = await MqttQos0Client.connect(
        '127.0.0.1',
        port,
        clientId: 'native-v311-sub',
        version: MqttVersion.v311,
      );
      final publisher = await MqttQos0Client.connect(
        '127.0.0.1',
        port,
        clientId: 'native-v5-pub',
        version: MqttVersion.v5,
      );
      addTearDown(() async {
        await publisher.close();
        await subscriber.close();
      });
      await subscriber.subscribe('native/+/raw');
      final received = subscriber.messages.first.timeout(
        const Duration(seconds: 5),
      );
      await publisher.publish(
        'native/one/raw',
        Uint8List.fromList([0, 255, 17, 0]),
      );
      final publication = await received;
      expect(publication.topic, 'native/one/raw');
      expect(publication.payload, [0, 255, 17, 0]);
      expect(publication.qos, 0);
    },
  );

  test(
    'native MQTT listener exchanges exact binary bytes with Paho 5 and 3.1.1',
    () async {
      final port = await _startRouter();
      final client = await MqttQos0Client.connect(
        '127.0.0.1',
        port,
        clientId: 'native-dart-peer',
      );
      addTearDown(client.close);
      await client.subscribe('test/from-paho');
      final incoming = client.messages.first.timeout(
        const Duration(seconds: 5),
      );
      final process = await Process.start(
        Platform.environment['PAHO_PYTHON']!,
        ['test/mqtt/paho_qos0_peer.py', '$port'],
      );
      addTearDown(() => process.kill());
      final ready = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      expect(ready, 'READY');
      expect((await incoming).payload, [0, 255, 0, 17]);
      await client.publish('test/to-paho', Uint8List.fromList([17, 0, 255]));
      final stderr = await process.stderr.transform(utf8.decoder).join();
      expect(
        await process.exitCode.timeout(const Duration(seconds: 5)),
        0,
        reason: stderr,
      );
    },
    skip: Platform.environment['PAHO_PYTHON'] == null
        ? 'set PAHO_PYTHON to a Python with paho-mqtt 2.1.0'
        : false,
  );
}

Future<int> _startRouter({
  List<ListenerProtocol> protocols = const [ListenerProtocol.mqtt],
}) async {
  final nativeLib = resolveOrBuildNativeLib();
  expect(nativeLib, isNotNull);
  final runtime = NativeTransportRuntime(libraryPath: nativeLib);
  runtime.start();
  final listener = ListenerSettingsBuilder('mqtt', '127.0.0.1:0');
  for (final protocol in protocols) {
    listener.addProtocol(protocol);
  }
  final settings = RouterSettingsBuilder()..addListenerFromBuilder(listener);
  final binding = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: settings.build(),
  ).start(runtime);
  addTearDown(() async {
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  });
  return binding.listeners.single.port;
}
