import 'abstract_message.dart';
import 'message_types.dart';

class Published extends AbstractMessage {
  int publishRequestId;

  /// A Id chosen by the broker
  int publicationId;

  Published(this.publishRequestId, this.publicationId) {
    id = MessageTypes.CODE_PUBLISHED;
  }
}
