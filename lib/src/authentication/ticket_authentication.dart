import 'abstract_authentication.dart';
import '../message/authenticate.dart';
import '../message/challenge.dart';

class TicketAuthentication extends AbstractAuthentication {

  final String password;

  TicketAuthentication(this.password);

  @override
  Future<Authenticate> challenge(Extra extra) {
    return Future.value(new Authenticate(signature: this.password));
  }

  @override
  getName() {
    return "ticket";
  }
}