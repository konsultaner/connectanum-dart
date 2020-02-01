import 'dart:async';
import 'dart:convert';
import "dart:html";

import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/serializer/abstract_serializer.dart';
import 'package:connectanum_dart/src/transport/abstract_transport.dart';

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
    return _socket.readyState == WebSocket.OPEN;
  }

  @override
  Future<void> open() {
    _socket = WebSocket(_url, _serializerType);
    onDisconnect = new Completer();
    return _socket.onOpen.first;
  }

  @override
  void send(AbstractMessage message) {
    if (_serializerType == SERIALIZATION_JSON) {
      _socket.send(utf8.decode(_serializer.serialize(message).cast()));
    } else {
      _socket.send(_serializer.serialize(message).cast());
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    return _socket.onMessage.map((messageEvent) {
      if (_serializerType == SERIALIZATION_JSON) {
        return _serializer.deserialize(utf8.encode(messageEvent.data));
      } else {
        return _serializer.deserialize(messageEvent.data);
      }
    });
  }

}