import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/yield.dart';

import 'abstract_message_with_payload.dart';

class Invocation extends AbstractMessageWithPayload {
  int requestId;
  int registrationId;
  InvocationDetails details;

  Yield toYield() {
    YieldOptions details = new YieldOptions();
    return new Yield(this.requestId, details);
  }

  Invocation(this.requestId, this.registrationId, this.details) {
    this.id = MessageTypes.CODE_INVOCATION;
  }
}

class InvocationDetails {
  // caller_identification == true
  int caller;

  // pattern_based_registration == true
  String procedure;

  // pattern_based_registration == true
  bool receive_progress;

  InvocationDetails(this.caller, this.procedure, this.receive_progress);
}
