import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'message_types.dart';

class Event extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int subscriptionId;

  /// The ID of the publication of the published event.
  int publicationId;
  EventDetails details;

  Event(this.subscriptionId, this.publicationId, this.details,
      {List<dynamic>? arguments, Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codeEvent;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options used influence the event behavior
class EventDetails extends PPTOptions {
  // publisher_identification == true
  int? publisher;

  // publication_trustlevels == true
  int? trustlevel;

  // for pattern-matching
  String? topic;

  EventDetails(
      {this.publisher,
      this.trustlevel,
      this.topic,
      String? pptScheme,
      String? pptSerializer,
      String? pptCipher,
      String? pptKeyid}) {
    pptScheme = pptScheme;
    pptSerializer = pptSerializer;
    pptCipher = pptCipher;
    pptKeyId = pptKeyid;
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}
