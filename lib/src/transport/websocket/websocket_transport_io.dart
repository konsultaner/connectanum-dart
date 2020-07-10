import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum/src/message/goodbye.dart';

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
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;
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
    return _socket != null && _socket.readyState == WebSocket.open;
  }

  bool get isReady => isOpen;
  Future<void> get onReady => _onReady.future;

  @override
  Future<void> open({Duration pingInterval}) async {
    _onReady = Completer();
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    try {
      _socket = await WebSocket.connect(_url, protocols: [_serializerType]);
      _onReady.complete();
      if (pingInterval != null) {
        Timer.periodic(
            pingInterval,
            (timer) => _socket.pingInterval = Duration(
                milliseconds: (pingInterval.inMilliseconds * 2 / 3).floor()));
      }
    } on SocketException catch (exception) {
      _onConnectionLost.complete(exception);
    }
  }

  @override
  void send(AbstractMessage message) {
    if (message is Goodbye) {
      this._goodbyeSent = true;
    }
    List<int> byteMessage = _serializer.serialize(message).cast();
    if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
      _socket.addUtf8Text(byteMessage);
    } else {
      _socket.add(byteMessage);
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    _socket.done.then((done) {
      if ((_socket.closeCode == null || _socket.closeCode > 1000) &&
          !_goodbyeSent &&
          !_goodbyeReceived) {
        _onConnectionLost.complete();
      } else {
        _onDisconnect.complete();
      }
    }, onError: (error) {
      if (!_onDisconnect.isCompleted) {
        _onConnectionLost.complete(error);
      }
    });
    return _socket.map((messageEvent) {
      AbstractMessage message;
      if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
        message = _serializer.deserialize(utf8.encode(messageEvent));
      } else {
        message = _serializer.deserialize(messageEvent);
      }
      if (message is Goodbye) {
        this._goodbyeReceived = true;
      }
      return message;
    });
  }
}
