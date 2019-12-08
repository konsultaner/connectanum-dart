import 'abstract_message.dart';

class Register extends AbstractMessage {
    int requestId;
    Options options;
    Uri procedure;
}

class Options{
    static final String MATCH_EXACT = null;
    static final String MATCH_PREFIX = "prefix";
    static final String MATCH_WILDCARD = "wildcard";

    static final String INVOCATION_POLICY_SINGLE       = "single";
    static final String INVOCATION_POLICY_FIRST        = "first";
    static final String INVOCATION_POLICY_LAST         = "last";
    static final String INVOCATION_POLICY_ROUND_ROBIN  = "roundrobin";
    static final String INVOCATION_POLICY_RANDOM       = "random";

    // caller_identification == true
    bool disclose_caller;
    // pattern_based_registration == true
    String match;
    // shared_registration
    String invoke;
}