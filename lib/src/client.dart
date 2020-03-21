import '../src/message/abort.dart';
import '../src/message/error.dart';

import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';

class Client {
  AbstractTransport transport;
  String authId;
  String realm;
  List<AbstractAuthentication> authenticationMethods;
  int isolateCount;

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
  /// ping messages. If [reconnectCount], [onReconnect] and the [reconnectTime] is set
  /// the client will try to reestablish the session. Setting [reconnectCount] to -1 will infinite
  /// times reconnect the client or until the stack overflows
  Future<Session> connect(
      {
        Duration pingInterval,
        Duration reconnectTime,
        int reconnectCount = 3,
        onReconnecting(),
        onReconnect(Session session)
      }
  ) async {
    await transport.open(pingInterval: pingInterval);
    if (transport.isOpen) {
      if (onReconnect != null) {
        transport.onConnectionLost.future.then((_) async {
          await Future.delayed(reconnectTime);
          onReconnect(await connect(
              pingInterval: pingInterval,
              onReconnect: onReconnect,
              reconnectTime: reconnectTime,
              reconnectCount: reconnectCount == -1 ? reconnectCount : reconnectCount - 1
          ));
        });
      }
      try {
        Session session = await Session.start(realm, transport,
            authId: authId,
            authMethods: authenticationMethods,
            reconnect: reconnectTime);
        return session;
      } on Abort catch (abort) {
        if (abort.reason != Error.NOT_AUTHORIZED) {
          // if the router restarts we should wait until it has been initialized
          await Future.delayed(Duration(seconds: 2));
          return await Session.start(realm, transport,
              authId: authId,
              authMethods: authenticationMethods,
              reconnect: reconnectTime);
        }
      }
    } else {
      if(
        onReconnect != null &&
        reconnectTime != null &&
        transport.onConnectionLost.isCompleted
      ) {
        if (reconnectCount == 0) {
          throw Exception("Could not connect to server. No more retries!");
        } else {
          await Future.delayed(reconnectTime);
          return await connect(
              pingInterval: pingInterval,
              onReconnect: onReconnect,
              reconnectTime: reconnectTime,
              reconnectCount: reconnectCount == -1 ? reconnectCount : reconnectCount - 1);
        }
      } else {
        print("${transport.onConnectionLost.isCompleted} ${onReconnect != null} ${reconnectTime != null}");
        throw Exception("Could not connect to server. Please configure reconnectTime to retry automatically.");
      }
    }
  }
}
