@TestOn('vm')
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/native_transports_io.dart'
    show collectNativeReceiveBatch;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_core/cbor_serializer.dart' as serializer_cbor;
import 'package:connectanum_core/json_serializer.dart' as serializer_json;
import 'package:connectanum_core/msgpack_serializer.dart' as serializer_msgpack;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:test/test.dart';

class _SerializerCase {
  const _SerializerCase({
    required this.name,
    required this.serializer,
    required this.rawsocketType,
    required this.websocketProtocol,
    required this.rawsocketFactory,
    required this.websocketFactory,
  });

  final String name;
  final AbstractSerializer serializer;
  final int rawsocketType;
  final String websocketProtocol;
  final NativeRawSocketTransport Function(String host, int port)
  rawsocketFactory;
  final NativeWebSocketTransport Function(
    String url,
    Map<String, dynamic>? headers,
  )
  websocketFactory;
}

final _serializers = <_SerializerCase>[
  _SerializerCase(
    name: 'json',
    serializer: serializer_json.Serializer(),
    rawsocketType: SocketHelper.serializationJson,
    websocketProtocol: WebSocketSerialization.serializationJson,
    rawsocketFactory: (host, port) =>
        NativeRawSocketTransport.withJsonSerializer(host, port),
    websocketFactory: (url, headers) =>
        NativeWebSocketTransport.withJsonSerializer(url, headers),
  ),
  _SerializerCase(
    name: 'msgpack',
    serializer: serializer_msgpack.Serializer(),
    rawsocketType: SocketHelper.serializationMsgpack,
    websocketProtocol: WebSocketSerialization.serializationMsgpack,
    rawsocketFactory: (host, port) =>
        NativeRawSocketTransport.withMsgpackSerializer(host, port),
    websocketFactory: (url, headers) =>
        NativeWebSocketTransport.withMsgpackSerializer(url, headers),
  ),
  _SerializerCase(
    name: 'cbor',
    serializer: serializer_cbor.Serializer(),
    rawsocketType: SocketHelper.serializationCbor,
    websocketProtocol: WebSocketSerialization.serializationCbor,
    rawsocketFactory: (host, port) =>
        NativeRawSocketTransport.withCborSerializer(host, port),
    websocketFactory: (url, headers) =>
        NativeWebSocketTransport.withCborSerializer(url, headers),
  ),
];

void main() {
  group('collectNativeReceiveBatch', () {
    test('drains ready handles in order', () {
      final readyHandles = Queue<int>.from([2, 3, 0]);

      final batch = collectNativeReceiveBatch(
        1,
        () => readyHandles.removeFirst(),
      );

      expect(batch, [1, 2, 3]);
    });

    test('respects the configured batch limit', () {
      final readyHandles = Queue<int>.from([2, 3, 4, 5, 0]);

      final batch = collectNativeReceiveBatch(
        1,
        () => readyHandles.removeFirst(),
        maxBatchSize: 3,
      );

      expect(batch, [1, 2, 3]);
      expect(readyHandles, Queue<int>.from([4, 5, 0]));
    });
  });

  group('NativeRawSocketTransport', () {
    for (final config in _serializers) {
      test('connects and authenticates over ${config.name}', () async {
        final server = await _spawnNativeTestServer(
          kind: 'rawsocket',
          serializerName: config.name,
          rawsocketType: config.rawsocketType,
        );
        try {
          final transport = config.rawsocketFactory('127.0.0.1', server.port);
          final client = Client(realm: 'test.realm', transport: transport);
          final session = await client.connect().first;

          expect(session.id, equals(4242));
          expect(session.realm, equals('test.realm'));
          final hello = await server.helloFuture;
          expect(hello['realm'], equals('test.realm'));
          expect(transport.maxMessageLength, equals(1 << 24));
          expect(transport.headerLength, equals(4));

          await client.disconnect();
        } finally {
          await server.dispose();
        }
      });
    }

    test('receives back-to-back frames from one native worker batch', () async {
      final server = await _spawnNativeTestServer(
        kind: 'rawsocket',
        serializerName: 'json',
        rawsocketType: SocketHelper.serializationJson,
        sendBurstAfterHello: true,
      );
      try {
        final transport = NativeRawSocketTransport.withJsonSerializer(
          '127.0.0.1',
          server.port,
        );
        await transport.open();
        transport.send(Hello('test.realm', Details.forHello()));

        final messages = await transport
            .receive()!
            .take(2)
            .cast<AbstractMessage>()
            .toList()
            .timeout(const Duration(seconds: 2));

        expect(messages[0], isA<Welcome>());
        expect(messages[1], isA<Goodbye>());

        await transport.close();
      } finally {
        await server.dispose();
      }
    });
  });

  group('NativeWebSocketTransport', () {
    for (final config in _serializers) {
      test('connects and authenticates over ${config.name}', () async {
        final server = await _spawnNativeTestServer(
          kind: 'websocket',
          serializerName: config.name,
          websocketProtocol: config.websocketProtocol,
        );
        try {
          final url = 'ws://127.0.0.1:${server.port}/wamp';
          final transport = config.websocketFactory(url, {
            'X-Custom-Header': 'native-client',
          });
          final client = Client(realm: 'test.realm', transport: transport);
          final session = await client.connect().first;

          expect(session.id, equals(5150));
          expect(session.realm, equals('test.realm'));
          final hello = await server.helloFuture;
          expect(hello['realm'], equals('test.realm'));
          expect(hello['header'], equals('native-client'));
          expect(hello['protocol'], equals(config.websocketProtocol));

          await client.disconnect();
        } finally {
          await server.dispose();
        }
      });
    }
  });
}

class _NativeTestServer {
  _NativeTestServer({
    required this.isolate,
    required ReceivePort receivePort,
    required StreamSubscription<dynamic> subscription,
    required this.port,
    required this.helloFuture,
  }) : _receivePort = receivePort,
       _subscription = subscription;

  final Isolate isolate;
  final ReceivePort _receivePort;
  final StreamSubscription<dynamic> _subscription;
  final int port;
  final Future<Map<String, Object?>> helloFuture;

  Future<void> dispose() async {
    isolate.kill(priority: Isolate.immediate);
    await _subscription.cancel();
    _receivePort.close();
  }
}

Future<_NativeTestServer> _spawnNativeTestServer({
  required String kind,
  required String serializerName,
  int? rawsocketType,
  String? websocketProtocol,
  bool sendBurstAfterHello = false,
}) async {
  final receivePort = ReceivePort();
  final readyCompleter = Completer<int>();
  final helloCompleter = Completer<Map<String, Object?>>();
  late final StreamSubscription<dynamic> subscription;
  subscription = receivePort.listen((dynamic event) {
    final message = Map<String, Object?>.from(event as Map);
    switch (message['type']) {
      case 'ready':
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message['port']! as int);
        }
        break;
      case 'hello':
        if (!helloCompleter.isCompleted) {
          helloCompleter.complete(message);
        }
        break;
      case 'error':
        final error = StateError(message['message']! as String);
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(error);
        }
        if (!helloCompleter.isCompleted) {
          helloCompleter.completeError(error);
        }
        break;
    }
  });
  final isolate = await Isolate.spawn(_nativeTestServerMain, {
    'kind': kind,
    'sendPort': receivePort.sendPort,
    'serializerName': serializerName,
    'rawsocketType': rawsocketType,
    'websocketProtocol': websocketProtocol,
    'sendBurstAfterHello': sendBurstAfterHello,
  });
  final port = await readyCompleter.future;
  return _NativeTestServer(
    isolate: isolate,
    receivePort: receivePort,
    subscription: subscription,
    port: port,
    helloFuture: helloCompleter.future,
  );
}

@pragma('vm:entry-point')
Future<void> _nativeTestServerMain(Map<String, Object?> config) async {
  final sendPort = config['sendPort']! as SendPort;
  try {
    switch (config['kind']! as String) {
      case 'rawsocket':
        await _runRawSocketServer(
          sendPort,
          serializerName: config['serializerName']! as String,
          rawsocketType: config['rawsocketType']! as int,
          sendBurstAfterHello: config['sendBurstAfterHello'] as bool? ?? false,
        );
        return;
      case 'websocket':
        await _runWebSocketServer(
          sendPort,
          serializerName: config['serializerName']! as String,
          websocketProtocol: config['websocketProtocol']! as String,
        );
        return;
      default:
        throw UnsupportedError(
          'Unknown native test server kind ${config['kind']}',
        );
    }
  } catch (error, stackTrace) {
    sendPort.send({'type': 'error', 'message': '$error\n$stackTrace'});
  }
}

Future<void> _runRawSocketServer(
  SendPort sendPort, {
  required String serializerName,
  required int rawsocketType,
  bool sendBurstAfterHello = false,
}) async {
  final serializer = _serializerForName(serializerName);
  final server = await ServerSocket.bind('127.0.0.1', 0);
  sendPort.send({'type': 'ready', 'port': server.port});
  try {
    final socket = await server.first;
    var pending = Uint8List(0);
    var handshakeComplete = false;
    await for (final chunk in socket) {
      pending = _mergePending(pending, chunk);
      if (!handshakeComplete && pending.length >= 4) {
        final handshake = Uint8List.sublistView(pending, 0, 4);
        if (handshake[0] != 0x7F || (handshake[1] & 0x0F) != rawsocketType) {
          throw StateError(
            'Unexpected rawsocket handshake ${handshake.toList()}',
          );
        }
        socket.add(
          SocketHelper.getInitialHandshake(
            SocketHelper.maxMessageLengthExponent,
            rawsocketType,
          ),
        );
        pending = Uint8List.sublistView(pending, 4);
        handshakeComplete = true;
      }
      if (!handshakeComplete) {
        continue;
      }
      const headerLength = 4;
      if (pending.length < headerLength) {
        continue;
      }
      final frameType = pending[0];
      final payloadLength = SocketHelper.getPayloadLength(
        pending,
        headerLength,
      );
      if (pending.length < headerLength + payloadLength) {
        continue;
      }
      final payload = Uint8List.sublistView(
        pending,
        headerLength,
        headerLength + payloadLength,
      );
      if (frameType != SocketHelper.messageWamp) {
        throw StateError(
          'Unexpected rawsocket frame type $frameType with payload ${payload.toList()}',
        );
      }
      sendPort.send({
        'type': 'hello',
        'realm': _helloRealmFromPayload(serializerName, payload),
      });
      final welcomeFrame = _buildRawSocketFrame(
        _encodePayload(
          serializer,
          Welcome(
            4242,
            Details.forWelcome(
              realm: 'test.realm',
              authId: 'native-user',
              authMethod: 'none',
              authProvider: 'native',
              authRole: 'client',
            ),
          ),
        ),
      );
      if (sendBurstAfterHello) {
        final goodbyeFrame = _buildRawSocketFrame(
          _encodePayload(
            serializer,
            Goodbye(
              GoodbyeMessage('server closing'),
              Goodbye.reasonGoodbyeAndOut,
            ),
          ),
        );
        final burst = Uint8List(welcomeFrame.length + goodbyeFrame.length);
        burst.setRange(0, welcomeFrame.length, welcomeFrame);
        burst.setRange(welcomeFrame.length, burst.length, goodbyeFrame);
        socket.add(burst);
      } else {
        socket.add(welcomeFrame);
      }
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await socket.close();
      return;
    }
  } finally {
    await server.close();
  }
}

Future<void> _runWebSocketServer(
  SendPort sendPort, {
  required String serializerName,
  required String websocketProtocol,
}) async {
  final serializer = _serializerForName(serializerName);
  final server = await HttpServer.bind('127.0.0.1', 0);
  sendPort.send({'type': 'ready', 'port': server.port});
  try {
    await for (final request in server) {
      if (request.uri.path != '/wamp') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final header = request.headers.value('X-Custom-Header');
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) => protocols.first,
      );
      await for (final message in socket) {
        sendPort.send({
          'type': 'hello',
          'realm': _helloRealmFromWebSocketMessage(serializerName, message),
          'header': header,
          'protocol': socket.protocol,
        });
        socket.add(
          _encodeWebSocketPayload(
            serializer,
            websocketProtocol,
            Welcome(
              5150,
              Details.forWelcome(
                realm: 'test.realm',
                authId: 'native-user',
                authMethod: 'none',
                authProvider: 'native',
                authRole: 'client',
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await socket.close();
        return;
      }
    }
  } finally {
    await server.close(force: true);
  }
}

Uint8List _buildRawSocketFrame(Uint8List payload) {
  final header = Uint8List.fromList(
    SocketHelper.buildMessageHeader(
      SocketHelper.messageWamp,
      payload.length,
      false,
    ),
  );
  final frame = Uint8List(header.length + payload.length);
  frame.setRange(0, header.length, header);
  frame.setRange(header.length, frame.length, payload);
  return frame;
}

AbstractSerializer _serializerForName(String name) {
  switch (name) {
    case 'json':
      return serializer_json.Serializer();
    case 'msgpack':
      return serializer_msgpack.Serializer();
    case 'cbor':
      return serializer_cbor.Serializer();
    default:
      throw UnsupportedError('Unsupported serializer $name');
  }
}

Uint8List _mergePending(Uint8List current, List<int> next) {
  final merged = Uint8List(current.length + next.length);
  merged.setRange(0, current.length, current);
  merged.setRange(current.length, merged.length, next);
  return merged;
}

Uint8List _encodePayload(
  AbstractSerializer serializer,
  AbstractMessage message,
) {
  final encoded = serializer.serialize(message);
  if (encoded is Uint8List) {
    return encoded;
  }
  if (encoded is String) {
    return Uint8List.fromList(utf8.encode(encoded));
  }
  return Uint8List.fromList((encoded as List<int>).toList(growable: false));
}

String _helloRealmFromPayload(String serializerName, Uint8List payload) {
  switch (serializerName) {
    case 'json':
      return (json.decode(utf8.decode(payload)) as List<dynamic>)[1] as String;
    case 'msgpack':
      return (msgpack_dart.deserialize(payload) as List<dynamic>)[1] as String;
    case 'cbor':
      final decoded = cbor.cborDecode(payload.toList());
      return ((decoded as cbor.CborList).toObject() as List<dynamic>)[1]
          as String;
    default:
      throw UnsupportedError('Unsupported serializer $serializerName');
  }
}

String _helloRealmFromWebSocketMessage(String serializerName, Object message) {
  final payload = message is String
      ? Uint8List.fromList(utf8.encode(message))
      : Uint8List.fromList((message as List).cast<int>());
  return _helloRealmFromPayload(serializerName, payload);
}

Object _encodeWebSocketPayload(
  AbstractSerializer serializer,
  String websocketProtocol,
  AbstractMessage message,
) {
  final payload = _encodePayload(serializer, message);
  return websocketProtocol == WebSocketSerialization.serializationJson
      ? utf8.decode(payload)
      : payload;
}
