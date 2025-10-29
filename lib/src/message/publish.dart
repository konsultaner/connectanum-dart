import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'message_types.dart';

/// A WAMP publish message used to notify subscribers about an event.
class Publish extends AbstractMessageWithPayload {
  /// Unique identifier used to correlate a publish request and the routers
  /// response.
  int requestId;

  /// Options influencing the publish behaviour such as acknowledgement or
  /// publisher disclosure.
  PublishOptions? options;

  /// The topic URI the event should be published to.
  String topic;

  /// Creates a publish message that will publish to [topic]. Optional
  /// [arguments] and [argumentsKeywords] are forwarded to the subscribers.
  /// The [options] parameter configures additional publish features.
  Publish(this.requestId, this.topic,
      {this.options,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codePublish;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Configuration options used while publishing an event.
class PublishOptions extends PPTOptions {
  /// Request a publish acknowledgement from the router.
  bool? acknowledge;

  // subscriber_blackwhite_listing == true
  /// Exclude the given session ids from receiving the event.
  List<int>? exclude;

  /// Exclude sessions with one of these authentication ids.
  List<String>? excludeAuthId;

  /// Exclude sessions with one of these authentication roles.
  List<String>? excludeAuthRole;

  /// Only allow these session ids to receive the event.
  List<int>? eligible;

  /// Only allow these authentication ids to receive the event.
  List<String>? eligibleAuthId;

  /// Only allow these authentication roles to receive the event.
  List<String>? eligibleAuthRole;

  // publisher_exclusion == true
  /// If true the publishing session will not receive the event itself.
  bool? excludeMe;

  // publisher_identification == true
  /// If true the publisher identity will be disclosed to receivers.
  bool? discloseMe;

  // event_retention == true
  /// Instruct the broker to retain the event for new subscribers.
  bool? retain;

  /// Creates a set of options for publishing events.
  PublishOptions(
      {this.acknowledge,
      this.exclude,
      this.excludeAuthId,
      this.excludeAuthRole,
      this.eligible,
      this.eligibleAuthId,
      this.eligibleAuthRole,
      this.excludeMe,
      this.discloseMe,
      this.retain,
      String? pptScheme,
      String? pptSerializer,
      String? pptCipher,
      String? pptKeyId}) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
  }

  @override
  /// Validate PPT options supplied for this publish request.
  bool verify() {
    return verifyPPT();
  }
}
