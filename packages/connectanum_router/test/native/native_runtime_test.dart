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

void main() {
  final libraryPath = _resolveLibraryPath();
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
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":30}]}';
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
  });
}

String? _resolveLibraryPath() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    '../../native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
    'native/transport/target/debug/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
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

List<int> _encodeFrameHeader(int length) {
  if (length >= 1 << 24) {
    throw ArgumentError.value(length, 'length', 'Frame too large');
  }
  return [0x00, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF];
}

final Map<Socket, StreamQueue<List<int>>> _socketQueues = {};
final Map<Socket, List<int>> _socketLeftovers = {};

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
