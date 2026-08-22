@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/hello.dart';
import 'package:connectanum_core/src/message/message_types.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with io communication', () {
    test(
      'Opening a server connection and simple send receive scenario using a serializer',
      () async {
        var server = await HttpServer.bind('localhost', 9911);
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest req) async {
          if (req.uri.path == '/wamp') {
            var socket = await WebSocketTransformer.upgrade(req);
            socket.listen((message) {
              if (message is String &&
                  message.contains('[${MessageTypes.codeHello}')) {
                if (message.contains('headers.realm') &&
                    req.headers['X_Custom_Header'] != null &&
                    req.headers.value('X_Custom_Header') == 'custom_value') {
                  socket.add('[${MessageTypes.codeWelcome},5555,{}]');
                } else {
                  socket.add('[${MessageTypes.codeWelcome},1234,{}]');
                }
              } else {
                // received msgpack
                if (message.contains(MessageTypes.codeHello)) {
                  if (req.headers.value('sec-websocket-protocol') ==
                      WebSocketSerialization.serializationMsgpack) {
                    socket.add(
                      Uint8List.fromList([
                        221,
                        0,
                        0,
                        0,
                        3,
                        2,
                        205,
                        4,
                        210,
                        223,
                        0,
                        0,
                        0,
                        0,
                      ]),
                    );
                  } else {
                    socket.add(Uint8List.fromList([131, 2, 25, 4, 210, 160]));
                  }
                }
              }
            });
          }
        });

        var transportJSON = WebSocketTransport.withJsonSerializer(
          'ws://localhost:9911/wamp',
        );

        var transportMsgpack = WebSocketTransport.withMsgpackSerializer(
          'ws://localhost:9911/wamp',
        );

        var transportCbor = WebSocketTransport.withCborSerializer(
          'ws://localhost:9911/wamp',
        );

        var transportWithHeaders = WebSocketTransport.withJsonSerializer(
          'ws://localhost:9911/wamp',
          {'X_Custom_Header': 'custom_value'},
        );

        await transportJSON.open();
        transportJSON.send(Hello('my.realm', Details.forHello()));
        Welcome? welcome = (await transportJSON.receive().first) as Welcome;
        expect(welcome.sessionId, equals(1234));

        await transportMsgpack.open();
        transportMsgpack.send(Hello('my.realm', Details.forHello()));
        welcome = (await transportMsgpack.receive().first) as Welcome;
        expect(welcome.sessionId, equals(1234));

        await transportCbor.open();
        transportCbor.send(Hello('my.realm', Details.forHello()));
        welcome = (await transportCbor.receive().first) as Welcome;
        expect(welcome.sessionId, equals(1234));

        await transportWithHeaders.open();
        transportWithHeaders.send(Hello('headers.realm', Details.forHello()));
        welcome = (await transportWithHeaders.receive().first) as Welcome;
        expect(welcome.sessionId, equals(5555));
      },
    );

    test('closes connection when inbound WAMP frame is malformed', () async {
      final server = await HttpServer.bind('localhost', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          final socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            if (message is String &&
                message.contains('[${MessageTypes.codeHello}')) {
              socket.add('[999]');
            }
          });
        }
      });

      final transport = WebSocketTransport.withJsonSerializer(
        'ws://localhost:${server.port}/wamp',
      );
      addTearDown(transport.close);

      await transport.open();
      final subscription = transport.receive().listen((_) {});
      addTearDown(subscription.cancel);
      transport.send(Hello('my.realm', Details.forHello()));

      final error = await transport.onConnectionLost!.future.timeout(
        const Duration(seconds: 1),
      );

      expect(error, isA<FormatException>());
      expect(
        error.toString(),
        contains('Could not deserialize inbound WebSocket WAMP message'),
      );
      await transport.onDisconnect!.future.timeout(const Duration(seconds: 1));
    });

    test('sends lazy JSON payload fragments as one text message', () async {
      final received = Completer<Object>();
      final server = await HttpServer.bind('localhost', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          if (!received.isCompleted) {
            received.complete(message);
          }
        });
      });

      final transport = WebSocketTransport.withJsonSerializer(
        'ws://localhost:${server.port}/wamp',
      );
      addTearDown(transport.close);
      await transport.open();

      final argumentsBytes = Uint8List.fromList(utf8.encode('["lazy"]'));
      final call = Call(42, 'bench.rpc.echo')
        ..setLazyPayload(
          argumentsBytes: argumentsBytes,
          argumentsDecoder: (_) => throw StateError('must stay lazy'),
          encoding: LazyPayloadEncoding.json,
        );
      transport.send(call);

      final message = await received.future.timeout(const Duration(seconds: 1));
      expect(message, isA<String>());
      expect(jsonDecode(message as String), [
        48,
        42,
        {},
        'bench.rpc.echo',
        ['lazy'],
      ]);
    });

    test('sends MessagePack fragments as one binary message', () async {
      final received = Completer<Object>();
      final server = await HttpServer.bind('localhost', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          if (!received.isCompleted) {
            received.complete(message);
          }
        });
      });

      final transport = WebSocketTransport.withMsgpackSerializer(
        'ws://localhost:${server.port}/wamp',
      );
      addTearDown(transport.close);
      await transport.open();

      final payload = Uint8List.fromList(const [1, 2, 3, 4]);
      transport.send(
        Call(43, 'bench.rpc.echo', arguments: <dynamic>[payload]),
      );

      final message = await received.future.timeout(const Duration(seconds: 1));
      expect(message, isA<Uint8List>());
      final decoded = msgpack_dart.deserialize(message as Uint8List) as List;
      expect(decoded[0], MessageTypes.codeCall);
      expect(decoded[1], 43);
      expect(decoded[3], 'bench.rpc.echo');
      expect(decoded[4][0], orderedEquals(payload));
    });
  });
}
