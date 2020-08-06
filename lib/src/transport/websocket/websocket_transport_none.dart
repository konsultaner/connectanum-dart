import 'dart:async';

import '../abstract_transport.dart';
import '../../message/abstract_message.dart';

/// This is a mock class to provide a unified interface for js and native usage of this package
class WebSocketTransport extends AbstractTransport {
  WebSocketTransport(url, serializer, serializerType);

  /// on connection lost will only complete if the other end closes unexpectedly
  @override
  Completer get onConnectionLost => null;

  /// on disconnect will complete whenever the socket connection closes down
  @override
  Completer get onDisconnect => null;

  /// Calling close will close the underlying socket connection
  @override
  Future<void> close({error}) {
    return null;
  }

  /// This method will return true if the underlying socket has a ready state of open
  @override
  bool get isOpen {
    return false;
  }

  /// for this transport this is equal to [isOpen]
  @override
  bool get isReady => isOpen;

  /// This future completes as soon as the connection is established and fully initialized
  @override
  Future<void> get onReady => Future.error(null);

  /// This method opens the underlying socket connection and prepares all state completers.
  @override
  Future<void> open({Duration pingInterval}) {
    return null;
  }

  /// This method takes a [message], serializes it to a JSON and passes it to
  /// the underlying socket.
  @override
  void send(AbstractMessage message) {}

  /// This method return a [Stream] that streams all incoming messages as unserialized
  /// objects.
  @override
  Stream<AbstractMessage> receive() {
    return null;
  }
}
