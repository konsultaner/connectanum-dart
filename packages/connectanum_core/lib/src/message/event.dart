import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'custom_fields.dart';
import 'message_types.dart';

class Event extends AbstractMessageWithPayload {
  /// The ID for the subscription under which the Subscriber receives the event.
  /// The ID for the subscription originally handed out by the Broker to the Subscriber.
  int subscriptionId;

  /// The ID of the publication of the published event.
  int publicationId;
  EventDetails details;

  Event(
    this.subscriptionId,
    this.publicationId,
    this.details, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeEvent;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options used influence the event behavior
class EventDetails extends PPTOptions with CustomFieldContainer {
  // publisher_identification == true
  int? publisher;

  // publication_trustlevels == true
  int? trustlevel;

  // for pattern-matching
  String? topic;

  EventDetails({
    this.publisher,
    this.trustlevel,
    this.topic,
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyid,
    Map<String, dynamic>? custom,
  }) {
    // ignore: unnecessary_this
    this.pptScheme = pptScheme;
    // ignore: unnecessary_this
    this.pptSerializer = pptSerializer;
    // ignore: unnecessary_this
    this.pptCipher = pptCipher;
    // ignore: unnecessary_this
    this.pptKeyId = pptKeyid;
    if (custom != null) {
      this.custom.addAll(custom);
    }
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}
