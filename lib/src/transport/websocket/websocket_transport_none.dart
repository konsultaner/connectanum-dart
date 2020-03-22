import 'dart:async';

import '../abstract_transport.dart';
import '../../message/abstract_message.dart';

class WebSocketTransport extends AbstractTransport {
  WebSocketTransport(url, serializer, serializerType);

  @override
  Completer get onConnectionLost => null;

  @override
  Completer get onDisconnect => null;

  @override
  Future<void> close({error}) {
    return null;
  }

  @override
  bool get isOpen {
    return false;
  }

  bool get isReady => isOpen;
  Future<void> get onReady => Future.error(null);

  @override
  Future<void> open({Duration pingInterval}) {
    return null;
  }

  @override
  void send(AbstractMessage message) {}

  @override
  Stream<AbstractMessage> receive() {
    return null;
  }
}
