@TestOn('browser')

import 'dart:io';

import 'package:connectanum/src/message/message_types.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// Once the hybrid isolate starts, it will call the special function
// hybridMain() with a StreamChannel that's connected to the channel
// returned spawnHybridCode().
hybridMain(StreamChannel channel) async {
  var server = await HttpServer.bind('localhost', 9101);
  server.listen((HttpRequest req) async {
    print("receive open request");
    if (req.uri.path == '/wamp') {
      var socket = await WebSocketTransformer.upgrade(req);
      print("Received protocol" + socket.protocol);
      socket.listen((message) {
        print("Received Message: " + message);
        if (message is String &&
            message.contains("[" + MessageTypes.CODE_HELLO.toString())) {
          socket.add("[" + MessageTypes.CODE_WELCOME.toString() + ",1234,{}]");
        }
      });
    }
  });
  channel.sink.add(server.port);
}
