import 'dart:async';
import 'dart:convert';
import "dart:html";

import 'package:logging/logging.dart';

import 'websocket_transport_serialization.dart';
import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {
  static Logger _logger = Logger("WebSocketTransport");

  String _url;
  AbstractSerializer _serializer;
  String _serializerType;
  WebSocket _socket;
  Completer _onConnectionLost;
  Completer _onDisconnect;
  Completer _onReady;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType,
  ) : assert(_serializerType == WebSocketSerialization.SERIALIZATION_JSON ||
            _serializerType == WebSocketSerialization.SERIALIZATION_MSGPACK);

  @override
  Future<void> close({error}) {
    _socket.close();
    complete(_onDisconnect, error);
    return Future.value();
  }

  @override
  Completer get onConnectionLost => _onConnectionLost;

  @override
  Completer get onDisconnect => _onDisconnect;

  @override
  bool get isOpen {
    return _socket.readyState == WebSocket.OPEN;
  }

  bool get isReady => isOpen;
  Future<void> get onReady => _onReady.future;

  @override
  Future<void> open({Duration pingInterval}) async {
    _onReady = Completer();
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    Completer openCompleter = Completer();
    _socket = WebSocket(_url, _serializerType);
    if (pingInterval != null) {
      _logger.info(
          "The browsers WebSocket API does not support ping interval configuration.");
    }
    _socket.onOpen.listen((open) => openCompleter.complete(open));
    _socket.onError.listen((Event error) {
      openCompleter.completeError(error);
      _onConnectionLost.complete(error);
    });
    try {
      await openCompleter.future;
      _onReady.complete();
    } on Event {}
  }

  @override
  void send(AbstractMessage message) {
    if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
      _socket.send(utf8.decode(_serializer.serialize(message).cast()));
    } else {
      _socket.send(_serializer.serialize(message).cast());
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    _socket.onClose.listen((closeEvent) {
      if (closeEvent.code > 1000) {
        // a status code other then 1000 indicates that the server tried to quit
        _onConnectionLost.complete();
      }
    });
    return _socket.onMessage.map((messageEvent) {
      if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
        return _serializer.deserialize(utf8.encode(messageEvent.data));
      } else {
        return _serializer.deserialize(messageEvent.data);
      }
    });
  }
}
