import 'abstract_message.dart';
import 'message_types.dart';

/// Sent by a client to register an RPC endpoint.
class Register extends AbstractMessage {
  /// Unique ID for this register request.
  int requestId;

  /// Optional registration options such as invocation policy.
  RegisterOptions? options;

  /// The URI of the procedure to register.
  String procedure;

  /// Create a register request for [procedure].
  Register(this.requestId, this.procedure, {this.options}) {
    id = MessageTypes.codeRegister;
  }
}

/// Options that influence procedure registration.
class RegisterOptions {
  static final String? matchExact = null;
  static final String matchPrefix = 'prefix';
  static final String matchWildcard = 'wildcard';

  /// Procedure is handled by a single callee.
  static final String invocationPolicySingle = 'single';
  static final String invocationPolicyFirst = 'first';
  static final String invocationPolicyLast = 'last';
  static final String invocationPolicyRoundRobin = 'roundrobin';
  static final String invocationPolicyRandom = 'random';

  // caller_identification == true
  /// Request the router to disclose caller identity.
  bool? discloseCaller;

  // pattern_based_registration == true
  /// Matching policy for the procedure URI.
  String? match;

  // shared_registration
  /// Invocation distribution policy when multiple callees are registered.
  String? invoke;

  /// Create a set of options for registering a procedure.
  RegisterOptions({this.discloseCaller, this.match, this.invoke});
}
