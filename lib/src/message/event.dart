import 'abstract_message_with_payload.dart';

class Event extends AbstractMessageWithPayload {
    /**
     *  The ID for the subscription under which the Subscriber receives the event.
     *  The ID for the subscription originally handed out by the Broker to the Subscriber.
     */
    int subscriptionId;
    /**
     * The ID of the publication of the published event.
     */
    int publicationId;
    Details details;
}

/**
 * Options used influence the event behavior
 */
class Details {
    // publisher_identification == true
    int publisher;
    // publication_trustlevels == true
    int trustlevel;
    // for pattern-matching
    Uri topic;
}
