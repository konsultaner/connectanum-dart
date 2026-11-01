import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/connectanum_router.dart' as router;
import 'package:connectanum_router/mqtt.dart' as gateway;

import 'mqtt_gateway_measurement.dart';

final class GatewayBenchmarkConfig {
  GatewayBenchmarkConfig(Map<String, dynamic> values)
    : path = values['path'] as String,
      transport = values['transport'] as String,
      serializer = values['serializer'] as String,
      mqttVersion = values['mqtt_version'] as String,
      payloadBytes = values['payload_bytes'] as int,
      window = values['window'] as int,
      port = values['port'] as int,
      library = values['native_library'] as String,
      certificate = values['certificate'] as String? ?? '',
      key = values['key'] as String? ?? '' {
    if (![
          'mqtt_to_mqtt',
          'wamp_to_wamp',
          'wamp_to_wamp_ack',
          'mqtt_to_wamp',
          'wamp_to_mqtt',
        ].contains(path) ||
        !['tcp', 'tls', 'ws', 'wss'].contains(transport) ||
        !['json', 'msgpack', 'cbor', 'flatbuffers'].contains(serializer) ||
        !['5', '3.1.1'].contains(mqttVersion) ||
        payloadBytes < 24 ||
        payloadBytes > 65536 ||
        window < 1 ||
        window > 512 ||
        port < 0 ||
        port > 65535 ||
        library.isEmpty ||
        (secure && (certificate.isEmpty || key.isEmpty))) {
      throw ArgumentError('Invalid gateway benchmark profile');
    }
  }
  static const realm = 'bench.gateway';
  static const topic = 'bench/gateway';
  final String path,
      transport,
      serializer,
      mqttVersion,
      library,
      certificate,
      key;
  final int payloadBytes, window, port;
  bool get secure => transport == 'tls' || transport == 'wss';
  bool get websocket => transport == 'ws' || transport == 'wss';
  bool get translation => path == 'mqtt_to_wamp' || path == 'wamp_to_mqtt';
  bool mqttFor(String role) =>
      role == 'publisher' ? path.startsWith('mqtt') : path.endsWith('mqtt');
  bool get ordered => path != 'wamp_to_mqtt' || window == 1;
}

abstract interface class GatewayBenchmarkPeer {
  Stream<Uint8List> get messages;
  Future<void> publish(Uint8List payload);
  Future<void> close();
}

Future<GatewayBenchmarkPeer> connectGatewayBenchmarkPeer(
  GatewayBenchmarkConfig config,
  String role,
) async {
  if (config.port == 0) throw ArgumentError('Client port must be bound');
  final topic = GatewayBenchmarkConfig.topic;
  if (config.mqttFor(role)) {
    final version = config.mqttVersion == '5'
        ? MqttVersion.v5
        : MqttVersion.v311;
    final trust = config.secure
        ? (SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates(config.certificate))
        : null;
    final MqttQos0Client client;
    if (config.websocket) {
      client = await MqttQos0Client.connectWebSocket(
        Uri.parse(
          '${config.secure ? 'wss' : 'ws'}://127.0.0.1:${config.port}/mqtt',
        ),
        clientId: 'bench-$role-$pid',
        version: version,
        context: trust,
      );
    } else if (config.secure) {
      client = await MqttQos0Client.connectSecure(
        '127.0.0.1',
        config.port,
        clientId: 'bench-$role-$pid',
        version: version,
        context: trust,
      );
    } else {
      client = await MqttQos0Client.connect(
        '127.0.0.1',
        config.port,
        clientId: 'bench-$role-$pid',
        version: version,
      );
    }
    try {
      if (role == 'subscriber') await client.subscribe(topic);
      return _MqttBenchmarkPeer(client, topic);
    } catch (_) {
      await client.close();
      rethrow;
    }
  }
  final wamp.AbstractTransport transport;
  final url = '${config.secure ? 'wss' : 'ws'}://127.0.0.1:${config.port}/wamp';
  if (config.websocket) {
    transport = switch (config.serializer) {
      'json' => wamp.NativeWebSocketTransport.withJsonSerializer(
        url,
        null,
        config.secure,
        config.library,
      ),
      'msgpack' => wamp.NativeWebSocketTransport.withMsgpackSerializer(
        url,
        null,
        config.secure,
        config.library,
      ),
      'cbor' => wamp.NativeWebSocketTransport.withCborSerializer(
        url,
        null,
        config.secure,
        config.library,
      ),
      _ => wamp.NativeWebSocketTransport.withFlatBuffersSerializer(
        url,
        null,
        config.secure,
        config.library,
      ),
    };
  } else {
    transport = switch (config.serializer) {
      'json' => wamp.NativeRawSocketTransport.withJsonSerializer(
        '127.0.0.1',
        config.port,
        ssl: config.secure,
        allowInsecureCertificates: config.secure,
        libraryPath: config.library,
      ),
      'msgpack' => wamp.NativeRawSocketTransport.withMsgpackSerializer(
        '127.0.0.1',
        config.port,
        ssl: config.secure,
        allowInsecureCertificates: config.secure,
        libraryPath: config.library,
      ),
      'cbor' => wamp.NativeRawSocketTransport.withCborSerializer(
        '127.0.0.1',
        config.port,
        ssl: config.secure,
        allowInsecureCertificates: config.secure,
        libraryPath: config.library,
      ),
      _ => wamp.NativeRawSocketTransport.withFlatBuffersSerializer(
        '127.0.0.1',
        config.port,
        ssl: config.secure,
        allowInsecureCertificates: config.secure,
        libraryPath: config.library,
      ),
    };
  }
  final session = await wamp.Client(
    realm: GatewayBenchmarkConfig.realm,
    transport: transport,
  ).connect().first.timeout(const Duration(seconds: 10));
  final peer = _WampBenchmarkPeer(
    session,
    config.path == 'wamp_to_mqtt',
    config.path == 'wamp_to_wamp_ack',
  );
  try {
    if (role == 'subscriber') {
      final subscription = await session.subscribe(
        MqttTopicUriMapper.toWampUri(topic),
      );
      subscription.onEvent((event) {
        try {
          if (config.path == 'mqtt_to_wamp' &&
              event.details.custom['mqtt_topic'] != topic) {
            throw const FormatException('Wrong mapped MQTT topic');
          }
          final args = event.arguments;
          if (args == null || args.length != 1 || args.single is! Uint8List) {
            throw const FormatException(
              'Expected one binary application payload',
            );
          }
          peer._messages.add(args.single as Uint8List);
        } catch (error, stack) {
          peer._messages.addError(error, stack);
        }
      });
    }
    return peer;
  } catch (_) {
    await peer.close();
    rethrow;
  }
}

final class _MqttBenchmarkPeer implements GatewayBenchmarkPeer {
  _MqttBenchmarkPeer(this.client, this.topic);
  final MqttQos0Client client;
  final String topic;
  @override
  Stream<Uint8List> get messages => client.messages.map((message) {
    if (message.topic != topic) throw const FormatException('Wrong MQTT topic');
    return message.payload;
  });
  @override
  Future<void> publish(Uint8List payload) => client.publish(topic, payload);
  @override
  Future<void> close() => client.close();
}

final class _WampBenchmarkPeer implements GatewayBenchmarkPeer {
  _WampBenchmarkPeer(this.session, this.gatewayCall, this.acknowledge);
  final wamp.Session session;
  final bool gatewayCall;
  final bool acknowledge;
  final _messages = StreamController<Uint8List>.broadcast(sync: true);
  @override
  Stream<Uint8List> get messages => _messages.stream;
  @override
  Future<void> publish(Uint8List payload) async {
    if (gatewayCall) {
      await session
          .call(
            gateway.MqttWampGateway.publishProcedure,
            arguments: [GatewayBenchmarkConfig.topic, payload],
          )
          .first;
    } else {
      await session.publish(
        MqttTopicUriMapper.toWampUri(GatewayBenchmarkConfig.topic),
        arguments: [payload],
        options: wamp.PublishOptions(acknowledge: acknowledge),
      );
    }
  }

  @override
  Future<void> close() async {
    try {
      await session.close(timeout: Duration.zero);
    } finally {
      await _messages.close();
    }
  }
}

abstract interface class GatewayBenchmarkServer {
  int get port;
  Map<String, int> get metrics;
  Future<Map<String, int>> sampleQueues();
  Future<void> close();
}

final class NativeGatewayBenchmarkServer implements GatewayBenchmarkServer {
  NativeGatewayBenchmarkServer._(this.runtime, this.binding, this.bridge);
  final router.NativeTransportRuntime runtime;
  final router.RouterBinding binding;
  final gateway.MqttWampGateway? bridge;

  static Future<NativeGatewayBenchmarkServer> start(
    GatewayBenchmarkConfig config, {
    Future<gateway.MqttWampGateway> Function(router.RouterBinding)?
    createGateway,
  }) async {
    final runtime = router.NativeTransportRuntime(libraryPath: config.library)
      ..start();
    router.RouterBinding? binding;
    try {
      final permissions = [
        const router.PermissionSettings(
          uri: MqttTopicUriMapper.prefix,
          matchPolicy: router.PermissionMatchPolicy.prefix,
          allow: ['publish', 'subscribe', 'unsubscribe'],
        ),
        const router.PermissionSettings(
          uri: gateway.MqttWampGateway.publishProcedure,
          allow: ['call'],
        ),
      ];
      final settings = router.RouterSettingsBuilder()
        ..addRealmFromBuilder(
          router.RealmSettingsBuilder(GatewayBenchmarkConfig.realm)
            ..addAuthMethod('anonymous')
            ..addRole(
              router.RoleSettings(name: 'anonymous', permissions: permissions),
            )
            ..addRole(
              router.RoleSettings(name: 'mqtt', permissions: permissions),
            )
            ..addRole(
              const router.RoleSettings(
                name: 'mqtt-gateway',
                permissions: [
                  router.PermissionSettings(
                    uri: '',
                    matchPolicy: router.PermissionMatchPolicy.prefix,
                    allow: ['register', 'unregister', 'publish'],
                  ),
                ],
              ),
            ),
        )
        ..addListenerFromBuilder(
          router.ListenerSettingsBuilder('mqtt', '127.0.0.1:${config.port}')
            ..addAuthMethod('anonymous')
            ..addProtocol(router.ListenerProtocol.mqtt)
            ..addProtocol(router.ListenerProtocol.rawsocket)
            ..addProtocol(router.ListenerProtocol.websocket),
        )
        ..addAuthenticator(
          'anonymous',
          const router.AuthenticatorDefinition(type: 'anonymous'),
        );
      binding = router.Router(
        router.RouterConfig(
          endpoints: [
            router.Endpoint(
              host: '127.0.0.1',
              port: config.port,
              tlsMode: config.secure
                  ? router.TlsMode.native
                  : router.TlsMode.disabled,
              maxRawSocketSizeExponent: 24,
              sniCertificates: config.secure
                  ? [
                      router.SniCertificate(
                        hostname: 'localhost',
                        certificateChainPem: File(
                          config.certificate,
                        ).readAsStringSync(),
                        privateKeyPem: File(config.key).readAsStringSync(),
                      ),
                    ]
                  : const [],
            ),
          ],
        ),
        settings: settings.build(),
      ).start(runtime);
      final bridge = config.translation
          ? await (createGateway?.call(binding) ??
                gateway.RouterMqttGateway(binding).enableMqttGateway(
                  realmUri: GatewayBenchmarkConfig.realm,
                  mqttAuthRole: 'mqtt',
                ))
          : null;
      return NativeGatewayBenchmarkServer._(runtime, binding, bridge);
    } catch (_) {
      try {
        await binding?.dispose();
      } finally {
        try {
          runtime.shutdown();
        } finally {
          runtime.dispose();
        }
      }
      rethrow;
    }
  }

  @override
  int get port => binding.listeners.single.port;
  @override
  Map<String, int> get metrics => bridge?.metrics ?? const {};
  @override
  Future<Map<String, int>> sampleQueues() async {
    final state = await binding.collectMetrics();
    return {
      ...metrics,
      'state_sessions': state.sessionCount,
      'state_subscriptions': state.subscriptionCount,
      'state_registrations': state.registrationCount,
      'state_pending_invocations': state.pendingInvocationCount,
      'active_connections': state.activeConnections,
    };
  }

  @override
  Future<void> close() async {
    try {
      await binding.dispose();
    } finally {
      try {
        runtime.shutdown();
      } finally {
        runtime.dispose();
      }
    }
  }
}

typedef GatewayPeerFactory =
    Future<GatewayBenchmarkPeer> Function(GatewayBenchmarkConfig, String);
typedef GatewayServerFactory =
    Future<GatewayBenchmarkServer> Function(GatewayBenchmarkConfig);

/// JSON-lines control separates setup, warm-up, load, drain and disconnect.
Future<void> runGatewayBenchmarkWorker(
  List<String> args, {
  Stream<String>? input,
  void Function(Map<String, Object?>)? emit,
  GatewayPeerFactory peerFactory = connectGatewayBenchmarkPeer,
  GatewayServerFactory serverFactory = NativeGatewayBenchmarkServer.start,
  int Function()? readRss,
  int Function()? nowMicros,
}) async {
  if (args.length != 2 ||
      !['server', 'publisher', 'subscriber'].contains(args[0])) {
    throw ArgumentError('Expected role and JSON profile');
  }
  final role = args[0];
  final config = GatewayBenchmarkConfig(
    jsonDecode(args[1]) as Map<String, dynamic>,
  );
  final output = emit ?? (message) => stdout.writeln(jsonEncode(message));
  final commands = StreamIterator(
    input ?? stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  final meter = GatewayMemoryMeter(readRss: readRss)..begin();
  final now = nowMicros ?? () => DateTime.now().microsecondsSinceEpoch;
  GatewayBenchmarkServer? server;
  GatewayBenchmarkPeer? peer;
  StreamSubscription<Uint8List>? subscription;
  final measurement = GatewayDeliveryMeasurement(
    payloadBytes: config.payloadBytes,
    requireOrder: config.ordered,
  );
  var phase = 0;
  var count = 0;
  Map<String, Object?> snapshot() => {
    'memory': meter.snapshot(),
  };
  Future<void> release() async {
    final ownedSubscription = subscription;
    final ownedPeer = peer;
    final ownedServer = server;
    subscription = null;
    peer = null;
    server = null;
    try {
      await ownedSubscription?.cancel();
    } finally {
      try {
        await ownedPeer?.close();
      } finally {
        await ownedServer?.close();
      }
    }
  }

  try {
    if (role == 'server') {
      server = await serverFactory(config);
    } else {
      peer = await peerFactory(config, role);
      if (role == 'subscriber') {
        subscription = peer!.messages.listen(
          (bytes) {
            try {
              measurement.accept(bytes, now());
              if (measurement.received % config.window == 0 ||
                  measurement.complete) {
                output({
                  'kind': 'progress',
                  'phase': phase,
                  'received': measurement.received,
                });
              }
              if (measurement.complete) {
                output({
                  'kind': 'received',
                  'phase': phase,
                  ...measurement.summary(),
                  ...snapshot(),
                });
              }
            } catch (error) {
              output({'kind': 'error', 'message': error.toString()});
            }
          },
          onError: (Object error) =>
              output({'kind': 'error', 'message': error.toString()}),
        );
      }
    }
    output({
      'kind': 'ready',
      'pid': pid,
      if (server case final owned?) 'port': owned.port,
    });
    while (await commands.moveNext()) {
      final command = jsonDecode(commands.current) as Map<String, dynamic>;
      switch (command['op']) {
        case 'begin':
          phase = command['phase'] as int;
          count = command['count'] as int;
          if (role == 'subscriber') measurement.begin(phase, count);
          meter.begin();
          output({'kind': 'armed', 'phase': phase});
        case 'sample':
          final queues = await server?.sampleQueues();
          output({
            'kind': 'sampled',
            ...snapshot(),
            if (queues != null) 'queues': queues,
          });
        case 'publish':
          if (role != 'publisher') {
            throw StateError('Only a publisher may send load');
          }
          phase = command['phase'] as int;
          count = command['count'] as int;
          if (count <= 0 || count > 1000000) {
            throw ArgumentError('Invalid publication count');
          }
          meter.begin();
          for (var first = 0; first < count; first += config.window) {
            final end = (first + config.window < count)
                ? first + config.window
                : count;
            await Future.wait([
              for (var i = first; i < end; i++)
                peer!.publish(
                  gatewayBenchmarkPayload(config.payloadBytes, phase, i, now()),
                ),
            ]);
            if (command['flow_control'] != false) {
              if (!await commands.moveNext()) {
                throw StateError('Missing delivery credit');
              }
              final credit =
                  jsonDecode(commands.current) as Map<String, dynamic>;
              if (credit['op'] != 'credit' ||
                  credit['phase'] != phase ||
                  credit['received'] != end) {
                throw StateError('Invalid delivery credit');
              }
            }
          }
          output({
            'kind': 'sent',
            'phase': phase,
            'sent': count,
            ...snapshot(),
          });
        case 'close':
          await release();
          output({'kind': 'closed', ...snapshot()});
          return;
        default:
          throw ArgumentError('Unknown worker command');
      }
    }
  } finally {
    meter.close();
    try {
      await commands.cancel();
    } finally {
      await release();
    }
  }
}
