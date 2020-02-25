@TestOn('browser')

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_html.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test('Opening a server connection and simple send receive scenario using a serializer', () async {
      var server = spawnHybridUri('websocket_transport_html_server.dart');
      var serializer = Serializer();
      var port = await server.stream.first;
      WebSocketTransport transport = WebSocketTransport(
          "ws://localhost:$port/wamp",
          serializer,
          WebSocketTransport.SERIALIZATION_JSON
      );

      print("try open transport to ws://localhost:$port/wamp");
      await transport.open();
      print("opened transport");
      transport.send(Hello("my.realm", Details()));
      Welcome welcome = await transport.receive().first;
      expect(welcome.sessionId, equals(1234));
    });
  });
}