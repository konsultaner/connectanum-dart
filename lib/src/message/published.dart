import 'abstract_message.dart';
import 'message_types.dart';

/// Acknowledges a [Publish] request.
class Published extends AbstractMessage {
  /// The request ID that initiated the publication.
  int publishRequestId;

  /// Identifier assigned by the broker to the publication event.
  int publicationId;

  /// Create an instance referencing the [publishRequestId] and [publicationId].
  Published(this.publishRequestId, this.publicationId) {
    id = MessageTypes.codePublished;
  }
}
