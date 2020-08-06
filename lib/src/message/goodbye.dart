import 'abstract_message.dart';
import 'message_types.dart';

class Goodbye extends AbstractMessage {
  static final String REASON_GOODBYE_AND_OUT = 'wamp.error.goodbye_and_out';
  static final String REASON_CLOSE_REALM = 'wamp.error.close_realm';
  static final String REASON_TIMEOUT = 'wamp.error.timeout';
  static final String REASON_SYSTEM_SHUTDOWN = 'wamp.error.system_shutdown';

  GoodbyeMessage message;
  String reason;

  Goodbye(this.message, this.reason) {
    id = MessageTypes.CODE_GOODBYE;
  }
}

class GoodbyeMessage {
  String message;
  GoodbyeMessage(this.message);
}
