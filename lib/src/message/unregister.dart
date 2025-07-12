import 'abstract_message.dart';
import 'message_types.dart';

/// WAMP message used to unregister a previously registered procedure.
class Unregister extends AbstractMessage {
  /// Unique id of the unregister request.
  int requestId;

  /// The registration id that should be removed from the router.
  int registrationId;

  /// Creates an unregister message for the given [registrationId].
  Unregister(this.requestId, this.registrationId) {
    id = MessageTypes.codeUnregister;
  }
}
