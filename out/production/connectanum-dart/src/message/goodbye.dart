import 'abstract_message.dart';
import 'message_types.dart';

class Goodbye extends AbstractMessage {
  static final String reasonGoodbyeAndOut = 'wamp.error.goodbye_and_out';
  static final String reasonCloseRealm = 'wamp.error.close_realm';
  static final String reasonTimeout = 'wamp.error.timeout';
  static final String reasonSystemShutdown = 'wamp.error.system_shutdown';

  GoodbyeMessage? message;
  String reason;

  Goodbye(this.message, this.reason) {
    id = MessageTypes.codeGoodbye;
  }
}

class GoodbyeMessage {
  String? message;
  GoodbyeMessage(this.message);
}
