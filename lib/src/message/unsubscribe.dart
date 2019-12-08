import 'abstract_message.dart';

class Unsubscribe extends AbstractMessage {
    int requestId;
    int subscriptionId;
}
