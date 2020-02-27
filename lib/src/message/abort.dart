import 'message_types.dart';
import 'abstract_message.dart';

class Abort extends AbstractMessage {
  Message message;
  String reason;

  Abort(this.reason, {String message}) {
    this.id = MessageTypes.CODE_ABORT;
    if (message != null) {
      this.message = Message(message);
    }
  }
}

class Message {
  String message;

  Message(this.message);
}
