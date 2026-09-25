import 'dart:async';
import 'package:web/web.dart';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:logging/logging.dart';

import 'websocket_transport_serialization.dart';
import 'package:connectanum_core/connectanum_core.dart' hide Event;
import '../../transport/abstract_transport.dart';
import 'package:connectanum_core/json_serializer.dart' as serializer_json;
import 'package:connectanum_core/msgpack_serializer.dart' as serializer_msgpack;
import 'package:connectanum_core/cbor_serializer.dart' as serializer_cbor;

class WebSocketTransport extends AbstractTransport {
  static final Logger _logger = Logger('Connectanum.WebSocketTransport');

  final String _url;
  final AbstractSerializer _serializer;
  final String _serializerType;
  WebSocket? _socket;
  int _openAttempt = 0;
  _WebSocketCloseState _closeState = _WebSocketCloseState();
  Completer? _onConnectionLost;
  Completer? _onDisconnect;
  late Completer _onReady;

  WebSocketTransport(
    this._url,
    this._serializer,
    this._serializerType, [
    Map<String, dynamic>? additionalHeaders,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) : assert(
         _serializerType == WebSocketSerialization.serializationJson ||
             _serializerType == WebSocketSerialization.serializationMsgpack ||
             _serializerType == WebSocketSerialization.serializationCbor,
       );

  factory WebSocketTransport.withJsonSerializer(
    String url, [
    Map<String, dynamic>? additionalHeaders,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_json.Serializer(),
    WebSocketSerialization.serializationJson,
    additionalHeaders,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  factory WebSocketTransport.withMsgpackSerializer(
    String url, [
    Map<String, dynamic>? additionalHeaders,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_msgpack.Serializer(),
    WebSocketSerialization.serializationMsgpack,
    additionalHeaders,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  factory WebSocketTransport.withCborSerializer(
    String url, [
    Map<String, dynamic>? additionalHeaders,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_cbor.Serializer(),
    WebSocketSerialization.serializationCbor,
    additionalHeaders,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  /// Calling close will close the underlying socket connection
  @override
  Future<void> close({error}) {
    _openAttempt++;
    _socket?.close();
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
    return _socket?.readyState == WebSocket.OPEN;
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
  Future<void> open({Duration? pingInterval}) async {
    final openAttempt = ++_openAttempt;
    _onReady = Completer();
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    _closeState = _WebSocketCloseState();
    final onReady = _onReady;
    final onConnectionLost = _onConnectionLost;
    var openCompleter = Completer();
    final previousSocket = _socket;
    final socket = WebSocket(_url, [_serializerType.toJS].toJS);
    _socket = socket;
    previousSocket?.close();
    if (pingInterval != null) {
      _logger.info(
        'The browsers WebSocket API does not support ping interval configuration.',
      );
    }
    socket.onOpen.listen((open) {
      if (!openCompleter.isCompleted) openCompleter.complete(open);
    });
    socket.onError.listen((Event error) {
      if (!openCompleter.isCompleted) openCompleter.completeError(error);
      if (openAttempt == _openAttempt) complete(onConnectionLost, error);
    });
    try {
      await openCompleter.future;
      if (openAttempt == _openAttempt && !onReady.isCompleted) {
        onReady.complete();
      }
    } catch (_) {
      _logger.info('Error while opening the channel');
    }
  }

  /// This method takes a [message], serializes it to a JSON and passes it to
  /// the underlying socket.
  @override
  void send(AbstractMessage message) {
    if (message is Goodbye) {
      _closeState.goodbyeSent = true;
    }
    var serializedMessage = _serializer.serialize(message);
    // toJS only works on casted objects
    _socket!.send(
      serializedMessage is String
          ? serializedMessage.toJS
          : (serializedMessage as Uint8List).toJS,
    );
  }

  /// This method return a [Stream] that streams all incoming messages as unserialized
  /// objects.
  @override
  Stream<AbstractMessage?> receive() {
    final socket = _socket;
    if (socket == null) {
      throw StateError('WebSocket transport is not open.');
    }
    final onDisconnect = _onDisconnect!;
    final closeState = _closeState;
    final onConnectionLost = _onConnectionLost!;
    socket.onClose.listen((closeEvent) {
      if (closeEvent.code > 1000 &&
          !closeState.goodbyeSent &&
          !closeState.goodbyeReceived) {
        // A status code other than 1000 indicates that the server tried to quit.
        complete(onConnectionLost, null);
      } else {
        complete(onDisconnect, null);
      }
      _logger.info('The connection has been closed with ${closeEvent.code}');
    });
    // Pausing a DOM event stream removes its listener. Buffer in Dart instead
    // so frames received while Blob decoding is pending cannot be dropped.
    final messages = Stream<MessageEvent>.multi((controller) {
      final subscription = socket.onMessage.listen(controller.addSync);
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
    return messages.asyncMap((messageEvent) async {
      try {
        final message = await _decodeInboundMessage(messageEvent);
        if (message is Goodbye) {
          closeState.goodbyeReceived = true;
        }
        return message;
      } on Object catch (error) {
        _handleInboundMessageError(
          error,
          socket,
          onDisconnect,
          onConnectionLost,
        );
        return null;
      }
    });
  }

  Future<AbstractMessage> _decodeInboundMessage(
    MessageEvent messageEvent,
  ) async {
    if (_serializerType == WebSocketSerialization.serializationJson) {
      final payload = messageEvent.data.toString();
      final message = (_serializer as serializer_json.Serializer)
          .deserializeFromString(payload);
      if (message == null) {
        throw FormatException(
          'Could not deserialize inbound WebSocket WAMP message '
          '(serializer: $_serializerType, payloadLength: ${payload.length})',
        );
      }
      return message;
    }

    final arraybuffer = await (messageEvent.data as Blob).arrayBuffer().toDart;
    final payload = arraybuffer.toDart.asUint8List(0);
    final message = _serializer.deserialize(payload);
    if (message == null) {
      throw FormatException(
        'Could not deserialize inbound WebSocket WAMP message '
        '(serializer: $_serializerType, payloadLength: ${payload.length})',
      );
    }
    return message;
  }

  void _handleInboundMessageError(
    Object error,
    WebSocket socket,
    Completer onDisconnect,
    Completer onConnectionLost,
  ) {
    if (identical(_socket, socket)) {
      unawaited(close(error: error));
    } else {
      socket.close();
      complete(onDisconnect, error);
    }
    if (!onConnectionLost.isCompleted) {
      onConnectionLost.complete(error);
    }
  }
}

class _WebSocketCloseState {
  bool goodbyeSent = false;
  bool goodbyeReceived = false;
}
