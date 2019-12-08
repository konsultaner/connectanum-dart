import 'abstract_message_with_payload.dart';

class Result extends AbstractMessageWithPayload {
    /**
     *  The ID for the subscription under which the Subscriber receives the event.
     *  The ID for the subscription originally handed out by the Broker to the Subscriber.
     */
    int callRequestId;
    /**
     * The ID of the publication of the published event.
     */
    Details details;

    bool isProgressive(){
        return this.details != null && this.details.progress != null && this.details.progress;
    }
}

class Details {
    // progressive_call_results == true
    bool progress;
}