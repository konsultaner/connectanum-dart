import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/transport/abstract_transport.dart';

import 'protocol/session.dart';
import 'message/uri_pattern.dart';

class Client {
  Duration reconnectTime;
  AbstractTransport transport;
  String authId;
  String realm;
  List<AbstractAuthentication> authenticationMethods;
  int isolateCount;

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

  Future<Session> connect() async {
    return Session.start(realm, transport, authId: authId, authMethods: authenticationMethods, reconnect: reconnectTime);
  }
}