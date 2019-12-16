import 'abstract_message.dart';
import 'message_types.dart';

class Unregistered extends AbstractMessage {
  int unregisterRequestId;

  Unregistered(this.unregisterRequestId) {
    this.id = MessageTypes.CODE_UNREGISTERED;
  }
}
