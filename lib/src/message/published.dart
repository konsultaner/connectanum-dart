import 'abstract_message.dart';

class Published extends AbstractMessage {

    int publishRequestId;
    /**
     * A Id chosen by the broker
     */
    int publicationId;
}
