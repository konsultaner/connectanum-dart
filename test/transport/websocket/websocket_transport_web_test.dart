@TestOn('browser')
library;

import 'dart:async';

import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test(
        'Opening a server connection and simple send receive scenario using a serializer',
        () async {
      var channel = spawnHybridUri('websocket_transport_web_server.dart');
      late String port;
      late WebSocketTransport transportJSON;
      late WebSocketTransport transportMsgpack;
      late WebSocketTransport transportCbor;
      Completer jsonCompleter = Completer();
      Completer msgpackCompleter = Completer();
      Completer cborCompleter = Completer();
      var channelValues = <dynamic>[];
      channel.stream.listen((event) async {
        channelValues.add(event);
        if (channelValues.length == 1) {
          port = event;
          transportJSON = WebSocketTransport.withJsonSerializer(
              'ws://localhost:$port/wamp');
          transportMsgpack = WebSocketTransport.withMsgpackSerializer(
              'ws://localhost:$port/wamp');
          transportCbor = WebSocketTransport.withCborSerializer(
              'ws://localhost:$port/wamp');
        }
        if (channelValues.length == 1) {
          print('Connect to ws://localhost:$port/wamp via json');
          await transportJSON.open();
        }
        if (channelValues.length == 2) {
          jsonCompleter.complete();
          print('Connect to ws://localhost:$port/wamp via msgpack');
          await transportMsgpack.open();
        }
        if (channelValues.length == 3) {
          msgpackCompleter.complete();
          print('Connect to ws://localhost:$port/wamp via cbor');
          await transportCbor.open();
        }
        if (channelValues.length == 4) {
          cborCompleter.complete();
        }
      });

      print('#### JSON transport');
      await jsonCompleter.future;
      transportJSON.send(Hello('my.realm', Details.forHello()));
      var welcome = await transportJSON.receive().first;
      expect(welcome, isA<Welcome>());

      print('#### MSGPACK transport');
      await msgpackCompleter.future;
      transportMsgpack.send(Hello('my.realm', Details.forHello()));
      welcome = await transportMsgpack.receive().first;
      expect(welcome, isA<Welcome>());

      print('#### CBOR transport');
      await cborCompleter.future;
      transportCbor.send(Hello('my.realm', Details.forHello()));
      welcome = await transportCbor.receive().first;
      expect(welcome, isA<Welcome>());
    });
  });
}
