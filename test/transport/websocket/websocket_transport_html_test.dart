@TestOn('browser')
import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_html.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      spawnHybridUri('websocket_transport_html_server.dart');
      var port = 9101;
      var transportJSON =
          WebSocketTransport.withJsonSerializer('ws://localhost:$port/wamp');

      var transportMsgpack =
          WebSocketTransport.withMsgpackSerializer('ws://localhost:$port/wamp');

      var transportCbor =
          WebSocketTransport.withCborSerializer('ws://localhost:$port/wamp');

      print('Start opening json server transport');
      await transportJSON.open();
      print('Start send HELLO opened');
      transportJSON.send(Hello('my.realm', Details.forHello()));
      print('Waiting for WELCOME opened');
      var welcome = await transportJSON.receive().first;
      print('WELCOME received');
      expect(welcome, isA<Welcome>());

      await transportMsgpack.open();
      transportMsgpack.send(Hello('my.realm', Details.forHello()));
      welcome = await transportMsgpack.receive().first;
      expect(welcome, isA<Welcome>());

      await transportCbor.open();
      transportCbor.send(Hello('my.realm', Details.forHello()));
      welcome = await transportCbor.receive().first;
      expect(welcome, isA<Welcome>());
    });
  });
}
