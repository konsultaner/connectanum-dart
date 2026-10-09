import 'dart:async';
import 'dart:typed_data';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;

import 'package:connectanum_core/connectanum_core.dart';
import '../../transport/socket/socket_helper.dart';
import '../abstract_transport.dart';

/// This class implements the raw socket transport for wamp messages. It is also
/// capable of using connectanums own upgrade method to allow more then 16MB of
/// payload.
class SocketTransport extends AbstractTransport {
  Completer? _onConnectionLost;
  Completer? _onDisconnect;

  /// This creates a socket transport instance. The [messageLengthExponent] configures
  /// the max message length that will be excepted to be send and received. It is negotiated
  /// with the router and may lead into a lower value that [messageLengthExponent] if
  /// the router only supports shorter messages. The message length is calculated by
  /// 2^[messageLengthExponent]
  SocketTransport(
    String host,
    int port,
    AbstractSerializer serializer,
    int serializerType, {
    ssl = false,
    allowInsecureCertificates = false,
    Object? tlsSecurityContext,
    messageLengthExponent = SocketHelper.maxMessageLengthExponent,
  }) {
    throw UnsupportedError('RawSocket transports require dart:io.');
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

  bool get isUpgradedProtocol => false;

  int get headerLength => 4;

  int? get maxMessageLength => null;

  @override
  Future<void> close({error}) => Future.value();

  @override
  bool get isOpen {
    return false;
  }

  @override
  bool get isReady => false;

  @override
  Future<void> get onReady =>
      Future.error(UnsupportedError('RawSocket transports require dart:io.'));

  set pingInterval(Duration pingInterval) {}

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  @override
  Future<void> open({Duration? pingInterval}) =>
      Future.error(UnsupportedError('RawSocket transports require dart:io.'));

  @override
  Stream<AbstractMessage> receive() =>
      Stream.error(UnsupportedError('RawSocket transports require dart:io.'));

  /// Send a ping message to keep the connection alive. The returning future will
  /// fail if no pong is received withing the given [timeout]. The default timeout
  /// is 5 seconds.
  Future<Uint8List?> sendPing({Duration? timeout}) async => Future.value();

  @override
  void send(AbstractMessage message) {
    throw UnsupportedError('RawSocket transports require dart:io.');
  }
}
