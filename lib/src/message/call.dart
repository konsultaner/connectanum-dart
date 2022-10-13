import 'abstract_message_with_payload.dart';
import 'message_types.dart';

/// The WAMP Call massage
class Call extends AbstractMessageWithPayload {
  int requestId;
  CallOptions? options;
  String procedure;

  /// Creates a WAMP Call message with a [requestId] that is kind of like a
  /// transaction identifier and a [procedure] that was registered to the router
  /// before. The [options] field may be passed to configure the call
  Call(this.requestId, this.procedure,
      {this.options,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.CODE_CALL;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options used influence the call behavior
class CallOptions {
  // progressive_call_results == true
  bool? receive_progress;

  // call_timeout == true
  int? timeout;

  // caller_identification == true
  bool? disclose_me;

  // Payload Passthru mode options
  String? ppt_scheme;
  String? ppt_serializer;
  String? ppt_cipher;
  String? ppt_keyid;

  CallOptions(
      {this.receive_progress,
      this.timeout,
      this.disclose_me,
      this.ppt_scheme,
      this.ppt_serializer,
      this.ppt_cipher,
      this.ppt_keyid});
}
