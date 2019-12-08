import 'abstract_message.dart';

class Subscribed extends AbstractMessage {
    int subscribeRequestId;
    int subscriptionId;
}
