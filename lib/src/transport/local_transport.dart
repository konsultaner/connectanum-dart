import 'dart:async';

import '../message/abstract_message.dart';
import 'abstract_transport.dart';

class LocalTransport extends AbstractTransport {
  final _receiveController = StreamController<AbstractMessage?>.broadcast();
  final _sentMessagesController = StreamController<AbstractMessage>.broadcast();

  final Completer<void> _onReady = Completer<void>();
  final Completer _onDisconnect = Completer<void>();
  final Completer _onConnectionLost = Completer<void>();

  bool _isOpen = false;

  /// Allow tests to listen to what was sent via the transport
  Stream<AbstractMessage> get sentMessages => _sentMessagesController.stream;

  /// Allow tests to inject messages into the receive stream
  void injectIncomingMessage(AbstractMessage message) {
    _receiveController.add(message);
  }

  @override
  Future<void>? close({error}) async {
    _isOpen = false;
    _receiveController.close();
    _sentMessagesController.close();
    if (!_onDisconnect.isCompleted) _onDisconnect.complete();
    if (!_onConnectionLost.isCompleted) _onConnectionLost.complete();
  }

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isReady => _isOpen;

  @override
  Completer get onConnectionLost => _onConnectionLost;

  @override
  Completer get onDisconnect => _onDisconnect;

  @override
  Future<void> get onReady => _onReady.future;

  @override
  Future<void>? open({Duration? pingInterval}) async {
    _isOpen = true;
    if (!_onReady.isCompleted) _onReady.complete();
  }

  @override
  Stream<AbstractMessage?>? receive() {
    return _receiveController.stream;
  }

  @override
  void send(AbstractMessage message) {
    _sentMessagesController.add(message);
  }
}
