import 'package:connectanum_dart/src/message/yield.dart';

import 'abstract_message_with_payload.dart';

class Invocation extends AbstractMessageWithPayload {

    int requestId;
    int registrationId;
    Details details;

    Yield toYield(){
        YieldDetails details = new YieldDetails();
        return new Yield(this.requestId,details);
    }



}
class Details {
    // caller_identification == true
    int caller;
    // pattern_based_registration == true
    Uri procedure;
    // pattern_based_registration == true
    bool receive_progress;
}