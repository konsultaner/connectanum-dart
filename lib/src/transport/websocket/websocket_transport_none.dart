import 'package:connectanum_dart/src/message/abstract_message.dart';

import '../abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {

  WebSocketTransport() {}

  @override
  Future<void> close() {
    return null;
  }

  @override
  bool get isOpen {
    return false;
  }

  @override
  Future<void> open() {}

  @override
  void send(AbstractMessage message) {}

  @override
  Stream<AbstractMessage> receive() {
    return null;
  }

}