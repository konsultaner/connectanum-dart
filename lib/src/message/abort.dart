import 'message_types.dart';
import 'abstract_message.dart';

/// The WAMP Abort message.
class Abort extends AbstractMessage {
  Message? message;
  String reason;

  /// Creates a WAMP Abort message with a [reason] why something was aborted and an
  /// optional [message] to describe the issue
  Abort(this.reason, {String? message}) {
    id = MessageTypes.codeAbort;
    if (message != null) {
      this.message = Message(message);
    }
  }
}

/// The message structure defined by the WAMP-Protocol
class Message {
  String message;

  Message(this.message);
}
