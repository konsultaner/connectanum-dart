import 'package:connectanum/connectanum.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';

abstract class AbstractAuthentication {
  Future<void> hello(String realm,Details details);
  Future<Authenticate> challenge(Extra extra);
  getName();
}
