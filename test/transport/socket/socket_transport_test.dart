@TestOn('vm')

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/socket/socket_helper.dart';
import 'package:connectanum/src/transport/socket/socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Socket open and close', () {
    test('inital close', () async {
      final server = await ServerSocket.bind('0.0.0.0', 8998);
      server.listen((socket) {
        socket.listen((message) {});
      });
      final transport = SocketTransport(
          '127.0.0.1', 8998, Serializer(), SocketHelper.serializationJson);
      await transport.open();
      transport.receive().listen((event) {});
      await transport.close();
    });
  });
  group('Socket protocol negotiation', () {
    test('Opening with max header', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = Serializer();
      final server = await ServerSocket.bind('0.0.0.0', 8999);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson));
          }
          if (message.length == 2) {
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent));
          }
        });
      });
      final transport = SocketTransport(
          '127.0.0.1', 8999, serializer, SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {
        handshakeCompleter.complete();
      }));
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 30)));
      expect(handshakes[1]![0], equals(0x3F));
    });
    test('Opening with server only allowing power of 20', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = Serializer();
      final server = await ServerSocket.bind('0.0.0.0', 9007);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                20, SocketHelper.serializationJson));
          }
        });
      });
      final transport = SocketTransport(
          '127.0.0.1', 9007, serializer, SocketHelper.serializationJson,
          messageLengthExponent:
              SocketHelper.maxMessageLengthConnectanumExponent);
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {
        handshakeCompleter.complete();
      }));
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with client max header of 20', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = Serializer();
      final server = await ServerSocket.bind('0.0.0.0', 9008);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson));
          }
          if (message.length == 2) {
            // Server could response with 30 but doesn't
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent));
          }
        });
      });
      final transport = SocketTransport(
          '127.0.0.1', 9008, serializer, SocketHelper.serializationJson,
          messageLengthExponent: 20);
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {
        handshakeCompleter.complete();
      }));
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with server error', () async {
      final server = await ServerSocket.bind('0.0.0.0', 9006);
      server.listen((socket) {
        socket.listen((message) {
          if (SocketHelper.getMaxMessageSizeExponent(message) == 9) {
            socket.add(SocketHelper.getError(
                SocketHelper.errorMaxConnectionCountExceeded));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 10) {
            socket.add(
                SocketHelper.getError(SocketHelper.errorUseOfReservedBits));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 11) {
            socket.add(SocketHelper.getError(
                SocketHelper.errorMessageLengthExceeded));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 12) {
            socket.add(SocketHelper.getError(
                SocketHelper.errorSerializerNotSupported));
          }
        });
      });

      // error 1
      var transport = SocketTransport(
          '127.0.0.1', 9006, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent: 9);
      await transport.open();
      var errorCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {},
          onError: (error) => errorCompleter.complete(error)));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect!.complete(error));
      var error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(error['errorNumber'],
          equals(SocketHelper.errorMaxConnectionCountExceeded));
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 2
      transport = SocketTransport(
          '127.0.0.1', 9006, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent: 10);
      await transport.open();
      errorCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {},
          onError: (error) => errorCompleter.complete(error)));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect!.complete(error),
          cancelOnError: true);
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(error['errorNumber'],
          equals(SocketHelper.errorUseOfReservedBits));
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 3
      transport = SocketTransport(
          '127.0.0.1', 9006, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent: 11);
      await transport.open();
      errorCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {},
          onError: (error) => errorCompleter.complete(error)));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect!.complete(error));
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(error['errorNumber'],
          equals(SocketHelper.errorMessageLengthExceeded));
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 4
      transport = SocketTransport(
          '127.0.0.1', 9006, Serializer(), SocketHelper.serializationJson,
          messageLengthExponent: 12);
      await transport.open();
      errorCompleter = Completer();
      unawaited(transport.onReady.then((aVoid) {},
          onError: (error) => errorCompleter.complete(error)));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect!.complete(error));
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(error['errorNumber'],
          equals(SocketHelper.errorSerializerNotSupported));
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);
    });
    test('Ping Pong', () async {
      var serializer = Serializer();
      var pongCompleter = Completer();
      final server = await ServerSocket.bind('0.0.0.0', 9004);
      server.listen((socket) {
        socket.listen((message) {
          if (message[0] == 0x7F) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                SocketHelper.serializationJson));
            if (message.length > 4) {
              message = message.sublist(4);
            }
          }
          if (message[0] == SocketHelper.messagePing) {
            Future.delayed(Duration(milliseconds: 1)).then((_) {
              socket.add(
                  SocketHelper.getPong(0, false) + SocketHelper.getPing(false));
            });
            if (message.length > 4) {
              message = message.sublist(4);
            }
          }
          if (message[0] == SocketHelper.messagePong) {
            pongCompleter.complete();
          }
        });
      });
      final transport = SocketTransport(
          '127.0.0.1', 9004, serializer, SocketHelper.serializationJson,
          messageLengthExponent: SocketHelper.maxMessageLengthExponent);
      await transport.open();
      transport.receive().listen((message) {});
      var pong = await transport.sendPing();
      expect(pong, isNotNull);
      await pongCompleter.future;
      expect(pongCompleter.isCompleted, isTrue);
    });
  });
}
