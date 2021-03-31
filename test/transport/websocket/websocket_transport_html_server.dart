@TestOn('browser')

import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum/src/message/message_types.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// Once the hybrid isolate starts, it will call the special function
// hybridMain() with a StreamChannel that's connected to the channel
// returned spawnHybridCode().
void hybridMain(StreamChannel channel) async {
  var server = await HttpServer.bind('localhost', 9101);
  server.listen((HttpRequest req) async {
    print('receive open request');
    if (req.uri.path == '/wamp') {
      var socket = await WebSocketTransformer.upgrade(req);
      print('Received protocol ' + (req.headers.value('sec-websocket-protocol') as String));
      socket.listen((message) {
        if (message is String &&
            message.contains('[' + MessageTypes.CODE_HELLO.toString())) {
          socket.add('[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]');
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
  channel.sink.add(server.port);
}
