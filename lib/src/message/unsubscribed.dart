import 'abstract_message.dart';
import 'message_types.dart';

/// Confirmation that a subscription was successfully cancelled.
class Unsubscribed extends AbstractMessage {
  /// Identifier of the original unsubscribe request.
  int unsubscribeRequestId;

  /// Additional unsubscribe details provided by the router.
  UnsubscribedDetails? details;

  /// Creates an unsubscribed message for the given [unsubscribeRequestId].
  Unsubscribed(this.unsubscribeRequestId, this.details) {
    id = MessageTypes.codeUnsubscribed;
  }
}

/// Optional details returned with an [Unsubscribed] message.
class UnsubscribedDetails {
  /// The subscription id that was revoked.
  int? subscription;

  /// The reason given by the router for the unsubscription.
  String? reason;

  /// Creates an instance with an optional [subscription] id and [reason].
  UnsubscribedDetails(this.subscription, this.reason);
}
