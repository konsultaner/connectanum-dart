import 'abstract_message.dart';
import 'message_types.dart';

class Unregister extends AbstractMessage {
  int requestId;
  int registrationId;

  Unregister(this.requestId, this.registrationId) {
    id = MessageTypes.CODE_UNREGISTER;
  }
}
