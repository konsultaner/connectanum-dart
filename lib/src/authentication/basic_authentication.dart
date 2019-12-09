import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';

class BasicAuthentication extends AbstractAuthentication {

  /**
   * This is never called for non advanced authentication
   */
  @override
  Future<Authenticate> challenge(Extra extra) {
    return null;
  }

}