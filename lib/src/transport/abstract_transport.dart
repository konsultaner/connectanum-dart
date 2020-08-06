import 'dart:async';

import '../message/abstract_message.dart';

abstract class AbstractTransport {
  // make it possible to have a connection state in the transport
  Completer get onDisconnect;
  Completer get onConnectionLost;
  Stream<AbstractMessage> receive();
  Future<void> open({Duration pingInterval});
  Future<void> close({error});
  Future<void> get onReady;
  bool get isOpen;
  bool get isReady;
  void send(AbstractMessage message);

  /// for internal use only
  /// is called to complete the private underlying [onDisconnect] with a void or an error
  void complete(Completer _onDisconnect, error) {
    if (_onDisconnect != null && !_onDisconnect.isCompleted) {
      if (error != null) {
        _onDisconnect.complete();
      } else {
        _onDisconnect.complete(error);
      }
    }
  }
}
