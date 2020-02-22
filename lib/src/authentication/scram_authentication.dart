import '../message/authenticate.dart';
import '../message/challenge.dart';
import 'abstract_authentication.dart';

class ScramAuthentication extends AbstractAuthentication {

  @override
  Future<Authenticate> challenge(Extra extra) {
    throw new UnimplementedError("Not implemented yet");
  }

  @override
  getName() {
    return "wamp-scram";
  }
}