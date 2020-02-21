import 'package:connectanum_dart/src/message/authenticate.dart';

import 'package:connectanum_dart/src/message/challenge.dart';

import 'abstract_authentication.dart';

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