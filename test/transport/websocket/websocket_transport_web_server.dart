@TestOn('browser')

import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'package:connectanum/src/message/message_types.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// Once the hybrid isolate starts, it will call the special function
// hybridMain() with a StreamChannel that's connected to the channel
// returned spawnHybridCode().
void hybridMain(StreamChannel channel) async {
  var server = await HttpServer.bind('localhost', 9110);
  server.listen((HttpRequest req) async {
    print('receive open request');
    if (req.uri.path == '/wamp') {
      WebSocket socket = await WebSocketTransformer.upgrade(req, protocolSelector: (protocols) => protocols[0]);
      print('Received protocol ${socket.protocol}');
      channel.sink.add(socket.protocol);
      await for (var message in socket) {
        if (socket.protocol == 'wamp.2.json') {
          print('received json message: $message');
          socket.add('[${MessageTypes.codeWelcome},1,{}]');
        } else if (socket.protocol == 'wamp.2.msgpack') {
          print('received msgpack message: $message');
          if (message[1] == MessageTypes.codeHello) {
            socket.add([147, MessageTypes.codeWelcome, 1, 128]);
          }
        } else if (socket.protocol == 'wamp.2.cbor') {
          print('received cbor message: $message');
          if (message[1] == MessageTypes.codeHello) {
            socket.add([131, MessageTypes.codeWelcome, 1, 160]);
          }
        }
      }
    }
  }, onError: (error) {
    print(error);
  }, onDone: () {
    print('Closed Test Server');
  });
  channel.sink.add(server.port);
}
