@TestOn('vm')

import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart'
    // ignore: library_prefixes
    as jsonSerializer;
import 'package:connectanum/src/serializer/msgpack/serializer.dart'
    // ignore: library_prefixes
    as msgpackSerializer;
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
          print('Received protocol ' + (req.headers.value('sec-websocket-protocol') as String));
          socket.listen((message) {
            if (message is String &&
                message.contains('[${MessageTypes.CODE_HELLO}')) {
              socket.add('[${MessageTypes.CODE_WELCOME},1234,{}]');
            } else {
              // received msgpack
              if (message.contains(MessageTypes.CODE_HELLO)) {
                socket.add(Uint8List.fromList(
                    [221, 0, 0, 0, 3, 2, 205, 4, 210, 223, 0, 0, 0, 0]));
              }
            }
          });
        }
      });

      var transportJSON = WebSocketTransport(
          'ws://localhost:9100/wamp',
          jsonSerializer.Serializer(),
          WebSocketSerialization.SERIALIZATION_JSON);

      var transportMsgpack = WebSocketTransport(
          'ws://localhost:9100/wamp',
          msgpackSerializer.Serializer(),
          WebSocketSerialization.SERIALIZATION_MSGPACK);

      await transportJSON.open();
      transportJSON.send(Hello('my.realm', Details.forHello()));
      var welcome = await transportJSON.receive().first as Welcome;
      expect(welcome.sessionId, equals(1234));

      await transportMsgpack.open();
      transportMsgpack.send(Hello('my.realm', Details.forHello()));
      welcome = await transportMsgpack.receive().first as Welcome;
      expect(welcome.sessionId, equals(1234));
    });
  });
}
