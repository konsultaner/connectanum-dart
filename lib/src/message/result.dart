import 'message_types.dart';
import 'abstract_message_with_payload.dart';

class Result extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int callRequestId;

  /// The ID of the publication of the published event.
  ResultDetails details;

  Result(this.callRequestId, this.details,
      {List<Object> arguments, Map<String, Object> argumentsKeywords}) {
    id = MessageTypes.CODE_RESULT;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return details != null && details.progress != null && details.progress;
  }
}

class ResultDetails {
  // progressive_call_results == true
  bool progress;

  ResultDetails(this.progress);
}
