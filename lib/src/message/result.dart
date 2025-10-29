import 'abstract_ppt_options.dart';
import 'message_types.dart';
import 'abstract_message_with_payload.dart';

/// Result message returned from a remote procedure call.
class Result extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int callRequestId;

  /// The ID of the publication of the published event.
  ResultDetails details;

  /// Create a result referencing the original [callRequestId]. Optional
  /// [arguments] and [argumentsKeywords] contain the RPC result payload.
  Result(this.callRequestId, this.details,
      {List<dynamic>? arguments, Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codeResult;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  /// Indicates whether this result is part of a progressive sequence.
  bool isProgressive() {
    return details.progress != null && details.progress!;
  }
}

/// Additional information returned with a [Result].
class ResultDetails extends PPTOptions {
  // progressive_call_results == true
  bool? progress;

  /// Create a set of result details describing PPT options and progression.
  ResultDetails(
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
  /// Validate that the PPT options are correct.
  bool verify() {
    return verifyPPT();
  }
}
