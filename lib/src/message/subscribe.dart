import 'abstract_message.dart';
import 'message_types.dart';

class Subscribe extends AbstractMessage {
  int requestId;
  SubscribeOptions options;
  String topic;

  Subscribe(this.requestId, this.topic, {this.options}) {
    id = MessageTypes.CODE_SUBSCRIBE;
  }
}

class SubscribeOptions {
  static final String MATCH_PLAIN = null;
  static final String MATCH_PREFIX = 'prefix';
  static final String MATCH_WILDCARD = 'wildcard';

  String match;
  String meta_topic;

  SubscribeOptions({this.match, this.meta_topic});
}
