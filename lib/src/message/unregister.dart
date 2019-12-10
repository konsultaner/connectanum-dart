import 'abstract_message.dart';

class Unregister extends AbstractMessage {
    int requestId;
    int registrationId;
    Unregister(this.requestId, this.registrationId);
}
