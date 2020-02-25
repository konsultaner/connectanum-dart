import 'abstract_message.dart';
import 'event.dart';
import 'message_types.dart';

class Subscribed extends AbstractMessage {
  int subscribeRequestId;
  int subscriptionId;

  Subscribed(this.subscribeRequestId, this.subscriptionId) {
    this.id = MessageTypes.CODE_SUBSCRIBED;
  }

  /// Is created by the protocol processor and will receive an event object
  /// when the transport receives one
  Stream<Event> eventStream;
}
