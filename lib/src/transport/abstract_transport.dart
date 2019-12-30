import 'dart:async';

import 'package:connectanum_dart/src/message/abstract_message.dart';

abstract class AbstractTransport {
  Stream<AbstractMessage> receive();
  Future<void> open();
  Future<void> close();
  bool isOpen();
  void send(AbstractMessage message);
}