import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';
import '../../transport/socket/socket_helper.dart';
import '../abstract_transport.dart';

/// This class implements the raw socket transport for wamp messages. It is also
/// capable of using connectanums own upgrade method to allow more then 16MB of
/// payload.
class SocketTransport extends AbstractTransport {
  static final _logger = Logger('Connectanum.SocketTransport');

  late bool _ssl;
  late bool _allowInsecureCertificates;
  final Object? _tlsSecurityContext;
  final String _host;
  final int _port;
  Socket? _socket;

  /// This will be negotiated during the handshake process.
  int? _messageLength;
  late int _messageLengthExponent;
  final int _serializerType;
  Duration? _pingInterval;
  final AbstractSerializer _serializer;
  Uint8List _inboundBuffer = Uint8List(0);
  Uint8List? _outboundBuffer = Uint8List(0);
  late Completer _handshakeCompleter;
  Completer? _pingCompleter;
  Completer? _onConnectionLost;
  Completer? _onDisconnect;
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;

  /// This creates a socket transport instance. The [messageLengthExponent] configures
  /// the max message length that will be excepted to be send and received. It is negotiated
  /// with the router and may lead into a lower value that [messageLengthExponent] if
  /// the router only supports shorter messages. The message length is calculated by
  /// 2^[messageLengthExponent]
  SocketTransport(
    this._host,
    this._port,
    this._serializer,
    this._serializerType, {
    ssl = false,
    allowInsecureCertificates = false,
    Object? tlsSecurityContext,
    messageLengthExponent = SocketHelper.maxMessageLengthExponent,
  }) : assert(
         _serializerType == SocketHelper.serializationJson ||
             _serializerType == SocketHelper.serializationMsgpack ||
             _serializerType == SocketHelper.serializationCbor,
       ),
       _tlsSecurityContext = tlsSecurityContext {
    _ssl = ssl;
    _allowInsecureCertificates = allowInsecureCertificates;
    _messageLengthExponent = messageLengthExponent;
  }

  /// Sends a handshake of the morphology
  void _sendInitialHandshake() {
    _send0(
      SocketHelper.getInitialHandshake(_messageLengthExponent, _serializerType),
    );
  }

  void _sendProtocolError(int errorCode) {
    _goodbyeSent = true;
    _send0(SocketHelper.getError(errorCode));
    close();
  }

  bool get isUpgradedProtocol {
    return _messageLength != null &&
        _messageLength! > SocketHelper.maxMessageLength;
  }

  int get headerLength {
    return isUpgradedProtocol ? 5 : 4;
  }

  int? get maxMessageLength => _messageLength;

  @override
  Future<void> close({error}) {
    // found at https://stackoverflow.com/questions/28745138/how-to-handle-socket-disconnects-in-dart
    if (isOpen) {
      try {
        return _socket!.drain().then((_) {
          _socket!.destroy(); // closes in and out going socket
          complete(_onDisconnect, error);
        });
      } catch (error) {
        _socket!.destroy(); // closes in and out going socket
        complete(_onDisconnect, error);
      }
    }
    return Future.value();
  }

  @override
  bool get isOpen {
    // Dart does not provide a socket channel state
    // fix when this issue is solved: https://github.com/dart-lang/web_socket_channel/issues/16
    return _socket != null &&
        !onDisconnect!.isCompleted &&
        !_onConnectionLost!.isCompleted;
  }

  @override
  bool get isReady => isOpen && _handshakeCompleter.isCompleted;

  @override
  Future<void> get onReady {
    return _handshakeCompleter.future;
  }

  set pingInterval(Duration pingInterval) {
    _pingInterval = pingInterval;
    _runPingInterval();
  }

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  Future<void> _runPingInterval() async {
    if (_pingInterval != null) {
      await Future.delayed(_pingInterval!);
      if (isReady) {
        unawaited(
          sendPing(
            timeout: Duration(
              milliseconds: (_pingInterval!.inMilliseconds * 2 / 3).floor(),
            ),
          ).then(
            (_) {},
            onError: (timeout) {
              if (!_goodbyeSent &&
                  !_goodbyeReceived &&
                  !_onDisconnect!.isCompleted &&
                  !_onConnectionLost!.isCompleted) {
                _onConnectionLost!.complete(timeout);
              } else if (!_onDisconnect!.isCompleted) {
                _onDisconnect!.complete();
              }
            },
          ),
        );
        unawaited(_runPingInterval());
      }
    }
  }

  @override
  Future<void> open({Duration? pingInterval}) async {
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    _handshakeCompleter = Completer();
    try {
      if (_ssl) {
        _socket = await SecureSocket.connect(
          _host,
          _port,
          context: _tlsSecurityContext as SecurityContext?,
          onBadCertificate: (certificate) => _allowInsecureCertificates,
        );
      } else {
        _socket = await Socket.connect(_host, _port);
      }
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _pingInterval = pingInterval;
      unawaited(_runPingInterval());
      _sendInitialHandshake();
    } on SocketException catch (error) {
      _onConnectionLost!.complete(error);
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    _socket!.done.then(
      (done) {
        if (!_goodbyeSent && !_goodbyeReceived && !_onDisconnect!.isCompleted) {
          _onConnectionLost!.complete();
        } else if (!_onDisconnect!.isCompleted) {
          _onDisconnect!.complete();
        }
      },
      onError: (error) {
        if (!_goodbyeSent && !_goodbyeReceived && !_onDisconnect!.isCompleted) {
          _onConnectionLost!.complete(error);
        }
      },
    );
    // TODO set keep alive to true
    //_socket.setOption(RawSocketOption.fromBool(??, SO_KEEPALIVE, true), true)
    return _socket!.expand(_consumeInboundChunk);
  }

  List<AbstractMessage> _consumeInboundChunk(List<int> message) {
    final inboundData = _mergeInboundChunk(message);
    final negotiatedData = _consumeNegotiation(inboundData);
    if (negotiatedData.isEmpty) {
      return const [];
    }
    if (negotiatedData.length < headerLength) {
      _inboundBuffer = negotiatedData;
      return const [];
    }
    if (!_assertValidMessage(negotiatedData)) {
      return const [];
    }
    final payloadLength = SocketHelper.getPayloadLength(
      negotiatedData,
      headerLength,
    );
    if (payloadLength > _messageLength!) {
      _sendProtocolError(SocketHelper.errorMessageLengthExceeded);
      _logger.fine(
        'Closed raw socket channel because the message length exceeded the max value of $_messageLength',
      );
      return const [];
    }
    if (negotiatedData.length < headerLength + payloadLength) {
      _inboundBuffer = negotiatedData;
      return const [];
    }
    return _handleMessage(negotiatedData);
  }

  Uint8List _mergeInboundChunk(List<int> message) {
    final typedMessage = message is Uint8List
        ? message
        : Uint8List.fromList(message);
    if (_inboundBuffer.isEmpty) {
      return typedMessage;
    }
    final merged = Uint8List(_inboundBuffer.length + typedMessage.length);
    merged.setRange(0, _inboundBuffer.length, _inboundBuffer);
    merged.setRange(_inboundBuffer.length, merged.length, typedMessage);
    _inboundBuffer = Uint8List(0);
    return merged;
  }

  Uint8List _consumeNegotiation(Uint8List message) {
    if (_handshakeCompleter.isCompleted) {
      return message;
    }
    if (message.isEmpty) {
      return message;
    }
    if (SocketHelper.isUpgrade(message)) {
      if (message.length < 2) {
        _inboundBuffer = message;
        return Uint8List(0);
      }
      _messageLength =
          pow(
                2,
                min(
                  SocketHelper.getMaxUpgradeMessageSizeExponent(message),
                  _messageLengthExponent,
                ),
              )
              as int?;
      _handshakeCompleter.complete();
      if (message.length == 2) {
        return Uint8List(0);
      }
      return Uint8List.sublistView(message, 2, message.length);
    }
    if (message.length < 4) {
      _inboundBuffer = message;
      return Uint8List(0);
    }
    final handshake = Uint8List.sublistView(message, 0, 4);
    final errorNumber = SocketHelper.getErrorNumber(handshake);
    if (errorNumber != 0) {
      _handleError(errorNumber);
      return Uint8List(0);
    }
    if (!SocketHelper.isRawSocket(handshake)) {
      return message;
    }
    final maxMessageSizeExponent = SocketHelper.getMaxMessageSizeExponent(
      handshake,
    );
    if (maxMessageSizeExponent == SocketHelper.maxMessageLengthExponent &&
        _messageLengthExponent > SocketHelper.maxMessageLengthExponent) {
      _logger.finer('Try to upgrade to 5 byte raw socket header');
      _send0(SocketHelper.getUpgradeHandshake(_messageLengthExponent));
      if (message.length > 4) {
        _inboundBuffer = Uint8List.sublistView(message, 4, message.length);
      }
      return Uint8List(0);
    }
    _messageLength =
        pow(
              2,
              min(
                SocketHelper.getMaxMessageSizeExponent(handshake),
                _messageLengthExponent,
              ),
            )
            as int?;
    _handshakeCompleter.complete();
    if (message.length == 4) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(message, 4, message.length);
  }

  void _handleError(int errorNumber) {
    String error;
    if (errorNumber == SocketHelper.errorSerializerNotSupported) {
      error = 'Router responded with an error: ERROR_SERIALIZER_UNSUPPORTED';
    } else if (errorNumber == SocketHelper.errorUseOfReservedBits) {
      // if another router other then connectanum has been connected with an upgrade header
      error = 'Router responded with an error: ERROR_USE_OF_RESERVED_BITS';
    } else if (errorNumber == SocketHelper.errorMaxConnectionCountExceeded) {
      error =
          'Router responded with an error: ERROR_MAX_CONNECTION_COUNT_EXCEEDED';
    } else if (errorNumber == SocketHelper.errorMessageLengthExceeded) {
      // if connectanum is configured with a lower message length
      error = 'Router responded with an error: ERROR_MESSAGE_LENGTH_EXCEEDED';
    } else {
      error = 'Router responded with an error: UNKNOWN $errorNumber';
    }
    _logger.shout('$errorNumber: $error');
    _handshakeCompleter.completeError({
      'error': error,
      'errorNumber': errorNumber,
    });
    close();
  }

  bool _assertValidMessage(Uint8List message) {
    if (!SocketHelper.isValidMessage(message)) {
      _send0(SocketHelper.getError(SocketHelper.errorUseOfReservedBits));
      _logger.shout(
        'Closed raw socket channel because the received message type ${SocketHelper.getMessageType(message)} is unknown.',
      );
      return false;
    }
    return true;
  }

  List<AbstractMessage> _handleMessage(Uint8List inboundData) {
    var messages = <AbstractMessage>[];
    try {
      for (var message in _splitMessages(inboundData)) {
        var messageType = SocketHelper.getMessageType(message);
        final payload = Uint8List.sublistView(
          message,
          headerLength,
          message.length,
        );
        if (messageType == SocketHelper.messageWamp) {
          var deserializedMessage = _serializer.deserialize(payload)!;
          if (deserializedMessage is Goodbye) {
            _goodbyeReceived = true;
          }
          _logger.finest('Received message type ${deserializedMessage.id}');
          messages.add(deserializedMessage);
        } else if (messageType == SocketHelper.messagePing) {
          // send pong
          _logger.finest(
            'Responded to ping with pong and a payload length of ${payload.length}',
          );
          _send0(SocketHelper.getPong(payload.length, isUpgradedProtocol));
          if (payload.isNotEmpty) {
            _send0(payload);
          }
        } else if (messageType == SocketHelper.messagePong) {
          // received a pong
          if (_pingCompleter != null && !_pingCompleter!.isCompleted) {
            _pingCompleter!.complete(payload);
          }
          _logger.finest(
            'Received a Pong with a payload length of ${payload.length}',
          );
        } else {
          _sendProtocolError(SocketHelper.errorUseOfReservedBits);
          _logger.shout(
            'Closed raw socket channel because the received message type $messageType is unknown.',
          );
          break;
        }
      }
    } on Exception catch (error) {
      // TODO handle serialization error
      _logger.fine('Error while handling incoming message $error');
    }
    return messages;
  }

  List<Uint8List> _splitMessages(Uint8List inboundData) {
    var messages = <Uint8List>[];
    var offset = 0;
    while (offset < inboundData.length) {
      final remaining = inboundData.length - offset;
      if (remaining < headerLength) {
        _inboundBuffer = Uint8List.sublistView(
          inboundData,
          offset,
          inboundData.length,
        );
        break;
      }
      var messageLength = SocketHelper.getPayloadLength(
        inboundData,
        headerLength,
        offset: offset,
      );
      if (messageLength > _messageLength!) {
        _sendProtocolError(SocketHelper.errorMessageLengthExceeded);
        _logger.fine(
          'Closed raw socket channel because the message length exceeded the max value of $_messageLength',
        );
        break;
      }
      if (offset + headerLength + messageLength <= inboundData.length) {
        // cut out the message
        messages.add(
          Uint8List.sublistView(
            inboundData,
            offset,
            offset + headerLength + messageLength,
          ),
        );
      } else {
        // send the rest of the message back to the buffer
        _inboundBuffer = Uint8List.sublistView(
          inboundData,
          offset,
          inboundData.length,
        );
        break;
      }
      offset += headerLength + messageLength;
    }
    if (offset >= inboundData.length) {
      _inboundBuffer = Uint8List(0);
    }
    return messages;
  }

  /// Send a ping message to keep the connection alive. The returning future will
  /// fail if no pong is received withing the given [timeout]. The default timeout
  /// is 5 seconds.
  Future<Uint8List?> sendPing({Duration? timeout}) async {
    if (_pingCompleter == null || _pingCompleter!.isCompleted) {
      _pingCompleter = Completer<Uint8List>();
      _send0(SocketHelper.getPing(isUpgradedProtocol));
      try {
        Uint8List pong = await _pingCompleter!.future.timeout(
          timeout ?? Duration(seconds: 5),
        );
        return pong;
      } on TimeoutException {
        if (isOpen) {
          rethrow;
        }
        _pingCompleter!.complete();
        return null;
      }
    } else {
      throw Exception('Wait for the last ping to complete or to timeout');
    }
  }

  @override
  void send(AbstractMessage message) {
    if (message is Goodbye) {
      _goodbyeSent = true;
    }
    var serialalizedMessage = _serializer.serialize(message);
    if (serialalizedMessage is String) {
      serialalizedMessage = utf8.encoder.convert(serialalizedMessage);
    }
    final frame = _buildWampFrame(serialalizedMessage as List<int>);
    if (!_handshakeCompleter.isCompleted) {
      if (_outboundBuffer!.isEmpty) {
        _handshakeCompleter.future.then((aVoid) {
          _send0(_outboundBuffer!);
          _outboundBuffer = null;
        });
      }
      _outboundBuffer!.addAll(frame);
    } else {
      _send0(frame);
    }
  }

  void _send0(List<int> data) {
    _socket!.add(data);
  }

  Uint8List _buildWampFrame(List<int> payload) {
    final builder = BytesBuilder(copy: false);
    builder.add(
      SocketHelper.buildMessageHeader(
        SocketHelper.messageWamp,
        payload.length,
        isUpgradedProtocol,
      ),
    );
    builder.add(payload);
    return builder.takeBytes();
  }
}
