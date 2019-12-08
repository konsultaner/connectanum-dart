import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message_with_payload.dart';

class Yield extends AbstractMessageWithPayload {
    int invocationRequestId;
    YieldDetails details;

    Yield(this.invocationRequestId, this.details){
        this.id = MessageTypes.CODE_YIELD;
    }
}

class YieldDetails {
    bool progress;
}

