import 'dart:async';

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
    test('on challenge event', () async {
      final authMethod = TicketAuthentication("test");
      final completer = Completer<Extra>();
      authMethod.onChallenge.listen(
        (event) {
          completer.complete(event);
        },
      );
      var extra = Extra(challenge: "challenge", channelBinding: null);
      authMethod.challenge(extra);
      var receivedExtra = await completer.future;
      expect(receivedExtra, isNotNull);
      expect(receivedExtra.challenge, equals("challenge"));
    });
  });
}
