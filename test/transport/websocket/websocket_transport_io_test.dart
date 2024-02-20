@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with io communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      var server = await HttpServer.bind('localhost', 9911);
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          var socket = await WebSocketTransformer.upgrade(req);
          print(
              'Received protocol ${req.headers.value('sec-websocket-protocol')!}');
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
                  socket.add(Uint8List.fromList(
                      [221, 0, 0, 0, 3, 2, 205, 4, 210, 223, 0, 0, 0, 0]));
                } else {
                  socket.add(Uint8List.fromList([131, 2, 25, 4, 210, 160]));
                }
              }
            }
          });
        }
      });

      var transportJSON =
          WebSocketTransport.withJsonSerializer('ws://localhost:9911/wamp');

      var transportMsgpack =
          WebSocketTransport.withMsgpackSerializer('ws://localhost:9911/wamp');

      var transportCbor =
          WebSocketTransport.withCborSerializer('ws://localhost:9911/wamp');

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
    });
  });
}
