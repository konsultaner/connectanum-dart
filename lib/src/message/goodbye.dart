import 'abstract_message.dart';
import 'message_types.dart';

/// Sent by either peer to close the session.
class Goodbye extends AbstractMessage {
  static final String reasonGoodbyeAndOut = 'wamp.error.goodbye_and_out';
  static final String reasonCloseRealm = 'wamp.error.close_realm';
  static final String reasonTimeout = 'wamp.error.timeout';
  static final String reasonSystemShutdown = 'wamp.error.system_shutdown';

  /// Optional human readable farewell message.
  GoodbyeMessage? message;

  /// The reason code for closing the session.
  String reason;

  /// Create a [Goodbye] message with an optional [message] and [reason].
  Goodbye(this.message, this.reason) {
    id = MessageTypes.codeGoodbye;
  }
}

/// Additional message details for a [Goodbye] frame.
class GoodbyeMessage {
  /// Optional textual goodbye message.
  String? message;

  /// Create an instance containing a goodbye [message].
  GoodbyeMessage(this.message);
}
