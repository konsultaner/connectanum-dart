import 'abstract_authentication.dart';
import '../message/authenticate.dart';
import '../message/challenge.dart';

/// This is the ticket based authentication implementation for this package.
/// Use it with the [Client].
class TicketAuthentication extends AbstractAuthentication {
  final String password;

  TicketAuthentication(this.password);

  @override
  Future<Authenticate> challenge(Extra extra) {
    return Future.value(Authenticate(signature: this.password));
  }

  @override
  getName() {
    return "ticket";
  }
}
