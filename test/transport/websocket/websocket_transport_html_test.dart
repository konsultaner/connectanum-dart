@TestOn('browser')

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:connectanum/src/transport/websocket/websocket_transport_html.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      // var server = spawnHybridUri('websocket_transport_html_server.dart');
      // var port = await server.stream.first;
      var transportJSON = WebSocketTransport(
          'wss://www.connectanum.com/wamp', // TODO as soon as https://github.com/dart-lang/sdk/issues/40786 is fixed "ws://localhost:$port/wamp",
          json_serializer.Serializer(),
          WebSocketSerialization.serializationJson);

      var transportMsgpack = WebSocketTransport(
          'wss://www.connectanum.com/wamp', // TODO as soon as https://github.com/dart-lang/sdk/issues/40786 is fixed "ws://localhost:$port/wamp",
          msgpack_serializer.Serializer(),
          WebSocketSerialization.serializationMsgpack);

      await transportJSON.open();
      transportJSON.send(Hello('my.realm', Details.forHello()));
      var welcome = await transportJSON.receive().first;
      expect(welcome, isA<Welcome>());

      await transportMsgpack.open();
      transportMsgpack.send(Hello('my.realm', Details.forHello()));
      welcome = await transportMsgpack.receive().first;
      expect(welcome, isA<Welcome>());
    });
  });
}
