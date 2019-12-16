import 'abstract_message.dart';
import 'message_types.dart';

class Unsubscribed extends AbstractMessage {
  int unsubscribeRequestId;

  Unsubscribed(this.unsubscribeRequestId) {
    this.id = MessageTypes.CODE_UNSUBSCRIBED;
  }
}
