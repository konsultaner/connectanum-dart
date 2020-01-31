
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/serializer/json/serializer.dart';
import 'package:connectanum_dart/src/transport/socket/socket_helper.dart';
import 'package:connectanum_dart/src/transport/socket/socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Socket protocol negotiation', () {
    test('Default opening', () async {
      Uint8List _openHandshake;
      Uint8List _upgradeHandshake;
      Serializer serializer = new Serializer();
      final server = await ServerSocket.bind("0.0.0.0", 9000);
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            _openHandshake = message;
            socket.add(SocketHelper.getInitialHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT, SocketHelper.SERIALIZATION_JSON));
          }
          if (message.length == 2) {
            _upgradeHandshake = message;
            socket.add(SocketHelper.getUpgradeHandshake(SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT));
            // negotiation complete send first message
            final welcome = new Uint8List.fromList("[2,12,{}]".codeUnits);
            final welcomeHeader = SocketHelper.buildMessageHeader(SocketHelper.MESSAGE_WAMP, welcome.length, true);
            socket.add(welcomeHeader);
            socket.add(welcome);
          }
        });
      });
      final transport = SocketTransport(
          "127.0.0.1",
          9000,
          serializer,
          SocketHelper.SERIALIZATION_JSON,
          ssl: false,
          messageLengthExponent: SocketHelper.MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT
      );
      await transport.open();
      final handshakeCompleter = new Completer();
      transport.receive().listen((incomingMessage) {
        if (incomingMessage.id == MessageTypes.CODE_WELCOME) {
          handshakeCompleter.complete();
        }
      });
      await handshakeCompleter.future;
      expect(_openHandshake[0], equals(0x7F));
      expect(_upgradeHandshake[0], equals(0x3F));
    });
  });
}