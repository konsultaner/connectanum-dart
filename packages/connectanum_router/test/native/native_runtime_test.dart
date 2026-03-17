@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library native_runtime_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:connectanum_core/connectanum_core.dart'
    show Hello, MessageTypes, Publish;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  final libraryPath = resolveOrBuildNativeLib();
  final skipReason = !Platform.isLinux
      ? 'Native runtime test only runs on Linux'
      : libraryPath == null
      ? 'Native ct_ffi library not found'
      : null;

  group('NativeTransportRuntime', () {
    test('start, listen, poll and shutdown', () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      addTearDown(runtime.dispose);

      final listenerEvents = <(int, int)>[];
      final connectionEvents = <(int, int)>[];
      runtime.setListenerCallbacks(
        onStarted: (id, status) => listenerEvents.add((id, status)),
        onConnection: (id, conn) => connectionEvents.add((id, conn)),
      );

      // Ensure a clean native runtime state in case a previous test left it running.
      try {
        runtime.shutdown();
      } catch (_) {}

      runtime.start();
      addTearDown(runtime.shutdown);

      const configJson =
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":30}]}';
      runtime.applyRouterConfig(Uint8List.fromList(utf8.encode(configJson)));

      final listenerId = runtime.listen('127.0.0.1', 0);
      expect(listenerId, greaterThan(0));
      expect(
        listenerEvents,
        contains((listenerId, NativeTransportErrorCode.success)),
      );

      final port = runtime.getLocalPort(listenerId);
      expect(port, greaterThan(0));

      final socket = await Socket.connect('127.0.0.1', port);
      await _performHandshake(socket);
      await _sendHelloFrame(socket);
      await _sendPublishFrame(socket);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final polledId = runtime.pollConnection(listenerId);
      expect(polledId, greaterThan(0));
      expect(runtime.connectionMaxRawSocketExponent(polledId), 16);
      expect(connectionEvents, contains((listenerId, polledId)));

      final incoming = runtime.pollMessage(polledId);
      expect(incoming, isNotNull);
      expect(incoming!.serializer, NativeMessageSerializer.json);
      final hello = incoming.message as Hello;
      expect(hello.id, MessageTypes.codeHello);
      expect(hello.realm, 'com.example.realm');
      expect(incoming.bytes, isNotEmpty);

      final publishMessage = runtime.pollMessage(polledId);
      expect(publishMessage, isNotNull);
      expect(publishMessage!.serializer, NativeMessageSerializer.json);
      final publish = publishMessage.message as Publish;
      expect(publish.topic, 'com.example.topic');
      expect(publishMessage.frameAddress, isNot(equals(0)));
      expect(publishMessage.argumentsAddress, isNot(equals(0)));
      expect(publishMessage.argumentsKeywordsAddress, isNot(equals(0)));
      final argsOffset =
          publishMessage.argumentsAddress - publishMessage.frameAddress;
      final kwargsOffset =
          publishMessage.argumentsKeywordsAddress - publishMessage.frameAddress;
      expect(argsOffset, greaterThan(0));
      expect(kwargsOffset, greaterThan(argsOffset));
      expect(
        argsOffset + publishMessage.argumentsBytes!.length <=
            publishMessage.bytes.length,
        isTrue,
      );
      expect(
        kwargsOffset + publishMessage.argumentsKeywordsBytes!.length <=
            publishMessage.bytes.length,
        isTrue,
      );
      final decodedFrame =
          jsonDecode(utf8.decode(publishMessage.bytes)) as List<dynamic>;
      expect(decodedFrame[4], ['alpha']);
      expect((decodedFrame[5] as Map)['flag'], true);
      expect(publishMessage.argumentsBytes, isNotNull);
      expect(publishMessage.argumentsKeywordsBytes, isNotNull);
      expect(
        identical(
          publishMessage.argumentsBytes,
          publish.debugEncodedArgumentsBytes,
        ),
        isTrue,
      );
      expect(
        identical(
          publishMessage.argumentsKeywordsBytes,
          publish.debugEncodedArgumentsKeywordsBytes,
        ),
        isTrue,
      );
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      // Lazy decode on demand.
      expect(publish.arguments, ['alpha']);
      expect(publish.argumentsKeywords, {'flag': true});
      publishMessage.dispose();

      expect(runtime.pollMessage(polledId), isNull);

      final welcomePayload = utf8.encode(
        jsonEncode([
          MessageTypes.codeWelcome,
          9129137332,
          {
            'roles': {'broker': {}},
          },
        ]),
      );
      runtime.sendMessage(polledId, Uint8List.fromList(welcomePayload));
      final framePayload = await _readFrame(socket);
      expect(framePayload, welcomePayload);

      expect(
        () => runtime.pollConnection(9999),
        throwsA(isA<NativeTransportException>()),
      );
      expect(
        () => runtime.connectionMaxRawSocketExponent(9999),
        throwsA(isA<NativeTransportException>()),
      );
      expect(
        () => runtime.pollMessage(9999),
        throwsA(isA<NativeTransportException>()),
      );
      incoming.dispose();
      await socket.close();
    }, skip: skipReason);

    test('websocket messages expose zero-copy payload slices', () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      final decoder = NativeMessageHandleDecoder(libraryPath: libraryPath);
      addTearDown(runtime.dispose);

      try {
        runtime.shutdown();
      } catch (_) {}

      runtime.start();
      addTearDown(runtime.shutdown);

      const configJson =
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":30,"protocols":["rawsocket","websocket","http"],"websocket_path":"/ws","http":{"alpn":["http/1.1"]}}]}';
      runtime.applyRouterConfig(Uint8List.fromList(utf8.encode(configJson)));

      final listenerId = runtime.listen('127.0.0.1', 0);
      expect(listenerId, greaterThan(0));

      final port = runtime.getLocalPort(listenerId);
      expect(port, greaterThan(0));

      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.close);

      await _sendWebSocketHandshakeRequest(
        socket,
        path: '/ws',
        host: '127.0.0.1:$port',
        protocols: const ['wamp.2.json'],
      );

      final connectionId = await _pollConnectionUntil(runtime, listenerId);
      expect(connectionId, greaterThan(0));

      final handshake = await _takeWebSocketHandshakeUntil(
        runtime,
        connectionId,
      );
      addTearDown(handshake.release);
      expect(handshake.protocols, contains('wamp.2.json'));
      runtime.acceptWebSocket(
        connectionId: connectionId,
        handshakeHandle: handshake.handle,
        serializer: NativeMessageSerializer.json,
        protocol: 'wamp.2.json',
      );
      handshake.consume();

      final handshakeResponse = await _readHttpResponse(socket);
      expect(handshakeResponse, contains('101 Switching Protocols'));
      expect(
        handshakeResponse.toLowerCase(),
        contains('sec-websocket-protocol: wamp.2.json'),
      );
      expect(runtime.connectionWebSocketProtocol(connectionId), 'wamp.2.json');

      final payload = utf8.encode(
        jsonEncode([
          16,
          900,
          {},
          'com.example.topic',
          ['alpha'],
          {'flag': true},
        ]),
      );
      await _sendWebSocketFrame(
        socket,
        opcode: 0x1,
        fin: true,
        payload: payload,
      );

      final handle = await _pollWebSocketHandleUntil(runtime, connectionId);
      expect(handle, greaterThan(0));

      final incoming = decoder.materialize(handle);
      addTearDown(incoming.dispose);
      expect(incoming.serializer, NativeMessageSerializer.json);
      final publish = incoming.message as Publish;
      expect(publish.topic, 'com.example.topic');
      expect(incoming.frameAddress, isNot(equals(0)));
      expect(incoming.argumentsAddress, isNot(equals(0)));
      expect(incoming.argumentsKeywordsAddress, isNot(equals(0)));
      final argsOffset = incoming.argumentsAddress - incoming.frameAddress;
      final kwargsOffset =
          incoming.argumentsKeywordsAddress - incoming.frameAddress;
      expect(argsOffset, greaterThan(0));
      expect(kwargsOffset, greaterThan(argsOffset));
      expect(
        argsOffset + incoming.argumentsBytes!.length <= incoming.bytes.length,
        isTrue,
      );
      expect(
        kwargsOffset + incoming.argumentsKeywordsBytes!.length <=
            incoming.bytes.length,
        isTrue,
      );
      expect(
        utf8.decode(incoming.bytes),
        jsonEncode([
          16,
          900,
          {},
          'com.example.topic',
          ['alpha'],
          {'flag': true},
        ]),
      );
      expect(
        identical(incoming.argumentsBytes, publish.debugEncodedArgumentsBytes),
        isTrue,
      );
      expect(
        identical(
          incoming.argumentsKeywordsBytes,
          publish.debugEncodedArgumentsKeywordsBytes,
        ),
        isTrue,
      );
      expect(publish.hasLazyArguments, isTrue);
      expect(publish.hasLazyArgumentsKeywords, isTrue);
      expect(publish.arguments, ['alpha']);
      expect(publish.argumentsKeywords, {'flag': true});
      expect(runtime.pollWebSocketMessageHandle(connectionId), 0);
      await _sendWebSocketFrame(
        socket,
        opcode: 0x8,
        fin: true,
        payload: const [],
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, skip: skipReason);

    test('http request bodies surface inline and streaming handles', () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      addTearDown(runtime.dispose);

      try {
        runtime.shutdown();
      } catch (_) {}

      runtime.start();
      addTearDown(runtime.shutdown);

      const configJson =
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/","match_kind":"prefix","methods":{"POST":{"type":"reserved_realm","append_method_suffix":true}}}]}]}';
      runtime.applyRouterConfig(Uint8List.fromList(utf8.encode(configJson)));

      final listenerId = runtime.listen('127.0.0.1', 0);
      expect(listenerId, greaterThan(0));
      final port = runtime.getLocalPort(listenerId);
      expect(port, greaterThan(0));

      final inlineSocket = await Socket.connect('127.0.0.1', port);
      addTearDown(inlineSocket.close);
      const inlineBodyText = 'inline-body';
      final inlineBody = Uint8List.fromList(utf8.encode(inlineBodyText));
      await _sendHttpRequest(
        inlineSocket,
        method: 'POST',
        path: '/inline',
        host: '127.0.0.1:$port',
        body: inlineBody,
      );

      final inlineConnectionId = await _pollConnectionUntil(
        runtime,
        listenerId,
      );
      expect(
        runtime.connectionProtocol(inlineConnectionId),
        NativeConnectionProtocol.http,
      );
      final inlineHandshake = await _takeHttpHandshakeUntil(
        runtime,
        inlineConnectionId,
      );
      addTearDown(inlineHandshake.release);
      expect(inlineHandshake.method, 'POST');
      expect(inlineHandshake.path, '/inline');
      expect(inlineHandshake.body.length, inlineBody.length);
      expect(inlineHandshake.body.view, inlineBody);
      expect(await _readBody(inlineHandshake.body, chunkSize: 4), inlineBody);

      runtime.sendHttpResponse(
        handshakeHandle: inlineHandshake.handle,
        response: NativeHttpResponse(
          status: 204,
          body: NativeHttpResponseBytes(Uint8List(0)),
        ),
      );
      inlineHandshake.release();
      final inlineResponse = await _readHttpResponse(inlineSocket);
      expect(inlineResponse, contains('204 No Content'));

      final streamingSocket = await Socket.connect('127.0.0.1', port);
      addTearDown(streamingSocket.close);
      final streamingBody = Uint8List.fromList(
        List<int>.filled(70 * 1024, 'x'.codeUnitAt(0)),
      );
      await _sendHttpRequest(
        streamingSocket,
        method: 'POST',
        path: '/stream',
        host: '127.0.0.1:$port',
        body: streamingBody,
      );

      final streamingConnectionId = await _pollConnectionUntil(
        runtime,
        listenerId,
      );
      expect(
        runtime.connectionProtocol(streamingConnectionId),
        NativeConnectionProtocol.http,
      );
      final streamingHandshake = await _takeHttpHandshakeUntil(
        runtime,
        streamingConnectionId,
      );
      addTearDown(streamingHandshake.release);
      expect(streamingHandshake.method, 'POST');
      expect(streamingHandshake.path, '/stream');
      expect(streamingHandshake.body.length, streamingBody.length);
      expect(
        await _readBody(streamingHandshake.body, chunkSize: 16 * 1024),
        streamingBody,
      );

      runtime.sendHttpResponse(
        handshakeHandle: streamingHandshake.handle,
        response: NativeHttpResponse(
          status: 204,
          body: NativeHttpResponseBytes(Uint8List(0)),
        ),
      );
      streamingHandshake.release();
      final streamingResponse = await _readHttpResponse(streamingSocket);
      expect(streamingResponse, contains('204 No Content'));
    }, skip: skipReason);
  });
}

Future<void> _performHandshake(Socket socket) async {
  const serializerJson = 0x01;
  const exponent = 16;
  final handshakeByte = ((exponent - 9) << 4) | serializerJson;
  socket.add([0x7F, handshakeByte, 0x00, 0x00]);
  await socket.flush();
  final response = await _readExact(socket, 4);
  expect(response[0], 0x7F);
}

Future<void> _sendHelloFrame(Socket socket) async {
  final payload = utf8.encode(
    jsonEncode([
      1,
      'com.example.realm',
      {
        'roles': {'dealer': {}},
      },
    ]),
  );
  final header = _encodeFrameHeader(payload.length);
  socket.add(header);
  socket.add(payload);
  await socket.flush();
}

Future<void> _sendPublishFrame(Socket socket) async {
  final payload = utf8.encode(
    jsonEncode([
      16,
      900,
      {},
      'com.example.topic',
      ['alpha'],
      {'flag': true},
    ]),
  );
  final header = _encodeFrameHeader(payload.length);
  socket.add(header);
  socket.add(payload);
  await socket.flush();
}

Future<void> _sendWebSocketHandshakeRequest(
  Socket socket, {
  required String path,
  required String host,
  required List<String> protocols,
}) async {
  final key = base64.encode(List<int>.generate(16, (index) => index + 1));
  final lines = <String>[
    'GET $path HTTP/1.1',
    'Host: $host',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: $key',
    'Sec-WebSocket-Version: 13',
    'Sec-WebSocket-Protocol: ${protocols.join(',')}',
    '',
  ];
  socket.add(utf8.encode('${lines.join('\r\n')}\r\n'));
  await socket.flush();
}

Future<void> _sendHttpRequest(
  Socket socket, {
  required String method,
  required String path,
  required String host,
  required Uint8List body,
}) async {
  final lines = <String>[
    '$method $path HTTP/1.1',
    'Host: $host',
    'Content-Length: ${body.length}',
    '',
  ];
  socket
    ..add(utf8.encode('${lines.join('\r\n')}\r\n'))
    ..add(body);
  await socket.flush();
}

Future<List<int>> _readFrame(Socket socket) async {
  final header = await _readExact(socket, 4);
  final type = header[0] & 0x07;
  expect(type, 0);
  final lengthHi = (header[0] >> 3) & 0x01;
  var length = (header[1] << 16) | (header[2] << 8) | header[3];
  if (lengthHi == 1) {
    length = 1 << 24;
  }
  if (length == 0) {
    return const [];
  }
  return _readExact(socket, length);
}

Future<String> _readHttpResponse(Socket socket) async {
  final queue = _socketQueues.putIfAbsent(
    socket,
    () => StreamQueue(socket.asBroadcastStream()),
  );
  final leftovers = _socketLeftovers.putIfAbsent(socket, () => <int>[]);
  final buffer = <int>[];
  const terminator = [13, 10, 13, 10];

  while (true) {
    if (leftovers.isNotEmpty) {
      buffer.addAll(leftovers);
      leftovers.clear();
    } else {
      if (!await queue.hasNext) {
        break;
      }
      buffer.addAll(await queue.next);
    }
    final end = _indexOfSublist(buffer, terminator);
    if (end != -1) {
      final headerLength = end + terminator.length;
      final remaining = buffer.sublist(headerLength);
      leftovers
        ..clear()
        ..addAll(remaining);
      return utf8.decode(buffer.sublist(0, headerLength));
    }
  }
  throw StateError('Handshake response incomplete');
}

Future<NativeHttpHandshake> _takeHttpHandshakeUntil(
  NativeTransportRuntime runtime,
  int connectionId,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 2)) {
    final handshake = runtime.takeHttpHandshake(connectionId);
    if (handshake != null) {
      return handshake;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for http handshake on connection $connectionId',
  );
}

List<int> _encodeFrameHeader(int length) {
  if (length >= 1 << 24) {
    throw ArgumentError.value(length, 'length', 'Frame too large');
  }
  return [0x00, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF];
}

final Map<Socket, StreamQueue<List<int>>> _socketQueues = {};
final Map<Socket, List<int>> _socketLeftovers = {};

Future<int> _pollConnectionUntil(
  NativeTransportRuntime runtime,
  int listenerId,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 2)) {
    final connectionId = runtime.pollConnection(listenerId);
    if (connectionId > 0) {
      return connectionId;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for native connection on listener $listenerId',
  );
}

Future<NativeWebSocketHandshake> _takeWebSocketHandshakeUntil(
  NativeTransportRuntime runtime,
  int connectionId,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 2)) {
    final handshake = runtime.takeWebSocketHandshake(connectionId);
    if (handshake != null) {
      return handshake;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for websocket handshake on connection $connectionId',
  );
}

Future<int> _pollWebSocketHandleUntil(
  NativeTransportRuntime runtime,
  int connectionId,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 2)) {
    final handle = runtime.pollWebSocketMessageHandle(connectionId);
    if (handle > 0) {
      return handle;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for websocket message on connection $connectionId',
  );
}

Future<Uint8List> _readBody(
  NativeHttpRequestBody body, {
  required int chunkSize,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in body.openRead(chunkSize: chunkSize)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> _sendWebSocketFrame(
  Socket socket, {
  required int opcode,
  required bool fin,
  required List<int> payload,
}) async {
  const maskKey = [0x11, 0x22, 0x33, 0x44];
  final header = <int>[(fin ? 0x80 : 0x00) | (opcode & 0x0F)];
  if (payload.length < 126) {
    header.add(0x80 | payload.length);
  } else if (payload.length <= 0xFFFF) {
    header
      ..add(0x80 | 126)
      ..add((payload.length >> 8) & 0xFF)
      ..add(payload.length & 0xFF);
  } else {
    header.add(0x80 | 127);
    final view = ByteData(8)..setUint64(0, payload.length);
    header.addAll(view.buffer.asUint8List());
  }
  header.addAll(maskKey);
  final maskedPayload = List<int>.generate(
    payload.length,
    (index) => payload[index] ^ maskKey[index % 4],
  );
  socket
    ..add(header)
    ..add(maskedPayload);
  await socket.flush();
}

int _indexOfSublist(List<int> data, List<int> pattern) {
  if (pattern.isEmpty) {
    return 0;
  }
  for (var i = 0; i <= data.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

Future<List<int>> _readExact(Socket socket, int length) async {
  final queue = _socketQueues.putIfAbsent(
    socket,
    () => StreamQueue(socket.asBroadcastStream()),
  );
  final leftovers = _socketLeftovers.putIfAbsent(socket, () => <int>[]);
  final buffer = <int>[];

  void drainLeftovers() {
    if (leftovers.isEmpty || buffer.length >= length) {
      return;
    }
    final remaining = length - buffer.length;
    if (leftovers.length <= remaining) {
      buffer.addAll(leftovers);
      leftovers.clear();
    } else {
      buffer.addAll(leftovers.sublist(0, remaining));
      leftovers.removeRange(0, remaining);
    }
  }

  drainLeftovers();

  while (buffer.length < length) {
    if (!await queue.hasNext) {
      break;
    }
    final chunk = await queue.next;
    final remaining = length - buffer.length;
    if (chunk.length <= remaining) {
      buffer.addAll(chunk);
    } else {
      buffer.addAll(chunk.sublist(0, remaining));
      leftovers
        ..clear()
        ..addAll(chunk.sublist(remaining));
    }
  }

  return buffer;
}
