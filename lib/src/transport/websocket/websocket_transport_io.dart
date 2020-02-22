import 'dart:async';
import 'dart:convert';
import "dart:io";

import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {

  static const String SERIALIZATION_JSON = "wamp.2.json";
  static const String SERIALIZATION_MSGPACK = "wamp.2.msgpack";

  String _url;
  AbstractSerializer _serializer;
  String _serializerType;
  WebSocket _socket;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType,
  ) {}

  @override
  Future<void> close() {
    _socket.close();
    return Future.value();
  }

  @override
  bool get isOpen {
    return _socket.readyState == WebSocket.open;
  }

  @override
  Future<void> open() async {
    _socket = await WebSocket.connect(_url,protocols:[_serializerType]);
    onDisconnect = new Completer();
  }

  @override
  void send(AbstractMessage message) {
    if (_serializerType == SERIALIZATION_JSON) {
      _socket.addUtf8Text(_serializer.serialize(message).cast());
    } else {
      _socket.add(_serializer.serialize(message).cast());
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    return _socket.map((messageEvent) {
      if (_serializerType == SERIALIZATION_JSON) {
        return _serializer.deserialize(utf8.encode(messageEvent.data));
      } else {
        return _serializer.deserialize(messageEvent.data);
      }
    });
  }

}