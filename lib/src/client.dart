import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';

class Client {
  Duration reconnectTime;
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
  /// final client = new Client(
  ///   realm: "test.realm",
  ///   transport: new SocketTransport(
  ///     'localhost',
  ///     8080,
  ///     new Serializer(),
  ///     SocketHelper.SERIALIZATION_JSON
  ///   )
  /// );
  ///
  /// final Session session = await client.connect();
  /// ```
  Client({
    this.reconnectTime: null,
    AbstractTransport this.transport: null,
    String this.authId: null,
    String this.realm,
    List<AbstractAuthentication> this.authenticationMethods: null,
    int this.isolateCount: 1
  }) :
        assert (transport != null),
        assert (realm != null && UriPattern.match(realm))
  {}

  /// Calling this method will start the authentication process and result into
  /// a [Session] object on success.
  Future<Session> connect() async {
    await transport.open();
    return Session.start(realm, transport, authId: authId, authMethods: authenticationMethods, reconnect: reconnectTime);
  }
}