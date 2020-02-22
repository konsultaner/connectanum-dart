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
    await transport.open();
    return Session.start(realm, transport, authId: authId, authMethods: authenticationMethods, reconnect: reconnectTime);
  }
}