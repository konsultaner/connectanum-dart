import 'abstract_message.dart';

class Subscribe extends AbstractMessage {
    int requestId;
    Options options;
    Uri topic;
}

class Options{
    static final String MATCH_PLAIN = null;
    static final String MATCH_PREFIX = "prefix";
    static final String MATCH_WILDCARD  = "wildcard";

    String match;
    String meta_topic;
}