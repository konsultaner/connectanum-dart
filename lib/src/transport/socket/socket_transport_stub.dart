import 'dart:async';
import 'dart:typed_data';

import '../../serializer/abstract_serializer.dart';
import '../../message/abstract_message.dart';
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
  SocketTransport(String host, int port, AbstractSerializer serializer,
      String serializerType,
      {ssl = false,
      allowInsecureCertificates = false,
      messageLengthExponent = SocketHelper.maxMessageLengthExponent});

  bool get isUpgradedProtocol => true;

  int get headerLength => 4;

  int? get maxMessageLength => null;

  @override
  Future<void> close({error}) => Future.value();

  @override
  bool get isOpen {
    return true;
  }

  @override
  bool get isReady => true;

  @override
  Future<void> get onReady => Future.value();

  set pingInterval(Duration pingInterval) {}

  @override
  Completer? get onConnectionLost => _onConnectionLost;

  @override
  Completer? get onDisconnect => _onDisconnect;

  @override
  Future<void> open({Duration? pingInterval}) async => Future.value();

  @override
  Stream<AbstractMessage> receive() => Stream.empty();

  /// Send a ping message to keep the connection alive. The returning future will
  /// fail if no pong is received withing the given [timeout]. The default timeout
  /// is 5 seconds.
  Future<Uint8List?> sendPing({Duration? timeout}) async => Future.value();

  @override
  void send(AbstractMessage message) {}
}
