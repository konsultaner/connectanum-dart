import 'abstract_message.dart';

class Abort extends AbstractMessage {
  Message message;
  String reason;

  Abort(this.reason, {String message}) {
    if (message != null) {
      this.message = Message(message);
    }
  }
}

class Message {
  String message;

  Message(this.message);
}
