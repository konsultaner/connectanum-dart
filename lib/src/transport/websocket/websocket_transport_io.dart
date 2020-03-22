import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'websocket_transport_serialization.dart';
import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/abstract_transport.dart';

/// This transport type is used to connect via web sockets
/// in a dart vm environment. A known issue is that this
/// transport does not support auto reconnnect in the dart vm
/// use [SocketTransport] instead! This may not work if your
/// router does not raw socket transport
class WebSocketTransport extends AbstractTransport {
  String _url;
  AbstractSerializer _serializer;
  String _serializerType;
  WebSocket _socket;
  Completer _onConnectionLost;
  Completer _onDisconnect;
  Completer _onReady = new Completer();

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
    return _socket != null && _socket.readyState == WebSocket.open;
  }

  bool get isReady => isOpen;
  Future<void> get onReady => _onReady.future;

  @override
  Future<void> open({Duration pingInterval}) async {
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    try {
      _socket = await WebSocket.connect(_url, protocols: [_serializerType]);
      _onReady.complete();
      if (pingInterval != null) {
        _socket.pingInterval = pingInterval;
      }
    } on SocketException catch (exception) {
      _onConnectionLost.complete(exception);
    }
  }

  @override
  void send(AbstractMessage message) {
    List<int> byteMessage = _serializer.serialize(message).cast();
    if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
      _socket.addUtf8Text(byteMessage);
    } else {
      _socket.add(byteMessage);
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    _socket.done.then((done) => null, onError: (error) {
      if (!_onDisconnect.isCompleted) {
        _onConnectionLost.complete(error);
      }
    });
    return _socket.map((messageEvent) {
      if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
        return _serializer.deserialize(utf8.encode(messageEvent));
      } else {
        return _serializer.deserialize(messageEvent);
      }
    });
  }
}
