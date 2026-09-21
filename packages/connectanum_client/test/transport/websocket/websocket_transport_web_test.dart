@TestOn('browser')
library;

import 'dart:async';

import 'websocket_test_observer.dart';

import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/hello.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:test/test.dart';

void main() {
  late WebSocketTestObserver observer;
  setUp(() {
    observer = WebSocketTestObserver();
    addTearDown(observer.restore);
  });
  group('WebSocket protocol with html communication', () {
    test('closing before opening is safe', () async {
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://localhost:1/wamp',
      );

      await expectLater(transport.close(), completes);
      expect(transport.isOpen, isFalse);
    });

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
        final startupFailure = Completer<Object>();
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
        Future<void> initialize(dynamic event) async {
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
            await observer.open(transportJSON!);
            expect(transportJSON!.isReady, isTrue);
          }
          if (channelValues.length == 2) {
            jsonCompleter.complete();
            await observer.open(transportMsgpack!);
            expect(transportMsgpack!.isReady, isTrue);
          }
          if (channelValues.length == 3) {
            msgpackCompleter.complete();
            await observer.open(transportCbor!);
            expect(transportCbor!.isReady, isTrue);
          }
          if (channelValues.length == 4) {
            cborCompleter.complete();
          }
        }

        var startup = Future<void>.value();
        channelSubscription = channel.stream.listen((event) {
          startup = startup.then((_) => initialize(event)).catchError((
            Object error,
            StackTrace stack,
          ) {
            if (!startupFailure.isCompleted) startupFailure.complete(error);
          });
        });

        await _expectStartup(jsonCompleter.future, startupFailure.future);
        transportJSON!.send(Hello('my.realm', Details.forHello()));
        var welcome = await transportJSON!.receive().first;
        expect(welcome, isA<Welcome>());

        await _expectStartup(msgpackCompleter.future, startupFailure.future);
        transportMsgpack!.send(Hello('my.realm', Details.forHello()));
        welcome = await transportMsgpack!.receive().first;
        expect(welcome, isA<Welcome>());

        await _expectStartup(cborCompleter.future, startupFailure.future);
        transportCbor!.send(Hello('my.realm', Details.forHello()));
        welcome = await transportCbor!.receive().first;
        expect(welcome, isA<Welcome>());
      },
    );
  });
}

Future<void> _expectStartup(Future<void> ready, Future<Object> failure) async {
  final earlyFailure = await Future.any<Object?>([
    ready.then((_) => null),
    failure,
  ]);
  expect(
    earlyFailure,
    isNull,
    reason: 'WebSocket startup failed before the protocol handshake.',
  );
}
