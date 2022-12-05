import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final String _url;
  final AbstractSerializer _serializer;
  final String _serializerType;

  /// The keys of the map are the header
  /// fields and the values are either String or List<String>
  final Map<String, dynamic>? _headers;
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;
  WebSocket? _socket;
  Completer? _onConnectionLost;
  Completer? _onDisconnect;
  late Completer _onReady;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType,
    [this._headers]
  ) : assert(_serializerType == WebSocketSerialization.serializationJson ||
            _serializerType == WebSocketSerialization.serializationMsgpack ||
            _serializerType == WebSocketSerialization.serializationCbor);

  /// Calling close will close the underlying socket connection
  @override
  Future<void> close({error}) {
    _socket!.close();
    complete(_onDisconnect, error);
    return Future.value();
  }

  /// on connection lost will only complete if the other end closes unexpectedly
  @override
  Completer? get onConnectionLost => _onConnectionLost;

  /// on disconnect will complete whenever the socket connection closes down
  @override
  Completer? get onDisconnect => _onDisconnect;

  /// This method will return true if the underlying socket has a ready state of open
  @override
  bool get isOpen {
    return _socket != null && _socket!.readyState == WebSocket.open;
  }

  /// for this transport this is equal to [isOpen]
  @override
  bool get isReady => isOpen;

  /// This future completes as soon as the connection is established and fully initialized
  @override
  Future<void> get onReady => _onReady.future;

  /// This method opens the underlying socket connection and prepares all state completers.
  /// Since dart does not handle states for io WebSockets, this class contains a custom ping pong
  /// mechanism to achieve connection states. The [pingInterval] controls the ping pong mechanism.
  /// As soon as the web socket connection is established, the returning future will complete
  /// or fail respectively
  @override
  Future<void> open({Duration? pingInterval}) async {
    _onReady = Completer();
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    try {
      _socket = await WebSocket.connect(_url,
          protocols: [_serializerType], headers: _headers);
      _onReady.complete();
      if (pingInterval != null) {
        Timer.periodic(
            pingInterval,
            (timer) => _socket!.pingInterval = Duration(
                milliseconds: (pingInterval.inMilliseconds * 2 / 3).floor()));
      }
    } on SocketException catch (exception) {
      _onConnectionLost!.complete(exception);
    }
  }

  /// This method takes a [message], serializes it to a JSON and passes it to
  /// the underlying socket.
  @override
  void send(AbstractMessage message) {
    if (message is Goodbye) {
      _goodbyeSent = true;
    }
    var byteMessage = _serializer.serialize(message).cast<int>();
    if (_serializerType == WebSocketSerialization.serializationJson) {
      _socket!.addUtf8Text(byteMessage);
    } else {
      _socket!.add(byteMessage);
    }
  }

  /// This method return a [Stream] that streams all incoming messages as unserialized
  /// objects.
  @override
  Stream<AbstractMessage?> receive() {
    _socket!.done.then((done) {
      if ((_socket!.closeCode == null || _socket!.closeCode! > 1000) &&
          !_goodbyeSent &&
          !_goodbyeReceived) {
        _onConnectionLost!.complete();
      } else {
        _onDisconnect!.complete();
      }
    }, onError: (error) {
      if (!_onDisconnect!.isCompleted) {
        _onConnectionLost!.complete(error);
      }
    });
    return _socket!.map((messageEvent) {
      AbstractMessage? message;
      if (_serializerType == WebSocketSerialization.serializationJson) {
        message =
            _serializer.deserialize(utf8.encode(messageEvent) as Uint8List?);
      } else {
        message = _serializer.deserialize(messageEvent);
      }
      if (message is Goodbye) {
        _goodbyeReceived = true;
      }
      return message;
    });
  }
}
