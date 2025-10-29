import 'abstract_ppt_options.dart';
import 'message_types.dart';
import 'abstract_message_with_payload.dart';

/// Reply from the callee with the result of an invocation.
class Yield extends AbstractMessageWithPayload {
  /// The invocation request this yield answers to.
  int invocationRequestId;

  /// Additional return options.
  YieldOptions? options;

  /// Create a [Yield] message with an optional result payload.
  Yield(this.invocationRequestId,
      {this.options,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codeYield;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options influencing how invocation results are transmitted.
class YieldOptions extends PPTOptions {
  /// Whether more results will follow.
  bool progress = false;

  /// Create a set of yield options.
  YieldOptions(
      {bool? progress,
      String? pptScheme,
      String? pptSerializer,
      String? pptCipher,
      String? pptKeyId}) {
    this.progress = progress ?? false;
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
  }

  @override
  /// Validate the PPT options associated with this yield message.
  bool verify() {
    return verifyPPT();
  }
}
