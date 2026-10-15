@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  test(
    'MQTT client rejects oversized CONNECT before opening any transport',
    () async {
      final oversizedId = List<String>.filled(65536, 'a').join();
      for (final connect in <Future<MqttQos0Client> Function()>[
        () => MqttQos0Client.connect('127.0.0.1', 1, clientId: oversizedId),
        () =>
            MqttQos0Client.connectSecure('127.0.0.1', 1, clientId: oversizedId),
        () => MqttQos0Client.connectWebSocket(
          Uri.parse('ws://127.0.0.1:1/mqtt'),
          clientId: oversizedId,
        ),
      ]) {
        await expectLater(connect(), throwsA(isA<MqttProtocolException>()));
      }
    },
  );

  test('MQTT WebSocket client rejects unsupported URI scheme', () async {
    await expectLater(
      MqttQos0Client.connectWebSocket(
        Uri.parse('http://127.0.0.1/mqtt'),
        clientId: 'bad-uri',
      ),
      throwsArgumentError,
    );
  });

  test('MQTT WebSocket client requires negotiated mqtt subprotocol', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      await WebSocketTransformer.upgrade(request);
    });
    addTearDown(() => server.close(force: true));
    await expectLater(
      MqttQos0Client.connectWebSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/mqtt'),
        clientId: 'no-subprotocol',
      ),
      throwsA(isA<MqttProtocolException>()),
    );
  });

  for (final reply in ['rejected', 'text', 'malformed']) {
    test('MQTT WebSocket client handles $reply broker reply', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) => 'mqtt',
        );
        socket.listen((_) {
          switch (reply) {
            case 'rejected':
              socket.add(
                MqttPacketCodec.encodeConnack(MqttVersion.v5, reasonCode: 0x87),
              );
            case 'text':
              socket.add('text data is invalid for MQTT');
            case 'malformed':
              socket.add([0x00, 0x00]);
          }
        });
      });
      addTearDown(() => server.close(force: true));
      await expectLater(
        MqttQos0Client.connectWebSocket(
          Uri.parse('ws://127.0.0.1:${server.port}/mqtt'),
          clientId: 'bad-$reply',
        ),
        throwsA(isA<MqttProtocolException>()),
      );
    });
  }

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

  for (final tls in [false, true]) {
    for (final version in [MqttVersion.v5, MqttVersion.v311]) {
      test(
        'native ${tls ? 'WSS' : 'WS'} MQTT ${version == MqttVersion.v5 ? '5' : '3.1.1'} exchanges exact bytes between Connectanum clients',
        () async {
          final port = await _startRouter(
            protocols: [ListenerProtocol.mqtt, ListenerProtocol.websocket],
            tls: tls,
          );
          final context = SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates('test/certs/remote_auth_ca_cert.pem');
          final uri = Uri.parse(
            '${tls ? 'wss' : 'ws'}://127.0.0.1:$port/mqtt',
          );
          final subscriber = await MqttQos0Client.connectWebSocket(
            uri,
            clientId: 'native-${tls ? 'wss' : 'ws'}-sub',
            version: version,
            context: tls ? context : null,
          );
          final publisher = await MqttQos0Client.connectWebSocket(
            uri,
            clientId: 'native-${tls ? 'wss' : 'ws'}-pub',
            version: version,
            context: tls ? context : null,
          );
          addTearDown(() async {
            await publisher.close();
            await subscriber.close();
          });
          await subscriber.subscribe('native/websocket/raw');
          await expectLater(
            publisher.publish('native/#', Uint8List(0)),
            throwsA(isA<MqttProtocolException>()),
          );
          final received = subscriber.messages.first.timeout(
            const Duration(seconds: 5),
          );
          await publisher.publish(
            'native/websocket/raw',
            Uint8List.fromList([0, 255, 17, 0]),
          );
          final publication = await received;
          expect(publication.topic, 'native/websocket/raw');
          expect(publication.payload, [0, 255, 17, 0]);
          expect(publication.qos, 0);
        },
      );
    }
  }

  test('native TLS MQTT exchanges exact QoS 0 bytes across versions', () async {
    final port = await _startRouter(tls: true);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/certs/remote_auth_ca_cert.pem');
    final subscriber = await MqttQos0Client.connectSecure(
      '127.0.0.1',
      port,
      clientId: 'native-tls-v311-sub',
      version: MqttVersion.v311,
      context: context,
    );
    final publisher = await MqttQos0Client.connectSecure(
      '127.0.0.1',
      port,
      clientId: 'native-tls-v5-pub',
      context: context,
    );
    addTearDown(() async {
      await publisher.close();
      await subscriber.close();
    });
    await subscriber.subscribe('native/tls/raw');
    final received = subscriber.messages.first.timeout(
      const Duration(seconds: 5),
    );
    await publisher.publish(
      'native/tls/raw',
      Uint8List.fromList([0, 255, 17, 0]),
    );
    expect((await received).payload, [0, 255, 17, 0]);
  });

  test('native TLS listener negotiates MQTT and HTTPS on one port', () async {
    final port = await _startRouter(
      protocols: [ListenerProtocol.mqtt, ListenerProtocol.http],
      tls: true,
    );
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/certs/remote_auth_ca_cert.pem');
    final client = await MqttQos0Client.connectSecure(
      '127.0.0.1',
      port,
      clientId: 'mixed-tls-listener-mqtt',
      context: context,
    );
    addTearDown(client.close);
    await client.ping();
    final http = HttpClient(context: context);
    addTearDown(http.close);
    final request = await http.getUrl(
      Uri.parse('https://127.0.0.1:$port/unmapped'),
    );
    final response = await request.close();
    expect(response.statusCode, isIn([400, 404, 501]));
    await response.drain<void>();
  });

  test('native TLS MQTT rejects an untrusted server certificate', () async {
    final port = await _startRouter(tls: true);
    await expectLater(
      MqttQos0Client.connectSecure(
        '127.0.0.1',
        port,
        clientId: 'untrusted-tls-peer',
        context: SecurityContext(withTrustedRoots: false),
      ),
      throwsA(isA<HandshakeException>()),
    );
  });

  test(
    'native TLS MQTT exchanges exact binary bytes with Paho 5 and 3.1.1',
    () async {
      final port = await _startRouter(tls: true);
      final context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('test/certs/remote_auth_ca_cert.pem');
      final client = await MqttQos0Client.connectSecure(
        '127.0.0.1',
        port,
        clientId: 'native-tls-dart-peer',
        context: context,
      );
      addTearDown(client.close);
      await client.subscribe('test/from-paho');
      final incoming = client.messages.first.timeout(
        const Duration(seconds: 5),
      );
      final process = await Process.start(
        Platform.environment['PAHO_PYTHON']!,
        [
          'test/mqtt/paho_qos0_peer.py',
          '$port',
          'test/certs/remote_auth_ca_cert.pem',
        ],
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

  for (final tls in [false, true]) {
    for (final version in [MqttVersion.v5, MqttVersion.v311]) {
      test(
        'native ${tls ? 'WSS' : 'WS'} MQTT ${version == MqttVersion.v5 ? '5' : '3.1.1'} exchanges exact binary bytes with Paho',
        () async {
          final port = await _startRouter(
            protocols: [ListenerProtocol.mqtt, ListenerProtocol.websocket],
            tls: tls,
          );
          final context = SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates('test/certs/remote_auth_ca_cert.pem');
          final client = await MqttQos0Client.connectWebSocket(
            Uri.parse('${tls ? 'wss' : 'ws'}://127.0.0.1:$port/mqtt'),
            clientId: tls ? 'wss-dart-peer' : 'ws-dart-peer',
            version: version,
            context: tls ? context : null,
          );
          addTearDown(client.close);
          await client.subscribe('test/from-paho');
          final incoming = client.messages.first
              .timeout(const Duration(seconds: 5))
              .then<MqttPublish?>(
                (message) => message,
                onError: (Object _, StackTrace _) => null,
              );
          final process = await Process.start(
            Platform.environment['PAHO_PYTHON']!,
            [
              'test/mqtt/paho_qos0_peer.py',
              '$port',
              if (tls) 'test/certs/remote_auth_ca_cert.pem' else '-',
              'websockets',
            ],
          );
          addTearDown(() => process.kill());
          late final String ready;
          try {
            ready = await process.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 5));
          } on StateError {
            fail(
              'Paho closed before READY: ${await process.stderr.transform(utf8.decoder).join()}',
            );
          }
          expect(ready, 'READY');
          expect((await incoming)?.payload, [0, 255, 0, 17]);
          await client.publish(
            'test/to-paho',
            Uint8List.fromList([17, 0, 255]),
          );
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
  }

  test(
    'native MQTT WebSocket accepts partial and multiple control packets',
    () async {
      final port = await _startRouter(
        protocols: [ListenerProtocol.mqtt, ListenerProtocol.websocket],
      );
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$port/mqtt',
        protocols: ['mqtt'],
      );
      addTearDown(socket.close);
      expect(socket.protocol, 'mqtt');
      final messages = StreamIterator<dynamic>(socket);
      addTearDown(messages.cancel);
      final connect = MqttPacketCodec.encodeConnect(
        const MqttConnect(version: MqttVersion.v5, clientId: 'ws-chunks'),
      );
      socket.add(connect.sublist(0, 4));
      socket.add(connect.sublist(4));
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final decoder = MqttFrameDecoder();
      final connack = decoder.add(
        Uint8List.fromList(messages.current as List<int>),
      );
      expect(connack, hasLength(1));
      expect(
        MqttPacketCodec.decodeConnack(
          connack.single,
          MqttVersion.v5,
        ).reasonCode,
        0,
      );

      final ping = MqttFrame(
        MqttPacketType.pingreq,
        flags: 0,
        body: Uint8List(0),
      ).encode();
      socket.add(Uint8List.fromList([...ping, ...ping]));
      final responses = <MqttFrame>[];
      while (responses.length < 2) {
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        responses.addAll(
          decoder.add(Uint8List.fromList(messages.current as List<int>)),
        );
      }
      expect(responses.map((frame) => frame.type), [
        MqttPacketType.pingresp,
        MqttPacketType.pingresp,
      ]);

      socket.add('text is forbidden for MQTT');
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(socket.closeCode, 1003);
    },
  );

  test(
    'native MQTT WebSocket rejects invalid upgrade keys and versions',
    () async {
      final port = await _startRouter(
        protocols: [ListenerProtocol.mqtt, ListenerProtocol.websocket],
      );
      for (final (key, version) in [
        ('invalid', '13'),
        ('SGVsbG9OZWdvdGlvbg==', '12'),
      ]) {
        final socket = await Socket.connect('127.0.0.1', port);
        socket.write(
          'GET /mqtt HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: $version\r\n'
          'Sec-WebSocket-Protocol: mqtt\r\n\r\n',
        );
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        expect(response, isNot(contains('101 Switching Protocols')));
        socket.destroy();
      }
    },
  );

  for (final (name, frame, code) in [
    ('unmasked client frame', <int>[0x82, 0x00], 1002),
    ('unexpected continuation', <int>[0x80, 0x80, 0, 0, 0, 0], 1002),
    ('oversized frame', <int>[0x82, 0xff, 0, 0, 0, 0, 1, 0, 0, 1], 1009),
  ]) {
    test('native MQTT WebSocket closes $name with $code', () async {
      final port = await _startRouter(
        protocols: [ListenerProtocol.mqtt, ListenerProtocol.websocket],
      );
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      socket.add([
        ...ascii.encode(
          'GET /mqtt HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          'Sec-WebSocket-Protocol: mqtt\r\n\r\n',
        ),
        ...frame,
      ]);
      await socket.flush();
      final bytes = (await socket.toList().timeout(
        const Duration(seconds: 5),
      )).expand((chunk) => chunk).toList();
      final headerEnd =
          ascii.decode(bytes, allowInvalid: true).indexOf('\r\n\r\n') + 4;
      expect(headerEnd, greaterThan(3));
      expect(
        ascii.decode(bytes.sublist(0, headerEnd)),
        contains('101 Switching Protocols'),
      );
      expect(bytes.length, greaterThanOrEqualTo(headerEnd + 4));
      expect(bytes.sublist(headerEnd, headerEnd + 4), [
        0x88,
        0x02,
        code >> 8,
        code & 0xff,
      ]);
    });
  }

  test(
    'mixed listener keeps MQTT and WAMP WebSocket selection distinct',
    () async {
      final port = await _startRouter(
        protocols: [
          ListenerProtocol.mqtt,
          ListenerProtocol.websocket,
          ListenerProtocol.http,
        ],
      );
      final mqttSocket = await WebSocket.connect(
        'ws://127.0.0.1:$port/mqtt',
        protocols: ['mqtt'],
      );
      addTearDown(mqttSocket.close);
      expect(mqttSocket.protocol, 'mqtt');
      final wampSocket = await WebSocket.connect(
        'ws://127.0.0.1:$port/wamp',
        protocols: ['wamp.2.json'],
      );
      addTearDown(wampSocket.close);
      expect(wampSocket.protocol, 'wamp.2.json');
      final http = HttpClient();
      addTearDown(http.close);
      final response = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:$port/unmapped'),
      )).close();
      expect(response.statusCode, isIn([400, 404, 501]));
      await response.drain<void>();
    },
  );
}

Future<int> _startRouter({
  List<ListenerProtocol> protocols = const [ListenerProtocol.mqtt],
  bool tls = false,
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
          tlsMode: tls ? TlsMode.native : TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
          sniCertificates: tls
              ? [
                  SniCertificate(
                    hostname: 'localhost',
                    certificateChainPem: File(
                      'test/certs/remote_auth_server_cert.pem',
                    ).readAsStringSync(),
                    privateKeyPem: File(
                      'test/certs/remote_auth_server_key.pem',
                    ).readAsStringSync(),
                  ),
                ]
              : const [],
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
