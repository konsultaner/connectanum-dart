import 'abstract_message.dart';
import 'custom_fields.dart';
import 'message_types.dart';

class Register extends AbstractMessage {
  int requestId;
  RegisterOptions? options;
  String procedure;

  Register(this.requestId, this.procedure, {this.options}) {
    id = MessageTypes.codeRegister;
  }
}

class RegisterOptions with CustomFieldContainer {
  static final String? matchExact = null;
  static final String matchPrefix = 'prefix';
  static final String matchWildcard = 'wildcard';

  static final String invocationPolicySingle = 'single';
  static final String invocationPolicyFirst = 'first';
  static final String invocationPolicyLast = 'last';
  static final String invocationPolicyRoundRobin = 'roundrobin';
  static final String invocationPolicyRandom = 'random';

  // caller_identification == true
  bool? discloseCaller;

  // pattern_based_registration == true
  String? match;

  // shared_registration
  String? invoke;

  // call_timeout == true
  bool? forwardTimeout;

  RegisterOptions({
    this.discloseCaller,
    this.match,
    this.invoke,
    this.forwardTimeout,
    Map<String, dynamic>? custom,
  }) {
    if (custom != null) {
      this.custom.addAll(custom);
    }
  }
}
