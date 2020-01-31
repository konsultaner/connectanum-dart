import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/transport/abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {
  @override
  Future<void> close() {
    // TODO: implement close
    return null;
  }

  @override
  bool get isOpen {
    // TODO: implement isOpen
    return null;
  }

  @override
  Future<void> open() {
    // TODO: implement open
    return null;
  }

  @override
  void send(AbstractMessage message) {
    // TODO: implement send
  }

  @override
  Stream<AbstractMessage> receive() {
    // TODO: implement receive
    return null;
  }

}