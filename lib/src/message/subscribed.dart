import 'package:rxdart/rxdart.dart';

import 'abstract_message.dart';
import 'event.dart';

class Subscribed extends AbstractMessage {
    int subscribeRequestId;
    int subscriptionId;

    /**
     * Is created by the protocol processor and will receive an event object
     * when the transport receives one
     */
    BehaviorSubject<Event> eventStream;
}
