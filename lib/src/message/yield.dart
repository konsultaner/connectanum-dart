import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message_with_payload.dart';

class Yield extends AbstractMessageWithPayload {
    int invocationRequestId;
    YieldOptions options;

    Yield(this.invocationRequestId, this.options){
        this.id = MessageTypes.CODE_YIELD;
    }
}

class YieldOptions {
    bool progress;
}

