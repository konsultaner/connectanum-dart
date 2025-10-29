import 'abstract_message.dart';
import 'message_types.dart';

/// Sent by the router as confirmation that a procedure was unregistered.
class Unregistered extends AbstractMessage {
  /// Identifier of the original unregister request.
  int unregisterRequestId;

  /// Creates an unregistered message for the given [unregisterRequestId].
  Unregistered(this.unregisterRequestId) {
    id = MessageTypes.codeUnregistered;
  }
}
