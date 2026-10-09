import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

import '../../transport/socket/socket_helper.dart';
import '../abstract_transport.dart';
import '../dart_transport_copy_metrics.dart';
import '../native/canonical_base64_io.dart';
import '../native/external_byte_buffer.dart';

/// This class implements the raw socket transport for wamp messages. It is also
/// capable of using connectanums own upgrade method to allow more then 16MB of
/// payload.
class SocketTransport extends AbstractTransport implements DrainableTransport {
  static final _logger = Logger('Connectanum.SocketTransport');
  static const _segmentedSendThreshold = nativeCanonicalBase64Threshold;
  static const _nativeInboundFrameThreshold = 64 * 1024;

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
  Uint8List? _inboundFrameBuffer;
  int _inboundFrameLength = 0;
  List<Uint8List>? _outboundBuffer = <Uint8List>[];
  int _openAttempt = 0;
  bool _upgradeRequested = false;
  flatbuffers.FlatBuffersSessionProfile? _flatBuffersProfile;
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
             _serializerType == SocketHelper.serializationCbor ||
             _serializerType == SocketHelper.serializationFlatBuffers,
       ),
       _tlsSecurityContext = tlsSecurityContext {
    _ssl = ssl;
    _allowInsecureCertificates = allowInsecureCertificates;
    _messageLengthExponent = messageLengthExponent;
    if ((_serializerType == SocketHelper.serializationFlatBuffers) !=
        (_serializer is flatbuffers.Serializer)) {
      throw ArgumentError('FlatBuffers transport requires its matching codec');
    }
    installNativeCanonicalBase64Codecs(_serializer);
  }

  factory SocketTransport.withFlatBuffersSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    Object? tlsSecurityContext,
    int messageLengthExponent = SocketHelper.maxMessageLengthExponent,
  }) => SocketTransport(
    host,
    port,
    flatbuffers.Serializer(),
    SocketHelper.serializationFlatBuffers,
    ssl: ssl,
    allowInsecureCertificates: allowInsecureCertificates,
    tlsSecurityContext: tlsSecurityContext,
    messageLengthExponent: messageLengthExponent,
  );

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
  Future<void> close({error}) async {
    _openAttempt++;
    _outboundBuffer?.clear();
    final socket = _socket;
    _socket = null;
    complete(_onDisconnect, error);
    if (socket == null) return;
    try {
      if (error == null) await socket.close();
    } finally {
      // Do not wait for inbound EOF: the caller may never consume receive().
      socket.destroy();
    }
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
    final openAttempt = ++_openAttempt;
    _socket?.destroy();
    _socket = null;
    _messageLength = null;
    _upgradeRequested = false;
    _outboundBuffer = <Uint8List>[];
    _flatBuffersProfile = _serializer is flatbuffers.Serializer
        ? const flatbuffers.FlatBuffersSessionProfile.client()
        : null;
    _onDisconnect = Completer();
    _onConnectionLost = Completer();
    _handshakeCompleter = Completer();
    _inboundBuffer = Uint8List(0);
    _inboundFrameBuffer = null;
    _inboundFrameLength = 0;
    _goodbyeSent = false;
    _goodbyeReceived = false;
    try {
      final Socket socket;
      if (_ssl) {
        socket = await SecureSocket.connect(
          _host,
          _port,
          context: _tlsSecurityContext as SecurityContext?,
          onBadCertificate: (certificate) => _allowInsecureCertificates,
        );
      } else {
        socket = await Socket.connect(_host, _port);
      }
      if (openAttempt != _openAttempt) {
        socket.destroy();
        return;
      }
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      _pingInterval = pingInterval;
      unawaited(_runPingInterval());
      _sendInitialHandshake();
    } on SocketException catch (error) {
      if (openAttempt == _openAttempt && !_onConnectionLost!.isCompleted) {
        _onConnectionLost!.complete(error);
      }
    }
  }

  @override
  Stream<AbstractMessage> receive() {
    final socket = _socket;
    if (socket == null) throw StateError('Transport is not open.');
    final openAttempt = _openAttempt;
    final onDisconnect = _onDisconnect!;
    final onConnectionLost = _onConnectionLost!;
    socket.done.then(
      (done) {
        if (!_goodbyeSent &&
            !_goodbyeReceived &&
            !onDisconnect.isCompleted &&
            !onConnectionLost.isCompleted) {
          onConnectionLost.complete();
        } else if (!onDisconnect.isCompleted) {
          onDisconnect.complete();
        }
      },
      onError: (error) {
        if (!_goodbyeSent &&
            !_goodbyeReceived &&
            !onDisconnect.isCompleted &&
            !onConnectionLost.isCompleted) {
          onConnectionLost.complete(error);
        }
      },
    );
    // TODO set keep alive to true
    //_socket.setOption(RawSocketOption.fromBool(??, SO_KEEPALIVE, true), true)
    return socket.expand((chunk) {
      if (openAttempt != _openAttempt || !identical(_socket, socket)) {
        return const <AbstractMessage>[];
      }
      return _consumeInboundChunk(chunk);
    });
  }

  List<AbstractMessage> _consumeInboundChunk(List<int> message) {
    final typedMessage = message is Uint8List
        ? message
        : Uint8List.fromList(message);
    final frameBuffer = _inboundFrameBuffer;
    if (frameBuffer != null) {
      final missing = frameBuffer.length - _inboundFrameLength;
      final take = min(missing, typedMessage.length);
      frameBuffer.setRange(
        _inboundFrameLength,
        _inboundFrameLength + take,
        typedMessage,
      );
      _inboundFrameLength += take;
      if (_inboundFrameLength < frameBuffer.length) {
        return const [];
      }

      _inboundFrameBuffer = null;
      _inboundFrameLength = 0;
      final messages = _handleMessage(frameBuffer);
      if (take < typedMessage.length && !_onConnectionLost!.isCompleted) {
        messages.addAll(
          _consumeInboundChunk(
            Uint8List.sublistView(typedMessage, take, typedMessage.length),
          ),
        );
      }
      return messages;
    }

    final inboundData = _mergeInboundChunk(typedMessage);
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
    final frameLength = headerLength + payloadLength;
    if (negotiatedData.length < frameLength) {
      final buffer = _allocateInboundFrameBuffer(frameLength);
      buffer.setRange(0, negotiatedData.length, negotiatedData);
      _inboundBuffer = Uint8List(0);
      _inboundFrameBuffer = buffer;
      _inboundFrameLength = negotiatedData.length;
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

  Uint8List _allocateInboundFrameBuffer(int frameLength) {
    if (frameLength >= _nativeInboundFrameThreshold) {
      return allocateNativeExternalBytes(frameLength);
    }
    return Uint8List(frameLength);
  }

  Uint8List _consumeNegotiation(Uint8List message) {
    if (_handshakeCompleter.isCompleted) {
      return message;
    }
    if (message.isEmpty) {
      return message;
    }
    if (SocketHelper.isUpgrade(message)) {
      if (!_upgradeRequested) {
        _handleError(SocketHelper.errorUseOfReservedBits);
        return Uint8List(0);
      }
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
      _upgradeRequested = false;
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
    if ((handshake[1] & 0x0f) != _serializerType) {
      _handleError(SocketHelper.errorSerializerNotSupported);
      return Uint8List(0);
    }
    final maxMessageSizeExponent = SocketHelper.getMaxMessageSizeExponent(
      handshake,
    );
    if (maxMessageSizeExponent == SocketHelper.maxMessageLengthExponent &&
        _messageLengthExponent > SocketHelper.maxMessageLengthExponent) {
      _upgradeRequested = true;
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
          retainNativeExternalBytes(payload, inboundData);
          var deserializedMessage = _serializer.deserialize(payload);
          if (deserializedMessage == null) {
            throw FormatException(
              'Could not deserialize inbound WAMP message '
              '(serializer: $_serializerType, payloadLength: ${payload.length})',
            );
          }
          if (_flatBuffersProfile case final profile?) {
            _flatBuffersProfile = profile.acceptIncoming(deserializedMessage);
          }
          if (deserializedMessage is Goodbye) {
            _goodbyeReceived = true;
          }
          retainNativeExternalBytes(deserializedMessage, inboundData);
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
    } on Object catch (error, stackTrace) {
      _handleInboundMessageError(error, stackTrace);
    }
    return messages;
  }

  void _handleInboundMessageError(Object error, StackTrace stackTrace) {
    _logger.fine('Error while handling incoming message', error, stackTrace);
    final closeFuture = close(error: error);
    if (!_onConnectionLost!.isCompleted) {
      _onConnectionLost!.complete(error);
    }
    unawaited(closeFuture);
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
        final frameLength = headerLength + messageLength;
        final buffer = _allocateInboundFrameBuffer(frameLength);
        buffer.setRange(0, remaining, inboundData, offset);
        _inboundBuffer = Uint8List(0);
        _inboundFrameBuffer = buffer;
        _inboundFrameLength = remaining;
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
    if (!isOpen) throw StateError('RawSocket transport is not open.');
    final nextProfile = _flatBuffersProfile?.prepareOutgoing(message);
    _sendMessage(message);
    _flatBuffersProfile = nextProfile;
    if (message is Goodbye) _goodbyeSent = true;
  }

  void _sendMessage(AbstractMessage message) {
    final fragments = _handshakeCompleter.isCompleted
        ? _serializer.serializeFragments(message)
        : null;
    if (fragments != null) {
      var payloadLength = 0;
      for (final fragment in fragments) {
        payloadLength += fragment.length;
      }
      if (payloadLength >= _segmentedSendThreshold) {
        _checkOutgoingPayloadLength(payloadLength);
        _send0(
          SocketHelper.buildMessageHeader(
            SocketHelper.messageWamp,
            payloadLength,
            isUpgradedProtocol,
          ),
        );
        for (final fragment in fragments) {
          if (fragment.isNotEmpty) {
            _send0(fragment, anchor: message);
          }
        }
        return;
      }
      _send0(_buildWampFrameFragments(fragments, payloadLength));
      return;
    }
    var serializedMessage = _serializer.serialize(message);
    if (serializedMessage is String) {
      serializedMessage = utf8.encoder.convert(serializedMessage);
    }
    if (!_handshakeCompleter.isCompleted) {
      final queue = _outboundBuffer!;
      final queuedBytes = queue.fold<int>(
        0,
        (length, bytes) => length + bytes.length,
      );
      if (queuedBytes + (serializedMessage as List<int>).length >
          1 << _messageLengthExponent) {
        throw StateError('RawSocket pre-handshake queue is full');
      }
      if (queue.isEmpty) {
        final socket = _socket!;
        final openAttempt = _openAttempt;
        final onConnectionLost = _onConnectionLost!;
        unawaited(
          _handshakeCompleter.future.then<void>(
            (_) {
              try {
                if (openAttempt != _openAttempt ||
                    !identical(_socket, socket) ||
                    !isOpen) {
                  return;
                }
                _outboundBuffer = null;
                // Build each frame using the header width negotiated by this peer.
                for (final payload in queue) {
                  _send0(_buildWampFrame(payload));
                }
              } on Object catch (error, stackTrace) {
                _logger.shout(
                  'Could not write queued RawSocket frame',
                  error,
                  stackTrace,
                );
                if (!onConnectionLost.isCompleted) {
                  onConnectionLost.complete(error);
                }
                unawaited(close(error: error));
              } finally {
                queue.clear();
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              queue.clear();
            },
          ),
        );
      }
      // Match the ordinary framed-send ownership: the queue retains its bytes.
      final queuedPayload = Uint8List.fromList(serializedMessage);
      DartTransportCopyMetrics.recordRawSocketPreHandshakeQueueCopy(
        queuedPayload.length,
      );
      queue.add(queuedPayload);
    } else {
      _send0(_buildWampFrame(serializedMessage as List<int>));
    }
  }

  void _send0(List<int> data, {Object? anchor}) {
    if (data is Uint8List) {
      if (data.offsetInBytes == 0 &&
          data.buffer.lengthInBytes == data.lengthInBytes) {
        _socket!.add(data);
        return;
      }
      final bounded = nativeExternalByteView(data, anchor: anchor);
      if (bounded != null) {
        _socket!.add(bounded);
        return;
      }
    }
    // Give the SDK full backing storage so retries reuse this one measured
    // copy instead of copying the remaining subview on every write attempt.
    final copied = Uint8List.fromList(data);
    DartTransportCopyMetrics.recordRawSocketInputCopy(copied.length);
    _socket!.add(copied);
  }

  @override
  Future<void> drain() async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    await socket.flush();
    await Future<void>.delayed(Duration.zero);
  }

  Uint8List _buildWampFrame(List<int> payload) {
    _checkOutgoingPayloadLength(payload.length);
    final builder = BytesBuilder(copy: false);
    final header = SocketHelper.buildMessageHeader(
      SocketHelper.messageWamp,
      payload.length,
      isUpgradedProtocol,
    );
    builder.add(header);
    builder.add(payload);
    final frame = builder.takeBytes();
    DartTransportCopyMetrics.recordRawSocketFramePayloadCopy(payload.length);
    DartTransportCopyMetrics.recordRawSocketFrameHeaderCopy(header.length);
    return frame;
  }

  Uint8List _buildWampFrameFragments(
    List<Uint8List> fragments,
    int payloadLength,
  ) {
    _checkOutgoingPayloadLength(payloadLength);
    final header = SocketHelper.buildMessageHeader(
      SocketHelper.messageWamp,
      payloadLength,
      isUpgradedProtocol,
    );
    final frame = Uint8List(header.length + payloadLength);
    frame.setRange(0, header.length, header);
    var offset = header.length;
    for (final fragment in fragments) {
      frame.setRange(offset, offset + fragment.length, fragment);
      offset += fragment.length;
    }
    DartTransportCopyMetrics.recordRawSocketFramePayloadCopy(payloadLength);
    DartTransportCopyMetrics.recordRawSocketFrameHeaderCopy(header.length);
    return frame;
  }

  void _checkOutgoingPayloadLength(int length) {
    final limit = maxMessageLength;
    if (limit == null || length > limit) {
      throw StateError(
        'RawSocket payload length $length exceeds negotiated limit $limit',
      );
    }
  }
}
