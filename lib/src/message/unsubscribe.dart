import 'abstract_message.dart';
import 'message_types.dart';

class Unsubscribe extends AbstractMessage {
  int requestId;
  int subscriptionId;

  Unsubscribe(this.requestId, this.subscriptionId) {
    this.id = MessageTypes.CODE_UNSUBSCRIBE;
  }
}
