import 'abstract_message.dart';
import 'message_types.dart';

class Unsubscribe extends AbstractMessage {
  int requestId;
  int subscriptionId;

  Unsubscribe(this.requestId, this.subscriptionId) {
    id = MessageTypes.CODE_UNSUBSCRIBE;
  }
}
