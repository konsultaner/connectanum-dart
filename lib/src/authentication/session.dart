import 'package:connectanum_dart/src/message/challenge.dart';

import 'abstract_authentication.dart';

class Session {
  int id;
  String realm;
  String authId;
  String authRole;
  String authMethod;
  String authProvider;
}