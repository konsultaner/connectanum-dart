@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library native_runtime_test;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:connectanum_client/native_message_handles.dart';
import 'package:connectanum_core/connectanum_core.dart'
    show Hello, MessageTypes, Publish, Unsubscribe;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

class _MinimalRuntime extends NativeRuntime {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected runtime operation: ${invocation.memberName}',
  );
}

void main() {
  final libraryPath = resolveOrBuildNativeLib();
  final usesWide =
      libraryPath != null &&
      NativeMessageHandleAbi.detect(ffi.DynamicLibrary.open(libraryPath)) ==
          NativeMessageHandleAbi.wide;
  final skipReason = libraryPath == null
      ? 'Native ct_ffi library not found'
      : null;

  group('NativeRuntime optional capabilities', () {
    final runtime = _MinimalRuntime();
    test('absent subprotocol and metrics remain absent', () {
      expect(runtime.connectionWebSocketProtocol(42), isNull);
      expect(runtime.pollRouterMetrics(), isNull);
    });
    test('unsupported HTTP responses fail explicitly', () {
      expect(
        () => runtime.sendHttpResponse(
          handshakeHandle: 42,
          response: NativeHttpResponse(
            status: 204,
            body: NativeHttpResponseText(''),
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => runtime.openHttpResponseStream(
          handshakeHandle: 42,
          status: 200,
          headers: const {},
        ),
        throwsUnsupportedError,
      );
      expect(
        () => runtime.openHttpResponseStreamDescriptor(
          handshakeHandle: 42,
          status: 200,
          headers: const {},
        ),
        throwsUnsupportedError,
      );
    });
    test('unsupported TLS reload does not report success', () {
      expect(runtime.reloadTls, throwsUnsupportedError);
    });
  });

  group('NativeTransportRuntime', () {
    group('resource error contracts', () {
      late NativeTransportRuntime runtime;
      late int listener;

      Uint8List endpointConfig([String host = '127.0.0.1']) =>
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'schema': 'connectanum.router',
                'version': 1,
                'endpoints': [
                  {
                    'host': host,
                    'port': 0,
                    'tls_mode': 'disabled',
                    'protocols': ['rawsocket'],
                  },
                ],
              }),
            ),
          );

      setUp(() {
        runtime = NativeTransportRuntime(libraryPath: libraryPath!);
        addTearDown(runtime.dispose);
        runtime.start();
        addTearDown(runtime.shutdown);
        runtime.applyRouterConfig(endpointConfig());
        listener = runtime.listen('127.0.0.1', 0);
        expect(listener, greaterThan(0));
        expect(runtime.getLocalPort(listener), greaterThan(0));
      });

      const absent = 0x7ffffffe;
      final operations = <String, (int, void Function(NativeTransportRuntime))>{
        'listener port': (
          NativeTransportErrorCode.listenerNotFound,
          (r) => r.getLocalPort(absent),
        ),
        'listener HTTP3 port': (
          NativeTransportErrorCode.listenerNotFound,
          (r) => r.getHttp3Port(absent),
        ),
        'listener close': (
          NativeTransportErrorCode.listenerNotFound,
          (r) => r.closeListener(absent),
        ),
        'listener poll': (
          NativeTransportErrorCode.listenerNotFound,
          (r) => r.pollConnection(absent),
        ),
        'connection protocol': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.connectionProtocol(absent),
        ),
        'connection close': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.closeConnection(absent),
        ),
        'connection exponent': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.connectionMaxRawSocketExponent(absent),
        ),
        'connection subprotocol': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.connectionWebSocketProtocol(absent),
        ),
        'HTTP handshake': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.takeHttpHandshake(absent),
        ),
        'HTTP2 handshake': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.takeHttp2Handshake(absent),
        ),
        'HTTP3 handshake': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.takeHttp3Handshake(absent),
        ),
        'WebSocket handshake': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.takeWebSocketHandshake(absent),
        ),
        'HTTP3 connection': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.takeHttp3Connection(absent),
        ),
        'HTTP3 stream': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.pollHttp3Stream(absent),
        ),
        'HTTP3 request': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.pollHttp3Request(absent),
        ),
        'message poll': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.pollMessage(absent),
        ),
        'message handle poll': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.pollMessageHandle(absent),
        ),
        'WebSocket message poll': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.pollWebSocketMessageHandle(absent),
        ),
        'message send': (
          NativeTransportErrorCode.connectionNotFound,
          (r) => r.sendMessage(absent, Uint8List.fromList([91, 93])),
        ),
      };

      for (final entry in operations.entries) {
        test('${entry.key} preserves native error and healthy listener', () {
          expect(
            () => entry.value.$2(runtime),
            throwsA(
              isA<NativeTransportException>().having(
                (error) => error.code,
                'native code',
                entry.value.$1,
              ),
            ),
          );
          expect(runtime.getLocalPort(listener), greaterThan(0));
          expect(runtime.getHttp3Port(listener), 0);
          expect(runtime.pollConnection(listener), 0);
        });
      }

      test(
        'wrong-protocol queries preserve RawSocket frame delivery',
        () async {
          final socket = await Socket.connect(
            '127.0.0.1',
            runtime.getLocalPort(listener),
          );
          addTearDown(() async {
            await _socketQueues.remove(socket)?.cancel(immediate: true);
            _socketLeftovers.remove(socket);
            socket.destroy();
          });
          await _performHandshake(socket);
          final connection = await _pollConnectionUntil(runtime, listener);
          expect(
            runtime.connectionProtocol(connection),
            NativeConnectionProtocol.rawsocket,
          );
          final queries = <String, Object? Function(int)>{
            'WebSocket subprotocol': runtime.connectionWebSocketProtocol,
            'WebSocket handshake': runtime.takeWebSocketHandshake,
            'HTTP handshake': runtime.takeHttpHandshake,
            'HTTP2 handshake': runtime.takeHttp2Handshake,
            'HTTP3 handshake': runtime.takeHttp3Handshake,
            'HTTP3 connection': runtime.takeHttp3Connection,
            'HTTP3 stream': runtime.pollHttp3Stream,
            'HTTP3 request': runtime.pollHttp3Request,
          };
          for (final entry in queries.entries) {
            expect(
              () => entry.value(connection),
              throwsA(
                isA<NativeTransportException>().having(
                  (error) => error.code,
                  'native code',
                  NativeTransportErrorCode.unsupportedProtocol,
                ),
              ),
              reason: entry.key,
            );
            expect(
              runtime.connectionProtocol(connection),
              NativeConnectionProtocol.rawsocket,
              reason: entry.key,
            );
          }
          // The optional WebSocket poll maps "unsupported" to no available handle.
          expect(runtime.pollWebSocketMessageHandle(connection), 0);
          final payload = Uint8List.fromList(utf8.encode('[2,123,{}]'));
          runtime.sendMessage(connection, payload);
          expect(await _readFrame(socket), orderedEquals(payload));
          runtime.closeConnection(connection);
          expect(
            () => runtime.connectionProtocol(connection),
            throwsA(
              isA<NativeTransportException>().having(
                (error) => error.code,
                'native code',
                NativeTransportErrorCode.connectionNotFound,
              ),
            ),
          );
        },
      );

      test('releasing empty handshakes is idempotent', () {
        for (final handle in [0, -1]) {
          for (var repeat = 0; repeat < 2; repeat++) {
            runtime.releaseHttpHandshake(handle);
            runtime.releaseHttp2Handshake(handle);
            runtime.releaseHttp3Handshake(handle);
          }
        }
        expect(runtime.getLocalPort(listener), greaterThan(0));
        final port = runtime.getLocalPort(listener);
        // Reload counts reconfigured listeners, including cleartext endpoints.
        expect(runtime.reloadTls(), 1);
        expect(runtime.getLocalPort(listener), port);
        runtime.closeListener(listener);
        expect(runtime.reloadTls(), 0);
      });
      test('failed TLS reload preserves listener and can recover', () {
        final port = runtime.getLocalPort(listener);
        runtime.applyRouterConfig(endpointConfig('127.0.0.2'));
        expect(
          runtime.reloadTls,
          throwsA(
            isA<NativeTransportException>().having(
              (error) => error.code,
              'native code',
              NativeTransportErrorCode.endpointNotConfigured,
            ),
          ),
        );
        expect(runtime.getLocalPort(listener), port);
        runtime.applyRouterConfig(endpointConfig());
        expect(runtime.reloadTls(), 1);
        expect(runtime.getLocalPort(listener), port);
        expect(runtime.pollConnection(listener), 0);
      });
    }, skip: skipReason);

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
      await _sendUnsubscribeFrame(socket);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final polledId = runtime.pollConnection(listenerId);
      expect(polledId, greaterThan(0));
      expect(runtime.connectionMaxRawSocketExponent(polledId), 16);
      expect(connectionEvents, contains((listenerId, polledId)));

      final incoming = runtime.pollMessage(polledId);
      expect(incoming, isNotNull);
      expect(incoming!.serializer, NativeMessageSerializer.json);
      expect(incoming.handle, greaterThan(usesWide ? 0xffffffff : 0));
      final hello = incoming.message as Hello;
      expect(hello.id, MessageTypes.codeHello);
      expect(hello.realm, 'com.example.realm');
      expect(hello.details.roles?.dealer, isNotNull);
      expect(incoming.bytes, isEmpty);
      expect(incoming.frameAddress, 0);

      final publishMessage = runtime.pollMessage(polledId);
      expect(publishMessage, isNotNull);
      expect(publishMessage!.serializer, NativeMessageSerializer.json);
      final publish = publishMessage.message as Publish;
      expect(publish.topic, 'com.example.topic');
      expect(publishMessage.bytes, isEmpty);
      expect(publishMessage.frameAddress, 0);
      expect(publishMessage.argumentsAddress, isNot(equals(0)));
      expect(publishMessage.argumentsKeywordsAddress, isNot(equals(0)));
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

      final unsubscribeMessage = runtime.pollMessage(polledId);
      expect(unsubscribeMessage, isNotNull);
      expect(unsubscribeMessage!.serializer, NativeMessageSerializer.json);
      expect(unsubscribeMessage.bytes, isEmpty);
      expect(unsubscribeMessage.frameAddress, 0);
      expect(unsubscribeMessage.message, isA<Unsubscribe>());
      final unsubscribe = unsubscribeMessage.message as Unsubscribe;
      expect(unsubscribe.requestId, 901);
      expect(unsubscribe.subscriptionId, 902);
      unsubscribeMessage.dispose();

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
      expect(handle, greaterThan(usesWide ? 0xffffffff : 0));

      final incoming = decoder.materialize(handle);
      addTearDown(incoming.dispose);
      expect(incoming.serializer, NativeMessageSerializer.json);
      final publish = incoming.message as Publish;
      expect(publish.topic, 'com.example.topic');
      expect(incoming.bytes, isEmpty);
      expect(incoming.frameAddress, 0);
      expect(incoming.argumentsAddress, isNot(equals(0)));
      expect(incoming.argumentsKeywordsAddress, isNot(equals(0)));
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

    test('cancelled HTTP body reader discards subsequent native chunks', () async {
      final runtime = NativeTransportRuntime(libraryPath: libraryPath!);
      addTearDown(runtime.dispose);
      runtime.start();
      addTearDown(runtime.shutdown);
      const configJson =
          '{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/","match_kind":"prefix","methods":{"POST":{"type":"reserved_realm","append_method_suffix":true}}}]}]}';
      runtime.applyRouterConfig(Uint8List.fromList(utf8.encode(configJson)));
      final listenerId = runtime.listen('127.0.0.1', 0);
      final port = runtime.getLocalPort(listenerId);
      final socket = await Socket.connect('127.0.0.1', port);
      addTearDown(socket.destroy);
      const length = 70 * 1024;
      socket
        ..add(
          utf8.encode(
            'POST /cancel HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n'
            'Content-Length: $length\r\nConnection: close\r\n\r\n',
          ),
        )
        ..add([11, 12, 13, 14]);
      await socket.flush();
      final connection = await _pollConnectionUntil(runtime, listenerId);
      final handshake = await _takeHttpHandshakeUntil(runtime, connection);
      addTearDown(handshake.release);
      expect(handshake.body.isStreaming, isTrue);
      expect(handshake.body.length, length);
      final reader = StreamIterator(handshake.body.openRead(chunkSize: 4));
      expect(await reader.moveNext(), isTrue);
      expect(reader.current, [11, 12, 13, 14]);
      await reader.cancel();

      // No response or handshake release may implicitly finish the body first.
      socket.add(Uint8List.fromList(List<int>.filled(length - 4, 37)));
      await socket.flush();
      expect(await _readBody(handshake.body, chunkSize: 16 * 1024), isEmpty);
      runtime.sendHttpResponse(
        handshakeHandle: handshake.handle,
        response: NativeHttpResponse(
          status: 204,
          body: NativeHttpResponseBytes(Uint8List(0)),
        ),
      );
      handshake.release();
      expect(await _readHttpResponse(socket), contains('204 No Content'));
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
        headerLines: const <String>[
          'X-Connectanum-Realm: realm1',
          'X-Connectanum-Realm: realm1',
          'X-Connectanum-Auth-Method: ticket',
          'x-connectanum-auth-method: ticket',
        ],
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
      expect(inlineHandshake.duplicateHeaderNames, {
        'x-connectanum-realm',
        'x-connectanum-auth-method',
      });
      expect(inlineHandshake.headerValues['x-connectanum-realm'], [
        'realm1',
        'realm1',
      ]);
      expect(inlineHandshake.headerValues['x-connectanum-auth-method'], [
        'ticket',
        'ticket',
      ]);
      expect(
        () => inlineHandshake.headerValues['x-connectanum-realm']!.add(
          'other',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => inlineHandshake.headerValues['other'] = const <String>[],
        throwsUnsupportedError,
      );
      expect(inlineHandshake.body.length, inlineBody.length);
      expect(inlineHandshake.body.view, inlineBody);
      expect(await _readBody(inlineHandshake.body, chunkSize: 4), inlineBody);

      final borrowed = NativeHttpRequestBody.borrowed(
        handle: inlineHandshake.body.nativeHandle!,
        length: inlineBody.length,
        streaming: false,
        libraryPath: libraryPath,
      );
      for (final declaredLength in [inlineBody.length, inlineBody.length + 3]) {
        for (final useView in [false, true]) {
          final descriptor = NativeHttpRequestBody.borrowed(
            handle: inlineHandshake.body.nativeHandle!,
            length: declaredLength,
            streaming: false,
            libraryPath: libraryPath,
          );
          final copied = useView
              ? descriptor.view
              : descriptor.materializeOwnedBytes();
          expect(copied, inlineBody);
          copied[0] = 0;
          expect(inlineHandshake.body.view, inlineBody);
        }
      }
      expect(await _readBody(borrowed, chunkSize: 4), inlineBody);
      expect(borrowed.copy(), inlineBody);
      expect(borrowed.hasNativeHandle, isTrue);

      runtime.sendHttpResponse(
        handshakeHandle: inlineHandshake.handle,
        response: NativeHttpResponse(
          status: 204,
          headers: const {'Set-Cookie': 'sid=first; HttpOnly'},
          additionalHeaders: const [
            MapEntry(
              'SET-cookie',
              'language=de; Expires=Wed, 09 Jun 2032 10:18:14 GMT',
            ),
            MapEntry('set-cookie', 'theme=dark; Secure'),
          ],
          body: NativeHttpResponseBytes(Uint8List(0)),
        ),
      );
      inlineHandshake.release();
      expect(
        borrowed.materializeOwnedBytes,
        throwsA(
          isA<NativeTransportException>().having(
            (error) => error.code,
            'released body handle',
            NativeTransportErrorCode.handshakeConsumed,
          ),
        ),
      );
      final inlineResponse = await _readHttpResponse(inlineSocket);
      expect(inlineResponse, contains('204 No Content'));
      expect(
        const LineSplitter()
            .convert(inlineResponse)
            .where(
              (line) => line.toLowerCase().startsWith('set-cookie:'),
            ),
        [
          'set-cookie: sid=first; HttpOnly',
          'set-cookie: language=de; Expires=Wed, 09 Jun 2032 10:18:14 GMT',
          'set-cookie: theme=dark; Secure',
        ],
      );

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

Future<void> _sendUnsubscribeFrame(Socket socket) async {
  final payload = utf8.encode(
    jsonEncode([MessageTypes.codeUnsubscribe, 901, 902]),
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
  List<String> headerLines = const <String>[],
}) async {
  final lines = <String>[
    '$method $path HTTP/1.1',
    'Host: $host',
    ...headerLines,
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
