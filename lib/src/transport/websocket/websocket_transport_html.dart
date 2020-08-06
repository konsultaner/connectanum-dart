import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:logging/logging.dart';

import 'websocket_transport_serialization.dart';
import '../../message/goodbye.dart';
import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/abstract_transport.dart';

class WebSocketTransport extends AbstractTransport {
  static final Logger _logger = Logger('WebSocketTransport');

  final String _url;
  final AbstractSerializer _serializer;
  final String _serializerType;
  WebSocket _socket;
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;
  Completer _onConnectionLost;
  Completer _onDisconnect;
  Completer _onReady;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType,
  ) : assert(_serializerType == WebSocketSerialization.SERIALIZATION_JSON ||
            _serializerType == WebSocketSerialization.SERIALIZATION_MSGPACK);

  /// Calling close will close the underlying socket connection
  @override
  Future<void> close({error}) {
    _socket.close();
    complete(_onDisconnect, error);
    return Future.value();
  }

  /// on connection lost will only complete if the other end closes unexpectedly
  @override
  Completer get onConnectionLost => _onConnectionLost;

  /// on disconnect will complete whenever the socket connection closes down
  @override
  Completer get onDisconnect => _onDisconnect;

  /// This method will return true if the underlying socket has a ready state of open
  @override
  bool get isOpen {
    return _socket.readyState == WebSocket.OPEN;
  }

  /// for this transport this is equal to [isOpen]
  @override
  bool get isReady => isOpen;

  @override
  Future<void> get onReady => _onReady.future;

  /// This method opens the underlying socket connection and prepares all state completers
  /// As soon as the web socket connection is established, the returning future will complete
  /// or fail respectively
  @override
  Future<void> open({Duration pingInterval}) async {
    _onReady = Completer();
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    var openCompleter = Completer();
    _socket = WebSocket(_url, _serializerType);
    if (pingInterval != null) {
      _logger.info(
          'The browsers WebSocket API does not support ping interval configuration.');
    }
    _socket.onOpen.listen((open) => openCompleter.complete(open));
    _socket.onError.listen((Event error) {
      openCompleter.completeError(error);
      _onConnectionLost.complete(error);
    });
    try {
      await openCompleter.future;
      _onReady.complete();
    } on Event {
      _logger.info('Error while opening the channel');
    }
  }

  /// This method takes a [message], serializes it to a JSON and passes it to
  /// the underlying socket.
  @override
  void send(AbstractMessage message) {
    if (message is Goodbye) {
      _goodbyeSent = true;
    }
    if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
      _socket.send(utf8.decode(_serializer.serialize(message).cast()));
    } else {
      _socket.send(_serializer.serialize(message).cast());
    }
  }

  /// This method return a [Stream] that streams all incoming messages as unserialized
  /// objects.
  @override
  Stream<AbstractMessage> receive() {
    _socket.onClose.listen((closeEvent) {
      if ((closeEvent.code == null || closeEvent.code > 1000) &&
          !_goodbyeSent &&
          !_goodbyeReceived) {
        // a status code other then 1000 indicates that the server tried to quit
        _onConnectionLost.complete();
      } else {
        _onDisconnect.complete();
      }
    });
    return _socket.onMessage.map((messageEvent) {
      AbstractMessage message;
      if (_serializerType == WebSocketSerialization.SERIALIZATION_JSON) {
        message = _serializer.deserialize(utf8.encode(messageEvent.data));
      } else {
        message = _serializer.deserialize(messageEvent.data);
      }
      if (message is Goodbye) {
        _goodbyeReceived = true;
      }
      return message;
    });
  }
}
