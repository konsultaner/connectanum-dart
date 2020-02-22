import '../message/authenticate.dart';
import '../message/challenge.dart';

abstract class AbstractAuthentication {
  Future<Authenticate> challenge(Extra extra);
  getName();
}