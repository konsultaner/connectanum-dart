import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message.dart';

class Authenticate extends AbstractMessage {
    String signature;
    Map<String, Object> extra;

    Authenticate() {
        this.id = MessageTypes.CODE_AUTHENTICATE;
    }
}
