import 'abstract_message.dart';
import 'message_types.dart';

class Goodbye extends AbstractMessage {
  static const String reasonNormal = 'wamp.close.normal';
  static const String reasonGoodbyeAndOut = 'wamp.close.goodbye_and_out';
  static const String reasonCloseRealm = 'wamp.close.close_realm';
  static const String reasonKilled = 'wamp.close.killed';
  static const String reasonTimeout = 'wamp.error.timeout';
  static const String reasonSystemShutdown = 'wamp.close.system_shutdown';

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
