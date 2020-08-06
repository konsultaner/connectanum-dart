import 'abstract_message.dart';
import 'message_types.dart';

class Unsubscribed extends AbstractMessage {
  int unsubscribeRequestId;
  UnsubscribedDetails details;

  Unsubscribed(this.unsubscribeRequestId, this.details) {
    id = MessageTypes.CODE_UNSUBSCRIBED;
  }
}

class UnsubscribedDetails {
  int subscription;
  String reason;

  UnsubscribedDetails(this.subscription, this.reason);
}
