import '../abstract_transport.dart';
import '../../message/abstract_message.dart';

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
  Future<void> open() {
    return null;
  }

  @override
  void send(AbstractMessage message) {}

  @override
  Stream<AbstractMessage> receive() {
    return null;
  }
}
