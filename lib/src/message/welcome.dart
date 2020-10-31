import 'message_types.dart';
import 'abstract_message.dart';
import 'details.dart';

/// Is passed if a session was created by the server after or without an
/// authentication process
class Welcome extends AbstractMessage {
  int sessionId;
  Details details;

  /// the constructor with a server generated [sessionId] and other [details]
  Welcome(this.sessionId, this.details) {
    id = MessageTypes.CODE_WELCOME;
  }
}
