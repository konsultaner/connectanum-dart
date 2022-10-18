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
    id = MessageTypes.CODE_EVENT;
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
      String? ppt_scheme,
      String? ppt_serializer,
      String? ppt_cipher,
      String? ppt_keyid}) {
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
