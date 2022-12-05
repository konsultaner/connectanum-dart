import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'message_types.dart';

class Publish extends AbstractMessageWithPayload {
  int requestId;
  PublishOptions? options;
  String topic;

  Publish(this.requestId, this.topic,
      {this.options,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codePublish;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

class PublishOptions extends PPTOptions {
  bool? acknowledge;

  // subscriber_blackwhite_listing == true
  List<int>? exclude;
  List<String>? excludeAuthId;
  List<String>? excludeAuthRole;
  List<int>? eligible;
  List<String>? eligibleAuthId;
  List<String>? eligibleAuthRole;

  // publisher_exclusion == true
  bool? excludeMe;

  // publisher_identification == true
  bool? discloseMe;

  // event_retention == true
  bool? retain;

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
  bool verify() {
    return verifyPPT();
  }
}
