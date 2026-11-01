@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_bench/src/mqtt_gateway_worker.dart';
import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/connectanum_router.dart' as router;
import 'package:test/test.dart';

import '../../connectanum_router/test/support/native_lib.dart';

Future<void> _serve(List<Object?> args) async {
  final reply = args[0] as SendPort;
  final commands = ReceivePort();
  final server = await NativeGatewayBenchmarkServer.start(
    GatewayBenchmarkConfig((args[1] as Map).cast<String, dynamic>()),
  );
  try {
    reply.send([commands.sendPort, server.port]);
    await for (final raw in commands) {
      final command = raw as List;
      final output = command[1] as SendPort;
      if (command[0] == 'metrics') {
        output.send(server.metrics);
      } else {
        await server.close();
        output.send(null);
        return;
      }
    }
  } finally {
    commands.close();
  }
}

Future<
  ({int port, Future<Map> Function() metrics, Future<void> Function() close})
>
_server(Map<String, dynamic> config) async {
  final ready = ReceivePort();
  final isolate = await Isolate.spawn(_serve, [ready.sendPort, config]);
  final response =
      await ready.first.timeout(const Duration(seconds: 10)) as List;
  ready.close();
  final commands = response[0] as SendPort;
  Future<Object?> request(String op) async {
    final reply = ReceivePort();
    try {
      commands.send([op, reply.sendPort]);
      return await reply.first.timeout(const Duration(seconds: 5));
    } finally {
      reply.close();
    }
  }

  return (
    port: response[1] as int,
    metrics: () async => (await request('metrics')) as Map,
    close: () async {
      try {
        await request('close');
      } finally {
        isolate.kill(priority: Isolate.immediate);
      }
    },
  );
}

void main() {
  final root = Directory.current.path.endsWith('connectanum_bench')
      ? '../..'
      : '.';
  final library = resolveOrBuildNativeLib()!;
  // Reuse the same owned test CA as the existing MQTT interoperability gates.
  final certificate = File(
    '$root/packages/connectanum_router/test/certs/remote_auth_server_cert.pem',
  );
  final Map<String, dynamic> base = {
    'path': 'mqtt_to_wamp',
    'transport': 'tcp',
    'serializer': 'cbor',
    'mqtt_version': '5',
    'payload_bytes': 128,
    'window': 1,
    'port': 0,
    'native_library': library,
  };
  for (final link in ['tcp', 'tls', 'ws', 'wss']) {
    for (final codec in ['json', 'msgpack', 'cbor', 'flatbuffers']) {
      for (final direction in ['mqtt_to_wamp', 'wamp_to_mqtt']) {
        test('native $link $codec $direction keeps exact binary bytes', () async {
          final config = {
            ...base,
            'path': direction,
            'transport': link,
            'serializer': codec,
            'mqtt_version': codec == 'json' || codec == 'cbor' ? '5' : '3.1.1',
            'certificate': certificate.absolute.path,
            'key': File(
              '$root/packages/connectanum_router/test/certs/remote_auth_server_key.pem',
            ).absolute.path,
          };
          // Native WebSocket open performs a synchronous FFI handshake. Keep
          // the router's negotiation loop in an independently running isolate.
          final server = await _server(config);
          addTearDown(server.close);
          final live = GatewayBenchmarkConfig({...config, 'port': server.port});
          Future<GatewayBenchmarkPeer> connect(String role) async {
            try {
              return await connectGatewayBenchmarkPeer(live, role);
            } on wamp.Abort catch (error) {
              throw StateError('$role: ${error.reason}: ${error.details}');
            }
          }

          final subscriber = await connect('subscriber');
          addTearDown(subscriber.close);
          final publisher = await connect('publisher');
          addTearDown(publisher.close);
          final received = subscriber.messages
              .take(2)
              .toList()
              .timeout(const Duration(seconds: 5));
          final bytes = [
            Uint8List.fromList([0, 255, 16, 0]),
            Uint8List(65536)..[65535] = 255,
          ];
          for (final payload in bytes) {
            await publisher.publish(payload);
          }
          expect(await received, bytes);
          expect(
            (await server.metrics())[direction == 'mqtt_to_wamp'
                ? 'mqtt_publications'
                : 'wamp_publications'],
            2,
          );
        });
      }
    }
  }

  test(
    'ordinary WAMP output cannot masquerade as a translated MQTT event',
    () async {
      final server = await NativeGatewayBenchmarkServer.start(
        GatewayBenchmarkConfig(base),
      );
      addTearDown(server.close);
      final subscriber = await connectGatewayBenchmarkPeer(
        GatewayBenchmarkConfig({...base, 'port': server.port}),
        'subscriber',
      );
      addTearDown(subscriber.close);
      final session = await wamp.Client(
        realm: GatewayBenchmarkConfig.realm,
        transport: wamp.NativeRawSocketTransport.withCborSerializer(
          '127.0.0.1',
          server.port,
          libraryPath: library,
        ),
      ).connect().first;
      addTearDown(() => session.close(timeout: Duration.zero));
      final rejected = expectLater(
        subscriber.messages.first,
        throwsFormatException,
      );
      await session.publish(
        MqttTopicUriMapper.toWampUri(GatewayBenchmarkConfig.topic),
        arguments: [Uint8List(1)],
        options: wamp.PublishOptions(acknowledge: true),
      );
      await rejected;
    },
  );

  test(
    'failed server setup releases the native runtime before retry',
    () async {
      await expectLater(
        NativeGatewayBenchmarkServer.start(
          GatewayBenchmarkConfig({
            ...base,
            'transport': 'tls',
            'certificate': 'missing-certificate.pem',
            'key': 'missing-key.pem',
          }),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        NativeGatewayBenchmarkServer.start(
          GatewayBenchmarkConfig(base),
          createGateway: (_) async => throw StateError('gateway setup failed'),
        ),
        throwsStateError,
      );
      final server = await NativeGatewayBenchmarkServer.start(
        GatewayBenchmarkConfig(base),
      );
      await server.close();
    },
  );

  test(
    'a rejected MQTT subscription closes the connected participant',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      final closed = Completer<void>();
      final listener = server.listen((socket) {
        final decoder = MqttFrameDecoder();
        socket.listen(
          (bytes) {
            for (final frame in decoder.add(bytes)) {
              if (frame.type == MqttPacketType.connect) {
                socket.add(
                  MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 0),
                );
              } else if (frame.type == MqttPacketType.subscribe) {
                final subscription = MqttPacketCodec.decodeSubscribe(
                  frame,
                  MqttVersion.v5,
                );
                socket.add(
                  MqttPacketCodec.encodeSuback(
                    MqttVersion.v5,
                    subscription.packetId,
                    [0x80],
                  ),
                );
              } else if (frame.type == MqttPacketType.disconnect) {
                socket.destroy();
              }
            }
          },
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
      });
      addTearDown(listener.cancel);
      await expectLater(
        connectGatewayBenchmarkPeer(
          GatewayBenchmarkConfig({
            ...base,
            'path': 'wamp_to_mqtt',
            'port': server.port,
          }),
          'subscriber',
        ),
        throwsA(isA<MqttProtocolException>()),
      );
      await closed.future.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'a denied WAMP subscription releases the connected participant',
    () async {
      final runtime = router.NativeTransportRuntime(libraryPath: library)
        ..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      final settings = router.RouterSettingsBuilder()
        ..addRealmFromBuilder(
          router.RealmSettingsBuilder(GatewayBenchmarkConfig.realm)
            ..addAuthMethod('anonymous')
            ..addRole(
              const router.RoleSettings(
                name: 'anonymous',
                permissions: [
                  router.PermissionSettings(
                    uri: '',
                    matchPolicy: router.PermissionMatchPolicy.prefix,
                    deny: ['subscribe'],
                  ),
                ],
              ),
            ),
        )
        ..addListenerFromBuilder(
          router.ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
            ..addAuthMethod('anonymous')
            ..addProtocol(router.ListenerProtocol.rawsocket),
        )
        ..addAuthenticator(
          'anonymous',
          const router.AuthenticatorDefinition(type: 'anonymous'),
        );
      final binding = router.Router(
        router.RouterConfig(
          endpoints: [
            router.Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: router.TlsMode.disabled,
              maxRawSocketSizeExponent: 24,
            ),
          ],
        ),
        settings: settings.build(),
      ).start(runtime);
      addTearDown(binding.dispose);
      await expectLater(
        connectGatewayBenchmarkPeer(
          GatewayBenchmarkConfig({
            ...base,
            'port': binding.listeners.single.port,
          }),
          'subscriber',
        ),
        throwsA(isA<wamp.Error>()),
      );
    },
  );

  test(
    'direct controls expose an empty gateway queue set and reject nonbinary events',
    () async {
      for (final path in ['mqtt_to_mqtt', 'wamp_to_wamp', 'wamp_to_wamp_ack']) {
        final server = await NativeGatewayBenchmarkServer.start(
          GatewayBenchmarkConfig({...base, 'path': path}),
        );
        try {
          expect(server.metrics, isEmpty);
          final live = GatewayBenchmarkConfig({
            ...base,
            'path': path,
            'port': server.port,
          });
          final subscriber = await connectGatewayBenchmarkPeer(
            live,
            'subscriber',
          );
          final publisher = await connectGatewayBenchmarkPeer(
            live,
            'publisher',
          );
          try {
            final received = subscriber.messages.first.timeout(
              const Duration(seconds: 3),
            );
            await publisher.publish(Uint8List.fromList([0, 255]));
            expect(await received, [0, 255]);
          } finally {
            await publisher.close();
            await subscriber.close();
          }
        } finally {
          await server.close();
        }
      }
    },
  );
}
