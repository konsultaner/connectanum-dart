import 'abstract_message_with_payload.dart';
import 'message_types.dart';

class Event extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int subscriptionId;

  /// The ID of the publication of the published event.
  int publicationId;
  EventDetails details;

  Event(this.subscriptionId, this.publicationId, this.details,
      {List<Object> arguments, Map<String, Object> argumentsKeywords}) {
    id = MessageTypes.CODE_EVENT;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options used influence the event behavior
class EventDetails {
  // publisher_identification == true
  int publisher;

  // publication_trustlevels == true
  int trustlevel;

  // for pattern-matching
  String topic;

  EventDetails({this.publisher, this.trustlevel, this.topic});
}
