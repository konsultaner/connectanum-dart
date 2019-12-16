import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message.dart';

class Published extends AbstractMessage {
  int publishRequestId;

  /**
   * A Id chosen by the broker
   */
  int publicationId;

  Published(this.publishRequestId, this.publicationId) {
    this.id = MessageTypes.CODE_PUBLISHED;
  }
}
