@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:connectanum/src/client.dart';
import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/abstract_message.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/socket/socket_helper.dart';
import 'package:connectanum/src/transport/socket/socket_transport.dart';
import 'package:connectanum/src/transport/websocket/websocket_transport_io.dart';
import 'package:test/test.dart';

void main() {
  group('Client Events', () {
    // WebSocket transport
    test('test disconnect with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9200);
      serverListenHandler(HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          var socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            if (message is String &&
                message.contains('[${MessageTypes.codeHello}')) {
              socket.add('[${MessageTypes.codeWelcome},1234,{}]');
            }
            if (message is String &&
                message.contains('[${MessageTypes.codeGoodbye}')) {
              socket.close();
            }
          });
        }
      }

      server.listen(serverListenHandler);
      final transport =
          WebSocketTransport.withJsonSerializer('ws://localhost:9200/wamp');
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 100))
          .listen((session) {
        session.onDisconnect.then((_) => closeCompleter.complete());
        session.close();
      });
      await closeCompleter.future;
      expect(client.transport.isOpen, isFalse);
    });

    test('test on reconnect with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9201);
      late WebSocket currentSocket;
      serverListenHandler(HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          final socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            currentSocket = socket;
            if (message is String &&
                message.contains('[${MessageTypes.codeHello}')) {
              socket.add('[${MessageTypes.codeWelcome},1234,{}]');
            }
          });
        }
      }

      server.listen(serverListenHandler);
      final transport =
          WebSocketTransport.withJsonSerializer('ws://localhost:9201/wamp');
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      var hitConnectionLostEvent = false;
      Abort? abort;
      var options = ClientConnectOptions(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 2,
      );
      client.connect(options: options).listen((session) {
        session.onConnectionLost.then((_) {
          hitConnectionLostEvent = true;
        });
        server.close(force: true).then((_) => currentSocket.close());
      }, onError: (receivedAbort) {
        abort = receivedAbort;
        closeCompleter.complete();
      });
      client.onNextTryToReconnect.listen((passedOptions) {
        passedOptions.reconnectTime = Duration(milliseconds: 800);
        reconnects++;
      });
      await closeCompleter.future;

      expect(abort, isA<Abort>());
      expect(abort!.reason, equals(Error.couldNotConnect));
      expect(hitConnectionLostEvent, isTrue);
      expect(reconnects, equals(2));
      expect(client.transport.isOpen, isFalse);
      expect(options.reconnectTime!.inMilliseconds, equals(800));
    });

    test('test on multiple reconnects with web socket transport', () async {
      final server = await HttpServer.bind('localhost', 9202);
      late WebSocket currentSocket;
      serverListenHandler(HttpRequest req) async {
        if (req.uri.path == '/wamp') {
          final socket = await WebSocketTransformer.upgrade(req);
          socket.listen((message) {
            currentSocket = socket;
            if (message is String &&
                message.contains('[${MessageTypes.codeHello}')) {
              socket.add('[${MessageTypes.codeWelcome},1234,{}]');
            }
          });
        }
      }

      server.listen(serverListenHandler);
      final transport =
          WebSocketTransport.withJsonSerializer('ws://localhost:9202/wamp');
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      client
          .connect(
              options: ClientConnectOptions(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 3,
      ))
          .listen((session) {
        if (reconnects < 3) {
          reconnects++;
          currentSocket.close();
        } else {
          server.close(force: true).then((_) {
            currentSocket.close().then((__) => closeCompleter.complete());
          });
        }
      }, onError: (_) {});
      await closeCompleter.future;

      expect(reconnects, equals(3));
      expect(client.transport.isOpen, isTrue);
    });

    test('test on connect web socket transport and no server available',
        () async {
      final transport =
          WebSocketTransport.withJsonSerializer('ws://localhost:9203/wamp');
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
      expect(abort.reason, equals(Error.couldNotConnect));
      expect(abort.message!.message, startsWith('Could not connect to server'));
      expect(client.transport.isOpen, isFalse);
    });

    // Socket transport
    test('test disconnect with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9010);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[${MessageTypes.codeHello}')) {
            var resultMessage =
                ('[${MessageTypes.codeWelcome},1234,{}]').codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.messageWamp, messageLength, true) +
                resultMessage);
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[${MessageTypes.codeGoodbye}')) {
            socket.close();
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9010, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 100))
          .listen((session) {
        session.onDisconnect.then((_) => closeCompleter.complete());
        session.close();
      });
      await closeCompleter.future;
      expect(client.transport.isOpen, isFalse);
    });

    test('test on reconnect with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9011);
      late Socket currentSocket;
      server.listen((socket) {
        currentSocket = socket;
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[${MessageTypes.codeHello}')) {
            var resultMessage =
                ('[${MessageTypes.codeWelcome},1234,{}]').codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.messageWamp, messageLength, true) +
                resultMessage);
            return;
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9011, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
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
        session.onConnectionLost.then((_) {
          hitConnectionLostEvent = true;
        });
        server.close().then((_) => currentSocket.close());
      }, onError: (receivedAbort) {
        abort = receivedAbort;
        closeCompleter.complete();
      });
      client.onNextTryToReconnect.listen((_) {
        reconnects++;
      });
      await closeCompleter.future;

      expect(abort, isA<Abort>());
      expect(abort!.reason, equals(Error.couldNotConnect));
      expect(hitConnectionLostEvent, isTrue);
      expect(reconnects, equals(2));
      expect(client.transport.isOpen, isFalse);
    });

    test('test on multiple reconnects with socket transport', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9021);
      late Socket currentSocket;
      server.listen((socket) {
        currentSocket = socket;
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson));
            return;
          }
          if (message.length == 2) {
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent));
            return;
          }
          if (message.length > 4 &&
              String.fromCharCodes(message.toList())
                  .contains('[${MessageTypes.codeHello}')) {
            var resultMessage =
                ('[${MessageTypes.codeWelcome},1234,{}]').codeUnits;
            var messageLength = resultMessage.length;
            socket.add(SocketHelper.buildMessageHeader(
                    SocketHelper.messageWamp, messageLength, true) +
                resultMessage);
            return;
          }
        });
      });
      final transport = SocketTransport(
          'localhost', 9021, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
      final client = Client(realm: 'com.connectanum', transport: transport);
      var closeCompleter = Completer();
      var reconnects = 0;
      client
          .connect(
              options: ClientConnectOptions(
                  pingInterval: Duration(seconds: 1),
                  reconnectTime: Duration(seconds: 1),
                  reconnectCount: 3))
          .listen((session) {
        if (reconnects < 3) {
          reconnects++;
          currentSocket.close();
        } else {
          server.close().then((_) {
            currentSocket.close().then((__) => closeCompleter.complete());
          });
        }
      }, onError: (_) {});
      await closeCompleter.future;

      expect(reconnects, equals(3));
      expect(client.transport.isOpen, isTrue);
    });

    test('test on connect socket transport and no server available', () async {
      final transport = SocketTransport(
          'localhost', 9019, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
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
      expect(abort.reason, equals(Error.couldNotConnect));
      expect(abort.message!.message, startsWith('Could not connect to server'));
      expect(client.transport.isOpen, isFalse);
    });
  });

  group('Reconnection testing', () {
    test('WebSocket - stop on authorization error', () async {
      final suite = WebSocketTestSuite((msgType) {
        if (msgType == MessageTypes.codeHello) {
          return Abort(
            Error.notAuthorized,
            message: 'The given realm is not valid',
          );
        }

        return null;
      });
      await suite.open();

      final options = ClientConnectOptions(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 2,
      );

      var closeCompleter = Completer();
      var errors = 0;
      suite.client.connect(options: options).listen(
            (_) {},
            onError: (_) => errors++,
            onDone: () => closeCompleter.complete(),
          );
      await closeCompleter.future;

      expect(errors, equals(1));
      expect(suite.client.transport.isOpen, isTrue);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('WebSocket - retry on invalid argument error', () async {
      final suite = WebSocketTestSuite((msgType) {
        if (msgType == MessageTypes.codeHello) {
          return Abort(
            Error.invalidArgument,
            message: 'Invalid argument',
          );
        }

        return null;
      });
      await suite.open();

      final options = ClientConnectOptions(
        pingInterval: Duration(seconds: 1),
        reconnectTime: Duration(seconds: 1),
        reconnectCount: 2,
      );

      var closeCompleter = Completer();
      var errors = 0;
      suite.client.connect(options: options).listen(
            (_) {},
            onError: (_) => errors++,
            onDone: () => closeCompleter.complete(),
          );
      await closeCompleter.future;

      expect(errors, equals(3));
      expect(suite.client.transport.isOpen, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}

int webSocketTestSuitePort = 9300;

class WebSocketTestSuite {
  late WebSocket socket;
  late HttpServer server;
  late Client client;
  final port = webSocketTestSuitePort++;

  final AbstractMessage? Function(int msgType) onServerMessage;

  WebSocketTestSuite(this.onServerMessage);

  Future<void> open() async {
    await openServer();
    openTransport();
  }

  Future<void> openServer() async {
    server = await HttpServer.bind('localhost', port);

    serverListenHandler(HttpRequest req) async {
      if (req.uri.path == '/wamp') {
        socket = await WebSocketTransformer.upgrade(req);
        socket.listen((message) {
          final msg = jsonDecode(message);
          final msgType = msg[0];

          final response = onServerMessage(msgType);
          if (response != null) {
            socket.add(Serializer().serializeToString(response));
          }
        });
      }
    }

    server.listen(serverListenHandler);
  }

  Future<void> openTransport() async {
    final transport =
        WebSocketTransport.withJsonSerializer('ws://localhost:$port/wamp');
    client = Client(realm: 'com.connectanum', transport: transport);
  }
}
