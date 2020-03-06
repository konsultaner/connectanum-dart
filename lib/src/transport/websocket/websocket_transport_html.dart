import 'dart:async';
import 'dart:convert';
import "dart:html";

import 'websocket_transport_serialization.dart';
import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {
  String _url;
  AbstractSerializer _serializer;
  String _serializerType;
  WebSocket _socket;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType,
  ) : assert(_serializerType == WebSocketSerialization.SERIALIZATION_JSON ||
            _serializerType == WebSocketSerialization.SERIALIZATION_MSGPACK);

  @override
  Future<void> close() {
    _socket.close();
    return Future.value();
  }

  @override
  bool get isOpen {
    return _socket.readyState == WebSocket.OPEN;
  }

  @override
  Future<void> open() async {
    _socket = WebSocket(_url, _serializerType);
    onDisconnect = Completer();
    await _socket.onOpen.first;
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
    return _socket.onMessage.map((messageEvent) {
      if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
        return _serializer.deserialize(utf8.encode(messageEvent.data));
      } else {
        return _serializer.deserialize(messageEvent.data);
      }
    });
  }
}
