import 'dart:async';
@TestOn('vm')

import 'dart:io';

import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:test/test.dart';

void main() {
  group('Client Events', () {
    test("test disconnect with web socket transport", () async {
      final server = await HttpServer.bind('localhost', 9200);
      final serverListenHandler = (HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          var socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            if (message is String &&
                message.contains("[" + MessageTypes.CODE_HELLO.toString())) {
              socket.add(
                  "[" + MessageTypes.CODE_WELCOME.toString() + ",1234,{}]");
            }
            if (message is String &&
                message.contains("[" + MessageTypes.CODE_GOODBYE.toString())) {
              socket.close();
            }
          });
        }
      };
      server.listen(serverListenHandler);
      final transport = WebSocketTransport(
          "ws://localhost:9200/wamp", Serializer(), WebSocketSerialization.SERIALIZATION_JSON
      );
      final client = Client(
          realm: "biz.dls",
          transport:transport
      );
      Completer closeCompleter = Completer();
      client.connect(
          pingInterval: Duration(seconds: 1),
          reconnectTime: Duration(seconds: 1),
          reconnectCount: 100).listen((session) {
        session.onDisconnect.then((_) => closeCompleter.complete());
        session.close();
      });
      await closeCompleter.future;
      expect(client.transport.isOpen, isFalse);
    });
  });
  test("test on reconnect with web socket transport", () async {
    final server = await HttpServer.bind('localhost', 9201);
    WebSocket _socket;
    final serverListenHandler = (HttpRequest req) async {
      if (req.uri.path == '/wamp') {
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((message) {
          _socket = socket;
          if (message is String &&
              message.contains("[" + MessageTypes.CODE_HELLO.toString())) {
            socket.add(
                "[" + MessageTypes.CODE_WELCOME.toString() + ",1234,{}]");
          }
        });
      }
    };
    server.listen(serverListenHandler);
    final transport = WebSocketTransport(
        "ws://localhost:9201/wamp", Serializer(), WebSocketSerialization.SERIALIZATION_JSON
    );
    final client = Client(
        realm: "biz.dls",
        transport:transport
    );
    Completer closeCompleter = Completer();
    int reconnects = 0;
    bool hitConnectionLostEvent = false;
    Abort abort;
    client.connect(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 2)
      .listen((session) {
        session.onConnectionLost.then((_) {
          hitConnectionLostEvent = true;
        });
        server.close(force: true).then((_) => _socket.close());
      },
      onError: (_abort) {
        abort = _abort;
        closeCompleter.complete();
      });
    client.onNextTryToReconnect.listen((_) {
      reconnects++;
    });
    await closeCompleter.future;

    expect(abort, isA<Abort>());
    expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
    expect(hitConnectionLostEvent, isTrue);
    expect(reconnects, equals(3));
    expect(client.transport.isOpen, isFalse);
  });

  test("test on multiple reconnects with web socket transport", () async {
    final server = await HttpServer.bind('localhost', 9202);
    WebSocket _socket;
    final serverListenHandler = (HttpRequest req) async {
      if (req.uri.path == '/wamp') {
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((message) {
          _socket = socket;
          if (message is String &&
              message.contains("[" + MessageTypes.CODE_HELLO.toString())) {
            socket.add(
                "[" + MessageTypes.CODE_WELCOME.toString() + ",1234,{}]");
          }
        });
      }
    };
    server.listen(serverListenHandler);
    final transport = WebSocketTransport(
        "ws://localhost:9202/wamp", Serializer(), WebSocketSerialization.SERIALIZATION_JSON
    );
    final client = Client(
        realm: "biz.dls",
        transport:transport
    );
    Completer closeCompleter = Completer();
    int reconnects = 0;
    client.connect(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 2)
        .listen((session) {
          if (reconnects < 3) {
            reconnects++;
            _socket.close();
          } else {
            server.close(force: true).then((_) {
              _socket.close().then((__) => closeCompleter.complete());
            });
          }
        },
        onError: (_) {});
    await closeCompleter.future;

    expect(reconnects, equals(3));
    expect(client.transport.isOpen, isTrue);
  });
}