import 'abstract_ppt_options.dart';
import 'message_types.dart';
import 'abstract_message_with_payload.dart';

class Result extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int callRequestId;

  /// The ID of the publication of the published event.
  ResultDetails details;

  Result(this.callRequestId, this.details,
      {List<dynamic>? arguments, Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.CODE_RESULT;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return details.progress != null && details.progress!;
  }
}

class ResultDetails extends PPTOptions {
  // progressive_call_results == true
  bool? progress;

  ResultDetails({bool? progress,
      String? ppt_scheme,
      String? ppt_serializer,
      String? ppt_cipher,
      String? ppt_keyid}) {
      this.progress = progress ?? false;
      this.ppt_scheme = ppt_scheme;
      this.ppt_serializer = ppt_serializer;
      this.ppt_cipher = ppt_cipher;
      this.ppt_keyid = ppt_keyid;
  }

  @override
  bool Verify() {
      return VerifyPPT();
  }
}
