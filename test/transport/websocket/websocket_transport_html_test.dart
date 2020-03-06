@TestOn('browser')

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/abstract_message.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_html.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      var server = spawnHybridUri('websocket_transport_html_server.dart');
      var serializer = Serializer();
      var port = await server.stream.first;
      WebSocketTransport transport = WebSocketTransport(
          "ws://localhost:$port/wamp",
          serializer,
          WebSocketSerialization.SERIALIZATION_JSON);

      await transport.open();
      transport.send(Hello("my.realm", Details.forHello()));
      AbstractMessage welcome = await transport.receive().first;
      expect(welcome, isA<Welcome>());
    });
  });
}
