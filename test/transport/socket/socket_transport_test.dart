
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_dart/src/serializer/json/serializer.dart';
import 'package:connectanum_dart/src/transport/socket/socket_helper.dart';
import 'package:connectanum_dart/src/transport/socket/socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Socket protocol negotiation', () {
    test('Opening with max header', () async {
      List<Uint8List> handshakes = [null,null];
      Serializer serializer = new Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9000);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT, SocketHelper.SERIALIZATION_JSON));
          }
          if (message.length == 2) {
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
          }
        });
      });
      final transport = SocketTransport("127.0.0.1", 9000, serializer, SocketHelper.SERIALIZATION_JSON, messageLengthExponent: SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      await transport.open();
      final handshakeCompleter = new Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2,30)));
      expect(handshakes[1][0], equals(0x3F));
    });
    test('Opening with server only allowing power of 20', () async {
      List<Uint8List> handshakes = [null,null];
      Serializer serializer = new Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9001);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(20, SocketHelper.SERIALIZATION_JSON));
          }
        });
      });
      final transport = SocketTransport("127.0.0.1", 9001, serializer, SocketHelper.SERIALIZATION_JSON, messageLengthExponent: SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);
      await transport.open();
      final handshakeCompleter = new Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2,20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with client max header of 20', () async {
      List<Uint8List> handshakes = [null,null];
      Serializer serializer = new Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9002);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(SocketHelper.getInitialHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT, SocketHelper.SERIALIZATION_JSON));
          }
          if (message.length == 2) {
            // Server could response with 30 but doesn't
            handshakes[1] = message;
            socket.add(SocketHelper.getUpgradeHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
          }
        });
      });
      final transport = SocketTransport("127.0.0.1", 9002, serializer, SocketHelper.SERIALIZATION_JSON, messageLengthExponent: 20);
      await transport.open();
      final handshakeCompleter = new Completer();
      transport.onOpen.then((aVoid) {
        handshakeCompleter.complete();
      });
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0][0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2,20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with server ERROR_MAX_CONNECTION_COUNT_EXCEEDED', () async {
      final server = await ServerSocket.bind("0.0.0.0", 9003);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            socket.add(SocketHelper.getError(SocketHelper.ERROR_MAX_CONNECTION_COUNT_EXCEEDED));
          }
        });
      });
      final transport = SocketTransport("127.0.0.1", 9003, new Serializer(), SocketHelper.SERIALIZATION_JSON, messageLengthExponent: 20);
      await transport.open();
      Completer errorCompleter = new Completer();
      transport.onOpen.then((aVoid) {}, onError: (error) => errorCompleter.complete(error));
      transport.receive().listen(
        (message) {},
        onError: (error) => transport.onDisconnect.complete(error),
        onDone: () => transport.onDisconnect.complete()
      );
      var error = await errorCompleter.future;
      expect(error["error"], isNotNull);
      expect(error["errorNumber"], equals(SocketHelper.ERROR_MAX_CONNECTION_COUNT_EXCEEDED));
      await transport.onDisconnect.future;
      expect(transport.isOpen, isFalse);
    });
  });
}