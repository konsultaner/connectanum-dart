import 'dart:async';
@TestOn('vm')
import 'dart:io';

import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/socket/socket_helper.dart';
import 'package:connectanum/src/transport/socket/socket_transport.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_serialization.dart';
import 'package:test/test.dart';

void main() {
  group('Client Events', () {
    // WebSocket transport
    test('test disconnect with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9200);
      final serverListenHandler = (HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          var socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            if (message is String &&
                message.contains('[' + MessageTypes.CODE_HELLO.toString())) {
              socket.add(
                  '[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]');
            }
            if (message is String &&
                message.contains('[' + MessageTypes.CODE_GOODBYE.toString())) {
              socket.close();
            }
          });
        }
      };
      server.listen(serverListenHandler);
      final transport = WebSocketTransport('ws://localhost:9200/wamp',
          Serializer(), WebSocketSerialization.SERIALIZATION_JSON);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 100))
          .listen((session) {
        session.onDisconnect!.then((_) => closeCompleter.complete());
        session.close();
      });
      await closeCompleter.future;
      expect(client.transport!.isOpen, isFalse);
    });

    test('test on reconnect with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9201);
      WebSocket? _socket;
      final serverListenHandler = (HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          final socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            _socket = socket;
            if (message is String &&
                message.contains('[' + MessageTypes.CODE_HELLO.toString())) {
              socket.add(
                  '[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]');
            }
          });
        }
      };
      server.listen(serverListenHandler);
      final transport = WebSocketTransport('ws://localhost:9201/wamp',
          Serializer(), WebSocketSerialization.SERIALIZATION_JSON);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      var hitConnectionLostEvent = false;
      Abort? abort;
      var options = ClientConnectOptions(
          pingInterval: Duration(seconds: 1),
          reconnectTime: Duration(seconds: 1),
          reconnectCount: 2);
      client.connect(options: options).listen((session) {
        session.onConnectionLost!.then((_) {
          hitConnectionLostEvent = true;
        });
        server.close(force: true).then((_) => _socket!.close());
      }, onError: (_abort) {
        abort = _abort;
        closeCompleter.complete();
      });
      client.onNextTryToReconnect.listen((passedOptions) {
        passedOptions.reconnectTime = Duration(milliseconds: 800);
        reconnects++;
      });
      await closeCompleter.future;

      expect(abort, isA<Abort>());
      expect(abort!.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(hitConnectionLostEvent, isTrue);
      expect(reconnects, equals(4));
      expect(client.transport!.isOpen, isFalse);
      expect(options.reconnectTime!.inMilliseconds, equals(800));
    });

    test('test on multiple reconnects with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9202);
      WebSocket? _socket;
      final serverListenHandler = (HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          final socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            _socket = socket;
            if (message is String &&
                message.contains('[' + MessageTypes.CODE_HELLO.toString())) {
              socket.add(
                  '[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]');
            }
          });
        }
      };
      server.listen(serverListenHandler);
      final transport = WebSocketTransport('ws://localhost:9202/wamp',
          Serializer(), WebSocketSerialization.SERIALIZATION_JSON);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 2))
          .listen((session) {
        if (reconnects < 3) {
          reconnects++;
          _socket!.close();
        } else {
          server.close(force: true).then((_) {
            _socket!.close().then((__) => closeCompleter.complete());
          });
        }
      }, onError: (_) {});
      await closeCompleter.future;

      expect(reconnects, equals(3));
      expect(client.transport!.isOpen, isTrue);
    });

    test('test on connect web socket transport and no server available',
        () async {
      final transport = WebSocketTransport('ws://localhost:9203/wamp',
          Serializer(), WebSocketSerialization.SERIALIZATION_JSON);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(milliseconds: 20),
                  reconnectCount: 2))
          .listen((_) {}, onError: (abort) {
        closeCompleter.complete(abort);
      });
      Abort abort = await closeCompleter.future;
      expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(abort.message!.message, startsWith('Could not connect to server'));
      expect(client.transport!.isOpen, isFalse);
    });

    // Socket transport
    test('test disconnect with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9010);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[' + MessageTypes.CODE_HELLO.toString())) {
            var resultMessage =
                ('[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]')
                    .codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.MESSAGE_WAMP, messageLength, true) +
                resultMessage);
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[' + MessageTypes.CODE_GOODBYE.toString())) {
            socket.close();
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9010, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 100))
          .listen((session) {
        session.onDisconnect!.then((_) => closeCompleter.complete());
        session.close();
      });
      await closeCompleter.future;
      expect(client.transport!.isOpen, isFalse);
    });

    test('test on reconnect with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9011);
      Socket? _socket;
      server.listen((socket) {
        _socket = socket;
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[' + MessageTypes.CODE_HELLO.toString())) {
            var resultMessage =
                ('[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]')
                    .codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.MESSAGE_WAMP, messageLength, true) +
                resultMessage);
            return;
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9011, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      var hitConnectionLostEvent = false;
      Abort? abort;
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 2))
          .listen((session) {
        session.onConnectionLost!.then((_) {
          hitConnectionLostEvent = true;
        });
        server.close().then((_) => _socket!.close());
      }, onError: (_abort) {
        abort = _abort;
        closeCompleter.complete();
      });
      client.onNextTryToReconnect.listen((_) {
        reconnects++;
      });
      await closeCompleter.future;

      expect(abort, isA<Abort>());
      expect(abort!.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(hitConnectionLostEvent, isTrue);
      expect(reconnects, equals(4));
      expect(client.transport!.isOpen, isFalse);
    });

    test('test on multiple reconnects with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9021);
      Socket? _socket;
      server.listen((socket) {
        _socket = socket;
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[' + MessageTypes.CODE_HELLO.toString())) {
            var resultMessage =
                ('[' + MessageTypes.CODE_WELCOME.toString() + ',1234,{}]')
                    .codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.MESSAGE_WAMP, messageLength, true) +
                resultMessage);
            return;
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9021, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 2))
          .listen((session) {
        if (reconnects < 3) {
          reconnects++;
          _socket!.close();
        } else {
          server.close().then((_) {
            _socket!.close().then((__) => closeCompleter.complete());
          });
        }
      }, onError: (_) {});
      await closeCompleter.future;

      expect(reconnects, equals(3));
      expect(client.transport!.isOpen, isTrue);
    });

    test('test on connect socket transport and no server available', () async {
      final transport = SocketTransport(
          'localhost', 9019, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(milliseconds: 20),
                  reconnectCount: 2))
          .listen((_) {}, onError: (abort) {
        closeCompleter.complete(abort);
      });
      Abort abort = await closeCompleter.future;
      expect(abort.reason, equals(Error.AUTHORIZATION_FAILED));
      expect(abort.message!.message, startsWith('Could not connect to server'));
      expect(client.transport!.isOpen, isFalse);
    });
  });
}
