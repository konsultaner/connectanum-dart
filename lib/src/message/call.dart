import 'abstract_message_with_payload.dart';

class Call extends AbstractMessageWithPayload {
    int requestId;
    Options options;
    Uri procedure;
}

/**
 * Options used influence the call behavior
 */
class Options{
    // progressive_call_results == true
    bool receive_progress;
    // call_timeout == true
    int timeout;
    // caller_identification == true
    bool disclose_me;
}