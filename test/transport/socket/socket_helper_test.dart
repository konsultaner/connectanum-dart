@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum/src/transport/socket/socket_helper.dart';
import 'package:test/test.dart';

void main() {
  group('SocketHelper.isValidMessage', () {
    test('accepts valid message types', () {
      expect(
          SocketHelper.isValidMessage(
              Uint8List.fromList([SocketHelper.messageWamp])),
          isTrue);
      expect(
          SocketHelper.isValidMessage(
              Uint8List.fromList([SocketHelper.messagePing])),
          isTrue);
      expect(
          SocketHelper.isValidMessage(
              Uint8List.fromList([SocketHelper.messagePong])),
          isTrue);
    });

    test('rejects invalid message types', () {
      expect(SocketHelper.isValidMessage(Uint8List.fromList([3])), isFalse);
      expect(SocketHelper.isValidMessage(Uint8List.fromList([0x7F])), isFalse);
      expect(SocketHelper.isValidMessage(Uint8List.fromList([0x3F])), isFalse);
    });
  });
}
