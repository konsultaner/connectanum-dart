@TestOn('browser')
library;

import 'dart:async';

import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/hello.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket protocol with html communication', () {
    test(
      'Opening a server connection and simple send receive scenario using a serializer',
      () async {
        final channel = spawnHybridCode(r'''
          import 'dart:io';

          import 'package:connectanum_core/src/message/message_types.dart';
          import 'package:stream_channel/stream_channel.dart';

          Future<void> hybridMain(StreamChannel<Object?> channel) async {
            final server = await HttpServer.bind('localhost', 0);
            server.listen((HttpRequest req) async {
              if (req.uri.path != '/wamp') {
                req.response.statusCode = HttpStatus.notFound;
                await req.response.close();
                return;
              }

              final socket = await WebSocketTransformer.upgrade(
                req,
                protocolSelector: (protocols) => protocols[0],
              );
              channel.sink.add(socket.protocol);
              await for (final message in socket) {
                if (socket.protocol == 'wamp.2.json') {
                  socket.add('[${MessageTypes.codeWelcome},1,{}]');
                } else if (socket.protocol == 'wamp.2.msgpack') {
                  if ((message as List)[1] == MessageTypes.codeHello) {
                    socket.add([147, MessageTypes.codeWelcome, 1, 128]);
                  }
                } else if (socket.protocol == 'wamp.2.cbor') {
                  if ((message as List)[1] == MessageTypes.codeHello) {
                    socket.add([131, MessageTypes.codeWelcome, 1, 160]);
                  }
                }
              }
            });
            channel.sink.add(server.port);

            await channel.stream.firstWhere((event) => event == 'shutdown');
            await server.close(force: true);
            await channel.sink.close();
          }
        ''');
        late final StreamSubscription<dynamic> channelSubscription;
        late int port;
        WebSocketTransport? transportJSON;
        WebSocketTransport? transportMsgpack;
        WebSocketTransport? transportCbor;
        final jsonCompleter = Completer<void>();
        final msgpackCompleter = Completer<void>();
        final cborCompleter = Completer<void>();
        var channelValues = <dynamic>[];
        addTearDown(() async {
          if (transportJSON != null) {
            await transportJSON!.close();
          }
          if (transportMsgpack != null) {
            await transportMsgpack!.close();
          }
          if (transportCbor != null) {
            await transportCbor!.close();
          }
          channel.sink.add('shutdown');
          await channel.sink.close();
          await channelSubscription.cancel();
        });
        channelSubscription = channel.stream.listen((event) async {
          channelValues.add(event);
          if (channelValues.length == 1) {
            port = (event as num).toInt();
            transportJSON = WebSocketTransport.withJsonSerializer(
              'ws://localhost:$port/wamp',
            );
            transportMsgpack = WebSocketTransport.withMsgpackSerializer(
              'ws://localhost:$port/wamp',
            );
            transportCbor = WebSocketTransport.withCborSerializer(
              'ws://localhost:$port/wamp',
            );
          }
          if (channelValues.length == 1) {
            print('Connect to ws://localhost:$port/wamp via json');
            await transportJSON!.open();
          }
          if (channelValues.length == 2) {
            jsonCompleter.complete();
            print('Connect to ws://localhost:$port/wamp via msgpack');
            await transportMsgpack!.open();
          }
          if (channelValues.length == 3) {
            msgpackCompleter.complete();
            print('Connect to ws://localhost:$port/wamp via cbor');
            await transportCbor!.open();
          }
          if (channelValues.length == 4) {
            cborCompleter.complete();
          }
        });

        print('#### JSON transport');
        await jsonCompleter.future;
        transportJSON!.send(Hello('my.realm', Details.forHello()));
        var welcome = await transportJSON!.receive().first;
        expect(welcome, isA<Welcome>());

        print('#### MSGPACK transport');
        await msgpackCompleter.future;
        transportMsgpack!.send(Hello('my.realm', Details.forHello()));
        welcome = await transportMsgpack!.receive().first;
        expect(welcome, isA<Welcome>());

        print('#### CBOR transport');
        await cborCompleter.future;
        transportCbor!.send(Hello('my.realm', Details.forHello()));
        welcome = await transportCbor!.receive().first;
        expect(welcome, isA<Welcome>());
      },
    );
  });
}
