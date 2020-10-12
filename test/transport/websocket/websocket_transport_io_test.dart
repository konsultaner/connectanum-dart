@TestOn('vm')

import 'dart:io';

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
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
          print('Received protocol ' +
              req.headers.value('sec-websocket-protocol'));
          socket.listen((message) {
            if (message is String &&
                message.contains('[${MessageTypes.CODE_HELLO}')) {
              socket.add('[${MessageTypes.CODE_WELCOME},1234,{}]');
            } else {
              // received msgpack
              if (message.contains(MessageTypes.CODE_HELLO)) {
                socket.add([221, 0, 0, 0, 3, 2, 205, 4, 210, 223, 0, 0, 0, 0]);
              }
            }
          });
        }
      });

      var transportJSON = WebSocketTransport(
          'ws://localhost:9100/wamp',
          json_serializer.Serializer(),
          WebSocketSerialization.SERIALIZATION_JSON);

      var transportMsgpack = WebSocketTransport(
          'ws://localhost:9100/wamp',
          msgpack_serializer.Serializer(),
          WebSocketSerialization.SERIALIZATION_MSGPACK);

      await transportJSON.open();
      transportJSON.send(Hello('my.realm', Details.forHello()));
      Welcome welcome = await transportJSON.receive().first;
      expect(welcome.sessionId, equals(1234));

      await transportMsgpack.open();
      transportMsgpack.send(Hello('my.realm', Details.forHello()));
      welcome = await transportMsgpack.receive().first;
      expect(welcome.sessionId, equals(1234));
    });
  });
}
