import 'package:connectanum/src/authentication/ticket_authentication.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:test/test.dart';

void main() {
  group('Ticket', () {
    var secret = '3614';

    test('message handling', () async {
      final authMethod = TicketAuthentication(secret);
      expect(authMethod.getName(), equals('ticket'));
      final authenticate = await authMethod.challenge(Extra());
      expect(authenticate.signature, equals(secret));
    });
  });
}
