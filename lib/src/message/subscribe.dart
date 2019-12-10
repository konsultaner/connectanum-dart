import 'abstract_message.dart';

class Subscribe extends AbstractMessage {
    int requestId;
    SubscribeOptions options;
    String topic;
    Subscribe(this.requestId, this.topic, {this.options});
}

class SubscribeOptions {
    static final String MATCH_PLAIN = null;
    static final String MATCH_PREFIX = "prefix";
    static final String MATCH_WILDCARD  = "wildcard";

    String match;
    String meta_topic;
}