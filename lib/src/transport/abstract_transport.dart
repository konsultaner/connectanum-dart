import 'dart:async';

import 'package:connectanum_dart/src/message/abstract_message.dart';

abstract class AbstractTransport {
  // make it possible to have a connection state in the transport
  Completer onDisconnect = new Completer();
  Stream<AbstractMessage> receive();
  Future<void> open();
  Future<void> close();
  bool get isOpen;
  void send(AbstractMessage message);
}