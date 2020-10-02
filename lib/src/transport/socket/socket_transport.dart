import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum/src/message/goodbye.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';

import '../../message/abstract_message.dart';
import '../../serializer/abstract_serializer.dart';
import '../../transport/socket/socket_helper.dart';
import '../abstract_transport.dart';

/// This class implements the raw socket transport for wamp messages. It is also
/// capable of using connectanums own upgrade method to allow more then 16MB of
/// payload.
class SocketTransport extends AbstractTransport {
  static final _logger = Logger('SocketTransport');

  bool _ssl;
  bool _allowInsecureCertificates;
  final String _host;
  final int _port;
  Socket _socket;

  /// This will be negotiated during the handshake process.
  int _messageLength;
  int _messageLengthExponent;
  final int _serializerType;
  Duration _pingInterval;
  final AbstractSerializer _serializer;
  Uint8List _inboundBuffer = Uint8List(0);
  Uint8List _outboundBuffer = Uint8List(0);
  Completer _handshakeCompleter;
  Completer _pingCompleter;
  Completer _onConnectionLost;
  Completer _onDisconnect;
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;

  /// This creates a socket transport instance. The [messageLengthExponent] configures
  /// the max message length that will be excepted to be send and received. It is negotiated
  /// with the router and may lead into a lower value that [messageLengthExponent] if
  /// the router only supports shorter messages. The message length is calculated by
  /// 2^[messageLengthExponent]
  SocketTransport(
      this._host, this._port, this._serializer, this._serializerType,
      {ssl = false,
      allowInsecureCertificates = false,
      messageLengthExponent = SocketHelper.MAX_MESSAGE_LENGTH_EXPONENT})
      : assert(_serializerType == SocketHelper.SERIALIZATION_JSON ||
            _serializerType == SocketHelper.SERIALIZATION_MSGPACK) {
    _ssl = ssl;
    _allowInsecureCertificates = allowInsecureCertificates;
    _messageLengthExponent = messageLengthExponent;
  }

  /// Sends a handshake of the morphology
  void _sendInitialHandshake() {
    _send0(SocketHelper.getInitialHandshake(
        _messageLengthExponent, _serializerType));
  }

  void _sendProtocolError(int errorCode) {
    _goodbyeSent = true;
    _send0(SocketHelper.getError(errorCode));
    close();
  }

  bool get isUpgradedProtocol {
    return _messageLength != null &&
        _messageLength > SocketHelper.MAX_MESSAGE_LENGTH;
  }

  int get headerLength {
    return isUpgradedProtocol ? 5 : 4;
  }

  int get maxMessageLength => _messageLength;

  @override
  Future<void> close({error}) {
    // found at https://stackoverflow.com/questions/28745138/how-to-handle-socket-disconnects-in-dart
    if (isOpen) {
      return _socket.drain().then((_) {
        _socket.destroy(); // closes in and out going socket
        complete(_onDisconnect, error);
      });
    } else {
      return Future.value();
    }
  }

  @override
  bool get isOpen {
    // Dart does not provide a socket channel state
    // fix when this issue is solved: https://github.com/dart-lang/web_socket_channel/issues/16
    return _socket != null &&
        !onDisconnect.isCompleted &&
        !_onConnectionLost.isCompleted;
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
  Completer get onConnectionLost => _onConnectionLost;

  @override
  Completer get onDisconnect => _onDisconnect;

  Future<void> _runPingInterval() async {
    if (_pingInterval != null) {
      await Future.delayed(_pingInterval);
      if (isReady) {
        unawaited(sendPing(
                timeout: Duration(
                    milliseconds:
                        (_pingInterval.inMilliseconds * 2 / 3).floor()))
            .then((_) {}, onError: (timeout) {
          if (!_goodbyeSent &&
              !_goodbyeReceived &&
              !_onDisconnect.isCompleted &&
              !_onConnectionLost.isCompleted) {
            _onConnectionLost.complete(timeout);
          } else if (!_onDisconnect.isCompleted) {
            _onDisconnect.complete();
          }
        }));
        unawaited(_runPingInterval());
      }
    }
  }

  @override
  Future<void> open({Duration pingInterval}) async {
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    _handshakeCompleter = Completer();
    try {
      if (_ssl) {
        _socket = await SecureSocket.connect(_host, _port,
            onBadCertificate: (certificate) => _allowInsecureCertificates);
      } else {
        _socket = await Socket.connect(_host, _port);
      }
      _pingInterval = pingInterval;
      unawaited(_runPingInterval());
      _sendInitialHandshake();
    } on SocketException catch (error) {
      _onConnectionLost.complete(error);
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    _socket.done.then((done) {
      if (!_goodbyeSent && !_goodbyeReceived && !_onDisconnect.isCompleted) {
        _onConnectionLost.complete();
      } else {
        _onDisconnect.complete();
      }
    }, onError: (error) {
      if (!_goodbyeSent && !_goodbyeReceived && !_onDisconnect.isCompleted) {
        _onConnectionLost.complete(error);
      }
    });
    // TODO set keep alive to true
    //_socket.setOption(RawSocketOption.fromBool(??, SO_KEEPALIVE, true), true)
    return _socket
        .where((List<int> message) {
          message = Uint8List.fromList(_inboundBuffer + message);
          if (_negotiateProtocol(message) || !_assertValidMessage(message)) {
            return false;
          }
          final finalMessageLength = message.length - headerLength;
          final payloadLength =
              SocketHelper.getPayloadLength(message, headerLength);
          if (finalMessageLength < payloadLength) {
            _inboundBuffer = message;
            return false;
          }
          if (finalMessageLength > _messageLength) {
            _sendProtocolError(SocketHelper.ERROR_MESSAGE_LENGTH_EXCEEDED);
            _logger.fine(
                'Closed raw socket channel because the message length exceeded the max value of ' +
                    _messageLength.toString());
            return false;
          }
          return true;
        })
        .expand((Uint8List message) => _handleMessage(message))
        .where((message) => message != null);
  }

  bool _negotiateProtocol(Uint8List message) {
    if (_handshakeCompleter.isCompleted) return false;
    var errorNumber = SocketHelper.getErrorNumber(message);
    if (errorNumber == 0) {
      // RECEIVED FIRST HANDSHAKE RESPONSE
      if (SocketHelper.isRawSocket(message)) {
        var maxMessageSizeExponent =
            SocketHelper.getMaxMessageSizeExponent(message);
        // TRY UPGRADE TO 5 BYTE HEADER, IF WANTED
        if (maxMessageSizeExponent ==
                SocketHelper.MAX_MESSAGE_LENGTH_EXPONENT &&
            _messageLengthExponent > SocketHelper.MAX_MESSAGE_LENGTH_EXPONENT) {
          _logger.finer('Try to upgrade to 5 byte raw socket header');
          _send0(SocketHelper.getUpgradeHandshake(_messageLengthExponent));
        } else {
          // AN UPGRADE WAS NOT WANTED SO SET THE MESSAGE LENGTH AND COMPLETE THE HANDSHAKE
          _messageLength = pow(
              2,
              min(SocketHelper.getMaxMessageSizeExponent(message),
                  _messageLengthExponent));
          _handshakeCompleter.complete();
        }
      }
      // RECEIVED SECOND HANDSHAKE / UPGRADE
      if (SocketHelper.isUpgrade(message)) {
        _messageLength = pow(
            2,
            min(SocketHelper.getMaxUpgradeMessageSizeExponent(message),
                _messageLengthExponent));
        _handshakeCompleter.complete();
      }
      return true;
    } else {
      _handleError(errorNumber);
      return true;
    }
  }

  void _handleError(int errorNumber) {
    String error;
    if (errorNumber == SocketHelper.ERROR_SERIALIZER_NOT_SUPPORTED) {
      error = 'Router responded with an error: ERROR_SERIALIZER_UNSUPPORTED';
    } else if (errorNumber == SocketHelper.ERROR_USE_OF_RESERVED_BITS) {
      // if another router other then connectanum has been connected with an upgrade header
      error = 'Router responded with an error: ERROR_USE_OF_RESERVED_BITS';
    } else if (errorNumber ==
        SocketHelper.ERROR_MAX_CONNECTION_COUNT_EXCEEDED) {
      error =
          'Router responded with an error: ERROR_MAX_CONNECTION_COUNT_EXCEEDED';
    } else if (errorNumber == SocketHelper.ERROR_MESSAGE_LENGTH_EXCEEDED) {
      // if connectanum is configured with a lower message length
      error = 'Router responded with an error: ERROR_MESSAGE_LENGTH_EXCEEDED';
    } else {
      error =
          'Router responded with an error: UNKNOWN ' + errorNumber.toString();
    }
    _logger.shout(errorNumber.toString() + ': ' + error);
    _handshakeCompleter
        .completeError({'error': error, 'errorNumber': errorNumber});
    close();
  }

  bool _assertValidMessage(Uint8List message) {
    if (!SocketHelper.isValidMessage(message)) {
      _send0(SocketHelper.getError(SocketHelper.ERROR_USE_OF_RESERVED_BITS));
      _logger.shout(
          'Closed raw socket channel because the received message type ' +
              SocketHelper.getMessageType(message).toString() +
              ' is unknown.');
      return false;
    }
    return true;
  }

  List<AbstractMessage> _handleMessage(Uint8List inboundData) {
    var messages = <AbstractMessage>[];
    try {
      for (var message in _splitMessages(inboundData)) {
        var messageType = SocketHelper.getMessageType(message);
        message = message.sublist(headerLength);
        if (messageType == SocketHelper.MESSAGE_WAMP) {
          var deserializedMessage = _serializer.deserialize(message);
          if (deserializedMessage is Goodbye) {
            _goodbyeReceived = true;
          }
          _logger.finest(
              'Received message type ' + deserializedMessage.id.toString());
          messages.add(deserializedMessage);
        } else if (messageType == SocketHelper.MESSAGE_PING) {
          // send pong
          _logger.finest(
              'Responded to ping with pong and a payload length of ' +
                  message.length.toString());
          _send0(SocketHelper.getPong(message.length, isUpgradedProtocol));
          if (message.isNotEmpty) {
            _send0(message);
          }
        } else {
          // received a pong
          _pingCompleter.complete(message);
          _logger.finest('Received a Pong with a payload length of ' +
              message.length.toString());
        }
      }
    } on Exception catch (error) {
      // TODO handle serialization error
      _logger.fine('Error while handling incoming message ' + error.toString());
    }
    return messages;
  }

  List<Uint8List> _splitMessages(Uint8List inboundData) {
    var messages = <Uint8List>[];
    var offset = 0;
    while (offset < inboundData.length) {
      var messageLength = SocketHelper.getPayloadLength(
          inboundData, headerLength,
          offset: offset);
      if (offset + headerLength + messageLength <= inboundData.length) {
        // cut out the message
        messages.add(
            inboundData.sublist(offset, offset + headerLength + messageLength));
      } else {
        // send the rest of the message back to the buffer
        _inboundBuffer = inboundData.sublist(offset, inboundData.length);
      }
      offset += headerLength + messageLength;
    }
    return messages;
  }

  /// Send a ping message to keep the connection alive. The returning future will
  /// fail if no pong is received withing the given [timeout]. The default timeout
  /// is 5 seconds.
  Future<Uint8List> sendPing({Duration timeout}) async {
    if (_pingCompleter == null || _pingCompleter.isCompleted) {
      _pingCompleter = Completer<Uint8List>();
      _send0(SocketHelper.getPing(isUpgradedProtocol));
      try {
        Uint8List pong = await _pingCompleter.future
            .timeout(timeout ?? Duration(seconds: 5));
        return pong;
      } on TimeoutException {
        if (isOpen) {
          rethrow;
        }
        _pingCompleter.complete();
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
    if (!_handshakeCompleter.isCompleted) {
      if (_outboundBuffer.isEmpty) {
        _handshakeCompleter.future.then((aVoid) {
          _send0(_outboundBuffer);
          _outboundBuffer = null;
        });
      }
      var serialalizedMessage = _serializer.serialize(message);
      _outboundBuffer += SocketHelper.buildMessageHeader(
          SocketHelper.MESSAGE_WAMP,
          serialalizedMessage.length,
          isUpgradedProtocol);
      _outboundBuffer += serialalizedMessage;
    } else {
      var serialalizedMessage = _serializer.serialize(message);
      _send0(SocketHelper.buildMessageHeader(SocketHelper.MESSAGE_WAMP,
          serialalizedMessage.length, isUpgradedProtocol));
      _send0(serialalizedMessage);
    }
  }

  void _send0(List<int> data) {
    _socket.add(data);
  }
}
