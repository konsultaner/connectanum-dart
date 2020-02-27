@TestOn('vm')

import 'dart:io';

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with io communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      var server = await HttpServer.bind('localhost', 9100);
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          var socket = await WebSocketTransformer.upgrade(req);
          print("Received protocol " +
              req.headers.value("sec-websocket-protocol"));
          socket.listen((message) {
            if (message is String &&
                message.contains("[" + MessageTypes.CODE_HELLO.toString())) {
              socket.add(
                  "[" + MessageTypes.CODE_WELCOME.toString() + ",1234,{}]");
            }
          });
        }
      });

      WebSocketTransport transport = WebSocketTransport(
          "ws://localhost:9100/wamp",
          Serializer(),
          WebSocketTransport.SERIALIZATION_JSON);

      await transport.open();
      transport.send(Hello("my.realm", Details.forHello()));
      Welcome welcome = await transport.receive().first;
      expect(welcome.sessionId, equals(1234));
    });
  });
}
