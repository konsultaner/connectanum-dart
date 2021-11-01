import 'package:connectanum/connectanum.dart';

import '../message/authenticate.dart';
import '../message/challenge.dart';

abstract class AbstractAuthentication {
  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Since Ticket does not need to modify it.
  Future<void> hello(String? realm, Details details);

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively.
  Future<Authenticate> challenge(Extra extra);

  /// This method is called by the session to identify the authentication name.
  String getName();
}
