import 'abstract_message_with_payload.dart';

class Call extends AbstractMessageWithPayload {
    int requestId;
    CallOptions options;
    String procedure;

    Call(this.requestId, this.procedure, {this.options, List<Object> arguments, Map<String, Object> argumentsKeywords}) {
        this.arguments = arguments;
        this.argumentsKeywords = argumentsKeywords;
    }
}

/**
 * Options used influence the call behavior
 */
class CallOptions{
    // progressive_call_results == true
    bool receive_progress;
    // call_timeout == true
    int timeout;
    // caller_identification == true
    bool disclose_me;

    CallOptions(this.receive_progress, this.timeout, this.disclose_me);
}