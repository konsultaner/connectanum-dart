import 'package:connectanum/authentication.dart';
import 'package:connectanum/connectanum.dart';
import 'package:test/test.dart';

void main() {
  group('Local transport authentication test', () {
    test('success', () async {
      var client = Client(
          realm: "com.connectanum",
          authenticationMethods: [TicketAuthentication("Richard")],
          authId: "Burkhardt",
          transport: LocalTransport(authenticationPassword: "Richard"));
      var session = await client.connect().first;
      expect(session, isNotNull);
    });
    test('fail', () async {
      var client = Client(
          realm: "com.connectanum",
          authenticationMethods: [TicketAuthentication("Richard")],
          authId: "Burkhardt",
          transport: LocalTransport());
      AbstractMessage? errorMessage;
      Session? session;
      try {
        session = await client.connect().first;
      } catch (error) {
        errorMessage = error as AbstractMessage;
      }
      expect(session, isNull);
      expect(errorMessage, isNotNull);
    });
  });
}
