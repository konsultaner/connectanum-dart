import 'abstract_message_with_payload.dart';
import 'message_types.dart';

class Publish extends AbstractMessageWithPayload {
  int requestId;
  PublishOptions options;
  String topic;

  Publish(this.requestId, this.topic,
      {this.options,
      List<Object> arguments,
      Map<String, Object> argumentsKeywords}) {
    id = MessageTypes.CODE_PUBLISH;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

class PublishOptions {
  bool acknowledge;

  // subscriber_blackwhite_listing == true
  List<int> exclude;
  List<String> exclude_authid;
  List<String> exclude_authrole;
  List<int> eligible;
  List<String> eligible_authid;
  List<String> eligible_authrole;

  // publisher_exclusion == true
  bool exclude_me;

  // publisher_identification == true
  bool disclose_me;

  // event_retention == true
  bool retain;

  PublishOptions(
      {this.acknowledge,
      this.exclude,
      this.exclude_authid,
      this.exclude_authrole,
      this.eligible,
      this.eligible_authid,
      this.eligible_authrole,
      this.exclude_me,
      this.disclose_me,
      this.retain});
}
