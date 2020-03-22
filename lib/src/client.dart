import 'dart:async';

import 'package:connectanum/src/message/goodbye.dart';
import 'package:logging/logging.dart';

import '../src/message/abort.dart';
import '../src/message/error.dart';

import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';

class Client {
  static Logger _logger = Logger("Client");

  String authId;
  String realm;
  int isolateCount;
  AbstractTransport transport;
  List<AbstractAuthentication> authenticationMethods;

  int _reconnectCount = 3;
  StreamController<Session> _controller = StreamController<Session>();

  /// The client connects to the wamp server by using the given [transport] and
  /// the given [authenticationMethods]. Passing more then one [AbstractAuthentication]
  /// to the client will make the router choose which method to choose.
  /// The [authId] and the [realm] will be used for all given [authenticationMethods]
  ///
  /// Example:
  /// ```dart
  /// import 'package:connectanum/connectanum.dart';
  /// import 'package:connectanum/socket.dart';
  ///
  /// final client = Client(
  ///   realm: "test.realm",
  ///   transport: SocketTransport(
  ///     'localhost',
  ///     8080,
  ///     Serializer(),
  ///     SocketHelper.SERIALIZATION_JSON
  ///   )
  /// );
  ///
  /// final Session session = await client.connect();
  /// ```
  Client(
      {this.transport,
      this.authId,
      this.realm,
      this.authenticationMethods,
      this.isolateCount = 1})
      : assert(transport != null),
        assert(realm != null && UriPattern.match(realm));

  /// Calling this method will start the authentication process and result into
  /// a [Session] object on success. If a [pingInterval] is given and the underlying transport
  /// supports sending of ping messages. the given duration is used by the transport
  /// to send ping messages every [pingInterval]. [SocketTransport] and [WebSocketTransport] not
  /// within the browser support ping messages. The browser API does not allow to control
  /// ping messages. If [reconnectCount] and the [reconnectTime] is set
  /// the client will try to reestablish the session. Setting [reconnectCount] to -1 will infinite
  /// times reconnect the client or until the stack overflows
  Stream<Session> connect(
      {Duration pingInterval,
      Duration reconnectTime,
      reconnectCount,
      onReconnecting()}) {
    this._reconnectCount = reconnectCount;
    _connect(
        pingInterval: pingInterval,
        reconnectTime: reconnectTime,
        reconnectCount: reconnectCount);
    return _controller.stream;
  }

  void _connect(
      {Duration pingInterval,
      Duration reconnectTime,
      int reconnectCount = 3}) async {
    await transport.open(pingInterval: pingInterval);
    if (transport.isOpen) {
      transport.onConnectionLost.future.then((_) async {
        await Future.delayed(reconnectTime);
        _connect(
            pingInterval: pingInterval,
            reconnectTime: reconnectTime,
            reconnectCount: this._reconnectCount);
      });
      try {
        Session session = await Session.start(realm, transport,
            authId: authId,
            authMethods: authenticationMethods,
            reconnect: reconnectTime);
        _controller.add(session);
      } on Abort catch (abort) {
        if (abort.reason != Error.NOT_AUTHORIZED && reconnectTime != null) {
          // if the router restarts we should wait until it has been initialized
          _connect(
              pingInterval: pingInterval,
              reconnectTime: Duration(seconds: 2),
              reconnectCount: 0);
        } else {
          _controller.addError(abort);
        }
      } on Goodbye catch (goodbye) {
        _logger.shout(goodbye.reason);
        _controller.close();
      }
    } else {
      if (reconnectTime != null && transport.onConnectionLost.isCompleted) {
        if (reconnectCount == 0) {
          _controller.addError(Abort(Error.AUTHORIZATION_FAILED,
              message:
                  "Could not connect to server. Please configure reconnectTime to retry automatically."));
        } else {
          await Future.delayed(reconnectTime);
          _connect(
              pingInterval: pingInterval,
              reconnectTime: reconnectTime,
              reconnectCount:
                  reconnectCount == -1 ? reconnectCount : reconnectCount - 1);
        }
      } else {
        _controller.addError(Abort(Error.AUTHORIZATION_FAILED,
            message:
                "Could not connect to server. Please configure reconnectTime to retry automatically."));
      }
    }
  }
}
