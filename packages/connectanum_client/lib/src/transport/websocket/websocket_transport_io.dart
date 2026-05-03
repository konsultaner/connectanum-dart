import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';

import 'websocket_transport_serialization.dart';
import '../../transport/abstract_transport.dart';
import 'package:connectanum_core/json_serializer.dart' as serializer_json;
import 'package:connectanum_core/msgpack_serializer.dart' as serializer_msgpack;
import 'package:connectanum_core/cbor_serializer.dart' as serializer_cbor;

/// This transport type is used to connect via web sockets
/// in a dart vm environment. A known issue is that this
/// transport does not support auto reconnnect in the dart vm
/// use [SocketTransport] instead! This may not work if your
/// router does not raw socket transport
class WebSocketTransport extends AbstractTransport {
  final String _url;
  final AbstractSerializer _serializer;
  final String _serializerType;
  final bool _allowInsecureCertificates;
  final Object? _tlsSecurityContext;

  /// The keys of the map are the header
  /// fields and the values are either String or List of String
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
    this._serializerType, [
    this._headers,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) : _allowInsecureCertificates = allowInsecureCertificates,
       _tlsSecurityContext = tlsSecurityContext,
       assert(
         _serializerType == WebSocketSerialization.serializationJson ||
             _serializerType == WebSocketSerialization.serializationMsgpack ||
             _serializerType == WebSocketSerialization.serializationCbor,
       );

  factory WebSocketTransport.withJsonSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_json.Serializer(),
    WebSocketSerialization.serializationJson,
    headers,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  factory WebSocketTransport.withMsgpackSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_msgpack.Serializer(),
    WebSocketSerialization.serializationMsgpack,
    headers,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  factory WebSocketTransport.withCborSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
  ]) => WebSocketTransport(
    url,
    serializer_cbor.Serializer(),
    WebSocketSerialization.serializationCbor,
    headers,
    allowInsecureCertificates,
    tlsSecurityContext,
  );

  /// Calling close will close the underlying socket connection
  @override
  Future<void> close({error}) {
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
      final securityContext = _tlsSecurityContext as SecurityContext?;
      final client = securityContext != null || _allowInsecureCertificates
          ? HttpClient(context: securityContext)
          : null;
      if (client != null && _allowInsecureCertificates) {
        client.badCertificateCallback =
            (X509Certificate certificate, String host, int port) => true;
      }
      _socket = await WebSocket.connect(
        _url,
        protocols: [_serializerType],
        headers: _headers,
        customClient: client,
      );
      _onReady.complete();
      if (pingInterval != null) {
        Timer.periodic(
          pingInterval,
          (timer) => _socket!.pingInterval = Duration(
            milliseconds: (pingInterval.inMilliseconds * 2 / 3).floor(),
          ),
        );
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
    if (_serializerType == WebSocketSerialization.serializationJson) {
      _socket!.addUtf8Text(
        utf8.encoder.convert(_serializer.serialize(message)),
      );
    } else {
      _socket!.add(_serializer.serialize(message));
    }
  }

  /// This method return a [Stream] that streams all incoming messages as unserialized
  /// objects.
  @override
  Stream<AbstractMessage?> receive() {
    _socket!.done.then(
      (done) {
        if ((_socket!.closeCode == null || _socket!.closeCode! > 1000) &&
            !_goodbyeSent &&
            !_goodbyeReceived) {
          complete(_onConnectionLost, null);
        } else {
          complete(_onDisconnect, null);
        }
      },
      onError: (error) {
        if (!_onDisconnect!.isCompleted) {
          complete(_onConnectionLost, error);
        }
      },
    );
    return _socket!.map((messageEvent) {
      try {
        final message = _decodeInboundMessage(messageEvent);
        if (message is Goodbye) {
          _goodbyeReceived = true;
        }
        return message;
      } on Object catch (error) {
        _handleInboundMessageError(error);
        return null;
      }
    });
  }

  AbstractMessage _decodeInboundMessage(Object messageEvent) {
    final Uint8List payload;
    if (_serializerType == WebSocketSerialization.serializationJson) {
      payload = Uint8List.fromList(utf8.encode(messageEvent as String));
    } else if (messageEvent is Uint8List) {
      payload = messageEvent;
    } else {
      payload = Uint8List.fromList(messageEvent as List<int>);
    }

    final message = _serializer.deserialize(payload);
    if (message == null) {
      throw FormatException(
        'Could not deserialize inbound WebSocket WAMP message '
        '(serializer: $_serializerType, payloadLength: ${payload.length})',
      );
    }
    return message;
  }

  void _handleInboundMessageError(Object error) {
    final closeFuture = close(error: error);
    if (!_onConnectionLost!.isCompleted) {
      _onConnectionLost!.complete(error);
    }
    unawaited(closeFuture);
  }
}
