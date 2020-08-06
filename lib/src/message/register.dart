import 'abstract_message.dart';
import 'message_types.dart';

class Register extends AbstractMessage {
  int requestId;
  RegisterOptions options;
  String procedure;

  Register(this.requestId, this.procedure, {this.options}) {
    id = MessageTypes.CODE_REGISTER;
  }
}

class RegisterOptions {
  static final String MATCH_EXACT = null;
  static final String MATCH_PREFIX = 'prefix';
  static final String MATCH_WILDCARD = 'wildcard';

  static final String INVOCATION_POLICY_SINGLE = 'single';
  static final String INVOCATION_POLICY_FIRST = 'first';
  static final String INVOCATION_POLICY_LAST = 'last';
  static final String INVOCATION_POLICY_ROUND_ROBIN = 'roundrobin';
  static final String INVOCATION_POLICY_RANDOM = 'random';

  // caller_identification == true
  bool disclose_caller;

  // pattern_based_registration == true
  String match;

  // shared_registration
  String invoke;

  RegisterOptions({this.disclose_caller, this.match, this.invoke});
}
