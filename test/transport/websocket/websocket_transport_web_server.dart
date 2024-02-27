@TestOn('browser')

import 'dart:io';

import 'package:connectanum/src/message/message_types.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// Once the hybrid isolate starts, it will call the special function
// hybridMain() with a StreamChannel that's connected to the channel
// returned spawnHybridCode().
void hybridMain(StreamChannel channel) async {
  var port = 9110;
  var server = await HttpServer.bind('localhost', port);
  server.listen((HttpRequest req) async {
    if (req.uri.path == '/wamp') {
      WebSocket socket = await WebSocketTransformer.upgrade(req, protocolSelector: (protocols) => protocols[0]);
      channel.sink.add(socket.protocol);
      await for (var message in socket) {
        if (socket.protocol == 'wamp.2.json') {
          socket.add('[${MessageTypes.codeWelcome},1,{}]');
        } else if (socket.protocol == 'wamp.2.msgpack') {
          if (message[1] == MessageTypes.codeHello) {
            socket.add([147, MessageTypes.codeWelcome, 1, 128]);
          }
        } else if (socket.protocol == 'wamp.2.cbor') {
          if (message[1] == MessageTypes.codeHello) {
            socket.add([131, MessageTypes.codeWelcome, 1, 160]);
          }
        }
      }
    }
  });
  channel.sink.add("$port");
}
