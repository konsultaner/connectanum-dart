import 'package:connectanum_dart/src/authentication/cra_authentication.dart';
import 'package:connectanum_dart/src/client.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/details.dart';
import 'package:connectanum_dart/src/message/hello.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:connectanum_dart/src/transport/abstract_transport.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    test("session creation without authentication process", () async {
      final transport = _MockTransport();
      final client = new Client(
        realm: "test.realm",
        transport: transport
      );
      transport.outbound.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receive(
              new Welcome(
                  sessionId: 42,
                  details: Details.forWelcome(
                    authId: "Richi",
                    authMethod: "none",
                    authProvider: "noProvider",
                    authRole: "client"
                  )
              )
          );
        }
      });
      final session = await client.connect();
      expect(session.realm, equals("test.realm"));
      expect(session.id, equals(42));
      expect(session.authId, equals("Richi"));
      expect(session.authRole, equals("client"));
      expect(session.authProvider, equals("noProvider"));
      expect(session.authMethod, equals("none"));
    });

    test("session creation with cra authentication process", () async {
      final transport = _MockTransport();
      final client = new Client(
          realm: "test.realm",
          transport: transport,
          authId: "11111111",
          authenticationMethods: [new CraAuthentication("3614")]
      );
      transport.outbound.listen((message) {
        if (message.id == MessageTypes.CODE_HELLO) {
          transport.receive(
              new Challenge(
                (message as Hello).details.authmethods[0],
                new Extra(
                    challenge : "{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}",
                    keylen : 32,
                    iterations : 1000,
                    salt : "gbnk5ji1b0dgoeavu31er567nb"
                )
              )
          );
        }
        if (message.id == MessageTypes.CODE_AUTHENTICATE && (message as Authenticate).signature == "APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=") {
          transport.receive(
              new Welcome(
                  sessionId: 586844620777222,
                  details: Details.forWelcome(
                      authId: "11111111",
                      authMethod: "wampcra",
                      authProvider: "cra",
                      authRole: "client"
                  )
              )
          );
        }
      });
      final session = await client.connect();
      expect(session.realm, equals("test.realm"));
      expect(session.id, equals(586844620777222));
      expect(session.authId, equals("11111111"));
      expect(session.authRole, equals("client"));
      expect(session.authProvider, equals("cra"));
      expect(session.authMethod, equals("wampcra"));
    });
  });
}

class _MockTransport extends AbstractTransport {

  bool _open = false;
  final BehaviorSubject<AbstractMessage> outbound = new BehaviorSubject();

  @override
  bool isOpen() {
    return _open;
  }

  @override
  void send(AbstractMessage message) {
    outbound.add(message);
  }

  void receive(AbstractMessage message) {
    this.inbound.add(message);
  }

  @override
  Future<void> close() {
    this._open = false;
    return Future.value();
  }

  @override
  Future<void> open() {
    this._open = true;
    return Future.value();
  }

}