import 'abstract_message.dart';
import 'message_types.dart';

/// Remove a previously established subscription.
class Unsubscribe extends AbstractMessage {
  /// Unique ID for the unsubscribe request.
  int requestId;

  /// The subscription ID to cancel.
  int subscriptionId;

  /// Create an unsubscribe request.
  Unsubscribe(this.requestId, this.subscriptionId) {
    id = MessageTypes.codeUnsubscribe;
  }
}
