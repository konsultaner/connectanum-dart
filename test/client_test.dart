import 'package:connectanum_dart/src/client.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/details.dart';
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