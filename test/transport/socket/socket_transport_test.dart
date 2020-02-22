import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum/src/serializer/json/serializer.dart';
import 'package:connectanum/src/transport/socket/socket_helper.dart';
import 'package:connectanum/src/transport/socket/socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Socket protocol negotiation', () {
    test('Opening with max header', () async {
      List<Uint8List> handshakes = [null, null];
      Serializer serializer = Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9000);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
          }
          if (message.length == 2) {
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
          }
        });
      });
      final transport = SocketTransport(
          "127.0.0.1", 9000, serializer, SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      await transport.open();
      final handshakeCompleter = Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 30)));
      expect(handshakes[1][0], equals(0x3F));
    });
    test('Opening with server only allowing power of 20', () async {
      List<Uint8List> handshakes = [null, null];
      Serializer serializer = Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9001);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                20, SocketHelper.SERIALIZATION_JSON));
          }
        });
      });
      final transport = SocketTransport(
          "127.0.0.1", 9001, serializer, SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent:
              SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      await transport.open();
      final handshakeCompleter = Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with client max header of 20', () async {
      List<Uint8List> handshakes = [null, null];
      Serializer serializer = Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9002);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
          }
          if (message.length == 2) {
            // Server could response with 30 but doesn't
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
          }
        });
      });
      final transport = SocketTransport(
          "127.0.0.1", 9002, serializer, SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: 20);
      await transport.open();
      final handshakeCompleter = Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with server error', () async {
      final server = await ServerSocket.bind("0.0.0.0", 9003);
      server.listen((socket) {
        socket.listen((message) {
          if (SocketHelper.getMaxMessageSizeExponent(message) == 9) {
            socket.add(SocketHelper.getError(
                SocketHelper.ERROR_MAX_CONNECTION_COUNT_EXCEEDED));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 10) {
            socket.add(
                SocketHelper.getError(SocketHelper.ERROR_USE_OF_RESERVED_BITS));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 11) {
            socket.add(SocketHelper.getError(
                SocketHelper.ERROR_MESSAGE_LENGTH_EXCEEDED));
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 12) {
            socket.add(SocketHelper.getError(
                SocketHelper.ERROR_SERIALIZER_NOT_SUPPORTED));
          }
        });
      });

      // error 1
      SocketTransport transport = SocketTransport(
          "127.0.0.1", 9003, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: 9);
      await transport.open();
      Completer errorCompleter = Completer();
      transport.onOpen
          .then((aVoid) {}, onError: (error) => errorCompleter.complete(error));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect.complete(error),
          onDone: () => transport.onDisconnect.complete());
      var error = await errorCompleter.future;
      expect(error["error"], isNotNull);
      expect(error["errorNumber"],
          equals(SocketHelper.ERROR_MAX_CONNECTION_COUNT_EXCEEDED));
      await transport.onDisconnect.future;
      expect(transport.isOpen, isFalse);

      // error 2
      transport = SocketTransport(
          "127.0.0.1", 9003, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: 10);
      await transport.open();
      errorCompleter = Completer();
      transport.onOpen
          .then((aVoid) {}, onError: (error) => errorCompleter.complete(error));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect.complete(error),
          onDone: () => transport.onDisconnect.complete(),
          cancelOnError: true);
      error = await errorCompleter.future;
      expect(error["error"], isNotNull);
      expect(error["errorNumber"],
          equals(SocketHelper.ERROR_USE_OF_RESERVED_BITS));
      await transport.onDisconnect.future;
      expect(transport.isOpen, isFalse);

      // error 3
      transport = SocketTransport(
          "127.0.0.1", 9003, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: 11);
      await transport.open();
      errorCompleter = Completer();
      transport.onOpen
          .then((aVoid) {}, onError: (error) => errorCompleter.complete(error));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect.complete(error),
          onDone: () => transport.onDisconnect.complete());
      error = await errorCompleter.future;
      expect(error["error"], isNotNull);
      expect(error["errorNumber"],
          equals(SocketHelper.ERROR_MESSAGE_LENGTH_EXCEEDED));
      await transport.onDisconnect.future;
      expect(transport.isOpen, isFalse);

      // error 4
      transport = SocketTransport(
          "127.0.0.1", 9003, Serializer(), SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: 12);
      await transport.open();
      errorCompleter = Completer();
      transport.onOpen
          .then((aVoid) {}, onError: (error) => errorCompleter.complete(error));
      transport.receive().listen((message) {},
          onError: (error) => transport.onDisconnect.complete(error),
          onDone: () => transport.onDisconnect.complete());
      error = await errorCompleter.future;
      expect(error["error"], isNotNull);
      expect(error["errorNumber"],
          equals(SocketHelper.ERROR_SERIALIZER_NOT_SUPPORTED));
      await transport.onDisconnect.future;
      expect(transport.isOpen, isFalse);
    });
    test('Ping Pong', () async {
      Serializer serializer = Serializer();
      Completer pongCompleter = Completer();
      final server = await ServerSocket.bind("0.0.0.0", 9004);
      server.listen((socket) {
        socket.listen((message) {
          if (message[0] == 0x7F) {
            socket.add(SocketHelper.getInitialHandshake(
                SocketHelper.MAX_MESSAGE_LENGTH_EXPONENT,
                SocketHelper.SERIALIZATION_JSON));
          }
          if (message[0] == SocketHelper.MESSAGE_PING) {
            socket.add(
                SocketHelper.getPong(0, false) + SocketHelper.getPing(false));
          }
          if (message[0] == SocketHelper.MESSAGE_PONG) {
            pongCompleter.complete();
          }
        });
      });
      final transport = SocketTransport(
          "127.0.0.1", 9004, serializer, SocketHelper.SERIALIZATION_JSON,
          messageLengthExponent: SocketHelper.MAX_MESSAGE_LENGTH_EXPONENT);
      await transport.open();
      transport.receive().listen((message) {});
      await transport.isOpen;
      Uint8List pong = await transport.sendPing();
      expect(pong, isNotNull);
      await pongCompleter.future;
      expect(pongCompleter.isCompleted, isTrue);
    });
  });
}
