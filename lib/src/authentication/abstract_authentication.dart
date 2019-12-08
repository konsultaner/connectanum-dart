import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';

abstract class AbstractAuthentication {
  Future<Authenticate> challenge(Extra extra) {}
}